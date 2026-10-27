# FastVideo for clips

Prometh does not vendor FastVideo or the FastMetal weights.

- FastVideo commit: `8db2d71ef217e84bec7dbb6e4ab65c92b144df4f` (Apache-2.0)
- Model: `FastVideo/FastMetal-1.3B-QAD`
- Revision: `2dac0154b217adabf8895d6cde7d6d93e68b7bec`
- Output: silent, 832×480, about 5 seconds, `--decode-backend wan-vae`

`media_worker.py` speaks newline-delimited JSON on stdin/stdout and binds no socket. A real generation needs the FastVideo checkout and the catalog download on the Mac. `PROMETH_MEDIA_MOCK=1` writes a stand-in file with the system ffmpeg when one is already installed. ffmpeg is not bundled.

Production commands enter through tracked `bounded_video.py`; the external
checkout remains unchanged. UMT5 loads directly onto its device in bf16/fp16
with mmap shard loading. Install the pinned checkout first, then install
`requirements-prometh.txt` in `media/.venv`: FastVideo's Accelerate 1.0.1 pin
is too old for its Transformers 5.15 dependency's direct-device loading.

Wan 1.3B/14B retain the full Wan VAE: fp16, 256px spatial tiles with 64px
overlap, and one latent frame at a time with persistent causal feature caches.
Completed pixel chunks move to CPU immediately. Wan 5B retains TAEHV with
fp16 weights, one latent frame, persistent MemBlock state, and 16px latent
spatial cores with a 20px convolution halo. MLX's allocator cache is capped at
256 MiB and MLX/MPS caches are cleared between encoder, load, denoise and decode.
The upstream entrypoints delete the transformer before invoking our decoder.

Numerical decoder regression (provisioned media venv):
`PYTHONPATH=PromethRuntime/media/fastvideo PromethRuntime/media/.venv/bin/python3 -m pytest PromethRuntime/media/test_bounded_video.py`.
