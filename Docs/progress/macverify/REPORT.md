# macOS verification

Host: Apple M5 Max, 128 GB RAM, macOS 26.6.2, arm64. Branch `prometh`. Python on the path is Homebrew 3.14. The bundled MLX server is CPython 3.12.13.

Follow-up after `news-live2.png`: fixed literal markdown list markers and single-source news citations. Verified at ~3:25 AM BA.

## Checklist

| Item | Result | Evidence |
|---|---|---|
| `scripts/prometh/build.sh` | PASS | Exit 0. `** BUILD SUCCEEDED **` and the app was ad-hoc signed. |
| `make verify` | PASS | Exit 0. Framework `mlx-vlm-server` imports on Python 3.12.13. |
| `xcodebuild` PromethTests | PASS | Exit 0. 43 tests, 0 failures (was 41; added nested-list + multi-source tests). |
| `xcodebuild` PromethUITests | PASS | Exit 0. 6 tests, 0 failures (draft clear + Sources ≥2 + stop race hardening). |
| Safe chat | PASS | `hello-live7.png`: "Say hello in five words." → "Hello there, how can I help?" |
| Evil chat (in-app switch) | PASS | Prior Mac run: mode menu → Evil Mode (`evil-sent-live.png`, `evil-reply-live.png`). |
| Web search / news | PASS | `news-live3.png`: bullet list of headlines, bold, blue `[n]` chips, Sources row with several distinct domains (7news, The World Now, Reuters, Google News, …). |
| Markdown + citation chips | PASS | `news-live3.png` shows Unicode `•` bullets (not literal `*`), bold, chips, paragraph spacing. Nested-list unit test covers indent + bold + `[n]`. |
| Multi-source citations | PASS (pipeline) / PARTIAL (model chips) | Prefetch dedupes by domain, reads several pages, keeps Sources aligned to indices 1…N. Unit test covers multi-source prompt + chip→Sources mapping. Live answer still often reuses chip `[1]` when only one page body is rich — Sources row itself lists multiple sites. |
| First-prompt chat title | PASS | Header/sidebar use the first prompt (`hello-live7.png`, `news-live3.png`). |
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

Exit 0.

## Fixes in this pass

1. **Literal list markers** — `PromethReplyMarkup` kept `.inlineOnlyPreservingWhitespace` (so paragraph spacing stays) and rewrites `*` / `-` / `1.` markers into Unicode bullets / numbers with nesting indent before parse. Covered by `testReplyMarkupRendersNestedListsWithBoldAndCitationChip`.
2. **Single-source news** — prefetch picks distinct domains (`preferDistinctDomains`), reindexes hits 1…N after parallel sidecar reads, retries extra domains when fewer than three bodies return, and the Sources row prefers that prefetch list over a tool-path extract that had collapsed every chip to `[1]`. Covered by `testDistinctDomainHitsMapChipIndicesToSources`.
3. **UITest flakes** — clear restored drafts before typing; tolerate a finished generation when Stop was the race; news UITest asserts ≥2 Source cards.

## Timing

Cold start of the Safe server is still on the order of a minute while Gemma loads. Warm short replies are under a second. News with search+sidecar reads answers in roughly 10–20s once the model is warm. FastMetal ~5 s clip took about six minutes on this Mac (parity row 18).

## Screenshots

- `Docs/progress/macverify/workspace-live.png`
- `Docs/progress/macverify/hello-live7.png`
- `Docs/progress/macverify/news-live3.png` (bullets + multi-domain Sources)
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
- Assistant lists render as real bullets; news Sources list several distinct domains.
