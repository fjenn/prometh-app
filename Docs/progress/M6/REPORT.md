# M6: Images and video

## What landed

- The Prometh shell sets the image model to catalog id `images`, `Runpod/FLUX.2-klein-4B-mflux-4bit` revision `7ee1b3aa8178a1240050490072196a57da2bf2a9`, when the stored id is empty or still Nativ's 8-bit fallback. `ImageGenerationViewModel.fallbackModelID` is unchanged, so Nativ's tests keep `mlx-community/flux2-klein-4b-8bit`. An explicit non-default id is left alone. Z-Image stays disabled.
- `generate_video` is registered in `ChatToolRegistry` only when the Prometh shell is on, the video flag is on, and the process is not XCTest. The pinned Nativ tool list is unchanged under test.
- `PromethRuntime/media/media_worker.py` is a stdio worker. It does not listen on a socket and does not download FastVideo `8db2d71ef217e84bec7dbb6e4ab65c92b144df4f` or `FastVideo/FastMetal-1.3B-QAD` (`2dac0154b217adabf8895d6cde7d6d93e68b7bec`). A real job is 832×480, silent, about 5 seconds, with `--decode-backend wan-vae`.
- Without FastVideo the worker reports that video is not ready. The composer shows "Make a clip", which opens preparation and leaves the draft in place.
- Trim writes a new file and keeps the source. Cancel terminates the worker's child process group. A poster frame is written beside a stand-in clip. ffmpeg is used only when it is already on the machine. It is not bundled.

## Linux tests

`python3 PromethRuntime/media/test_media.py`

```
{"passed": true, "tests": 3, "fastvideo": "8db2d71ef217e84bec7dbb6e4ab65c92b144df4f"}
```

The stand-in (not a FastVideo sample) was probed at 832×480 and about 5 seconds. Trim from 1.0 to 3.0 seconds measured 2.0 ± 0.1 seconds, and the original file was still present. Cancel stopped the child. `swiftc` is not installed, so `PromethMediaTests` was not executed.

## PENDING MAC VERIFICATION

```
scripts/prometh/build.sh
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethTests/PromethMediaTests \
  -only-testing:NativTests/ChatToolRegistryTests
```

On the Mac, after the image and video catalogs are prepared:

- "Create a cinematic photograph of a glass house above the Atlantic at sunrise." shows progress, then a decodable PNG at least 512 px on the 4-bit FLUX.2 Klein model. Save uses the system save panel. Edit ("make it dusk") keeps version 1 and writes version 2 through Nativ's image tool.
- "Make a 5-second clip of waves at sunset" shows progress, then an MP4 at 832×480 of about 5 seconds with a poster. Play, seek, and mute work. Trim to 1.0–3.0 seconds saves version 2 at 2.0 ± 0.1 seconds and keeps version 1. Cancel during generation leaves no worker (`pgrep`).
- With video unprepared, "Make a clip" explains and offers preparation without clearing the draft.

`make verify` was not run here. The stand-in MP4 is not the FastMetal model output.
