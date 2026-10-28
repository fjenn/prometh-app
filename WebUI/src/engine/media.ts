// Main-thread clients for the speech and image workers.
import type { ImageEngine } from './image.worker'
import type { SttQuality } from './stt.worker'
import { getDevice } from './device'

type Msg = { type: string; id?: number; [k: string]: unknown }

class WorkerClient {
  private w: Worker | null = null
  private seq = 0
  private handlers = new Map<number, (m: Msg) => void>()
  onProgress: ((loaded: number, total: number) => void) | null = null
  constructor(private make: () => Worker) {}

  private get worker() {
    if (!this.w) {
      this.w = this.make()
      this.w.onmessage = (e: MessageEvent<Msg>) => {
        const m = e.data
        if (m.type === 'progress') return this.onProgress?.(m.loaded as number, m.total as number)
        if (m.id != null) this.handlers.get(m.id)?.(m)
      }
      this.w.onerror = (e) => {
        const err: Msg = { type: 'error', error: e.message || 'The worker crashed.' }
        for (const h of this.handlers.values()) h(err)
        this.handlers.clear()
        this.terminate()
      }
    }
    return this.w
  }
  /** Send a message; `on` receives every reply for it until `off()` is called. */
  send(msg: Record<string, unknown>, on: (m: Msg) => void, transfer: Transferable[] = []) {
    const id = ++this.seq
    this.handlers.set(id, on)
    this.worker.postMessage({ ...msg, id }, transfer)
    return { id, off: () => this.handlers.delete(id) }
  }
  /** Fire-and-forget message addressed to an existing request id. */
  post(msg: Record<string, unknown>) {
    this.worker.postMessage(msg)
  }
  call(msg: Record<string, unknown>, transfer: Transferable[] = []): Promise<Msg> {
    return new Promise((resolve, reject) => {
      const h = this.send(
        msg,
        (m) => {
          if (m.type === 'error') {
            h.off()
            reject(new Error(String(m.error)))
          } else if (m.type === 'ready' || m.type === 'result' || m.type === 'image' || m.type === 'done') {
            h.off()
            resolve(m)
          }
        },
        transfer,
      )
    })
  }
  terminate() {
    this.w?.terminate()
    this.w = null
    for (const h of this.handlers.values()) h({ type: 'error', error: 'Cancelled' })
    this.handlers.clear()
  }
  get alive() {
    return !!this.w
  }
}

const stt = new WorkerClient(() => new Worker(new URL('./stt.worker.ts', import.meta.url), { type: 'module' }))
const tts = new WorkerClient(() => new Worker(new URL('./tts.worker.ts', import.meta.url), { type: 'module' }))
const img = new WorkerClient(() => new Worker(new URL('./image.worker.ts', import.meta.url), { type: 'module' }))

const STT_BYTES: Record<SttQuality, number> = { base: 206e6, turbo: 760e6 }
const TTS_BYTES = 326e6
/** The big Whisper where the GPU has room (much better with accents), the small one elsewhere. */
const sttQuality = (): SttQuality => ((getDevice()?.budgetMB ?? 0) >= 6000 ? 'turbo' : 'base')

/** Download and warm up both speech models. */
export async function prepareVoice(onProgress: (p: number) => void, signal: AbortSignal) {
  const abort = () => {
    stt.terminate()
    tts.terminate()
  }
  signal.addEventListener('abort', abort)
  try {
    const quality = sttQuality()
    const sttBytes = STT_BYTES[quality]
    let sttDone = 0
    let ttsDone = 0
    const report = () => onProgress(Math.min(0.99, (sttDone + ttsDone) / (sttBytes + TTS_BYTES)))
    stt.onProgress = (l) => {
      sttDone = Math.min(l, sttBytes)
      report()
    }
    tts.onProgress = (l) => {
      ttsDone = Math.min(l, TTS_BYTES)
      report()
    }
    await stt.call({ type: 'load', quality })
    sttDone = sttBytes
    report()
    await tts.call({ type: 'load' })
    onProgress(1)
  } finally {
    signal.removeEventListener('abort', abort)
    stt.onProgress = tts.onProgress = null
  }
}

/** Load (downloading if needed) the speech-to-text model this device uses; reports download progress 0..1. */
export async function warmListening(onProgress: (p: number) => void) {
  stt.onProgress = (l, t) => onProgress(Math.min(1, l / Math.max(t, 1)))
  try {
    await stt.call({ type: 'load', quality: sttQuality() })
  } finally {
    stt.onProgress = null
  }
}

export async function transcribe(audio: Float32Array): Promise<string> {
  const r = await stt.call({ type: 'transcribe', audio, quality: sttQuality() }, [audio.buffer])
  return String(r.text ?? '')
}

export interface Speech {
  push: (text: string) => void
  end: () => void
  cancel: () => void
  done: Promise<void>
}

/** Load the speech model and compile its shaders ahead of the first reply. */
export function warmSpeech() {
  void tts.call({ type: 'load' }).catch(() => {})
}

/** Stream text into speech. Chunks arrive per sentence, with the sentence they say, and go to `onChunk`. */
export function speak(text: string, voice: string, onChunk: (pcm: Float32Array, sampleRate: number, text: string) => void): Speech {
  let resolve!: () => void
  let reject!: (e: Error) => void
  const done = new Promise<void>((a, b) => {
    resolve = a
    reject = b
  })
  let cancelled = false
  const h = tts.send({ type: 'speak', text, voice }, (m) => {
    if (cancelled) return
    if (m.type === 'chunk') onChunk(m.pcm as Float32Array, m.sampleRate as number, String(m.text ?? ''))
    else if (m.type === 'done') {
      h.off()
      resolve()
    } else if (m.type === 'error') {
      h.off()
      reject(new Error(String(m.error)))
    }
  })
  return {
    push: (t) => {
      if (!cancelled) tts.post({ type: 'push', id: h.id, text: t })
    },
    end: () => tts.post({ type: 'end', id: h.id }),
    cancel: () => {
      cancelled = true
      tts.post({ type: 'end', id: h.id })
      h.off()
      resolve()
    },
    done,
  }
}

const IMG_BYTES = 2.15e9

/** Download and initialise the image model, then free its GPU memory until it's used. */
export async function prepareImages(engine: ImageEngine, onProgress: (p: number) => void, signal: AbortSignal) {
  const abort = () => img.terminate()
  signal.addEventListener('abort', abort)
  try {
    img.onProgress = (l, t) => onProgress(Math.min(0.99, l / Math.max(t || IMG_BYTES, 1)))
    await img.call({ type: 'load', engine })
    onProgress(1)
  } finally {
    signal.removeEventListener('abort', abort)
    img.onProgress = null
    img.terminate()
  }
}

type Took = { total: number; load: number }
export type ImageResult = ({ blob: Blob; width: number; height: number } | { blocked: 'nsfw' | 'minor' }) & { took: Took }

/** Generate an image. Progress reports load (phase 'load') then the 4 steps and the decode. The output checks run on it before it comes back. */
export async function generateImage(prompt: string, mode: 'safe' | 'evil', engine: ImageEngine, onProgress: (phase: 'load' | 'draw', p: number) => void, signal: AbortSignal): Promise<ImageResult> {
  const abort = () => img.terminate()
  signal.addEventListener('abort', abort)
  img.onProgress = (l, t) => onProgress('load', l / Math.max(t, 1))
  try {
    return await new Promise((resolve, reject) => {
      const seed = crypto.getRandomValues(new Uint32Array(1))[0]
      const h = img.send({ type: 'generate', prompt, mode, seed, engine }, (m) => {
        if (m.type === 'step') onProgress('draw', (m.done as number) / (m.total as number))
        else if (m.type === 'image') {
          h.off()
          const took = m.took as Took
          resolve(m.blocked ? { blocked: m.blocked as 'nsfw' | 'minor', took } : { blob: m.blob as Blob, width: m.width as number, height: m.height as number, took })
        } else if (m.type === 'error') {
          h.off()
          reject(new Error(signal.aborted ? 'Cancelled' : String(m.error)))
        }
      })
    })
  } finally {
    signal.removeEventListener('abort', abort)
    img.onProgress = null
  }
}

export function releaseImages() {
  img.terminate()
}
export const imagesLoaded = () => img.alive
