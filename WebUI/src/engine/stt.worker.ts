import './ort-paths'
import { pipeline, type ProgressInfo, type AutomaticSpeechRecognitionPipeline } from '@huggingface/transformers'

// base: whisper-base, ~206 MB, for small GPUs (encoder fp32 + decoder q4 is known to work on WebGPU).
// turbo: whisper-large-v3-turbo, ~760 MB with 4-bit weights, far better with accents, for GPUs with room.
// The 4-bit encoder keeps fp32 activations: its fp16 encoder loses precision on WebGPU (transformers.js #1590).
const MODELS = {
  base: { id: 'onnx-community/whisper-base', dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' } },
  turbo: { id: 'onnx-community/whisper-large-v3-turbo', dtype: { encoder_model: 'q4', decoder_model_merged: 'q4' } },
} as const
export type SttQuality = keyof typeof MODELS
let asr: Promise<AutomaticSpeechRecognitionPipeline> | null = null
let loaded: SttQuality | null = null

function load(quality: SttQuality) {
  if (loaded !== quality && asr) {
    const old = asr
    asr = null
    void old.then((p) => p.dispose()).catch(() => {})
  }
  loaded = quality
  asr ??= (async () => {
    const p = (await pipeline('automatic-speech-recognition', MODELS[quality].id, {
      device: 'webgpu',
      dtype: MODELS[quality].dtype,
      progress_callback: (i: ProgressInfo) => {
        if (i.status === 'progress_total') self.postMessage({ type: 'progress', loaded: i.loaded, total: i.total })
      },
    })) as AutomaticSpeechRecognitionPipeline
    await p(new Float32Array(16000)) // compile shaders now so the first real dictation is quick
    return p
  })()
  asr.catch(() => (asr = null))
  return asr
}

self.onmessage = async (e: MessageEvent<{ type: 'load'; id: number; quality: SttQuality } | { type: 'transcribe'; id: number; quality: SttQuality; audio: Float32Array }>) => {
  const msg = e.data
  try {
    const p = await load(msg.quality)
    if (msg.type === 'load') return void self.postMessage({ type: 'ready', id: msg.id })
    const out = await p(msg.audio, { task: 'transcribe', chunk_length_s: 30, stride_length_s: 5 })
    const text = (Array.isArray(out) ? out.map((o) => o.text).join(' ') : out.text).trim()
    self.postMessage({ type: 'result', id: msg.id, text })
  } catch (err) {
    self.postMessage({ type: 'error', id: msg.id, error: String((err as Error)?.message ?? err) })
  }
}
