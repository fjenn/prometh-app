"""Numerical regression for causal streaming and spatial halo cropping.

Run in the provisioned media venv with PYTHONPATH including FastVideo.
The deterministic inputs here are unit-test tensors, never verification clips.
"""
import numpy as np
import pytest

import bounded_video


@pytest.mark.parametrize("channels", [16, 48])
@pytest.mark.parametrize("height,width", [(8, 8), (18, 57)])
def test_tiny_streaming_matches_parallel_decoder(channels, height, width):
    import mlx.core as mx
    from fastvideo.mlx_runtime.wan_vae import MLXTAEHVDecoder, ensure_taehv_checkpoint

    # Crosses a spatial core boundary and exercises all causal transitions.
    latents = np.random.default_rng(7).normal(size=(1, channels, 3, height, width)).astype(np.float32)
    model = MLXTAEHVDecoder(ensure_taehv_checkpoint(z_dim=channels), z_dim=channels)
    full = model.decode_ntchw(mx.array(latents.transpose(0, 2, 1, 3, 4)))
    mx.eval(full)
    expected = np.array(full).transpose(0, 1, 3, 4, 2)
    del model, full
    bounded_video.clear_stage()
    actual = bounded_video.decode_tiny(latents, z_dim=channels, dtype_name="fp32")
    assert actual.shape == expected.shape
    if width == 8:
        # Identical spatial shape: causal states must reproduce parallel time.
        np.testing.assert_allclose(actual, expected, atol=0.0001, rtol=0.0001)
    else:
        # MLX selects different convolution kernels for different tile shapes.
        # Check average RGB error (<one 8-bit level), including internal seams.
        error = np.abs(actual - expected)
        assert error.mean() < 0.003
        scale = 16 if channels == 48 else 8
        for boundary in range(16*scale, width*scale, 16*scale):
            assert error[:, :, :, boundary-2:boundary+2].mean() < 0.003
    half = bounded_video.decode_tiny(latents, z_dim=channels)
    # fp16 conv kernels accumulate differently for sequential / batched time.
    # Bound average pixel error against the original fp32 reference as well.
    assert np.abs(half.astype(np.float32) - expected).mean() < 0.003
