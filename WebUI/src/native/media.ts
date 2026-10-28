import { request } from './bridge'
import { base64, unbase64 } from './encoding'
import { sentences } from './sentences'
import { voiceTurnId, voiceMark } from './voice-latency'
import { currentChat } from '../state/store'
type ImageEngine = 'sd15' | 'zimage'
const base = 'http://127.0.0.1:8080'
export async function prepareVoice(progress: (p: number) => void, _signal: AbortSignal) { progress(1) }
let voiceWarm: Promise<void> = Promise.resolve()
export async function warmListening(progress: (p: number) => void) { progress(0); await voiceWarm; progress(1) }
export function warmSpeech() { const chat = currentChat(); voiceWarm = request('audio.warm', { chatId: chat?.id, mode: chat?.mode }).catch(() => {}) }
function wav(audio: Float32Array) {
  const buf = new ArrayBuffer(44 + audio.length * 2), v = new DataView(buf)
  const str = (at: number, s: string) => [...s].forEach((c, i) => v.setUint8(at + i, c.charCodeAt(0)))
  str(0, 'RIFF'); v.setUint32(4, buf.byteLength - 8, true); str(8, 'WAVEfmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true); v.setUint32(24, 16000, true); v.setUint32(28, 32000, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true); str(36, 'data'); v.setUint32(40, audio.length * 2, true)
  audio.forEach((x, i) => v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, x)) * 32767, true))
  return new Blob([buf], { type: 'audio/wav' })
}
export async function transcribe(audio: Float32Array): Promise<string> {
  return request<string>('audio.transcribe', { data: base64(await wav(audio).arrayBuffer()), turnId: voiceTurnId() })
}
export interface Speech { push: (s: string) => void; end: () => void; cancel: () => void; done: Promise<void> }
export function speak(text: string, voice: string, onChunk: (pcm: Float32Array, sampleRate: number, text: string) => void): Speech {
  let content = '', ended = false, cancelled = false, busy = false, failed = false
  const turnId = voiceTurnId(), queue: string[] = []
  let finish!: () => void, fail!: (e: unknown) => void
  const done = new Promise<void>((resolve, reject) => { finish = resolve; fail = reject })
  // A synthesis error may arrive before the LLM finishes; endTurn awaits the same rejection later.
  void done.catch(() => {})
  const pump = async () => {
    if (busy || cancelled || failed) return
    busy = true
    try {
      while (queue.length && !cancelled) {
        const sentence = queue.shift()!
        voiceMark(turnId, 'tts_sentence')
        const encoded = await request<string>('audio.speech', { text: sentence, voice })
        if (cancelled) break
        const ctx = new AudioContext()
        try { const audio = await ctx.decodeAudioData(unbase64(encoded)); if (!cancelled) onChunk(audio.getChannelData(0), audio.sampleRate, sentence) }
        finally { await ctx.close() }
      }
      if (ended && !queue.length) finish()
    } catch (error) { failed = true; fail(error) }
    finally { busy = false }
  }
  const push = (s: string, final = false) => {
    if (cancelled || failed) return
    content += s
    const split = sentences(content, final)
    content = split.rest; queue.push(...split.ready)
    void pump()
  }
  if (text) push(text)
  return { push: s => push(s), cancel: () => { cancelled = true; queue.length = 0; finish() }, done, end: () => { ended = true; push('', true) } }
}
export async function prepareImages(_engine: ImageEngine, progress: (p: number) => void, _signal: AbortSignal) { progress(1) }
type Took = { total: number; load: number }
export type ImageResult = ({ blob: Blob; width: number; height: number } | { blocked: 'nsfw' | 'minor' }) & { took: Took }
export async function generateImage(prompt: string, _mode: 'safe' | 'evil', _engine: ImageEngine, onProgress: (phase: 'load' | 'draw', p: number) => void, signal: AbortSignal): Promise<ImageResult> {
  const started = performance.now(); onProgress('draw', 0)
  if (signal.aborted) throw new DOMException('Stopped', 'AbortError')
  const jobId = crypto.randomUUID()
  const cancel = () => { void request('media.cancel', { jobId }) }
  signal.addEventListener('abort', cancel)
  let result: { data?: { b64_json?: string; url?: string }[] }
  try { result = await request('media.image', { prompt, jobId }) } finally { signal.removeEventListener('abort', cancel) }
  if (signal.aborted) throw new DOMException('Stopped', 'AbortError')
  const data = result.data?.[0]; if (!data) throw new Error('The engine returned no image.')
  const image = await fetch(data.b64_json ? 'data:image/png;base64,' + data.b64_json : new URL(data.url ?? '', base).href, { signal }); const blob = await image.blob()
  const bitmap = await createImageBitmap(blob); const width = bitmap.width, height = bitmap.height; bitmap.close(); onProgress('draw', 1)
  return { blob, width, height, took: { total: (performance.now() - started) / 1000, load: 0 } }
}
export function releaseImages() {}
export const imagesLoaded = () => false
