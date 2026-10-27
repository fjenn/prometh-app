# macOS verification

Host: Apple M5 Max, 128 GB RAM, macOS 26.6.2, arm64. Branch `prometh`. Python on the path is Homebrew 3.14. The bundled MLX server is CPython 3.12.13.

Follow-up after `news-live4.png`: honest citations (no balance/round-robin), long-paste composer fix, and stress harness. Verified at ~5:00 AM BA. See `STRESS.md`.

## Checklist

| Item | Result | Evidence |
|---|---|---|
| `scripts/prometh/build.sh` | PASS | Exit 0. `** BUILD SUCCEEDED **` and the app was ad-hoc signed. |
| `make verify` | PASS | Exit 0. Framework `mlx-vlm-server` imports on Python 3.12.13. |
| `xcodebuild` PromethTests | PASS | Exit 0. 48 tests, 0 failures (honest remapper + drop-unsupported; no balance tests). |
| `xcodebuild` PromethUITests | PASS | Exit 0. 6 tests, 0 failures. |
| Safe chat | PASS | `hello-live8.png`: "Say hello in five words." → "Hello there, how may I assist you?" |
| Evil chat (in-app switch) | PASS | Prior Mac run: mode menu → Evil Mode (`evil-sent-live.png`, `evil-reply-live.png`). |
| Web search / news | PASS | `news-live5.png`: bullets, bold (`1000`), chips `[1]`/`[1]`/`[1]`/`[2]` mapped by content overlap to The World Now vs 7NEWS (see STRESS.md quotes). |
| Markdown + citation chips | PASS | Nested-list unit test + `news-live5.png` Unicode bullets, bold, sky chips, spacing. |
| Multi-source citations | PASS | Prefetch keeps only **read** pages; remapper assigns best-overlap chip or drops unsupported claims. Repeated chips allowed. |
| First-prompt chat title | PASS | Header/sidebar use the first prompt (`hello-live8.png`, `news-live4.png`). |
| No "Make a clip" label | PASS | Composer shows mode menu + mic + send/voice only. |
| Image generate + edit | PASS | Prior Mac run: `image.png`, `image-both.png`, `image-cards.png`, `parity-image.png`. |
| Video (~832×480, ~5 s, trim, cancel) | PASS | Prior Mac run: `fastmetal-sample.mp4`, trim/cancel shots. |
| Voice dictation | PASS | Whisper path wired; prior `voice-dictate.png`. |
| Spoken answer + Pocket TTS | PASS | Prior `pocket-tts-sample.wav`, `voice-answer.png`. |
| Interrupt clears "Speaking" | PASS | Prior `voice-interrupt-live.png` + `PromethVoiceTests`. |
| Composio | PASS for API, FAIL for connected account | See `Docs/progress/BLOCKED.md`. |
| `Docs/progress/M9/parity.md` | PASS | Prior 28 scored rows, mean 4.28. |

The test command was:

```
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:PromethTests -only-testing:PromethUITests
```

Exit codes this pass: `build.sh` 0 · `make verify` 0 · PromethTests 0 · PromethUITests 0.

## Fixes in this pass

1. **Honest citation remapper** — Best content-overlap only; drop chips below threshold; no least-used balance or force round-robin. Covered by `testCitationRemapperMapsLineToSourceContainingThatClaim`, `testCitationRemapperAllowsRepeatedChipsWhenOneSourceSupportsAllLines`, `testCitationRemapperDropsUnsupportedChips`.
2. **Read-only sources** — Prefetch/prompt injection and the Sources row include only pages with a fetched body; prompts require facts present in Page text. Covered by `testInjectedContextContainsOnlyReadSources`.
3. **HTML entities** — `PromethHTML.decode` handles named and numeric entities before display and injection. Covered by `testHTMLEntitiesAreDecodedInTitlesAndSnippets`.
4. **Long paste / AX draft** — Focused composer no longer cleared by an empty SwiftUI binding; accessibility sets sync into the draft (`ComposerEditor.swift`).

## Timing

Cold start of the Safe server is still on the order of a minute while Gemma loads. Warm short replies are under a second. News with search+sidecar reads answers in roughly 10–20s once the model is warm. FastMetal ~5 s clip took about six minutes on this Mac (parity row 18).

## Screenshots

- `Docs/progress/macverify/workspace-live.png`
- `Docs/progress/macverify/hello-live8.png`
- `Docs/progress/macverify/news-live5.png` (honest chips + quoted source snippets in STRESS.md)
- `Docs/progress/macverify/news-live4.png` (prior balanced chips — superseded)
- `Docs/progress/macverify/STRESS.md`
- `Docs/progress/macverify/news-live3.png` (prior: bullets + multi-domain Sources, all chips `[1]`)
- `Docs/progress/macverify/news-live2.png` (prior: real headlines but literal `*` and single Reuters source)
- `Docs/progress/macverify/news-live.png` (kept for regression history)
- `Docs/progress/macverify/evil-sent-live.png`
- `Docs/progress/macverify/evil-reply-live.png`
- `Docs/progress/macverify/voice-interrupt-live.png`
- `Docs/progress/macverify/markdown-reply.png`
- `Docs/progress/macverify/chat-citations.png`
- `Docs/progress/macverify/settings.png`

## Open the built app

```
open /Users/armando/Projects/Coding/prometh-app/build/NativDevelopmentDerivedData/Build/Products/Debug/Prometh.app
```

Note: `scripts/prometh/launch.sh --fresh` clears `hasCompletedWelcome1`, which skips `model.startServer()`. Prefer a normal launch after onboarding, or restore `defaults write studio.prometh.Prometh hasCompletedWelcome1 -bool YES`.

## Finn still has to

- Finish GitHub sign-in from the Composio redirect.
- Allow the microphone if dictation asks.

## Not blocked anymore

- Video generation uses FastVideo when the checkout and FastMetal weights are present.
- Pocket TTS speaks through `PromethRuntime/voice/pocket_speak.py` (no mlx-audio `config.json` required).
- News replies summarize fetched page text with citations instead of only listing aggregator sites.
- Assistant lists render as real bullets; citation chips are remapped to distinct Sources indices after the reply finishes.
