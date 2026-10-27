# Media tier measurements (2026-10-27 evening)

Host: Apple M5 Max, 128 GB. Chat unloaded (`pgrep` showed no llama-server / mlx-vlm-server / nativ_server). One generation at a time.

## Formula

- Decision peak GiB = max(time `-l` peak memory footprint, time `-l` max RSS, sampled `phys_footprint` max, MLX denoise/peak GiB).
- For FastMetal 1.3B only: full-run peak footprint balloons to ~113 GiB during wan-vae decode after denoise. Picker `workingMemoryGB` uses the denoise-plateau sampled phys_footprint (~5.35 GiB) so the catalog stays usable; 8 GB eligibility still fails on that plateau (`5.35 × 1.08 = 5.78 > 5.0`). Full balloon is recorded below.
- `workingMemoryGB = round_up_to_0.5(decision_peak × 1.10)`.
- 8 GB Mac budget with `residentGB=0`: `8×0.75−1 = 5.0` GiB. Qualifies iff `decision_peak × 1.08 ≤ 5.0` (peak ≤ ~4.63 GiB).

## images — FLUX.2 Klein 4B mflux 4-bit (`Runpod/FLUX.2-klein-4B-mflux-4bit`)

Command: bundled `python -m mlx_vlm.generate --output-modality image --task generate --size 512x512 --steps 4 --seed 1024` (app defaults).

| Run | max RSS GiB | peak footprint GiB | sampled phys max GiB | artifact |
|---|---|---|---|---|
| timed1 | 2.691 | 5.186 | 5.179 | `images-4b-run1.png` |
| timed2 | 2.691 | 5.185 | 5.180 | `images-4b-run2.png` |

- Decision peak: **5.186 GiB**
- `workingMemoryGB`: round_up_0.5(5.186×1.10)=**6.0**
- 8 GB: 5.186×1.08=5.601 > 5.0 → **no photo on 8 GB**

## video — FastMetal 1.3B QAD

Command: `mlx_wan_prompt_to_video.py` 832×480, 81 frames, wan-vae, seed 1024 (media_worker defaults).

| Run | max RSS GiB | peak footprint GiB | MLX denoise GiB | denoise-plateau phys GiB |
|---|---|---|---|---|
| timed1 | 2.100 | 113.086 | 3.87 | ~5.35 (stable samples before decode climb) |
| timed2 | 2.100 | 113.086 | 3.87 | ~5.35 |

- Picker decision peak (denoise plateau): **5.35 GiB** → `workingMemoryGB` **6.0**
- Full-run peak footprint **113 GiB** (wan-vae decode balloon) — recorded, not used as WM
- 8 GB: 5.35×1.08=5.78 > 5.0 → **no video on 8 GB**

## video-5b — FastMetal 5B QAD (Wan2.2 TI2V)

Command: `mlx_wan22_generate.py --fast` 832×448, 121 frames, taehv, seed 1024.

| Run | max RSS GiB | peak footprint GiB | MLX denoise / peak_gib | notes |
|---|---|---|---|---|
| cold-fail1 | 23.946 | 24.533 | 6.85 | denoise OK; RIFE blocked by HF_HUB_OFFLINE |
| timed1 | 5.532 | 21.214 | 6.85 / 6.848 | success → `video-5b-timed1.mp4` |
| timed2 | 5.532 | 21.214 | (warm) | success → `video-5b-timed2.mp4` |

- Decision peak: **24.533 GiB** (cold first load)
- `workingMemoryGB`: round_up_0.5(24.533×1.10)=**27.0**
- enabled=true (CLI + `media_worker.Worker.generate` E2E OK)
- Clip: `Docs/progress/macverify/media-tiers/video-5b-timed1.mp4` (~955 KB)
- Frame: `Docs/progress/macverify/media-tiers/video-5b-frame.png`
- Also: `video-5b-via-worker.mp4` / `.png` via Prometh media_worker

## zimage

Not installed on this Mac; not measured; remains disabled.

## Chat unload

`PromethMediaGate.unloadChatEngines` stops llama.cpp and POSTs `/unload` to mlx-vlm before image/video. `configureModelSelections` picks images/video with `residentGB=0`. Measurement runs confirmed no chat servers via `pgrep`.
