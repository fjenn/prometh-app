# M5: Evil Mode

## What landed

- Seam S7. `ChatViewModel.runChatLoop` asks `ChatEndpointResolver` before it builds the chat client. With the resolver unset, the queued host, port, key, and model are unchanged, so Nativ tests keep their endpoint. Prometh installs the resolver at launch.
- An Evil chat starts `PromethRuntime/llama/llama_supervisor.py`, which runs llama-server as `b11669` on `127.0.0.1` with `--ctx-size 8192 --parallel 1 --jinja --reasoning off` and a per-launch API key. The alias sent to the client is `evil`. The supervisor watches the app pid and stops the child when the parent dies, after 10 minutes idle, or after three failed starts.
- The binary and the 5.63 GB GGUF are not in git. `PromethRuntime/llama/bin/` is gitignored. The weights download through the catalog id `evil` under the friendly name `Qwen3.5 9B Heretic v2 · Evil · 5.63 GB`. Choosing Evil during onboarding starts that download. The first new chat uses the onboarding mode. Later chats start in Safe Mode. The mode is stored per chat.
- At 16 GiB or below, an Evil turn `POST`s `/unload` on the MLX server, and a Safe turn stops llama-server, so the two chat models are not both resident. `evil-vision-projector` stays disabled.
- If llama-server disappears mid-turn, the transcript says "Something interrupted that. Your request is saved. Try again when you're ready." The composer keeps the Evil gradient, and the header uses the red edge while that chat is Evil.
- Quitting the app stops the supervisor. The supervisor also exits if its parent pid disappears, including after `kill -9`.

## Linux tests

`python3 PromethRuntime/llama/test_llama.py`

```
{"passed": true, "tests": 4, "llamaCpp": "b11669"}
```

Covered: the launch argument list, rejection of a non-loopback bind, the 16 GiB unload rule, the idle clock, an OpenAI `tool_calls` round trip (`web_search`, then a final answer containing `[1]`), rejection of a request without the API key, a listener only on `127.0.0.1`, and the child exiting after its parent is killed. The GGUF was not downloaded.

`swiftc` is not installed here, so `PromethModeTests` was not executed. It pins the same 16 GiB rule, the interruption string, the opening-chat mode, and `5.63 GB`.

## PENDING MAC VERIFICATION

```
scripts/prometh/build.sh
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethTests/PromethModeTests
```

Install llama-server `b11669` at `PromethRuntime/llama/bin/llama-server` or point `PROMETH_LLAMA_BIN` at it. On the Mac, with the catalog download:

- Onboarding with Evil on shows the friendly name and 5.63 GB, then the first chat opens in Evil (gradient border, red header edge, "Evil Mode").
- Safe and Evil both answer "Search the web for today's weather in Buenos Aires and cite it" with a `web_search` tool call, a tool result, and `[n]`. The Evil selftest keeps the raw `tool_calls` JSON.
- Evil "Make an image of a red fox" produces a `generate_image` call.
- The composer switch changes only that chat. A new chat is Safe. Relaunch keeps each chat's mode.
- On a 16 GB Mac, only one of the MLX model or the llama-server model is resident during a turn (`footprint`).
- Killing llama-server mid-turn shows the interruption sentence, and Try again works. After quit, `pgrep llama-server` is empty.

`make verify` was not run on this machine.
