import * as ort from 'onnxruntime-web/webgpu'
import { pipeline, RawImage, type ImageClassificationPipeline } from '@huggingface/transformers'
import { detectFaces, faceCropBox } from './face'

// Output checks on every generated image, before it is shown or saved (research/H_image_csam_guard.md,
// thresholds from research/H_output_check_calibration.md). Any image that might be sexual gets an age
// check on every usable face, in both modes; Safe Mode also blocks nudity. Fail closed: if the checks
// can't load, image generation fails instead of skipping them.

export type Mode = 'safe' | 'evil'
export type Blocked = 'nsfw' | 'minor'

const NSFW_MODEL = 'onnx-community/nsfw_image_detection-ONNX' // Falconsai, Apache-2.0
const AGE_MODEL = 'onnx-community/fairface_age_image_detection-ONNX' // dima806 FairFace, Apache-2.0
const YUNET = '/models/checks/yunet-2023mar.onnx' // OpenCV YuNet face detector, MIT

const SAFE_MODE_NSFW = 0.5
/** Calibration: our own clothed adult images scored at most 0.21, so checking ages from 0.2 costs little. */
const AGE_CHECK_NSFW = 0.2
/** Faces smaller than this read as adults whatever their age. */
const MIN_FACE_PX = 32
/**
 * Block when P(0-2) + P(3-9) + P(10-19) reaches this, per image model. SD 1.5: adults up to 0.66, children from 0.76.
 * Z-Image: no clean gap; 0.5 caught one more child and no more adults than 0.6 (calibration doc, Z-Image section).
 */
const UNDER_20 = { sd15: 0.6, zimage: 0.5 }

let checks: Promise<{ nsfw: ImageClassificationPipeline; age: ImageClassificationPipeline; faces: ort.InferenceSession }> | null = null

export function loadChecks() {
  checks ??= (async () => {
    const nsfw = (await pipeline('image-classification', NSFW_MODEL, { device: 'webgpu', dtype: 'q4f16' })) as ImageClassificationPipeline
    const age = (await pipeline('image-classification', AGE_MODEL, { device: 'webgpu', dtype: 'q4f16' })) as ImageClassificationPipeline
    const r = await fetch(YUNET)
    if (!r.ok) throw new Error(`Image safety check unavailable (HTTP ${r.status}).`)
    const faces = await ort.InferenceSession.create(new Uint8Array(await r.arrayBuffer()), { executionProviders: ['wasm'] })
    return { nsfw, age, faces }
  })()
  checks.catch(() => (checks = null))
  return checks
}

type Scores = { label: string; score: number }[]

export async function checkImage(rgba: Uint8ClampedArray, w: number, h: number, mode: Mode, engine: keyof typeof UNDER_20): Promise<Blocked | null> {
  if (!checks) throw new Error('The image safety check isn’t loaded.')
  const { nsfw, age, faces } = await checks
  const rgb = new RawImage(rgba.slice(), w, h, 4).rgb()
  const nsfwScore = ((await nsfw(rgb, { top_k: 2 })) as Scores).find((o) => o.label === 'nsfw')?.score ?? 0
  if (nsfwScore >= AGE_CHECK_NSFW) {
    for (const f of await detectFaces(faces, ort.Tensor, rgba, w, h)) {
      if (Math.min(f.w, f.h) < MIN_FACE_PX) continue
      const scores = (await age(await rgb.crop(faceCropBox(f, w, h, 2)), { top_k: null })) as Scores
      const young = scores.filter((s) => ['0-2', '3-9', '10-19'].includes(s.label)).reduce((a, s) => a + s.score, 0)
      if (young >= UNDER_20[engine]) return 'minor'
    }
  }
  if (mode === 'safe' && nsfwScore >= SAFE_MODE_NSFW) return 'nsfw'
  return null
}
