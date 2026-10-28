// Stable Diffusion 1.5 sampling for the image worker: 4-step Euler on "trailing" timesteps, no CFG
// (Realistic Vision + Hyper-SD 4-step LoRA). Runtime-agnostic: the caller passes the ONNX sessions and the
// Tensor class, so the same code runs in the browser (onnxruntime-web) and in Node tests (onnxruntime-node).

export interface Tensor {
  getData(): Promise<unknown>
  dispose?(): void
}
export interface Session {
  run(feeds: Record<string, unknown>): Promise<Record<string, Tensor>>
}
export type MakeTensor = (type: 'float32' | 'int64', data: Float32Array | BigInt64Array, dims: number[]) => unknown

export const SIZE = 512
const LATENT = SIZE / 8
const VAE_SCALE = 0.18215

// SD 1.5 noise schedule: scaled_linear betas 0.00085 -> 0.012 over 1000 steps.
const alphasCumprod = (() => {
  const ac = new Float64Array(1000)
  let p = 1
  for (let i = 0; i < 1000; i++) {
    const b = (Math.sqrt(0.00085) + ((Math.sqrt(0.012) - Math.sqrt(0.00085)) * i) / 999) ** 2
    ac[i] = p *= 1 - b
  }
  return ac
})()
const sigmaAt = (t: number) => Math.sqrt((1 - alphasCumprod[t]) / alphasCumprod[t])

/** Trailing spacing, as Hyper-SD asks for: 4 steps -> 999, 749, 499, 249. */
export function timesteps(steps: number): number[] {
  return Array.from({ length: steps }, (_, i) => Math.round(1000 - (i * 1000) / steps) - 1)
}

/** Seeded standard normal noise (mulberry32 + Box-Muller), so a seed reproduces an image. */
export function randn(n: number, seed: number): Float32Array {
  let s = seed >>> 0
  const rand = () => {
    s = (s + 0x6d2b79f5) >>> 0
    let t = s
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  const out = new Float32Array(n)
  for (let i = 0; i < n; i += 2) {
    const r = Math.sqrt(-2 * Math.log(rand() || 1e-12))
    const a = 2 * Math.PI * rand()
    out[i] = r * Math.cos(a)
    if (i + 1 < n) out[i + 1] = r * Math.sin(a)
  }
  return out
}

export interface Sessions {
  textEncoder: Session
  unet: Session
  vae: Session
}

/**
 * Text ids (77, padded with 49407) -> image as CHW floats in [-1, 1].
 * onStep reports finished network passes out of steps + 1 (the last one is the VAE).
 */
export async function generate(s: Sessions, tensor: MakeTensor, ids: number[], opts: { steps: number; seed: number; onStep?: (done: number, total: number) => void; cancelled?: () => boolean }): Promise<Float32Array> {
  const { steps, seed } = opts
  const total = steps + 1
  const enc = await s.textEncoder.run({ input_ids: tensor('int64', BigInt64Array.from(ids, BigInt), [1, ids.length]) })
  const emb = enc.last_hidden_state
  for (const [k, t] of Object.entries(enc)) if (k !== 'last_hidden_state') t.dispose?.()

  const ts = timesteps(steps)
  const sigmas = [...ts.map(sigmaAt), 0]
  const n = 4 * LATENT * LATENT
  const x = randn(n, seed)
  for (let i = 0; i < n; i++) x[i] *= sigmas[0] // init_noise_sigma for trailing spacing = sigma_max
  try {
    for (let i = 0; i < ts.length; i++) {
      if (opts.cancelled?.()) throw new Error('Cancelled')
      const sigma = sigmas[i]
      const scale = 1 / Math.sqrt(sigma * sigma + 1)
      const input = new Float32Array(n)
      for (let j = 0; j < n; j++) input[j] = x[j] * scale
      const out = await s.unet.run({
        sample: tensor('float32', input, [1, 4, LATENT, LATENT]),
        timestep: tensor('float32', Float32Array.of(ts[i]), []),
        encoder_hidden_states: emb,
      })
      const eps = (await out.out_sample.getData()) as Float32Array
      out.out_sample.dispose?.()
      // Euler: dx/dsigma = eps for an epsilon-prediction model.
      const dt = sigmas[i + 1] - sigma
      for (let j = 0; j < n; j++) x[j] += eps[j] * dt
      opts.onStep?.(i + 1, total)
    }
  } finally {
    emb.dispose?.()
  }
  for (let i = 0; i < n; i++) x[i] /= VAE_SCALE
  const dec = await s.vae.run({ latent_sample: tensor('float32', x, [1, 4, LATENT, LATENT]) })
  const img = (await dec.sample.getData()) as Float32Array
  dec.sample.dispose?.()
  opts.onStep?.(total, total)
  return img
}

/** CHW [-1, 1] -> RGBA bytes. Throws on NaN, which fp16 overflow produces as a black image otherwise. */
export function toRGBA(chw: Float32Array, w = SIZE, h = SIZE): Uint8ClampedArray<ArrayBuffer> {
  const px = w * h
  const out = new Uint8ClampedArray(px * 4)
  for (let i = 0; i < px; i++) {
    for (let c = 0; c < 3; c++) {
      const v = chw[c * px + i]
      if (Number.isNaN(v)) throw new Error('The image model produced an invalid image.')
      out[i * 4 + c] = Math.round((v / 2 + 0.5) * 255)
    }
    out[i * 4 + 3] = 255
  }
  return out
}
