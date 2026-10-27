# Voice live verification — 2026-10-27

Initial diagnosis: Release Voice called `PromethVoice.sampleTurn()`, which only reads test transcript files. It never called `VoiceAudioRecorder.start()`. Dictation used the real recorder, but only filled the draft. The microphone Info.plist description and audio-input entitlement existed; explicit ad-hoc signing now preserves the entitlement.

Initial real-microphone trial (Release, 14:22 BA): no STT injection environment variables. Quit both old Prometh instances and Nativ, launched the signed Release, clicked New chat → Voice. Ran `say -o /tmp/prometh-live-question.aiff 'What is the capital of France?'`, then `afplay /tmp/prometh-live-question.aiff` through speakers.

Observed live meter 0.0875–0.1169, state “Hearing you…”, real WAV written. Initial RMS detector needed a manual orb click (room noise prevented its silence threshold). Whisper returned **“What is the capital of France? One plus.”** (last words are room audio or recognition error). Chat was not ready, so no spoken reply was verified in this trial. This is partial evidence, not a successful end-to-end certification. Scope update requires Silero/Kokoro; final evidence follows below when exercised.

Exact local preparation log:

```
2026-10-27T17:22:19Z voice real microphone capture started: Voice Recording 2026-10-27 at 14.22.19.818.wav
2026-10-27T17:22:53Z voice recording finished: 6547456 bytes; requesting Whisper STT
2026-10-27T17:22:57Z voice STT completed: 40 characters
```

Build gate passed; `make verify` passed; PromethTests: 65 tests, 0 failures. PromethUITests skipped: macOS Automation Mode requires the owner's password.

## Silero + Kokoro follow-up (B)

The default speech engine is now pinned `mlx-community/Kokoro-82M-bf16` (`af_heart`), run by mlx-audio in the bundled Python. Pocket remains compiled. Silero is `onnx-community/silero-vad` at `e71cae966052b992a7eca6b17738916ce0eca4ec` (repository dates July–December 2024, v5 era), ONNX Runtime CPU, 16 kHz mono, 512-sample frames plus 64-sample recurrent context. The app uses 700 ms silence after sustained speech. Capture also runs during playback with an echo gate for barge-in; microphone, worker, transcription, chat, and playback errors are visible.

The production `CatalogDownloader` CLI downloaded and hash-verified Kokoro (327,639,823 bytes), Silero (2,244,097 bytes including license), and Whisper base (148,065,824 bytes). Kokoro generated a 113 KB WAV offline and `afplay` played it. Its bundled espeak data needs a short temporary path because its wrapper resolves bundle paths; no system espeak install is required.

Live Debug test (14:38 BA): real microphone → Silero automatic end → Whisper → chat → Kokoro playback. A clear turn was transcribed as **“Yo, what's the capital of France?”** and the assistant replied **“The capital of France is Paris.”** Other turns captured other audible speech in the room, so they are not clean repetitions of the `say` file. No transcript was injected or saved data edited. The Release repeat and barge-in outcome are recorded later.

```
2026-10-27T17:38:13Z voice Silero v5 started (16 kHz, 512 + 64 context)
2026-10-27T17:38:13Z voice real microphone capture started: Voice Recording 2026-10-27 at 14.38.13.510.wav
2026-10-27T17:38:20Z voice recording finished: 1394688 bytes; requesting Whisper STT
2026-10-27T17:38:22Z voice STT completed: 111 characters
2026-10-27T17:38:34Z voice Kokoro playback started
2026-10-27T17:38:45Z voice recording finished: 534528 bytes; requesting Whisper STT
2026-10-27T17:38:46Z voice STT completed: 33 characters
2026-10-27T17:38:53Z voice Kokoro playback started
```

Ad-hoc signing now uses `Configuration/Prometh-AdHoc.entitlements` (microphone only), avoiding unresolved restricted keychain groups from the development entitlement file. Python verification uses `-B` to preserve signed resource seals. Gates: build, make verify, 66 PromethTests passed, 0 failures; UI test target skipped for Automation Mode.

## Release re-test + barge-in (16:36 BA)

Release build: `xcodebuild -scheme Nativ -configuration Release NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO`, then ad-hoc signed with `Configuration/Prometh-AdHoc.entitlements` (`com.apple.security.device.audio-input`). Bundle `studio.prometh.Prometh`. No `PROMETH_STT_FILE` / `PROMETH_STT_TRANSCRIPT`. Quit Debug Prometh and Nativ first; launched `build/.../Release/Prometh.app`.

Flow: New chat → Voice → `say`/`afplay` through speakers into the real mic. Silero ended the turn; Whisper transcribed; chat answered; Kokoro spoke.

**Turn 1 (live mic):** user **“What is the capital of France? Please answer briefly.”** → assistant **“The capital of France is Paris.”**

**Barge-in:** while Kokoro was playing that reply, played **“Interrupt now. Stop speaking. Interrupt.”** Log line `voice Silero barge-in` at `19:36:39Z` (2s after Kokoro start). Follow-up turn transcribed **“Stop speaking. Interrupt.”** Screenshot: `parity-B-release-voice2.png`.

```
2026-10-27T19:36:23Z voice Silero v5 started (16 kHz, 512 + 64 context)
2026-10-27T19:36:23Z voice real microphone capture started: Voice Recording 2026-10-27 at 16.36.23.256.wav
2026-10-27T19:36:29Z voice recording finished: 1284096 bytes; requesting Whisper STT
2026-10-27T19:36:30Z voice STT completed: 53 characters
2026-10-27T19:36:37Z voice Kokoro playback started
2026-10-27T19:36:37Z voice Silero v5 started (16 kHz, 512 + 64 context)
2026-10-27T19:36:37Z voice real microphone capture started: Voice Recording 2026-10-27 at 16.36.37.906.wav
2026-10-27T19:36:39Z voice Silero barge-in
2026-10-27T19:36:39Z voice Silero v5 started (16 kHz, 512 + 64 context)
2026-10-27T19:36:39Z voice real microphone capture started: Voice Recording 2026-10-27 at 16.36.39.680.wav
2026-10-27T19:36:42Z voice recording finished: 503808 bytes; requesting Whisper STT
2026-10-27T19:36:42Z voice STT completed: 25 characters
```

Release gates for this section: Release `xcodebuild` **BUILD SUCCEEDED**; Debug gates already green from Section C (`make verify`, 76 PromethTests). PromethUITests still skipped (Automation Mode).
