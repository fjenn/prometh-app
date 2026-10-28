# llama.cpp for Evil Mode

Prometh bundles an API-only build of llama.cpp, without model weights.

- Upstream: https://github.com/ggerganov/llama.cpp
- Tag: `b11669` (MIT)
- Binary name: `llama-server`
- Model: catalog id `evil`, `filvyb/Qwen3.5-9B-heretic-v2-GGUF` revision `1ea5060b658fdb7384cda09915d8432bb796165a`, file `Qwen3.5-9B-heretic-v2-Q4_K_M.gguf` (5.63 GB). The app downloads it through the catalog. Do not commit the weights.

`llama_supervisor.py` starts `llama-server` only on `127.0.0.1`, with:

```
--host 127.0.0.1 --port P --model <gguf> --alias evil --ctx-size 8192 --parallel 1 --jinja --reasoning off --api-key <secret>
```

The Mac build looks for the binary at `PROMETH_LLAMA_BIN` or `PromethRuntime/llama/bin/llama-server`. That directory is gitignored. The vision projector catalog id `evil-vision-projector` stays disabled.

Run `python3 scripts/prometh/provision-llama.py` to rebuild the exact b11669 commit
`620d2225cc436ab0b001e3200e590e3b286ef9ab`. It builds for generic Apple Silicon,
embeds the Metal library, and disables OpenSSL and the unused embedded Web UI.
Prometh owns filesystem, shell and MCP tools and their approval flow. The
provisioner therefore removes the engine's duplicate built-in tool factories
and external tool runtime creation; inference and app-supplied tool schemas
remain supported. This also removes unused development-directory exclusions
from the native library, keeping the literal release audit strict.
