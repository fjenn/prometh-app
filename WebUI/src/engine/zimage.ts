// Z-Image Turbo sampling for the image worker (Microsoft's webnn/Z-Image-Turbo q4f16 ONNX build): 8 flow-matching
// steps through its helper graphs (scheduler step, VAE pre-process), then the VAE decoder. Runtime-agnostic like
// sd.ts: the caller passes the sessions and a Tensor factory. All graph IO is float16, passed as raw bits.

import type { Session } from './sd'

export type MakeF16 = (bits: Uint16Array, dims: number[]) => unknown
export type MakeI64 = (data: BigInt64Array, dims: number[]) => unknown

export interface ZSessions {
  textEncoder: Session
  transformer: Session
  schedulerStep: Session
  vaePre: Session
  vae: Session
}

export const f32ToF16 = (v: number): number => {
  const u = new Uint32Array(new Float32Array([v]).buffer)[0]
  const s = (u >> 16) & 0x8000
  const e = ((u >> 23) & 0xff) - 127 + 15
  if (e <= 0) return s
  if (e >= 31) return s | 0x7c00
  return s | (e << 10) | ((u & 0x7fffff) >> 13)
}
export const f16ToF32 = (h: number): number => {
  const s = h & 0x8000 ? -1 : 1
  const e = (h >> 10) & 0x1f
  const m = h & 0x3ff
  if (e === 0) return s * m * 2 ** -24
  if (e === 31) return m ? NaN : s * Infinity
  return s * (1 + m / 1024) * 2 ** (e - 15)
}
const bits = (d: unknown) => (d instanceof Uint16Array ? d : new Uint16Array((d as Uint16Array).buffer, (d as Uint16Array).byteOffset, (d as Uint16Array).length))

/** The prompt in the chat template the text encoder was built for (Qwen3, generation prompt, thinking on). */
export const chatPrompt = (prompt: string) => `<|im_start|>user\n${prompt}<|im_end|>\n<|im_start|>assistant\n`

/** Transformer timesteps: flow-matching sigmas with shift 3, passed as (1000 - t) / 1000, last forced to 1 (demo scheduler.js). */
export function timesteps(steps: number): number[] {
  const shift = 3
  const sig = (s: number) => (shift * s) / (1 + (shift - 1) * s)
  const tMax = sig(1) * 1000
  const tMin = sig(1 / 1000) * 1000
  const out = Array.from({ length: steps }, (_, i) => {
    const s = sig((tMax + ((tMin - tMax) * i) / Math.max(1, steps - 1)) / 1000)
    return (1000 - s * 1000) / 1000
  })
  out[steps - 1] = 1
  return out
}

/** Seeded standard normal noise as float16 bits (mulberry32 + Box-Muller). */
function noise(n: number, seed: number): Uint16Array {
  let s = seed >>> 0
  const rand = () => {
    s = (s + 0x6d2b79f5) >>> 0
    let t = s
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  const out = new Uint16Array(n)
  for (let i = 0; i < n; i += 2) {
    const r = Math.sqrt(-2 * Math.log(rand() || 1e-12))
    const a = 2 * Math.PI * rand()
    out[i] = f32ToF16(r * Math.cos(a))
    if (i + 1 < n) out[i + 1] = f32ToF16(r * Math.sin(a))
  }
  return out
}

/** Token ids -> image as CHW floats in [-1, 1]. onStep counts finished passes out of steps + 1 (the last is the VAE). */
export async function generate(
  s: ZSessions,
  f16: MakeF16,
  i64: MakeI64,
  ids: number[],
  opts: { size: number; steps: number; seed: number; onStep?: (done: number, total: number) => void },
): Promise<Float32Array> {
  const { size, steps } = opts
  const L = size / 8
  const dims = [1, 16, L, L]
  const total = steps + 1
  const n = ids.length
  const enc = await s.textEncoder.run({ input_ids: i64(BigInt64Array.from(ids, BigInt), [1, n]), attention_mask: i64(new BigInt64Array(n).fill(1n), [1, n]) })
  const emb = enc.encoder_hidden_states
  const ts = timesteps(steps)
  let x = noise(16 * L * L, opts.seed)
  try {
    for (let i = 0; i < steps; i++) {
      const v = (await s.transformer.run({ hidden_states: f16(x, dims), encoder_hidden_states: emb, timestep: f16(Uint16Array.of(f32ToF16(ts[i])), [1]) })).sample
      const next = (await s.schedulerStep.run({ noise_pred: v, latents: f16(x, dims), step_info: f16(Uint16Array.of(f32ToF16(i), f32ToF16(steps)), [2]) })).latents_out
      x = new Uint16Array(bits(await next.getData()))
      v.dispose?.()
      next.dispose?.()
      opts.onStep?.(i + 1, total)
    }
  } finally {
    emb.dispose?.()
  }
  const pre = (await s.vaePre.run({ latents: f16(x, dims) })).scaled_latents
  const out = (await s.vae.run({ latent_sample: pre })).sample
  const px = bits(await out.getData())
  pre.dispose?.()
  out.dispose?.()
  opts.onStep?.(total, total)
  return Float32Array.from(px, f16ToF32)
}
