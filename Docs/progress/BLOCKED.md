# Blocked

These are the steps only Finn can finish. Everything else in the macOS verification was run on this machine.

## GitHub sign-in for Composio

The local key file is present and the connector server calls Composio's API directly. No broker URL is required. A managed GitHub auth config can be created, and the connect call returns a browser redirect on `connect.composio.dev`.

Finn still has to open that redirect and finish GitHub's sign-in. This session did not complete "Continue in browser", so no GitHub account is connected and the Approve / Deny sheet for a real tool call was not exercised.

## Microphone permission

Whisper dictation was driven with a file transcript in automation. If the first live dictation asks for microphone access, that prompt is Finn's.
