"""Speak stdin with the Pocket TTS weights already on disk.

mlx-audio cannot load kyutai/pocket-tts-without-voice-cloning (no config.json).
This loader uses the pocket-tts package and the local english_2026-09_2 snapshot.
"""

from __future__ import annotations

import os
import sys
import wave
from pathlib import Path

LANGUAGE = "english_2026-09_2"


def model_root() -> Path:
    override = os.environ.get("PROMETH_POCKET_ROOT")
    if override:
        return Path(override)
    return (
        Path.home()
        / "Library/Application Support/Prometh/Models"
        / "kyutai--pocket-tts-without-voice-cloning--a7056f505a4a"
    )


def write_wav(path: Path, samples, sample_rate: int) -> None:
    import numpy as np

    audio = np.asarray(samples, dtype="float32").reshape(-1)
    if audio.size == 0:
        raise RuntimeError("Pocket TTS returned no samples")
    peak = float(np.max(np.abs(audio)))
    if peak > 1:
        audio = audio / peak
    pcm = (np.clip(audio, -1.0, 1.0) * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(pcm.tobytes())


def local_config(weights: Path, tokenizer: Path) -> Path:
    import tempfile

    import yaml
    from importlib.resources import files

    raw = files("pocket_tts").joinpath(f"config/{LANGUAGE}.yaml").read_text(encoding="utf-8")
    config = yaml.safe_load(raw)
    local = str(weights)
    config["weights_path"] = local
    config["weights_path_without_voice_cloning"] = local
    config["flow_lm"]["lookup_table"]["tokenizer_path"] = str(tokenizer)
    handle = tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, encoding="utf-8")
    yaml.safe_dump(config, handle)
    handle.close()
    return Path(handle.name)


def main() -> None:
    text = sys.stdin.read().strip()
    if not text:
        raise SystemExit("empty text")
    if len(sys.argv) != 2:
        raise SystemExit("usage: pocket_speak.py OUTPUT.wav")
    output = Path(sys.argv[1])
    language = model_root() / "languages" / LANGUAGE
    weights = language / "model.safetensors"
    tokenizer = language / "tokenizer.json"
    voice = language / "embeddings" / "alba.safetensors"
    missing = [str(path) for path in (weights, tokenizer, voice) if not path.is_file()]
    if missing:
        raise SystemExit("missing Pocket TTS files: " + ", ".join(missing))

    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    from pocket_tts import TTSModel

    model = TTSModel.load_model(config=local_config(weights, tokenizer))
    state = model.get_state_for_audio_prompt(voice)
    audio = model.generate_audio(state, text)
    write_wav(output, audio.detach().cpu().float().numpy(), int(model.sample_rate))


if __name__ == "__main__":
    main()
