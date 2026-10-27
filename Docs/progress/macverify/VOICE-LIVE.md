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
