# M7: Voice

## What landed

- Dictation defaults to `mlx-community/whisper-large-v3-turbo`. An empty selection or `parakeet-redux-coreai` is rewritten to Whisper when the Prometh shell is on. Parakeet stays compiled. The shell does not preload it.
- Read-aloud and the voice surface use Pocket TTS voice `alba` (`kyutai/pocket-tts-without-voice-cloning`). The request body is `model`, `voice`, and `text`.
- Phases are Listening, Thinking, and Speaking. Interrupt clears playback. End stops the surface. A denied microphone sets the phase to "Microphone unavailable" and offers the Settings recovery line.
- `PROMETH_STT_FILE` or `PROMETH_STT_TRANSCRIPT` lands the transcript in the composer. A file selftest that asks "two plus two" speaks "The answer is four." Live microphone capture and Pocket TTS audio still run on the Mac.

## Linux tests

`python3 PromethRuntime/voice/test_voice.py`

```
{"passed": true, "tests": 2, "whisper": "mlx-community/whisper-large-v3-turbo", "voice": "alba"}
```

The mock transcriber, bound to `127.0.0.1`, returned a transcript containing "weekend" and "sea". The phase moved Listening → Thinking → Speaking. The spoken answer contained "four". Interrupt cleared playback in under 200 ms. The denied phase is "Microphone unavailable". No Whisper or Pocket weights were downloaded. `swiftc` is not installed, so `PromethVoiceTests` was not executed.

## PENDING MAC VERIFICATION

```
scripts/prometh/build.sh
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethTests/PromethVoiceTests
```

On the Mac, with Voice prepared:

- Play the voice demo through a loopback device, or launch with `PROMETH_STT_FILE` pointing at the wav and `PROMETH_STT_TRANSCRIPT` beside it. The composer contains "weekend" and "sea" and can still be edited.
- Voice round trip for "What is two plus two?": transcript shows the question, the phase moves Listening → Thinking → Speaking, Pocket TTS (Alba) plays, and the spoken answer contains "four". Record time to first audio. It must be under 3 seconds after speech ends. Interrupt stops playback within 200 ms. End, closing the window, or switching chats leaves nothing playing.
- "Read response aloud" speaks an existing message.
- With the microphone denied, the phase reads "Microphone unavailable" and the surface offers recovery.

`make verify` was not run here.
