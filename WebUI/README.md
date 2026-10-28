# Prometh web

The browser half of Prometh: the Mac app's UI rebuilt as a web app, with real models running on the
visitor's own GPU through WebGPU. Live at https://prometh.leyten.dev (login required).

## What runs where

| Capability | Engine | Model | Size |
|---|---|---|---|
| Chat (Safe Mode) | WebLLM 0.2.84 | Qwen3.5 9B / 4B / 2B or Llama 3.2 1B, picked by a GPU-memory probe; q4f32 twins when the GPU lacks shader-f16 | 0.7 to 5 GB |
| Chat (Evil Mode) | WebLLM 0.2.84 | leyten's Heretic-decensored Qwen3.5 9B / 4B (same builds and libs as the c0mpute browser worker) | 2.4 or 5 GB |
| Voice | Transformers.js 4.3.1 + kokoro-js 1.2.1 | Whisper base or large-v3-turbo (listening), Kokoro 82M (speaking), Silero VAD v5 (turn-taking) | 0.5 to 1.1 GB |
| Images | ONNX Runtime Web (WebGPU) | Realistic Vision 6 + Hyper-SD 4-step at 512 px; opt-in Z-Image Turbo at 1024 px | 2.3 or 6.2 GB |
| Video | none | points to the Mac app | |

Everything runs client-side. The server only serves static files. Chat, Whisper, Kokoro and the
image-check models come from Hugging Face (model libs from mlc-ai's GitHub), straight into the
browser's Cache Storage. Chats live in localStorage, images in IndexedDB.

The image models and two small helpers are self-hosted under `/models/` (about 8 GB, not in git):

- `/models/rv-hyper-v1/`: Realistic Vision 6 with Hyper-SD merged, converted to ONNX fp16
- `/models/zimage/`: Z-Image Turbo, q4f16 ONNX, with an fp32-inside VAE (the fp16 one gave NaN)
- `/models/checks/`: Silero VAD v5 and the OpenCV YuNet face detector

For local dev, copy them into `public/models/` (ask leyten for the files).

WebLLM is pinned to 0.2.84 with c0mpute's one-line shape-cache patch (`patches/`, applied by
patch-package on install). 0.2.86 produced garbage output in testing where 0.2.84 answered correctly
(same model, same prompt, SwiftShader), so don't upgrade without re-running that check.

## Safety

A CSAM blocklist (same list as c0mpute) applies to chat output in every mode. Image prompts go through
a stricter gate (`prompt-gate.ts`), and every generated image is checked before it is shown
(`image-check.ts`: NSFW classifier, face detector, age estimate with a per-model threshold).

## Layout

- `src/engine/`: device probe (`device.ts`), model catalog and prompts (`catalog.ts`), preparation queue
  with pause/resume (`prep.ts`), WebLLM wrapper with our own resumable weight prefetch (`llm.ts`),
  speech, VAD and image workers (`*.worker.ts`, `media.ts`, `sd.ts`, `zimage.ts`), mic capture and
  playback (`audio.ts`, `public/mic-worklet.js`), turn-taking (`vad.ts`), image safety checks.
- `src/state/`: persisted store (`store.ts`) and all user actions (`actions.ts`).
- `src/ui/`: onboarding, workspace, settings (incl. the Turbo tensor-core tutorial), media, overlays.
- `test/`: prompt gate and turn-taking tests.

## Build

```sh
npm ci            # also copies the ONNX Runtime wasm into public/ort/
npm run dev       # local dev server
npm run build     # tsc + vite build -> dist/
npm test
```

## Testing without a GPU

Headless Chrome can run WebGPU on the CPU through SwiftShader
(`--enable-unsafe-webgpu --use-webgpu-adapter=swiftshader --enable-unsafe-swiftshader`). It has no
shader-f16, so it exercises the q4f32 path. Set `localStorage['prometh.maxBudgetMB'] = '1300'` to force
the 1B model.
