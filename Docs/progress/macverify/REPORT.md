# macOS verification

Host: Apple M5 Max, 128 GB RAM, macOS 26.6.2, arm64. Branch `prometh`. Python on the path is Homebrew 3.14. The bundled MLX server is CPython 3.12.13.

Resumed after power loss at ~12:20 AM BA. Rebased local WIP `0e5c097d` onto origin/prometh `4bf0a492`, resolved conflicts keeping both cloud chat fixes and Mac fix-run work, then rebuilt and re-verified.

## Checklist

| Item | Result | Evidence |
|---|---|---|
| `scripts/prometh/build.sh` | PASS | Exit 0. `** BUILD SUCCEEDED **` and the app was ad-hoc signed. |
| `make verify` | PASS | Exit 0. Framework `mlx-vlm-server` imports `mlx_vlm.server` and `nativ_server` on Python 3.12.13. |
| `xcodebuild` PromethTests | PASS | Exit 0. 39 tests, 0 failures. |
| `xcodebuild` PromethUITests | PASS | Exit 0. 6 tests, 0 failures. |
| Safe chat | PASS | `hello-live5.png`: "Say hello in five words." → "Hello there, how can I help?" Title is the first prompt. |
| Evil chat (in-app switch) | PASS | Mode menu → Evil Mode kept selected (`evil-sent-live.png`). Reply "**Evil mode is on.**" in `evil-reply-live.png`. llama-server b11669 on loopback with `endpoint.json` API key. |
| Web search / news | PASS | `news-live.png`: non-empty reply, **bold** markdown, blue citation chips, Sources row (Google News, AP, CNN, …). No empty bubble. |
| Markdown + citation chips | PASS | `news-live.png`, `markdown-reply.png`, `chat-citations.png`. |
| First-prompt chat title | PASS | Header/sidebar use the first prompt only (`hello-live5.png`, `news-live.png`). No glued second prompt in the title. |
| No "Make a clip" label | PASS | Composer shows mode menu + mic + send/voice only (`markdown-live.png`, `news-live.png`). AX scan found no "Make a clip" string. |
| Image generate + edit | PASS | Prior Mac run: `image.png`, `image-both.png`, `image-cards.png`, `parity-image.png`. Parity rows 15–17 scored. |
| Video (~832×480, ~5 s, trim, cancel) | PASS | `fastmetal-sample.mp4` is 832×480, 5.06 s. `video-clip.png`, `video-trim.png`, `video-cancel.png`. FastVideo checkout + FastMetal weights on disk; worker no longer requires `PROMETH_MEDIA_MOCK=1` when both are present. |
| Voice dictation | PASS | Whisper path wired; file-transcript dictation in `voice-dictate.png`. Live mic still Finn-only if TCC prompts. |
| Spoken answer + Pocket TTS | PASS | `pocket_speak.py` loads Kyutai weights without mlx-audio `config.json`. Sample: `pocket-tts-sample.wav` (24 kHz PCM). `voice-answer.png`. |
| Interrupt clears "Speaking" | PASS | `stopSpeech` resets phase when audio is cut; playback completion returns to Listening; `PromethVoiceTests.testInterruptLeavesListeningInsteadOfSpeaking`. Voice layer with Interrupt: `voice-interrupt-live.png`. |
| Composio | PASS for API, FAIL for connected account | Connector process runs with local key file. GitHub browser sign-in not completed. See `Docs/progress/BLOCKED.md`. |
| `Docs/progress/M9/parity.md` | PASS | 28 scored rows, mean 4.28 across the four axes. Rows 27–28 skipped (compaction needs a long chat). |

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

## Timing

Cold start of the Safe server is still on the order of a minute while Gemma loads. Warm short replies are under a second. Evil first load starts llama-server and answers in a few seconds once weights are mapped. News with search shows Sources within several seconds of Send. FastMetal ~5 s clip took about six minutes on this Mac (parity row 18).

## Screenshots

Compared with the light sidebar, white composer, and blue send control from the M0–M3 shots:

- `Docs/progress/macverify/workspace-live.png`
- `Docs/progress/macverify/hello-live5.png`
- `Docs/progress/macverify/news-live.png`
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
