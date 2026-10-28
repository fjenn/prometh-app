// Turn-taking on top of Silero's per-frame speech probability. Pure (no audio APIs), so it can be tested with
// synthetic frames. Used by capture() in audio.ts.

export type VadEvent = 'candidate' | 'candidate-end' | 'speech' | 'speech-end'

export interface VadOptions {
  /** Speech only counts after this much voiced time (read on every frame, so it can change mid-capture). */
  minSpeechMs?: number
}

export class VoiceDetector {
  heard = false
  speaking = false
  lastLoud: number
  /** When the first speech began (ms since start), counted from the first voiced frame that led to it. */
  speechFrom: number | null = null
  private lastTick: number
  private lastVoiced = 0
  private candidate = false
  private candidateFrom: number | null = null
  private voicedMs = 0
  private outEnv = 0
  private echoK = 0
  private noise: number | null = null
  private outSince: number | null = null
  private opts: VadOptions
  private started: number

  constructor(opts: VadOptions, started: number) {
    this.opts = opts
    this.started = started
    this.lastLoud = started
    this.lastTick = started
  }

  /** One frame: Silero's speech probability, the mic loudness (RMS), our own output's loudness (0 if none), time. */
  step(prob: number, rms: number, out: number, now: number): VadEvent[] {
    const ev: VadEvent[] = []
    this.outEnv = Math.max(out, this.outEnv * 0.9) // decaying peak, covers the delay before her sound reaches the mic
    if (this.outEnv > 0.005) this.outSince ??= now
    else this.outSince = null
    // Her own voice coming back through speakers is speech too, so while she talks a frame must also be clearly
    // louder than her echo. The first 300 ms of each stretch of her speech measure that echo (none on headphones).
    const learning = this.outSince !== null && now - this.outSince < 300
    // Room noise: a floor that drops fast and rises slowly, so the echo is measured on top of it.
    const noise = (this.noise ??= prob >= 0.5 ? Math.min(0.001, rms * 0.1) : rms)
    const excess = Math.max(0, rms - noise)
    if (learning) this.echoK = Math.max(this.echoK * 0.8, excess / this.outEnv)
    const echoFloor = this.outEnv > 0.005 ? this.echoK * this.outEnv * 3 : 0
    const voiced = !learning && prob >= 0.5 && rms > Math.max(0.002, noise + echoFloor)
    if (!voiced && !this.candidate && !this.speaking) {
      this.noise = rms < noise ? noise * 0.7 + rms * 0.3 : noise * 0.995 + rms * 0.005
      if (this.outEnv > 0.005 && !learning) this.echoK = this.echoK * 0.97 + (excess / this.outEnv) * 0.03
    }
    const dt = Math.min(100, now - this.lastTick)
    this.lastTick = now
    // Voiced time adds up and drains at half speed in short gaps, so a pause between words doesn't reset it.
    this.voicedMs = voiced ? this.voicedMs + dt : Math.max(0, this.voicedMs - dt / 2)
    if (voiced) {
      this.lastVoiced = now
      if (!this.speaking && !this.candidate) {
        this.candidate = true
        this.candidateFrom = now - dt
        ev.push('candidate')
      }
    }
    if (this.candidate && !this.speaking && this.voicedMs === 0 && now - this.lastVoiced > 250) {
      this.candidate = false
      this.candidateFrom = null
      ev.push('candidate-end')
    }
    // Once speaking, Silero's lower bar keeps the turn going through soft word endings.
    const still = this.speaking && prob >= 0.35 && rms > Math.max(0.002, noise + echoFloor)
    if (still || (voiced && (this.speaking || this.voicedMs >= (this.opts.minSpeechMs ?? 0)))) {
      this.lastLoud = now
      if (!this.speaking) {
        this.speaking = true
        this.heard = true
        this.candidate = false
        this.speechFrom ??= (this.candidateFrom ?? now - dt) - this.started
        ev.push('speech')
      }
    } else if (this.speaking && now - this.lastLoud > 350) {
      this.speaking = false
      ev.push('speech-end')
    }
    return ev
  }
}


export const VOICE_SILENCE_MS = 550
export function captureEnded(detector: VoiceDetector, now: number, elapsed: number, silenceMs = VOICE_SILENCE_MS, maxMs = 60000) {
  return (detector.heard && now - detector.lastLoud >= silenceMs) || elapsed >= maxMs
}
