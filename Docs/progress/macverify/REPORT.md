# macOS verification

Host: Apple M5 Max, 128 GB RAM, macOS 26.6.2, arm64. Branch `prometh`. Python on the path is Homebrew 3.14. The bundled MLX server is CPython 3.12.13.

Follow-up after `news-live.png`: fixed glued markdown spacing and news answers that only listed sites. Verified at ~2:36 AM BA.

## Checklist

| Item | Result | Evidence |
|---|---|---|
| `scripts/prometh/build.sh` | PASS | Exit 0. `** BUILD SUCCEEDED **` and the app was ad-hoc signed. |
| `make verify` | PASS | Exit 0 (prior Mac verify). Framework `mlx-vlm-server` imports on Python 3.12.13. |
| `xcodebuild` PromethTests | PASS | Exit 0. 41 tests, 0 failures (was 39; added spacing + search-context tests). |
| `xcodebuild` PromethUITests | PASS | Exit 0. 6 tests, 0 failures (news UITest wait raised to 180s). |
| Safe chat | PASS | `hello-live6.png`: "Say hello in five words." → "Hello there, how are you?" |
| Evil chat (in-app switch) | PASS | Prior Mac run: mode menu → Evil Mode (`evil-sent-live.png`, `evil-reply-live.png`). |
| Web search / news | PASS | `news-live2.png`: concrete headline summaries (Sudan, Zelenskyy, Vanuatu **earthquake**, …), blue citation chips, Sources row. No empty “visit these sites” reply. Spacing no longer glues `information.Here`. |
| Markdown + citation chips | PASS | `news-live2.png` shows **earthquake** bold and `[n]` chips. Unit test covers paragraph-break glue. |
| First-prompt chat title | PASS | Header/sidebar use the first prompt (`hello-live6.png`, `news-live2.png`). |
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

1. **Glued assistant text** — `PromethReplyMarkup` used `AttributedString` markdown `.full`, which drops paragraph breaks (`A.\n\nB` → `A.B`). Switched to `.inlineOnlyPreservingWhitespace` and soft-spacing around `**` / `[n]`. Covered by `testReplyMarkupKeepsParagraphAndCitationSpacing`.
2. **News without article text** — `PromethWebPrefetch` only injected titles/snippets. It now SearXNG-searches, reads top pages through the local trafilatura sidecar, and puts `<search_results>` + page text in the model prompt (`PromethSearchContext`). Citation rules ask for 3–5 concrete headline summaries and skip a redundant tool round when page text is already present.
3. **WKWebView hang** — concurrent `ReadabilityWebViewReader` calls overwrote a shared continuation (`SWIFT TASK CONTINUATION MISUSE`). Reads are serialized and time-bounded; prefetch stays on the sidecar.

## Timing

Cold start of the Safe server is still on the order of a minute while Gemma loads. Warm short replies are under a second. News with search+sidecar reads answers in roughly 10–20s once the model is warm. FastMetal ~5 s clip took about six minutes on this Mac (parity row 18).

## Screenshots

- `Docs/progress/macverify/workspace-live.png`
- `Docs/progress/macverify/hello-live6.png`
- `Docs/progress/macverify/news-live2.png` (replaces the defective `news-live.png` answer quality)
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

## Finn still has to

- Finish GitHub sign-in from the Composio redirect.
- Allow the microphone if dictation asks.

## Not blocked anymore

- Video generation uses FastVideo when the checkout and FastMetal weights are present.
- Pocket TTS speaks through `PromethRuntime/voice/pocket_speak.py` (no mlx-audio `config.json` required).
- News replies summarize fetched page text with citations instead of only listing aggregator sites.
