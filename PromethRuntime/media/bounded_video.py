# SPDX-License-Identifier: Apache-2.0
"""Prometh's memory-bounded adapter for the pinned FastVideo entrypoints.

Keep upstream weights and sampling unchanged. Decode one causal time step at
a time, with spatial tiles, and put completed pixels on CPU immediately.
"""

from __future__ import annotations

import gc
import importlib
import sys
import time
from pathlib import Path
from typing import Any


def clear_stage() -> None:
    import mlx.core as mx
    import torch

    mx.synchronize()
    gc.collect()
    mx.clear_cache()
    if torch.backends.mps.is_available():
        torch.mps.synchronize()
        torch.mps.empty_cache()


def encode_prompt(
    *, model_root: Path, prompt: str, max_sequence_length: int,
    device_arg: str, dtype_arg: str,
) -> Any:
    """Load UMT5 once, directly in its inference dtype, using mmap shards.

    Transformers 5 uses `dtype`; keep compatibility with the pinned 4.x API.
    No fp32 state dict or second full model is constructed by this adapter.
    """
    import torch
    import transformers
    from transformers import AutoTokenizer, UMT5EncoderModel

    clear_stage()
    device = "mps" if device_arg == "auto" and torch.backends.mps.is_available() else device_arg
    if device == "auto":
        device = "cpu"
    dtype = {"fp16": torch.float16, "bf16": torch.bfloat16, "fp32": torch.float32}[dtype_arg]
    dtype_key = "dtype" if int(transformers.__version__.split(".")[0]) >= 5 else "torch_dtype"
    tokenizer = AutoTokenizer.from_pretrained(model_root / "tokenizer", local_files_only=True)
    model = UMT5EncoderModel.from_pretrained(
        model_root / "text_encoder", **{dtype_key: dtype},
        low_cpu_mem_usage=True, local_files_only=True, device_map={"": device},
    ).eval()
    actual_dtype = next(model.parameters()).dtype
    if actual_dtype != dtype:
        raise RuntimeError(f"UMT5 loaded {actual_dtype}, expected {dtype}")
    print(f"[Prometh] UMT5 direct load {actual_dtype} on {device}", flush=True)
    inputs = tokenizer([prompt], padding="max_length", max_length=max_sequence_length,
                       truncation=True, add_special_tokens=True, return_tensors="pt")
    ids = inputs.input_ids.to(device)
    mask = inputs.attention_mask.to(device)
    with torch.inference_mode():
        hidden = model(ids, mask).last_hidden_state
        # Transfer only the result, then release the entire encoder before DiT.
        result = hidden.to(device="cpu", dtype=torch.float32).contiguous()
        length = int(mask.sum().item())
        result[:, length:] = 0
    if not torch.isfinite(result).all():
        raise RuntimeError("UMT5 produced non-finite prompt embeddings")
    del model, tokenizer, inputs, ids, mask, hidden
    clear_stage()
    return result


def decode_wan(
    latents_np: Any, *, vae_dir: Path, device: str = "auto", dtype_name: str = "fp16",
) -> Any:
    """Wan VAE: overlapping 256px tiles, one latent frame, CPU pixel storage.

    This follows Diffusers' tiled_decode, including its causal feature cache
    and overlap blending. Only completed RGB chunks move to CPU; temporal
    context is never reset within a tile. Output storage is bounded by pixels,
    rather than retaining a clip's decoder activations on Metal.
    """
    import numpy as np
    import torch
    from diffusers import AutoencoderKLWan
    from diffusers.models.autoencoders.autoencoder_kl_wan import unpatchify

    clear_stage()
    if device == "auto":
        device = "mps" if torch.backends.mps.is_available() else "cpu"
    dtype = torch.float16 if device == "mps" else torch.float32
    vae = AutoencoderKLWan.from_pretrained(
        vae_dir, torch_dtype=dtype, low_cpu_mem_usage=True, local_files_only=True,
    ).eval().to(device)
    scale = vae.spatial_compression_ratio
    size, stride = 256 // scale, 192 // scale
    patch = vae.config.patch_size or 1
    pixel_stride = stride * scale // patch
    overlap = (size - stride) * scale // patch
    z = torch.from_numpy(latents_np)
    mean = torch.tensor(vae.config.latents_mean, dtype=dtype, device=device).view(1, -1, 1, 1, 1)
    std = torch.tensor(vae.config.latents_std, dtype=dtype, device=device).view(1, -1, 1, 1, 1)
    rows = []
    print("[Prometh] Wan VAE fp16: 256px tiles / 192px stride / 1 latent frame", flush=True)
    with torch.inference_mode():
        for y in range(0, z.shape[3], stride):
            row = []
            for x in range(0, z.shape[4], stride):
                vae.clear_cache()
                chunks = []
                for t in range(z.shape[2]):
                    tile = z[:, :, t:t+1, y:y+size, x:x+size].to(device=device, dtype=dtype)
                    tile = vae.post_quant_conv(tile * std + mean)
                    vae._conv_idx = [0]
                    decoded = vae.decoder(tile, feat_cache=vae._feat_map,
                                          feat_idx=vae._conv_idx, first_chunk=(t == 0))
                    chunks.append(decoded.cpu())
                    del tile, decoded
                    clear_stage()
                row.append(torch.cat(chunks, dim=2))
                del chunks
            rows.append(row)
        vae.clear_cache()
        result_rows = []
        for y, row in enumerate(rows):
            result_row = []
            for x, tile in enumerate(row):
                if y:
                    tile = vae.blend_v(rows[y-1][x], tile, overlap)
                if x:
                    tile = vae.blend_h(row[x-1], tile, overlap)
                result_row.append(tile[:, :, :, :pixel_stride, :pixel_stride])
            result_rows.append(torch.cat(result_row, dim=-1))
        video = torch.cat(result_rows, dim=3)[:, :, :, :z.shape[3]*scale//patch, :z.shape[4]*scale//patch]
        if patch > 1:
            video = unpatchify(video, patch_size=patch)
        video = (video.float().clamp(-1, 1) + 1) / 2
        result = video.permute(0, 2, 3, 4, 1).numpy()
    del vae, z, rows, result_rows, video, mean, std
    clear_stage()
    if not np.isfinite(result).all():
        raise RuntimeError("Wan VAE produced non-finite pixels")
    return result


def decode_tiny(
    latents_np: Any, *, z_dim: int | None = None,
    checkpoint_path: Path | None = None, dtype_name: str = "fp16",
) -> Any:
    """TAEHV in fp16, spatial cores with halo and persistent temporal state.

    The decoder's convolution radius is <20 latent pixels. Cropping that halo
    preserves the full-image result at internal tile boundaries. Each call
    processes one latent frame, retaining each MemBlock's previous feature.
    """
    import numpy as np
    import mlx.core as mx
    from fastvideo.mlx_runtime.wan_vae import MLXTAEHVDecoder, ensure_taehv_checkpoint

    # Adapted from fastvideo/mlx_runtime/wan_vae.py at FASTVIDEO_COMMIT in
    # media_worker.py (Apache-2.0), retaining the convolution order and weights.
    class StreamingDecoder(MLXTAEHVDecoder):
        def _run_decoder_parallel(self, x, *, n):
            # The pinned implementation calls mx.concatenate for mem_past.
            # Use the same conv stack with an explicit past cache instead.
            return self.run_frame(x, n=n)

        def run_frame(self, x, *, n):
            from fastvideo.mlx_runtime.wan_vae import _mlx_conv2d, _mlx_conv2d_1x1
            w = self.weights

            def conv(index, value):
                return _mlx_conv2d(value, w[f"decoder.{index}.weight"], w.get(f"decoder.{index}.bias"))

            def mem(index, value):
                nt, c, h, width = value.shape
                frames = value.reshape(n, nt//n, c, h, width)
                previous = self.past.get(index, mx.zeros_like(frames[:, :1]))
                past = mx.concatenate([previous, frames[:, :-1]], axis=1).reshape(value.shape)
                self.past[index] = frames[:, -1:]
                hidden = mx.concatenate([value, past], axis=1)
                for layer in (0, 2, 4):
                    base = f"decoder.{index}.conv.{layer}"
                    hidden = _mlx_conv2d(hidden, w[f"{base}.weight"], w.get(f"{base}.bias"))
                    if layer != 4:
                        hidden = mx.maximum(hidden, 0)
                key = f"decoder.{index}.skip.weight"
                skip = _mlx_conv2d_1x1(value, w[key]) if key in w else value
                return mx.maximum(hidden + skip, 0)

            def grow(index, value, temporal):
                value = mx.repeat(mx.repeat(value, 2, axis=2), 2, axis=3)
                channels = value.shape[1]
                weight = w[f"decoder.{index}.conv.weight"][-channels*temporal:]
                value = _mlx_conv2d_1x1(value, weight)
                return value.reshape(-1, channels, value.shape[2], value.shape[3])

            x = mx.maximum(conv(1, mx.tanh(x / 3) * 3), 0)
            for index in (3, 4, 5):
                x = mem(index, x)
            x = conv(8, grow(7, x, 1))
            for index in (9, 10, 11):
                x = mem(index, x)
            x = conv(14, grow(13, x, 2))
            for index in (15, 16, 17):
                x = mem(index, x)
            return conv(22, mx.maximum(conv(20, grow(19, x, 2)), 0))

    clear_stage()
    channels = z_dim or latents_np.shape[1]
    dec = StreamingDecoder(ensure_taehv_checkpoint(z_dim=channels, checkpoint_path=checkpoint_path), z_dim=channels)
    dtype = {"fp16": mx.float16, "fp32": mx.float32}[dtype_name]
    dec.weights = {k: v.astype(dtype) for k, v in dec.weights.items()}
    mx.eval(dec.weights)
    dec.frames_to_trim = 0
    batch, _, frames, height, width = latents_np.shape
    scale = 16 if channels == 48 else 8
    result = np.empty((batch, frames*4-3, height*scale, width*scale, 3), dtype=np.float16 if dtype_name == "fp16" else np.float32)
    core, halo = 16, 20
    print(f"[Prometh] TAEHV {dtype_name}: 16px latent cores / 20px halo / 1 latent frame", flush=True)
    for y in range(0, height, core):
        for x in range(0, width, core):
            y0, x0 = max(0, y-halo), max(0, x-halo)
            y1, x1 = min(height, y+core+halo), min(width, x+core+halo)
            dec.past = {}
            for t in range(frames):
                tile = mx.array(latents_np[:, :, t:t+1, y0:y1, x0:x1].transpose(0, 2, 1, 3, 4)).astype(dtype)
                out = dec.decode_ntchw(tile)
                mx.eval(out, dec.past)
                pixels = np.array(out).transpose(0, 1, 3, 4, 2)
                trim = 3 if t == 0 else 0
                start = max(0, t*4-3)
                h, w = min(core, height-y)*scale, min(core, width-x)*scale
                result[:, start:start+4-trim, y*scale:y*scale+h, x*scale:x*scale+w] = pixels[:, trim:, (y-y0)*scale:(y-y0)*scale+h, (x-x0)*scale:(x-x0)*scale+w]
                del tile, out, pixels
                mx.clear_cache()
            dec.past.clear()
    del dec
    clear_stage()
    if not np.isfinite(result).all():
        raise RuntimeError("TAEHV produced non-finite pixels")
    return result


def install() -> None:
    """Install adapters in the pinned modules, without editing the checkout."""
    import mlx.core as mx
    from fastvideo.mlx_runtime import checkpoint, wan_vae

    # A bounded allocator cache prevents freed denoise buffers from surviving
    # into decode. Packed DiT weights load directly through upstream mx.load.
    mx.set_cache_limit(256 * 1024**2)
    original_load = checkpoint.load_mlx_dit_checkpoint

    def load_checkpoint(*args, **kwargs):
        clear_stage()
        model = original_load(*args, **kwargs)
        clear_stage()
        return model

    checkpoint.load_mlx_dit_checkpoint = load_checkpoint
    wan_vae.decode_latents_taehv_mlx = decode_tiny
    wan_vae.decode_latents_wan_vae_torch = decode_wan
    wan21 = importlib.import_module("examples.inference.basic.mlx_wan_prompt_to_video")
    wan21.encode_prompt = encode_prompt
    # Avoid the upstream subprocess re-entering an unadapted script.
    wan21.encode_prompt_subprocess = encode_prompt

    def decode_wan21(**kwargs):
        return wan_vae.decode_latents_to_video(
            kwargs["latents_np"], kwargs["output_path"], fps=kwargs["fps"],
            backend=kwargs["backend"], vae_dir=kwargs["model_root"] / "vae",
            taehv_checkpoint=kwargs["taehv_checkpoint_path"], torch_device=kwargs["device_arg"],
        )

    wan21.decode_latents_to_video = decode_wan21


def main() -> None:
    script = Path(sys.argv.pop(1)).resolve()
    checkout = script.parents[3]
    sys.path.insert(0, str(checkout))
    install()
    name = "examples.inference.basic." + script.stem
    module = importlib.import_module(name)
    sys.argv[0] = str(script)
    started = time.perf_counter()
    module.main()
    clear_stage()
    print(f"[Prometh] full pipeline finished in {time.perf_counter()-started:.1f}s", flush=True)


if __name__ == "__main__":
    main()
