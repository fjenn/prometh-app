# Blocked

These are the steps only Finn can finish. Everything else in the macOS verification was run on this machine.

## GitHub sign-in for Composio

The local key file is present and the connector server calls Composio's API directly. No broker URL is required. A managed GitHub auth config can be created, and the connect call returns a browser redirect on `connect.composio.dev`.

Finn still has to open that redirect and finish GitHub's sign-in. This session did not complete "Continue in browser", so no GitHub account is connected and the Approve / Deny sheet for a real tool call was not exercised.

## Microphone permission

Whisper dictation and Pocket TTS were not driven from the microphone. If the first dictation asks for microphone access, that prompt is Finn's.

## Not a Finn step

Video jobs still stop in `PromethRuntime/media/media_worker.py` with "Video is not ready yet" unless `PROMETH_MEDIA_MOCK=1`. The FastMetal weights are on disk. Wiring FastVideo `8db2d71` is remaining code, not a missing permission.

Pocket TTS weights are on disk, but `kyutai/pocket-tts-without-voice-cloning` has no `config.json`. mlx-audio refuses to load that snapshot. That is remaining code, not a permission.
