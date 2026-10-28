import './ort-paths'
import * as ort from 'onnxruntime-web/webgpu'

// Silero VAD v5 (MIT, 2.3 MB): speech probability for each 512-sample frame of 16 kHz audio. A neural detector,
// so syllable gaps, keyboard clicks and loudness don't fool it the way a loudness threshold does.
const MODEL = '/models/checks/silero_vad.onnx'
let session: Promise<ort.InferenceSession> | null = null
const streams = new Map<number, { state: ort.Tensor; context: Float32Array }>()
const sr = new ort.Tensor('int64', BigInt64Array.of(16000n), [])
let queue: Promise<unknown> = Promise.resolve()

function load() {
  session ??= (async () => {
    const r = await fetch(MODEL)
    if (!r.ok) throw new Error(`Voice detector unavailable (HTTP ${r.status}).`)
    return ort.InferenceSession.create(new Uint8Array(await r.arrayBuffer()), { executionProviders: ['wasm'] })
  })()
  session.catch(() => (session = null))
  return session
}

type Msg = { type: 'load'; id: number } | { type: 'frame'; id: number; stream: number; frame: Float32Array } | { type: 'end'; stream: number }

self.onmessage = (e: MessageEvent<Msg>) => {
  const msg = e.data
  if (msg.type === 'end') return void streams.delete(msg.stream)
  // Frames run strictly in order: the model carries state from one frame to the next.
  queue = queue.then(async () => {
    try {
      const s = await load()
      if (msg.type === 'load') return void self.postMessage({ type: 'ready', id: msg.id })
      let st = streams.get(msg.stream)
      if (!st) streams.set(msg.stream, (st = { state: new ort.Tensor('float32', new Float32Array(256), [2, 1, 128]), context: new Float32Array(64) }))
      // v5 expects the last 64 samples of the previous frame in front of each 512-sample frame.
      const input = new Float32Array(576)
      input.set(st.context, 0)
      input.set(msg.frame, 64)
      const out = await s.run({ input: new ort.Tensor('float32', input, [1, 576]), state: st.state, sr })
      st.state = out.stateN
      st.context = msg.frame.slice(448)
      self.postMessage({ type: 'prob', id: msg.id, p: (out.output.data as Float32Array)[0] })
    } catch (err) {
      self.postMessage({ type: 'error', id: msg.id, error: String((err as Error)?.message ?? err) })
    }
  })
}
