// Mic tap: resamples the input to 16 kHz mono and posts it in 512-sample frames (32 ms), the size Silero VAD uses.
class MicTap extends AudioWorkletProcessor {
  constructor() {
    super()
    this.ratio = sampleRate / 16000
    this.pos = 0 // fractional read position into [prev, ...block]
    this.prev = 0
    this.frame = new Float32Array(512)
    this.n = 0
  }
  process(inputs) {
    const ch = inputs[0] && inputs[0][0]
    if (!ch) return true
    // Linear interpolation over the previous block's last sample followed by this block.
    const len = ch.length + 1
    const at = (i) => (i === 0 ? this.prev : ch[i - 1])
    while (this.pos < len - 1) {
      const i = Math.floor(this.pos)
      const f = this.pos - i
      this.frame[this.n++] = at(i) * (1 - f) + at(i + 1) * f
      if (this.n === 512) {
        this.port.postMessage(this.frame.slice(0))
        this.n = 0
      }
      this.pos += this.ratio
    }
    this.pos -= len - 1
    this.prev = ch[ch.length - 1]
    return true
  }
}
registerProcessor('mic-tap', MicTap)
