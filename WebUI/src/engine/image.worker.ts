import './ort-paths'
import * as ort from 'onnxruntime-web/webgpu'
import { AutoTokenizer, Qwen2Tokenizer } from '@huggingface/transformers'
import * as sd from './sd'
import * as zimage from './zimage'
import { checkImage, loadChecks, type Mode } from './image-check'

// Two image models, both served from our own origin behind the login (never a public mirror):
// - sd15: Realistic Vision 6 + Hyper-SD 4-step (SD 1.5, CreativeML OpenRAIL-M), our fp16 conversion, 512 px.
// - zimage: Z-Image Turbo (Apache-2.0), Microsoft's webnn q4f16 build with our fp32-inside VAE, for big GPUs.
export type ImageEngine = 'sd15' | 'zimage'
const BASES: Record<ImageEngine, string> = { sd15: '/models/rv-hyper-v1/', zimage: '/models/zimage/' }
const CACHE = 'prometh/image'
const CHUNK = 64 * 1024 * 1024
const Z_SIZE = 1024
const Z_STEPS = 8

interface File {
  path: string
  bytes: number
}
type Msg = { type: 'load'; id: number; engine: ImageEngine } | { type: 'generate'; id: number; engine: ImageEngine; prompt: string; mode: Mode; seed: number }

// Chunks are keyed by query string: the Cache API ignores URL fragments when matching.
const chunkKeys = (base: string, f: File) => Array.from({ length: Math.ceil(f.bytes / CHUNK) }, (_, i) => `${base}${f.path}?chunk=${i}`)

/** Download every file in 64 MB range chunks into Cache Storage, so a dropped connection resumes. */
async function download(base: string): Promise<File[]> {
  const cache = await caches.open(CACHE)
  let res = await cache.match(base + 'manifest.json')
  if (!res) {
    const r = await fetch(base + 'manifest.json')
    if (!r.ok) throw new Error(`Image model files unavailable (HTTP ${r.status}).`)
    await cache.put(base + 'manifest.json', r.clone())
    res = r
  }
  const files = ((await res.json()) as { files: File[] }).files
  const total = files.reduce((s, f) => s + f.bytes, 0)
  const have = new Set((await cache.keys()).map((k) => new URL(k.url).pathname + new URL(k.url).search))
  const todo: { path: string; i: number; size: number }[] = []
  let done = 0
  for (const f of files)
    chunkKeys(base, f).forEach((k, i) => {
      const size = Math.min(CHUNK, f.bytes - i * CHUNK)
      if (have.has(k)) done += size
      else todo.push({ path: f.path, i, size })
    })
  self.postMessage({ type: 'progress', loaded: done, total })
  let next = 0
  // One failed chunk stops the other fetchers, so a retry doesn't race leftover downloads.
  const stop = new AbortController()
  const fetcher = async () => {
    while (next < todo.length && !stop.signal.aborted) {
      const c = todo[next++]
      const start = c.i * CHUNK
      const r = await fetch(base + c.path, { headers: { Range: `bytes=${start}-${start + c.size - 1}` }, signal: stop.signal })
      if (r.status !== 206 && !(r.status === 200 && c.i === 0 && c.size === Number(r.headers.get('content-length')))) throw new Error(`Image model download failed (HTTP ${r.status}).`)
      const buf = await r.arrayBuffer()
      if (buf.byteLength !== c.size) throw new Error('Image model download was cut off. Try again.')
      await cache.put(`${base}${c.path}?chunk=${c.i}`, new Response(buf))
      done += c.size
      self.postMessage({ type: 'progress', loaded: done, total })
    }
  }
  await Promise.all(
    [fetcher(), fetcher(), fetcher(), fetcher()].map((f) =>
      f.catch((e) => {
        stop.abort()
        throw e
      }),
    ),
  )
  return files
}

async function read(cache: Cache, base: string, f: File): Promise<Uint8Array> {
  const out = new Uint8Array(f.bytes)
  let off = 0
  for (const k of chunkKeys(base, f)) {
    const r = await cache.match(k)
    if (!r) throw new Error('Image model files are incomplete. Prepare images again.')
    const b = new Uint8Array(await r.arrayBuffer())
    out.set(b, off)
    off += b.byteLength
  }
  return out
}

interface Engine {
  draw(prompt: string, seed: number, onStep: (done: number, total: number) => void): Promise<{ chw: Float32Array; size: number }>
  release(): Promise<void>
}

/** Downloads what's missing, then creates the sessions one at a time (the WebGPU EP refuses parallel creation). */
async function open(engine: ImageEngine) {
  const base = BASES[engine]
  const files = await download(base)
  const cache = await caches.open(CACHE)
  const file = (path: string) => files.find((f) => f.path === path)!
  const sessions: ort.InferenceSession[] = []
  const session = async (graph: string, data: string[], dims: Record<string, number>, extra: ort.InferenceSession.SessionOptions = {}) => {
    const s = await ort.InferenceSession.create(await read(cache, base, file(graph)), {
      executionProviders: ['webgpu'],
      freeDimensionOverrides: dims,
      // External weights go straight from JS to the GPU instead of through the wasm heap.
      ...(data.length ? { externalData: await Promise.all(data.map(async (d) => ({ path: d.split('/').pop()!, data: await read(cache, base, file(d)) }))) } : {}),
      ...extra,
    })
    sessions.push(s)
    return s
  }
  const release = async () => {
    for (const s of sessions) await s.release()
  }
  return { cache, base, file, session, release }
}

async function openSD15(): Promise<Engine> {
  const o = await open('sd15')
  // Pinned free dimensions: batch 1, 77 tokens, 64x64 latents (512 px).
  const unet = await o.session('unet/model.onnx', ['unet/model.onnx_data'], { batch_size: 1, height: 64, width: 64, sequence_length: 77 })
  const vae = await o.session('vae_decoder/model.onnx', ['vae_decoder/model.onnx_data'], { batch_size: 1, height_latent: 64, width_latent: 64 })
  const textEncoder = await o.session('text_encoder/model.onnx', ['text_encoder/model.onnx_data'], { batch_size: 1, sequence_length: 77 }, { preferredOutputLocation: { last_hidden_state: 'gpu-buffer' } })
  const tokenizer = await AutoTokenizer.from_pretrained('openai/clip-vit-large-patch14')
  return {
    draw: async (prompt, seed, onStep) => {
      const ids = tokenizer(prompt, { padding: 'max_length', max_length: 77, truncation: true, return_tensor: false }).input_ids as number[]
      const chw = await sd.generate({ textEncoder, unet, vae } as sd.Sessions, (type, data, dims) => new ort.Tensor(type, data, dims), ids, { steps: 4, seed, onStep })
      return { chw, size: sd.SIZE }
    },
    release: o.release,
  }
}

async function openZImage(): Promise<Engine> {
  const o = await open('zimage')
  const L = Z_SIZE / 8
  const transformer = await o.session('transformer_model_q4f16.onnx', ['transformer_model_q4f16.onnx_data', 'transformer_model_q4f16.onnx_data_1'], { height: L, width: L })
  const textEncoder = await o.session('text_encoder_model_q4f16.onnx', ['text_encoder_model_q4f16.onnx_data', 'text_encoder_model_q4f16.onnx_data_1'], {})
  const schedulerStep = await o.session('scheduler_step_model_f16.onnx', [], { height: L, width: L })
  const vaePre = await o.session('vae_pre_process_model_f16.onnx', [], { height: L, width: L })
  const vae = await o.session('vae_decoder_model_f32.onnx', [], { latent_height: L, latent_width: L, height: Z_SIZE, width: Z_SIZE })
  const json = async (p: string) => JSON.parse(new TextDecoder().decode(await read(o.cache, o.base, o.file(p))))
  const tokenizer = new Qwen2Tokenizer(await json('tokenizer.json'), await json('tokenizer_config.json'))
  return {
    draw: async (prompt, seed, onStep) => {
      const ids = tokenizer(zimage.chatPrompt(prompt), { add_special_tokens: false, return_tensor: false }).input_ids as number[]
      const chw = await zimage.generate(
        { textEncoder, transformer, schedulerStep, vaePre, vae } as zimage.ZSessions,
        (b, dims) => new ort.Tensor('float16', b, dims),
        (b, dims) => new ort.Tensor('int64', b, dims),
        ids.slice(0, 512),
        { size: Z_SIZE, steps: Z_STEPS, seed, onStep },
      )
      return { chw, size: Z_SIZE }
    },
    release: o.release,
  }
}

let current: { engine: ImageEngine; ready: Promise<Engine> } | null = null

/** The requested engine, loaded once; switching engines frees the other one's GPU memory first. */
async function load(engine: ImageEngine): Promise<Engine> {
  if (current?.engine !== engine) {
    const prev = current
    current = null
    if (prev) await prev.ready.then((e) => e.release()).catch(() => {})
    void dropJanus()
    const ready = (engine === 'zimage' ? openZImage() : openSD15()).then(async (e) => {
      await loadChecks()
      return e
    })
    current = { engine, ready }
    ready.catch(() => {
      if (current?.ready === ready) current = null
    })
  }
  return current!.ready
}

/** Janus-Pro was the image model before; its 2.4 GB stay in the browser's cache otherwise. */
async function dropJanus() {
  const c = await caches.open('transformers-cache')
  for (const k of await c.keys()) if (k.url.includes('Janus-Pro')) await c.delete(k)
}

self.onmessage = async (e: MessageEvent<Msg>) => {
  const msg = e.data
  const t0 = performance.now()
  try {
    const engine = await load(msg.engine)
    if (msg.type === 'load') return void self.postMessage({ type: 'ready', id: msg.id })
    const tLoad = performance.now()
    const { chw, size } = await engine.draw(msg.prompt, msg.seed, (done, total) => self.postMessage({ type: 'step', id: msg.id, done, total }))
    const tDraw = performance.now()
    const rgba = sd.toRGBA(chw, size, size)
    // Nothing leaves the worker before the checks pass.
    const blocked = await checkImage(rgba, size, size, msg.mode, msg.engine)
    const tEnd = performance.now()
    console.info(`[image] ${msg.engine}: load ${Math.round(tLoad - t0)} ms, draw ${Math.round(tDraw - tLoad)} ms, checks ${Math.round(tEnd - tDraw)} ms`)
    const took = { total: (tEnd - t0) / 1000, load: (tLoad - t0) / 1000 }
    if (blocked) return void self.postMessage({ type: 'image', id: msg.id, blocked, took })
    const canvas = new OffscreenCanvas(size, size)
    canvas.getContext('2d')!.putImageData(new ImageData(rgba, size, size), 0, 0)
    const blob = await canvas.convertToBlob({ type: 'image/png' })
    self.postMessage({ type: 'image', id: msg.id, blob, width: size, height: size, took })
  } catch (err) {
    self.postMessage({ type: 'error', id: msg.id, error: String((err as Error)?.message ?? err) })
  }
}
