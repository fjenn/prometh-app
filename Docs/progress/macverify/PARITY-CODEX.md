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

## Media tiers fix (2026-10-27 night)

This section supersedes the evening media estimates above. Every decision uses a complete cold-process generation, including encoder loading, denoise, VAE decode, export and RIFE; the 1.3B denoise-plateau exception is removed.

**Code commit:** `466986bea79e53ec37670b262f3e8357f66926da` (`fix(media): bound VAE decode and measure cold memory tiers`).

- Tracked `bounded_video.py` adapts the unchanged pinned FastVideo checkout. Full Wan VAE (1.3B/14B): fp16, 256px spatial tiles / 192px stride, one latent frame with causal caches, RGB chunks moved to CPU. MLX TAEHV (5B): fp16, one latent frame, persistent MemBlock state, 16px latent cores / 20px halo.
- Direct-device bf16/fp16 encoder loading avoids a complete upcast/duplicate model. 5B now encodes on MPS, releasing the encoder before packed quantized DiT loading. Both pipelines free the transformer before decode, cap MLX cache at 256 MiB, and synchronize/clear MLX and MPS caches between stages. Accelerate 1.15.0 compatibility override is recorded in `requirements-prometh.txt`.
- Two complete timed runs for every shipped media tier. Final 5B runs are `video-5b-timed3-fix` / `timed4-fix`; earlier CPU-encoder experiments remain separately recorded. No failed or partial run contributes to the catalog.

`workingMemoryGB = ceil(full-run peak GiB × 1.10 × 2) / 2`; picker keeps its existing 8% margin and `RAM × 0.75 − 1` budget after chat unload.

| Model id | Real full-run peak GiB | workingMemoryGB | Minimum Mac RAM that gets it |
|---|---:|---:|---|
| `images` | 5.187 | 6.0 | 16 GB |
| `images-9b` | 11.956 | 13.5 | 24 GB |
| `video` | 13.605 | 15.0 | 24 GB |
| `video-5b` | 15.607 | 17.5 | 32 GB |
| `video-14b` | 22.670 | 25.0 | 48 GB |

**5B now auto-picks on 32 and 36 GB Macs**, between 1.3B at 24 GB and 14B at 48 GB. This is budget eligibility from real peaks measured on the M5 Max 128 GB host; smaller physical Macs were not hardware-certified. The old 1.3B 16 GB eligibility was based on incomplete accounting and is removed. 8 GB gets neither media family; 16 GB gets FLUX 4B photo only.

**Output verification:** All eight new clips (six final-configuration video runs plus two CPU-encoder experiments) have extracted frame PNGs, were fully decoded with ffmpeg without errors, and were manually checked for coherent beach/ocean imagery. No black/garbage frames. `artifact-validation-fix.json` records hashes, 832×480 / 81 frames / 16 fps for 1.3B/14B, 832×448 / 121 frames / 24 fps for 5B, silent output, and non-black PNG statistics. Both runs of each FLUX tier also produced correct-looking 512×512 images.

**Tests and gates:**

- `scripts/prometh/build.sh` — passed (`media-tiers/build-final-fix.log`).
- `make verify` — passed (`media-tiers/verify-final-fix.log`). An initial overlapping build/verify attempt failed during resource copying and is retained separately; final verification ran after the build.
- `xcodebuild test -scheme Prometh -only-testing:PromethTests -destination "platform=macOS,arch=arm64" -derivedDataPath build/NativDevelopmentDerivedData CODE_SIGNING_ALLOWED=NO` — **77 tests, zero failures** (`media-tiers/xcode-tests-fix.log`).
- Picker assertions cover **8/16/24/32/36/48/64/128 GB** for both photo and video; catalog assertions require full-run peak +10%, rounded upward by at most 0.5 GiB.
- Combined Python suite — **10 passed** (`media-tiers/python-tests-final-fix.log`), including numerical causal/tiling decoder checks and worker command/cancel/trim tests.

**Evidence:** [MEASUREMENTS.md](media-tiers/MEASUREMENTS.md), [exact run summary](media-tiers/full-run-summary-fix.json), [artifact validation](media-tiers/artifact-validation-fix.json), and raw `*-fix.log` / `.time.txt` / `.footprint.txt` / MP4 / PNG files. Timed runners use production worker commands with prompt caches disabled. Cold means a new process, not a purged OS file cache.

Original Nativ.app was quit before live tests. OpenWhispr, temporarily quit after it started during the first 1.3B run, was restored after measurements. The pre-existing `launch.log` modification is left unstaged.

**Release app:** Release build succeeded; ad-hoc signing and standard `codesign --verify --deep` passed (`media-tiers/release-build-fix.log`, `release-verify-fix.log`). An additional `--strict` check flags the pre-existing external Homebrew interpreter symlinks in the reader/search/connector venvs; that runtime layout was retained. Bundled catalog and bounded-media runtime byte-match the committed source. Release `Prometh.app` is running (PID 74061), with its own descendant serving HTTP 200 on `/health` at port 8080; see `media-tiers/release-running-fix.json`.

## Stage 3 — chat polish and full Plugins catalog (2026-10-27)

**Implementation:** `a6768f7e` — `feat(prometh): polish chat editing and load the full Composio catalog`; `adaa3e2f` — retain the existing white provider-logo tile so black SVG marks remain visible in dark appearance.

- Chat: trailing user bubbles with a 560-point maximum width and natural short-message sizing; unboxed assistant replies; grouped Copy/Edit or Copy/Regenerate/Read SF Symbol actions with hover styling, tooltips, keyboard focus rings and timed checkmark/copied feedback. Existing Prometh colors, fonts and branding retained; original Nativ surfaces remain in the tree.
- Inline edit replaces the bubble at the full transcript width. An AppKit text area measures wrapped lines, grows to 300 points and scrolls for longer content; rounded container, Cancel/Send pills at bottom right. Live checks: Return adds a newline, Escape discards edits, and **Cmd+Return replaced the failed GitHub turn and regenerated it successfully**. Marked-text composition and modifier handling have unit coverage.
- References: three shallow repositories in `/tmp/ui-refs`. Enchanted is the primary SwiftUI reference; LibreChat informed hover/copy feedback. Open WebUI was studied only, with no source copied or translated. [Attribution and licenses](../../SOURCE/ATTRIBUTION-stage3.md).

**Before and after screenshots** (all real app captures; visually inspected and iterated):

- Before: [messages + existing action rows](ui-pass/before-messages.png), [inline edit](ui-pass/before-inline-edit.png).
- After, same France/Paris conversation: [messages](ui-pass/after-messages.png), [user hover actions](ui-pass/after-user-hover-actions.png), [assistant copied feedback](ui-pass/after-assistant-copied.png), [inline edit](ui-pass/after-inline-edit.png), [auto-growing editor](ui-pass/after-inline-growing.png). The added multiline editor text was cancelled; the original conversation was preserved.
- Catalog: [all plugins + live connections](ui-pass/after-plugins-catalog.png), [GitHub search + Connected badge](ui-pass/after-plugins-github-connected.png), [Email category](ui-pass/after-plugins-category-email.png), [Slack browser-authorization waiting state](ui-pass/after-plugins-slack-oauth.png), [final Release dark appearance](ui-pass/after-plugins-dark.png).

**Plugins:** **1,689 toolkits**, 1,689 unique slugs, **98 categories**, all 1,689 logo URLs loaded from Composio's `/api/v3.1/toolkits` endpoint (`type=all`, existing install user, following every `next_cursor`). The Email filter returned 61 entries; searching GitHub returned 7 entries. Logos decode SVG through AppKit. Search/filter controls remain above the scrolling catalog; connected apps sort first. [Live count/cache summary](ui-pass/catalog-live-summary.json).

Metadata cache: `~/Library/Application Support/Prometh/connectors/toolkits-v1.json`, atomic writes, 24-hour freshness, explicit Refresh, last-updated date, visible failure/retry banner, and saved-catalog fallback. Connection status is refreshed separately from the cache. Malformed responses and failed intermediate pages cannot replace the cache with a partial catalog. Missing credentials also leave Plugins visible with an actionable error. Every entry uses its own toolkit slug through the existing Composio hosted authorization flow; Slack reached a real authorization link and **Waiting for sign-in…**, without completing an additional grant. GitHub and Gmail both showed **Connected** from the real API. Credential file contents were never printed, logged or committed.

**Real GitHub chat test:** Prometh chat → connector discovery → app approval sheet → Composio execution → local-model answer. `GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER`, arguments `{"sort":"updated","direction":"desc","per_page":5,"type":"owner"}`. Actual result: **`ok=true`, `successful=true`, `executed=true`**, Composio log **`log_8Z-x-X7HRFC5`**, five repositories: `fjenn/the-source`, `fjenn/open-blocker-website`, `fjenn/open-blocker`, `fjenn/wispr-bro`, `fjenn/prometh-app`. [Recorded result metadata](ui-pass/github-live-result.json), [approval screenshot](ui-pass/github-tool-approval.png), [actual chat answer](ui-pass/after-github-live-chat.png). No mocked or staged response was used.

The first real attempt selected the GitHub App installation action and returned a genuine 400, missing `installation_id`: [original error](ui-pass/github-initial-error.json). Fixed discovery to include action input schemas, accept an explicit toolkit hint, and surface the authenticated-user repo action when an otherwise ambiguous repository search omitted the app name. Malformed execution arguments now return a visible error instead of silently executing with `{}`. The successful retry used the final helper through chat, after replacing the turn using Cmd+Return.

**Gates, completed before each code commit and rerun after the dark-logo correction:**

- `scripts/prometh/build.sh` — passed; Debug app ad-hoc signed ([log](ui-pass/build.log)).
- `make verify` — passed ([log](ui-pass/verify.log)).
- `xcodebuild test -scheme Prometh -only-testing:PromethTests -destination 'platform=macOS,arch=arm64' -derivedDataPath build/NativDevelopmentDerivedData CODE_SIGNING_ALLOWED=NO` — **82 tests, zero failures** ([log](ui-pass/xcode-tests.log)).
- Python catalog/discovery tests — **5 passed**; existing MCP approval/direct/broker checks — **3 scenarios passed**, including malformed arguments refused before execution ([catalog tests](ui-pass/python-catalog-tests.log), [MCP tests](ui-pass/python-mcp-tests.log)).
- Xcode prints the host's existing iOS CoreSimulator-version warning; the requested macOS build/test gates succeed. Trailing whitespace is normalized in committed logs; the original captures remain at `/tmp/prometh-stage3-*.log`.

Original Nativ.app was confirmed stopped before live tests. The pre-existing `Docs/progress/macverify/launch.log` modification remains excluded. Only `prometh` is pushed; `backup/wip-20261027-0055` is retained.

**Release / judges delivery:** Corrected Release build and `codesign --verify --deep` passed ([build log](ui-pass/release-build.log), [sign log](ui-pass/release-sign.log)). The final Release app was visually checked in dark and light appearance; the original Light preference was restored. Explicit Refresh was verified in Release (same 1,689 total, updated timestamp). `~/Desktop/Prometh-judges/Prometh.zip` was rebuilt, its ZIP CRC validated, and its executable and connector runtime byte-checked against the running Release app and committed source. The judges folder contains updated `JUDGES.md`, `ui-pass/` evidence and `SOURCE/` attribution/licenses.

Archive SHA-256: `72d09f3d8bd46485b7dafe0071adcb7f3e49a7a22693e55f21b01cbe19129dd4`. Release **Prometh.app is left running, PID 84935**, with its own descendant listening on port 8080 and `/health` returning **HTTP 200**. Original Nativ is stopped. [Running/package verification](ui-pass/release-running.json), [screenshot and gate manifest](ui-pass/verification-manifest.json), [delivery self-review](ui-pass/SELF-EVALUATION.md).
