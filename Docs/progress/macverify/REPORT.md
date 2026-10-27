# macOS verification

Host: Apple M5 Max, 128 GB RAM, macOS 26.6.2, arm64. Branch `prometh`. Python on the path is Homebrew 3.14. The bundled MLX server is CPython 3.12.13.

## Checklist

| Item | Result | Evidence |
|---|---|---|
| `python3 scripts/prometh/provision-runtime.py` | PASS | Exit 0. Reader, SearXNG, and Composio virtualenvs were created with Homebrew Python after a leftover interpreter with no pip was replaced. |
| `scripts/prometh/build.sh` | PASS | Exit 0. `** BUILD SUCCEEDED **` and the app was ad-hoc signed. |
| `make verify` | PASS | Exit 0. The framework `mlx-vlm-server` imports `mlx_vlm.server` and `nativ_server` on Python 3.12.13. |
| `xcodebuild` PromethTests | PASS | Exit 0. 25 tests, 0 failures. |
| `xcodebuild` PromethUITests | PASS | Exit 0. 6 tests, 0 failures. |
| Safe chat | PASS | Server command used `mlx-community/gemma-4-e4b-it-4bit`. After load, "Say hello in five words." returned in under a second. |
| Evil chat | PASS | `llama-server` b11669 bound `127.0.0.1` only and answered "Hello there, friend!" from the Heretic GGUF. The in-app mode menu was not switched in this pass. |
| Web search | PASS | SearXNG listened on `127.0.0.1:63530` only (`lsof`). A news question in the window produced a Sources row with Google News, CNN, CBS, AP, NBC, USA Today, BBC, and others. See `news-sources.png`. |
| Image | PASS | `POST /v1/images/generations` with `Runpod/FLUX.2-klein-4B-mflux-4bit` returned a 512×512 PNG (238,405 bytes) in 2.6 seconds. `Docs/progress/macverify/image.png`. |
| Video | FAIL | `PromethRuntime/media/media_worker.py` still raises "Video is not ready yet" unless `PROMETH_MEDIA_MOCK=1`. Weights are on disk. FastVideo is not invoked. |
| Voice | PARTIAL | Whisper transcribed a local clip, "the weekend by the sea", as "The Weekend by the Sea" (`POST /v1/audio/transcriptions`, HTTP 200, 0.56s). The processor files from `openai/whisper-large-v3-turbo` at `41f01f3fe87f` sit beside the MLX weights. Pocket TTS did not load: the pinned Kyutai snapshot has no `config.json`, and mlx-audio stops with "Config not found". The microphone was not opened. |
| Composio | PASS for the API, FAIL for a connected account | The connector process is running and calls Composio directly with the local key file. No broker. GitHub's browser sign-in was not completed. See `Docs/progress/BLOCKED.md`. |
| `Docs/progress/M9/parity.md` | PARTIAL | Six prompts scored from real replies. The other rows were not run. No crashes and no raw error text in the captured window. |

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

Cold start of the Safe server, from process launch until `GET /v1/models` returned 200, was about 80 seconds while the 5 GB Gemma weights loaded. After that, a short reply was under 1 second and the sampled writing prompts were about 2 seconds. That cold load is slower than the 2 second first-token target. A warm news answer showed Sources within a few seconds of Send.

## Screenshots

Compared with the light sidebar, white composer, and blue send control from the M0–M3 shots and the first design commit:

- `Docs/progress/macverify/workspace.png`
- `Docs/progress/macverify/news-sources.png`
- `Docs/progress/macverify/settings.png`
- `Docs/progress/macverify/settings-advanced.png`

## Open the built app

```
open /Users/armando/Projects/Coding/prometh-app/build/NativDevelopmentDerivedData/Build/Products/Debug/Prometh.app
```

On launch, if the catalog Safe folder hashes match, the app links those files into `Models/hub` and selects `mlx-community/gemma-4-e4b-it-4bit`.

## Finn still has to

- Finish GitHub sign-in from the Composio redirect.
- Allow the microphone if dictation asks.

## Linux follow-up

Citations, FastMetal video, and Pocket TTS were left for the Mac, which is building those with Xcode. This pass only changed chat presentation and the in-app Evil switch.

| Check | Result |
|---|---|
| Python `media/test_media.py` | PASS. 3 tests. FastVideo was not downloaded. |
| Python `voice/test_voice.py` | PASS. 2 tests. |
| Python `llama/test_llama.py` | PASS. 4 tests. |
| Python `reader/test_reader.py` | Not run. No reader virtualenv, and `trafilatura` is not installed, so the chain falls through to `plain`. |
| Python `composio_mcp/test_composio.py` | Not run. `anyio` is not installed in this environment. |
| Assistant markdown (`**bold**`, bullet lists) in chat bubbles | PENDING MAC VERIFICATION |
| Empty news reply uses search snippets instead of a blank bubble | PENDING MAC VERIFICATION. `PromethTranscriptTests` covers the helper. |
| Chat title is the first prompt only, including a second prompt jammed onto a `?` | PENDING MAC VERIFICATION. `PromethTranscriptTests` covers the helper. |
| No "Make a clip" label above the composer | PENDING MAC VERIFICATION |
| Evil Mode menu switches the open chat, and a choice made before a chat exists is kept | PENDING MAC VERIFICATION. `PromethModeTests` covers `openingMode`. |
| `xcodebuild` PromethTests and PromethUITests | PENDING MAC VERIFICATION |
