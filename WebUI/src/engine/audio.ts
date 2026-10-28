// Microphone capture with a simple voice-activity detector, and gapless playback.
// Main thread only: AudioContext doesn't exist inside workers.
import { VoiceDetector, type VadOptions } from './vad'

export class MicBlockedError extends Error {}

export interface Capture {
  /** Stop recording and return 16 kHz mono audio for Whisper (null when nothing was said). */
  stop: () => Promise<Float32Array | null>
  /** Drop the recording. */
  cancel: () => void
}

/**
 * Record until stop(), or until the speaker pauses (autoStop), whichever comes first.
 * onLevel gets 0..1 loudness for the UI; onSpeech fires when speech starts and ends.
 */
export interface CaptureOptions extends VadOptions {
  autoStop?: boolean
  silenceMs?: number
  maxMs?: number
  /**
   * Current loudness of our own speech output. While it plays, the mic hears some of it back; the detector learns
   * how much (mic level / output level) and only counts a voice clearly louder than that echo.
   */
  echo?: () => number
  /** A possible voice started (true) or faded out before it counted as speech (false). */
  onCandidate?: (on: boolean) => void
  onLevel?: (l: number) => void
  onSpeech?: (speaking: boolean) => void
  onAutoStop?: () => void
}

// Silero VAD runs in its own worker; every capture is one stream of frames into it.
let vadWorker: Worker | null = null
let streamSeq = 0
const vadListeners = new Map<number, (m: { type: string; p?: number; error?: string }) => void>()
function vad(): Worker {
  if (!vadWorker) {
    vadWorker = new Worker(new URL('./vad.worker.ts', import.meta.url), { type: 'module' })
    vadWorker.onmessage = (e) => vadListeners.get(e.data.id)?.(e.data)
  }
  return vadWorker
}

/**
 * Record 16 kHz mono from the mic (an AudioWorklet resamples and frames it), with Silero VAD deciding when
 * speech starts and ends. stop() returns the audio from just before the first speech: raw samples, so no
 * encoding, decoding or timing guesswork.
 */
export async function capture(opts: CaptureOptions): Promise<Capture> {
  let stream: MediaStream
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } })
  } catch (e) {
    throw new MicBlockedError((e as Error)?.name === 'NotAllowedError' ? 'Microphone access was blocked.' : 'No microphone found.')
  }
  const ctx = new AudioContext()
  await ctx.audioWorklet.addModule('/mic-worklet.js')
  const src = ctx.createMediaStreamSource(stream)
  const tap = new AudioWorkletNode(ctx, 'mic-tap')
  src.connect(tap)

  const id = ++streamSeq
  const frames: Float32Array[] = []
  const rmsOf: number[] = []
  const started = performance.now()
  const det = new VoiceDetector(opts, started)
  let finished = false
  let stopped = false
  let onDone: (() => void) | null = null

  vadListeners.set(id, (m) => {
    if (finished || m.type !== 'prob') return
    // Frame i ends 32 ms * (i + 1) after the start; using that keeps timing exact even if replies arrive bunched.
    const i = rmsOf.length - pending--
    const now = started + (i + 1) * 32
    for (const e of det.step(m.p ?? 0, rmsOf[i], opts.echo?.() ?? 0, now)) {
      if (e === 'candidate' || e === 'candidate-end') opts.onCandidate?.(e === 'candidate')
      else opts.onSpeech?.(e === 'speech')
    }
    const silence = opts.silenceMs ?? 1100
    if (!stopped && opts.autoStop && det.heard && now - det.lastLoud > silence) {
      stopped = true
      opts.onAutoStop?.()
    }
    if (!stopped && now - started > (opts.maxMs ?? 60000)) {
      stopped = true
      opts.onAutoStop?.()
    }
    if (!pending) onDone?.()
  })
  let pending = 0
  tap.port.onmessage = (e: MessageEvent<Float32Array>) => {
    if (finished) return
    const f = e.data
    let sum = 0
    for (let i = 0; i < f.length; i++) sum += f[i] * f[i]
    const rms = Math.sqrt(sum / f.length)
    frames.push(f)
    rmsOf.push(rms)
    opts.onLevel?.(Math.min(1, rms * 9))
    pending++
    vad().postMessage({ type: 'frame', id, stream: id, frame: f })
  }

  const shutdown = () => {
    finished = true
    tap.port.onmessage = null
    src.disconnect()
    stream.getTracks().forEach((t) => t.stop())
    void ctx.close()
    vadListeners.delete(id)
    vad().postMessage({ type: 'end', stream: id })
    opts.onLevel?.(0)
  }
  return {
    stop: async () => {
      if (finished) return null
      // Let the frames already sent to the detector finish, so a word at the very end still counts.
      if (pending) await new Promise<void>((r) => ((onDone = r), setTimeout(r, 300)))
      shutdown()
      if (!det.heard || det.speechFrom === null) return null
      // Keep 0.4 s before the speech began, so the first syllable is never clipped.
      const from = Math.max(0, Math.floor((det.speechFrom - 400) / 32))
      const out = new Float32Array((frames.length - from) * 512)
      for (let i = from; i < frames.length; i++) out.set(frames[i], (i - from) * 512)
      return out
    },
    cancel: () => {
      if (!finished) shutdown()
    },
  }
}

/** Gapless queue for synthesized speech chunks. stop() cuts playback immediately. */
export class Player {
  private ctx: AudioContext | null = null
  private meter: AnalyserNode | null = null
  private gain: GainNode | null = null
  private meterBuf = new Float32Array(512)
  private t = 0
  private sources = new Set<AudioBufferSourceNode>()
  private idle: (() => void)[] = []
  onLevel?: (l: number) => void

  /** Call from a user gesture once, so autoplay rules let audio start. */
  unlock() {
    if (!this.ctx) {
      this.ctx = new AudioContext()
      this.meter = this.ctx.createAnalyser()
      this.meter.fftSize = 512
      this.gain = this.ctx.createGain()
      // Measured after the volume dip, so the echo guard expects the quieter sound while she's dipped.
      this.gain.connect(this.meter).connect(this.ctx.destination)
    }
    void this.ctx.resume()
  }
  /** Dip the volume (someone may be starting to talk over her) or bring it back. */
  duck(on: boolean) {
    if (this.gain && this.ctx) this.gain.gain.setTargetAtTime(on ? 0.2 : 1, this.ctx.currentTime, 0.03)
  }
  /** RMS of what's playing right now (0 when silent). */
  level(): number {
    if (!this.meter || !this.sources.size) return 0
    this.meter.getFloatTimeDomainData(this.meterBuf)
    let sum = 0
    for (const v of this.meterBuf) sum += v * v
    return Math.sqrt(sum / this.meterBuf.length)
  }
  /** Queue a chunk; returns the milliseconds until it starts playing. */
  play(pcm: Float32Array, sampleRate: number): number {
    this.unlock()
    const ctx = this.ctx!
    const b = ctx.createBuffer(1, pcm.length, sampleRate)
    b.copyToChannel(pcm as Float32Array<ArrayBuffer>, 0)
    const s = ctx.createBufferSource()
    s.buffer = b
    s.connect(this.gain!)
    this.t = Math.max(this.t, ctx.currentTime + 0.02)
    s.start(this.t)
    const startsIn = (this.t - ctx.currentTime) * 1000
    this.t += b.duration
    this.sources.add(s)
    s.onended = () => {
      this.sources.delete(s)
      if (!this.sources.size) this.idle.splice(0).forEach((f) => f())
    }
    return startsIn
  }
  get playing() {
    return this.sources.size > 0
  }
  /** Resolves when everything queued so far has played. */
  drained(): Promise<void> {
    if (!this.sources.size) return Promise.resolve()
    return new Promise((r) => this.idle.push(r))
  }
  stop() {
    for (const s of this.sources) {
      s.onended = null
      try {
        s.stop()
      } catch {
        /* already stopped */
      }
    }
    this.sources.clear()
    this.t = 0
    this.duck(false)
    this.idle.splice(0).forEach((f) => f())
  }
}

export const player = new Player()
