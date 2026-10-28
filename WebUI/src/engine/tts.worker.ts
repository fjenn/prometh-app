import './ort-paths'
import { KokoroTTS, TextSplitterStream } from 'kokoro-js'

// Kokoro 82M, fp32 on WebGPU (325 MB; the library recommends fp32 for WebGPU). English voices.
let tts: Promise<KokoroTTS> | null = null
function load() {
  tts ??= KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX', {
    dtype: 'fp32',
    device: 'webgpu',
    progress_callback: (p: { status: string; loaded?: number; total?: number }) => {
      if (p.status === 'progress_total') self.postMessage({ type: 'progress', loaded: p.loaded, total: p.total })
    },
  })
  tts.catch(() => (tts = null))
  return tts
}

type Msg = { type: 'load'; id: number } | { type: 'speak'; id: number; text: string; voice: string } | { type: 'push'; id: number; text: string } | { type: 'end'; id: number }
const splitters = new Map<number, TextSplitterStream>()

self.onmessage = async (e: MessageEvent<Msg>) => {
  const msg = e.data
  try {
    if (msg.type === 'push') return void splitters.get(msg.id)?.push(msg.text)
    if (msg.type === 'end') return void splitters.get(msg.id)?.close()
    if (msg.type === 'load') {
      const t = await load()
      // Warm up: the first synthesis compiles the WebGPU shaders.
      await t.generate('Ready.', { voice: 'af_heart' })
      return void self.postMessage({ type: 'ready', id: msg.id })
    }
    // Register the splitter before the (possibly slow) model load, so push/end that arrive meanwhile aren't lost.
    const splitter = new TextSplitterStream()
    splitters.set(msg.id, splitter)
    if (msg.text) splitter.push(msg.text)
    const t = await load()
    for await (const { text, audio } of t.stream(splitter, { voice: msg.voice as 'af_heart' })) {
      const pcm = new Float32Array(audio.audio as Float32Array)
      self.postMessage({ type: 'chunk', id: msg.id, pcm, sampleRate: audio.sampling_rate, text }, { transfer: [pcm.buffer] })
    }
    splitters.delete(msg.id)
    self.postMessage({ type: 'done', id: msg.id })
  } catch (err) {
    splitters.delete(msg.id)
    self.postMessage({ type: 'error', id: msg.id, error: String((err as Error)?.message ?? err) })
  }
}
