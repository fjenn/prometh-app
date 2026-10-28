// YuNet (opencv_zoo face_detection_yunet_2023mar.onnx, MIT, 232,589 bytes) pre/post-processing.
// Works with onnxruntime-web or onnxruntime-node: pass the ort module's Tensor class and a session.
// Port of OpenCV's FaceDetectorYN (modules/objdetect/src/face_detect.cpp, 2023mar output layout).

export const YUNET_SIZE = 640 // the ONNX input is fixed at 1x3x640x640
const STRIDES = [8, 16, 32]

export interface Face { x: number; y: number; w: number; h: number; score: number; kps: number[] } // kps: 5 (x,y) pairs, image coords

interface OrtTensor { data: unknown }
interface OrtSession { run(feeds: Record<string, unknown>): Promise<Record<string, OrtTensor>> }
type TensorCtor = new (type: 'float32', data: Float32Array, dims: number[]) => unknown

/** RGBA (any square-ish size) -> 1x3x640x640 float32, BGR order, raw 0..255, no mean/std. Bilinear resize. */
export function yunetInput(rgba: Uint8ClampedArray | Uint8Array, w: number, h: number): Float32Array {
  const S = YUNET_SIZE
  const out = new Float32Array(3 * S * S)
  const sx = w / S, sy = h / S
  for (let y = 0; y < S; y++) {
    const fy = Math.max(0, (y + 0.5) * sy - 0.5), y0 = Math.floor(fy), y1 = Math.min(h - 1, y0 + 1), ay = fy - y0
    for (let x = 0; x < S; x++) {
      const fx = Math.max(0, (x + 0.5) * sx - 0.5), x0 = Math.floor(fx), x1 = Math.min(w - 1, x0 + 1), ax = fx - x0
      for (let c = 0; c < 3; c++) {
        const p = (yy: number, xx: number) => rgba[(yy * w + xx) * 4 + c]
        const v = (p(y0, x0) * (1 - ax) + p(y0, x1) * ax) * (1 - ay) + (p(y1, x0) * (1 - ax) + p(y1, x1) * ax) * ay
        out[(2 - c) * S * S + y * S + x] = v // RGB -> BGR planes
      }
    }
  }
  return out
}

const iou = (a: Face, b: Face) => {
  const ix = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x))
  const iy = Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y))
  const inter = ix * iy
  return inter / (a.w * a.h + b.w * b.h - inter)
}

/** Decode the 12 YuNet outputs, threshold, greedy NMS, and map back to the w x h source image. */
export function yunetDecode(o: Record<string, OrtTensor>, w: number, h: number, scoreThr = 0.6, nmsThr = 0.3): Face[] {
  const S = YUNET_SIZE
  const cand: Face[] = []
  for (const s of STRIDES) {
    const cols = S / s, rows = S / s
    const cls = o[`cls_${s}`].data as Float32Array, obj = o[`obj_${s}`].data as Float32Array
    const box = o[`bbox_${s}`].data as Float32Array, kps = o[`kps_${s}`].data as Float32Array
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      const i = r * cols + c
      const score = Math.sqrt(Math.min(1, Math.max(0, cls[i])) * Math.min(1, Math.max(0, obj[i])))
      if (score < scoreThr) continue
      const cx = (c + box[i * 4]) * s, cy = (r + box[i * 4 + 1]) * s
      const bw = Math.exp(box[i * 4 + 2]) * s, bh = Math.exp(box[i * 4 + 3]) * s
      const k: number[] = []
      for (let n = 0; n < 5; n++) k.push(((kps[i * 10 + 2 * n] + c) * s * w) / S, ((kps[i * 10 + 2 * n + 1] + r) * s * h) / S)
      cand.push({ x: ((cx - bw / 2) * w) / S, y: ((cy - bh / 2) * h) / S, w: (bw * w) / S, h: (bh * h) / S, score, kps: k })
    }
  }
  cand.sort((a, b) => b.score - a.score)
  const keep: Face[] = []
  for (const f of cand) if (keep.every((k) => iou(k, f) <= nmsThr)) keep.push(f)
  return keep
}

export async function detectFaces(session: OrtSession, Tensor: TensorCtor, rgba: Uint8ClampedArray | Uint8Array, w: number, h: number, scoreThr = 0.6): Promise<Face[]> {
  const out = await session.run({ input: new Tensor('float32', yunetInput(rgba, w, h), [1, 3, YUNET_SIZE, YUNET_SIZE]) })
  return yunetDecode(out, w, h, scoreThr)
}

/** Square crop around the face box, side = scale * max(w, h), clamped to the image. Returns [x1, y1, x2, y2]. */
export function faceCropBox(f: Face, w: number, h: number, scale = 1.5): [number, number, number, number] {
  const side = scale * Math.max(f.w, f.h), cx = f.x + f.w / 2, cy = f.y + f.h / 2
  const x1 = Math.max(0, Math.round(cx - side / 2)), y1 = Math.max(0, Math.round(cy - side / 2))
  return [x1, y1, Math.min(w - 1, Math.round(cx + side / 2)), Math.min(h - 1, Math.round(cy + side / 2))]
}
