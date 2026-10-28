import { request, on } from './bridge'
import { unbase64 } from './encoding'
import { noteVADPause, voiceTurnId, voiceMark } from './voice-latency'
// Microphone capture with a simple voice-activity detector, and gapless playback.
// Main thread only: AudioContext doesn't exist inside workers.
import { VoiceDetector, captureEnded, type VadOptions } from './vad'

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

export async function capture(opts: CaptureOptions): Promise<Capture> {
  noteVADPause(0)
  const token = crypto.randomUUID(), started = performance.now(), detector = new VoiceDetector(opts, started)
  let stopped = false, failure: Error | null = null, ready = false, pendingStop = false
  let lastFrameAt = performance.now(), watchdog: ReturnType<typeof setInterval> | undefined
  const autoStop = () => {
    if (stopped) return
    if (!ready) { pendingStop = true; return }
    stopped = true; clearInterval(watchdog); opts.onAutoStop?.()
  }
  const offMeter = on<{ token: string; level: number }>('audio.meter', e => { if (e.token === token && !stopped) opts.onLevel?.(e.level) })
  const offError = on<{ token: string; error: string }>('audio.error', e => { if (e.token === token && !stopped) { failure = new Error(e.error); autoStop() } })
  type Frame = { token: string; probability: number; rms: number; elapsed: number }
  const queued: Frame[] = []
  const frame = (e: Frame) => {
    if (e.token !== token || stopped) return
    lastFrameAt = performance.now()
    const now = started + e.elapsed * 1000
    for (const event of detector.step(e.probability, e.rms, opts.echo?.() ?? 0, now)) {
      if (event === 'candidate' || event === 'candidate-end') opts.onCandidate?.(event === 'candidate')
      else opts.onSpeech?.(event === 'speech')
    }
    if (opts.autoStop && captureEnded(detector, now, e.elapsed * 1000, opts.silenceMs, opts.maxMs)) {
      if (detector.heard) noteVADPause(now - detector.lastLoud)
      autoStop()
    }
  }
  const offFrame = on<Frame>('audio.frame', e => {
    if (e.token !== token || stopped) return
    if (!ready) queued.push(e)
    else frame(e)
  })
  const off = () => { clearInterval(watchdog); queued.length = 0; offMeter(); offFrame(); offError() }
  try { await request('audio.start', { token }) } catch (e) { off(); throw new MicBlockedError((e as Error).message) }
  lastFrameAt = performance.now()
  watchdog = setInterval(() => {
    if (!stopped && performance.now() - lastFrameAt > 5000) {
      failure = new Error('The microphone or speech detector stopped delivering audio. Check the selected input device.')
      autoStop()
    }
  }, 1000)
  // A cold native detector can deliver queued frames before audio.start resolves.
  // Let the caller install capture/take before reporting an already detected pause/error.
  setTimeout(() => {
    ready = true
    if (stopped) return
    if (pendingStop) autoStop()
    else for (const event of queued.splice(0)) frame(event)
  }, 0)
  return { cancel: () => { stopped = true; off(); void request('audio.cancel', { token }) }, stop: async () => {
    stopped = true; off()
    const encoded = await request<string>('audio.stop', { token }); if (failure) throw failure
    if (!encoded || !detector.heard || detector.speechFrom === null) return null
    const ctx = new AudioContext({ sampleRate: 16000 })
    try { const audio = await ctx.decodeAudioData(unbase64(encoded)); return audio.getChannelData(0).slice(Math.max(0, Math.floor((detector.speechFrom - 400) * 16))) } finally { await ctx.close() }
  } }
}

export class Player {
  private ctx: AudioContext | null = null
  private meter: AnalyserNode | null = null
  private gain: GainNode | null = null
  private meterBuf = new Float32Array(512)
  private t = 0
  private audibleTurn: string | undefined
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
    const startsAt = this.t
    s.start(startsAt)
    const startsIn = (this.t - ctx.currentTime) * 1000
    this.t += b.duration
    this.sources.add(s)
    const turnId = voiceTurnId()
    const observeStart = () => {
      if (!turnId || this.audibleTurn === turnId || !this.sources.has(s)) return
      if (ctx.state === 'running' && ctx.currentTime >= startsAt) {
        this.audibleTurn = turnId
        voiceMark(turnId, 'audio_played')
      } else setTimeout(observeStart, ctx.state === 'running' ? Math.max(10, (startsAt - ctx.currentTime) * 1000) : 50)
    }
    if (turnId) setTimeout(observeStart, startsIn)
    s.onended = () => {
      observeStart()
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
