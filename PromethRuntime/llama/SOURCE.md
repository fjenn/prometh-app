# llama.cpp for Evil Mode

Prometh does not vendor llama.cpp or the Qwen GGUF.

- Upstream: https://github.com/ggerganov/llama.cpp
- Tag: `b11669` (MIT)
- Binary name: `llama-server`
- Model: catalog id `evil`, `filvyb/Qwen3.5-9B-heretic-v2-GGUF` revision `1ea5060b658fdb7384cda09915d8432bb796165a`, file `Qwen3.5-9B-heretic-v2-Q4_K_M.gguf` (5.63 GB). The app downloads it through the catalog. Do not commit the weights.

`llama_supervisor.py` starts `llama-server` only on `127.0.0.1`, with:

```
--host 127.0.0.1 --port P --model <gguf> --alias evil --ctx-size 8192 --parallel 1 --jinja --reasoning off --api-key <secret>
```

The Mac build looks for the binary at `PROMETH_LLAMA_BIN` or `PromethRuntime/llama/bin/llama-server`. That directory is gitignored. The vision projector catalog id `evil-vision-projector` stays disabled.
