# Media tier measurements — 2026-10-27 night fix

Host: Apple M5 Max, 128 GB unified memory. Original Nativ.app and Prometh.app were quit before generation. Timed generations were serialized. Every timed run starts a fresh Python process; video runs disable prompt-embedding caches (`--no-prompt-cache`). OS file caches were not purged. Model revisions and generation geometry are unchanged.

## Measurement and picker policy

- Real full-run peak = max(`/usr/bin/time -l` max RSS, peak memory footprint, exact sampled `phys_footprint`/`phys_footprint_peak`, MLX peak). Includes uncached text encoding, loading, denoise, VAE decode, export and RIFE. No denoise-plateau exception.
- `workingMemoryGB = ceil(full-run peak GiB × 1.10 × 2) / 2` (10% margin, rounded upward to 0.5 GiB).
- Picker retains its policy: `workingMemoryGB × 1.08 ≤ RAM × 0.75 − 1`, with `residentGB=0` after chat unload. Minimum RAM below means automatic best-first selection with sufficient disk.
- `timed_run.sh` now requests footprint bytes. The first 1.3B run has old rounded samples (e.g. 14 GB); its exact `time -l` peak is used rather than treating rounded samples as more precise.
- Reproduce: `python3 run_video_fix.py <video|video-5b|video-14b> <run>`; `bash run_images_fix.sh <images|images-9b> <run>`; `python3 summarize_fix.py`. These scripts live beside this file.

## Final catalog table

| Model id | Real full-run peak GiB | workingMemoryGB | Minimum Mac RAM that gets it |
|---|---:|---:|---|
| `images` | 5.187 | 6.0 | 16 GB |
| `images-9b` | 11.956 | 13.5 | 24 GB |
| `video` | 13.605 | 15.0 | 24 GB |
| `video-5b` | 15.607 | 17.5 | 32 GB |
| `video-14b` | 22.670 | 25.0 | 48 GB |

These are measured process peaks on this 128 GB host and budget-based eligibility, not certification on each physical Mac RAM size. The 5B model now auto-picks on **32 and 36 GB** Macs. Uncached 1.3B encoding requires **24 GB** under this policy; the previous 16 GB eligibility based on its denoise plateau was incorrect.

## Two complete runs per shipped tier

| Model | Run label | Max RSS GiB | Peak footprint GiB | Exact sampled peak GiB | Full-run decision GiB |
|---|---|---:|---:|---:|---:|
| `images` | `images-timed1-fix` | 2.690 | 5.160 | 5.153 | 5.160 |
| `images` | `images-timed2-fix` | 2.692 | 5.187 | 5.180 | 5.187 |
| `images-9b` | `images-9b-timed1-fix` | 9.638 | 11.930 | 11.240 | 11.930 |
| `images-9b` | `images-9b-timed2-fix` | 9.639 | 11.956 | 11.950 | 11.956 |
| `video` | `video-timed1-fix` | 3.104 | 13.605 | rounded; excluded | 13.605 |
| `video` | `video-timed2-fix` | 3.025 | 13.605 | 13.605 | 13.605 |
| `video-5b` | `video-5b-timed3-fix` | 5.930 | 15.605 | 15.605 | 15.605 |
| `video-5b` | `video-5b-timed4-fix` | 5.928 | 15.607 | 15.607 | 15.607 |
| `video-14b` | `video-14b-timed1-fix` | 15.188 | 22.634 | 22.634 | 22.634 |
| `video-14b` | `video-14b-timed2-fix` | 15.189 | 22.670 | 22.670 | 22.670 |

Exact values and run/artifact associations: `full-run-summary-fix.json`. Raw `.time.txt`, `.footprint.txt`, `.log` and `.summary.log` files retain the complete timed runs. All final run exits are zero.

## Loading and decode changes

- `PromethRuntime/media/bounded_video.py` is a tracked adapter around the unchanged pinned FastVideo checkout (`8db2d71ef217e84bec7dbb6e4ab65c92b144df4f`). `media_worker` uses it for both Wan pipelines. Packed quantized DiT arrays still load directly through MLX; no full fp32 DiT conversion or copied weight dictionary is introduced.
- UMT5 uses direct-device shard loading in its requested bf16/fp16 inference dtype. Hugging Face safety-required fp32 submodules remain intact. Encoder weights and intermediates are freed before DiT load. The 5B command now selects `--text-encoder-device auto` (MPS on this Mac), rather than its upstream CPU default. `requirements-prometh.txt` pins Accelerate 1.15.0 because FastVideo's 1.0.1 pin is rejected by its Transformers 5.15 direct-device loader.
- 1.3B and 14B keep the full Wan VAE: fp16, overlapping 256px spatial tiles (192px stride), one latent frame at a time, persistent causal feature caches within each tile, completed RGB chunks transferred to CPU immediately. Live decode footprint stayed around 3–4 GiB; the full-run peak is now encoding/denoise rather than runaway decode.
- 5B keeps MLX TAEHV: fp16 weights/activations, one latent frame per decode call, persistent MemBlock state, 16px latent spatial cores plus 20px halo. No temporal history reset at chunk boundaries.
- MLX allocator cache is capped at 256 MiB. MLX and MPS are synchronized and caches cleared between encoding, loading and decode; the pinned entrypoints delete DiT/transformer weights before decode.

## Cold-load experiments and historical comparison

- Before this fix, 1.3B full VAE decode reached **113.086 GiB**. The old 5.35 GiB denoise-only picker estimate is retired. Final cold full-run maximum is **13.605 GiB**.
- Before this fix, 5B cold full-run footprint reached **24.533 GiB** (`workingMemoryGB=27`, so 48 GB eligibility).
- New adapter with the upstream **CPU** encoder still had max RSS **23.947 GiB**, despite only **13.202 GiB** peak footprint. These experiments are retained as `video-5b-timed1-fix` / `timed2-fix`, with real clips and frames. They are excluded from the final configuration table because production now encodes on MPS.
- Final **MPS** encoder runs are `video-5b-timed3-fix` / `timed4-fix`: full-run peaks **15.605 / 15.607 GiB**, max RSS **5.930 / 5.928 GiB**. This fits the 32 GB picker budget with both margins.
- OpenWhispr started a background model during the first 1.3B run and was temporarily quit; the repeat produced the same 13.605 GiB process peak. Original Nativ.app remained quit for live runs.
- `video-load-attempt-fix.*` records the initial Accelerate compatibility failure; no artifact or fabricated successful measurement was assigned to it.

## Output and numerical validation

All eight new clips (including the two CPU-encoder experiments) have extracted `*-frame-fix.png` files. Every PNG was manually inspected: coherent beach/ocean imagery, not black or garbage. ffmpeg decoded every complete clip without errors. `artifact-validation-fix.json` records hashes, frame counts, dimensions, FPS, silence, and PNG statistics: 1.3B/14B = 832×480, 81 frames, 16 fps; 5B = 832×448, 121 frames, 24 fps. All four new FLUX PNGs were also inspected and look correct.

`test_bounded_video.py` checks causal streaming against the original parallel decoder for both 16/48-channel latents: strict fp32 comparison without spatial splitting, and <0.003 average RGB error for spatial tiling (including seams) and fp16 against the original fp32 reference. MLX convolution shape changes introduce small numerical differences, so pointwise equality across spatial shapes is not assumed. Final combined Python suite: **10 passed** (`python-tests-final-fix.log`). Early numerical/fixture test attempts remain in separate attempt logs.

## Picker matrix

| Mac RAM | Photo | Video |
|---:|---|---|
| 8 GB | unavailable | unavailable |
| 16 GB | images | unavailable |
| 24 GB | images-9b | video |
| 32 GB | images-9b | video-5b |
| 36 GB | images-9b | video-5b |
| 48 GB | images-9b | video-14b |
| 64 GB | images-9b | video-14b |
| 128 GB | images-9b | video-14b |

Unit tests assert this complete matrix and ensure every media catalog value covers its measured full-run peak plus 10%, with upward 0.5 GiB rounding. zimage remains disabled/unmeasured. Final build/test gate results are recorded in PARITY-CODEX.md and `*-final-fix.log` / `xcode-tests-fix.log`.
