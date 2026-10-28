import type { AppConfig, ChatCompletionMessageParam, WebWorkerMLCEngine } from '@mlc-ai/web-llm'
import { ALL_LLMS, type LLMSpec } from './catalog'
import { ui } from '../state/store'

// web-llm is large (~6 MB), so it loads on first use instead of with the welcome screen.
const webllm = () => import('@mlc-ai/web-llm')

/** Official WebLLM records plus our own builds, which borrow lib and overrides from their official twin. */
let appConfig: AppConfig | null = null
async function config(): Promise<AppConfig> {
  if (appConfig) return appConfig
  const { prebuiltAppConfig } = await webllm()
  appConfig = {
    ...prebuiltAppConfig,
    model_list: [
      ...prebuiltAppConfig.model_list,
      ...ALL_LLMS.filter((m) => m.baseId).map((m) => {
        const base = prebuiltAppConfig.model_list.find((r) => r.model_id === m.baseId)
        if (!base) throw new Error(`Missing base record ${m.baseId}`)
        return { ...base, model: `https://huggingface.co/${m.repo}`, model_id: m.id }
      }),
    ],
  }
  return appConfig
}

const repoBase = (m: LLMSpec) => `https://huggingface.co/${m.repo}/resolve/main/`

interface Shard {
  dataPath: string
  nbytes: number
}

/**
 * Download a model's weights into the same Cache Storage WebLLM reads from
 * ("webllm/model", keyed by URL), without touching the GPU. Finished shards stay
 * cached, so pausing and resuming continues where it left off.
 */
export async function prefetchLLM(m: LLMSpec, signal: AbortSignal, onProgress: (done: number, total: number) => void) {
  const base = repoBase(m)
  const cache = await caches.open('webllm/model')
  const manifestUrl = new URL('tensor-cache.json', base).href
  let manifest = await cache.match(manifestUrl)
  if (!manifest) {
    const r = await fetch(manifestUrl, { signal })
    if (!r.ok) throw new Error(`Model files unavailable (HTTP ${r.status}).`)
    await cache.put(manifestUrl, r.clone())
    manifest = r
  }
  const records = ((await manifest.json()) as { records: Shard[] }).records
  const total = records.reduce((s, r) => s + r.nbytes, 0)
  const cachedUrls = new Set((await cache.keys()).map((k) => k.url))
  let done = 0
  const todo: Shard[] = []
  for (const r of records) {
    if (cachedUrls.has(new URL(r.dataPath, base).href)) done += r.nbytes
    else todo.push(r)
  }
  onProgress(done, total)
  // One failed shard stops the other downloads too, and nothing reports progress after that.
  const inner = new AbortController()
  const stopAll = () => inner.abort()
  signal.addEventListener('abort', stopAll)
  const report = (n: number) => !inner.signal.aborted && onProgress(Math.min(n, total), total)
  let bytes = done
  let next = 0
  const worker = async () => {
    while (next < todo.length) {
      if (inner.signal.aborted) throw new DOMException('Stopped', 'AbortError')
      const shard = todo[next++]
      const url = new URL(shard.dataPath, base).href
      const res = await fetch(url, { signal: inner.signal })
      if (!res.ok || !res.body) throw new Error(`Download failed (HTTP ${res.status}).`)
      const reader = res.body.getReader()
      const parts: Uint8Array[] = []
      for (;;) {
        const { done: end, value } = await reader.read()
        if (end) break
        parts.push(value)
        bytes += value.byteLength
        report(bytes)
      }
      await cache.put(url, new Response(new Blob(parts as BlobPart[]), { headers: { 'Content-Type': 'application/octet-stream' } }))
    }
  }
  try {
    await Promise.all(
      [worker(), worker(), worker(), worker()].map((w) =>
        w.catch((e) => {
          inner.abort()
          throw e
        }),
      ),
    )
  } finally {
    signal.removeEventListener('abort', stopAll)
  }
}

export async function isLLMCached(m: LLMSpec): Promise<boolean> {
  try {
    const cache = await caches.open('webllm/model')
    const manifest = await cache.match(new URL('tensor-cache.json', repoBase(m)).href)
    if (!manifest) return false
    const records = ((await manifest.json()) as { records: Shard[] }).records
    const keys = new Set((await cache.keys()).map((k) => k.url))
    return records.every((r) => keys.has(new URL(r.dataPath, repoBase(m)).href))
  } catch {
    return false
  }
}

export async function deleteLLM(m: LLMSpec) {
  const cache = await caches.open('webllm/model')
  const base = repoBase(m)
  for (const k of await cache.keys()) if (k.url.startsWith(base)) await cache.delete(k)
}

let engine: WebWorkerMLCEngine | null = null
let worker: Worker | null = null
let loadedId: string | null = null
let chain: Promise<unknown> = Promise.resolve()
let active = 0
let idleWaiters: (() => void)[] = []
const idle = () => (active ? new Promise<void>((r) => idleWaiters.push(r)) : Promise.resolve())

/** Load a chat model into the GPU (downloading whatever is missing). Calls are serialized. */
export function loadLLM(m: LLMSpec, onProgress?: (p: number, text: string) => void): Promise<WebWorkerMLCEngine> {
  const run = async () => {
    if (engine && loadedId === m.id) return engine
    ui.set({ chatLoading: { model: m.id, progress: 0, text: 'Loading' } })
    const cb = (r: { progress: number; text: string }) => {
      ui.set({ chatLoading: { model: m.id, progress: r.progress, text: r.text } })
      onProgress?.(r.progress, r.text)
    }
    try {
      if (!engine) {
        const { CreateWebWorkerMLCEngine } = await webllm()
        worker = new Worker(new URL('./llm.worker.ts', import.meta.url), { type: 'module' })
        engine = await CreateWebWorkerMLCEngine(worker, m.id, {
          appConfig: await config(),
          initProgressCallback: cb,
        })
      } else {
        engine.setInitProgressCallback(cb)
        loadedId = null
        await engine.reload(m.id)
      }
      loadedId = m.id
      ui.set({ chatLoaded: m.id })
      return engine
    } catch (e) {
      loadedId = null
      ui.set({ chatLoaded: null })
      throw e
    } finally {
      ui.set({ chatLoading: null })
    }
  }
  const p = chain.then(run, run)
  chain = p.catch(() => undefined)
  return p
}

/**
 * Load the model and run a one-token reply, so the GPU kernels are compiled before the user's first message
 * (the first real reply otherwise pays for that). A message sent meanwhile simply queues behind it.
 */
export async function warmLLM(m: LLMSpec) {
  const e = await loadLLM(m)
  active++
  try {
    await e.chat.completions.create({
      messages: [{ role: 'user', content: 'Hi' }],
      max_tokens: 1,
      ...(m.id.startsWith('Qwen') ? { extra_body: { enable_thinking: false } } : {}),
    })
  } finally {
    if (--active === 0) idleWaiters.splice(0).forEach((f) => f())
  }
}

export function loadedLLM() {
  return loadedId
}

/** Free the GPU memory held by the chat model once no reply is being written (it reloads from cache on the next message). */
export async function unloadLLM() {
  const run = async () => {
    await idle()
    if (engine && loadedId) {
      await engine.unload()
      loadedId = null
      ui.set({ chatLoaded: null })
    }
  }
  const p = chain.then(run, run)
  chain = p.catch(() => undefined)
  return p
}

/** After a lost GPU device or a broken engine: drop the worker so the next message starts clean. */
export function forgetLLM() {
  worker?.terminate()
  worker = null
  engine = null
  loadedId = null
  ui.set({ chatLoaded: null, chatLoading: null })
}

/** With thinking off, Qwen still emits an empty "<think>\n\n</think>\n\n" first; hide it (also while it's half-written). */
function stripEmptyThink(t: string) {
  if (!t.trimStart().startsWith('<think>') && !'<think>'.startsWith(t.trimStart() || '#')) return t
  const m = t.match(/^\s*<think>\s*<\/think>\s*/)
  if (m) return t.slice(m[0].length)
  return /^\s*<?t?h?i?n?k?>?\s*<?\/?t?h?i?n?k?>?\s*$/.test(t) ? '' : t
}

/** Stream a reply. Returns the full text and tokens/second. Aborting the signal stops it (also while the model loads). */
export async function streamChat(
  m: LLMSpec,
  messages: ChatCompletionMessageParam[],
  onText: (text: string) => void,
  opts: { maxTokens?: number; temperature?: number; signal: AbortSignal },
): Promise<{ text: string; tps?: number; stopped: boolean }> {
  const { signal } = opts
  const e = await loadLLM(m)
  if (signal.aborted) return { text: '', stopped: true }
  // Counted only once loaded: an unload waiting for idle sits in the same queue as loads.
  active++
  try {
    let firstToken = 0
    let text = ''
    let tokens = 0
    let stopped = false
    // create() returns once this request holds the model, so from here an interrupt can only hit our own reply.
    const stream = await e.chat.completions.create({
      messages,
      stream: true,
      stream_options: { include_usage: true },
      max_tokens: opts.maxTokens ?? 2048,
      temperature: opts.temperature ?? 0.7,
      top_p: 0.95,
      // Qwen3.5 thinking stays off: answers come straight away. Other families don't know the flag.
      ...(m.id.startsWith('Qwen') ? { extra_body: { enable_thinking: false } } : {}),
    })
    const interrupt = () => void e.interruptGenerate()
    signal.addEventListener('abort', interrupt)
    if (signal.aborted) interrupt()
    try {
      // Never break out early: the stream has to run to its end to release the model.
      for await (const chunk of stream) {
        // WebLLM clears the interrupt flag when generation starts, so repeat it while aborted.
        if (signal.aborted) interrupt()
        const delta = chunk.choices[0]?.delta?.content ?? ''
        if (delta && !signal.aborted) {
          firstToken ||= performance.now()
          text += delta
          onText(stripEmptyThink(text))
        }
        if (chunk.choices[0]?.finish_reason === 'abort') stopped = true
        if (chunk.usage) tokens = chunk.usage.completion_tokens
      }
    } finally {
      signal.removeEventListener('abort', interrupt)
    }
    // Generation speed from the first token on, so reading a long prompt doesn't drag it down.
    const secs = firstToken ? (performance.now() - firstToken) / 1000 : 0
    text = stripEmptyThink(text)
    return { text, tps: tokens > 1 && secs > 0.2 ? (tokens - 1) / secs : undefined, stopped: stopped || signal.aborted }
  } finally {
    if (--active === 0) idleWaiters.splice(0).forEach((r) => r())
  }
}
