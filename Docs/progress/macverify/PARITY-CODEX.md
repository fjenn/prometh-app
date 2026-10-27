# PARITY-CODEX — Prometh Mac ↔ web parity (2026-10-27)

Host: Apple M5 Max, 128 GB unified memory. Branch `prometh` only. Hard rules: no force-push, no `composio.env` printing, no fake verification, PromethUITests skipped (Automation Mode needs owner password).

## Commits (this parity pass)

| Section | Commit | Summary |
|---|---|---|
| B (voice, earlier) | `3c23bd91`, `0da22341` | Live mic → turns; Kokoro + Silero VAD |
| E | `f2ba77a2` | Inline ChatGPT-style message edit |
| A | `d098b4e7` | Qwen3.5 picker by RAM; migrate off Gemma |
| D | `41af612a` | Connectors Waiting + OAuth failure surfacing |
| F | `1407d110` | CSAM blocklist + warm/Evil/VOICE prompt merge |
| C | `448eebb1` | FLUX 9B + FastMetal 14B media tiering |
| B (Release evidence) | `af28d9cd` | Release live mic + barge-in in `VOICE-LIVE.md` |

## A — Chat model picker

- Best-first Safe: `safe-qwen9b` → `4b` → `2b` → `safe-llama1b`. Gemma (`safe`) remains a **manual** option only.
- Evil: `filvyb/Qwen3.5-9B-heretic-v2-GGUF` (9B) + `darrellbest/Qwen3.5-4B-Heretic-GGUF` (4B). Leyten MLC WebGPU builds are not loadable here.
- Budget: `RAM * 0.75 − 1 GiB − residents`; fit if `workingMemoryGB * 1.08 ≤ budget`.
- Migration: existing installs still on Gemma are re-pinned to the picked Qwen before server start.
- Live on this Mac: search-with-citations and image tool on `mlx-community/Qwen3.5-9B-4bit`.
- Tests: `ModelPickerTests` at 8/16/24/36/64/128 GB.

## B — Voice

- Listening: Whisper large-v3-turbo (base on small Macs). Speaking: Kokoro 82M (`af_heart`); Pocket hidden.
- Turn-taking: Silero VAD v5 ONNX, ~700 ms silence; standby capture + echo gate for barge-in.
- Debug live: Paris turn (see earlier `VOICE-LIVE.md`).
- **Release live (required follow-up):** New chat → Voice → speaker `afplay` into mic. Transcript **“What is the capital of France? Please answer briefly.”** → **“The capital of France is Paris.”** Kokoro played. Barge-in log `voice Silero barge-in` while speaking; follow-up **“Stop speaking. Interrupt.”** Evidence: `VOICE-LIVE.md`, `parity-B-release-voice2.png`.

## C — Images / video tiering

- Images best-first: `images-9b` (FLUX.2 Klein 9B 8-bit) → `images` (4B 4-bit).
- Video best-first: `video-14b` (FastMetal 14B) → `video` (1.3B). Catalog skips duplicate `ema/` DiT.
- Live on this Mac: `/images/generations` with `mlx-community/flux2-klein-9b-8bit` → `parity-c-image9b.png`. FastMetal 14B clip → `parity-c-video-14b.mp4` (~247 s, peak denoise ~21.7 GiB). 1.3B sample retained as fallback evidence.
- `media_worker` prefers 14B when folder complete; falls back to 1.3B.

## D — Connectors

- Connect opens Composio OAuth in the default browser; UI shows **Waiting for sign-in…**; polls until Connected or surfaces errors (never silent).
- Owner completes Google/GitHub sign-in himself.
- **Owner 3-line test:** (1) Settings → Connectors → Connect Gmail. (2) Finish Google OAuth in the browser. (3) Chat: “list my 3 latest emails” and confirm a tool call + answer.

## E — Inline edit

- Edit turns the user bubble into an in-place multiline field with Cancel / Send (Esc / ⌘↩). Popup removed from the Prometh chat UI.

## F — Safety / prompts

- Web CSAM `BLOCKED` / `BLOCKED_MESSAGE` on input, streaming output, and image/video prompts; unit tests.
- Warm persona prepended; Evil SYSTEM_EVIL bullets (no `[[image:]]`); VOICE_HINT for spoken replies.

## Gates

Per section: `scripts/prometh/build.sh`, `make verify`, `xcodebuild test -scheme Prometh -only-testing:PromethTests` — all green (76 PromethTests, 0 failures on final B pass). PromethUITests skipped.

## Judges package

- `~/Desktop/Prometh-judges/Prometh.zip` — Release ad-hoc signed `Prometh.app`.
- `~/Desktop/Prometh-judges/JUDGES.md` — updated for picker, Kokoro/Silero, connectors, inline edit.

## Not verified / owner follow-up

- Composio Connected → live “list my emails” after the owner signs in (OAuth up to the browser verified).
- PromethUITests (Automation Mode password).
- 16 GB hardware certification still pending as product copy notes.

## Media tiers (2026-10-27 evening)

Measured on M5 Max 128 GB with chat unloaded (no llama-server / mlx-vlm-server). One media job at a time. Formula: `workingMemoryGB = round_up_to_0.5(decision_peak × 1.10)`; 8 GB budget with `residentGB=0` is 5.0 GiB; qualifies iff `peak × 1.08 ≤ 5.0`.

| Family | Model id | Measured peaks (GiB) | Method | workingMemoryGB | Min Mac RAM that auto-picks it |
|---|---|---|---|---|---|
| images | `images` FLUX.2 Klein 4B 4-bit | timed1 FP 5.186 / RSS 2.691; timed2 FP 5.185 | `/usr/bin/time -l` + `footprint -p` on `mlx_vlm.generate` 512×512 / 4 steps | **6.0** | 16 GB (8 GB: no) |
| images | `images-9b` | (prior) | catalog | 14 | 24 GB |
| video | `video` FastMetal 1.3B | denoise plateau phys ~5.35; MLX denoise 3.87; full-run FP **113** (wan-vae decode balloon, logged not used for WM) | timed1/2 `mlx_wan_prompt_to_video` 832×480 / 81f | **6.0** | 16 GB (8 GB: no) |
| video | `video-5b` FastMetal 5B QAD | cold FP 24.533 / RSS 23.946; warm timed1/2 FP 21.214; MLX denoise 6.85 | `mlx_wan22_generate --fast` 832×448 / 121f taehv | **27.0** | Enabled; auto-pick only when 14B does not fit / is unavailable (best-first after 14B) |
| video | `video-14b` | (prior ~21.7 denoise) | catalog | 28 | 48 GB |

**8 GB Macs get neither photo nor video** (images 5.186×1.08=5.60 > 5.0; video plateau 5.35×1.08=5.78 > 5.0). Chat unload before media: `PromethMediaGate` (+ image gate) stops Evil llama and POSTs `/unload`; picks use `residentGB=0`.

**5B status:** enabled. Clip `Docs/progress/macverify/media-tiers/video-5b-timed1.mp4`; frame `video-5b-frame.png`; also `video-5b-via-worker.mp4` via `media_worker.Worker.generate`. Raw logs under `Docs/progress/macverify/media-tiers/*.log` and `MEASUREMENTS.md`.

**Commands:** see `run_images_4b.sh`, `run_video_1.3b.sh` / `timed_run.sh`, `run_video_5b.sh`.

**Commits:** `f9de3a11` feat(video) 5B mid tier; `92793ef7` measured peaks + picker matrix. Gates: `build.sh` OK, `make verify` OK, PromethTests **76** passed (`CODE_SIGNING_ALLOWED=NO`). PromethUITests skipped (Automation Mode). zimage not installed — not measured. Unverified: in-app UI click path for 5B (worker path verified).
