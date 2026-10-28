// Serve the ONNX Runtime wasm from our own origin instead of a CDN (copied to public/ort/ by npm install).
import { env } from '@huggingface/transformers'

env.backends.onnx.wasm!.wasmPaths = {
  mjs: '/ort/ort-wasm-simd-threaded.asyncify.mjs',
  wasm: '/ort/ort-wasm-simd-threaded.asyncify.wasm',
}
