# FastVideo for clips

- FastVideo commit: `8db2d71ef217e84bec7dbb6e4ab65c92b144df4f` (Apache-2.0)
- Model: `FastVideo/FastMetal-1.3B-QAD`
- Revision: `2dac0154b217adabf8895d6cde7d6d93e68b7bec`
- Output: silent, 832×480, about 5 seconds, `--decode-backend wan-vae`

Run `python3 scripts/prometh/provision-runtime.py --media` to install the exact
`requirements.lock` with the server's bundled CPython 3.12. The lock was frozen
from the working media environment, excluding the editable FastVideo install.
The provisioner fetches the commit above and copies its package non-editably
into `media/site-packages`, with only the two supported inference entrypoints
under `examples/inference/basic`. No source checkout, Git metadata, assets,
docs, ComfyUI, model weights or editable-install metadata are bundled.

`media_worker.py` speaks newline-delimited JSON on stdin/stdout and binds no
socket. Production uses the same interpreter as the server, with media's
package target first on PYTHONPATH, user packages disabled, and bytecode writes
disabled. FFmpeg comes from imageio-ffmpeg's bundled Apple Silicon executable.
Models and outputs honor the application's support directory. `PROMETH_MEDIA_MOCK`
remains a developer-only switch; portable release evidence must use real weights.

The exact lock retains Accelerate 1.15.0: FastVideo's Accelerate 1.0.1 pin is too
old for its Transformers 5.15 dependency's direct-device loading.

Production enters through `bounded_video.py`. UMT5 loads directly onto its
device in bf16/fp16 with mmap shard loading. Wan 1.3B/14B use the full Wan VAE:
fp16, 256px spatial tiles with 64px overlap, one latent frame at a time with
persistent causal feature caches. Completed pixel chunks move to CPU immediately.
Wan 5B uses TAEHV with fp16 weights, one latent frame, persistent MemBlock state,
and 16px latent spatial cores with a 20px convolution halo. MLX's allocator cache
is capped at 256 MiB; MLX/MPS caches clear between stages.

Release preparation removes development artifacts and unused training runners.
Real image/video execution after that preparation is a shipment prerequisite.
