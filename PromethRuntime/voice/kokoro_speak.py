"""Run pinned local Kokoro with mlx-audio in the bundled interpreter."""
import contextlib
import sys
from pathlib import Path
import numpy as np
import wave


def main():
    # espeak has a short internal data-path buffer. App bundle paths can exceed
    # it, so give the packaged phoneme data a short temporary copy (the wrapper resolves symlinks).
    import tempfile
    import shutil
    import espeakng_loader
    alias_root = tempfile.TemporaryDirectory(prefix='pv-', dir='/tmp')
    alias = Path(alias_root.name) / 'espeak-ng-data'
    shutil.copytree(espeakng_loader.get_data_path(), alias)
    espeakng_loader.get_data_path = lambda: str(alias)
    from mlx_audio.tts.utils import load_model
    text = sys.stdin.read().strip()
    if not text:
        raise ValueError('No text to speak')
    # Model diagnostics belong on stderr; the app never displays model internals.
    with contextlib.redirect_stdout(sys.stderr):
        model = load_model(Path(sys.argv[1]))
        chunks = list(model.generate(text, voice='af_heart', lang_code='a'))
    if not chunks:
        raise ValueError('Kokoro generated no audio')
    audio = np.concatenate([np.array(c.audio).reshape(-1) for c in chunks])
    with wave.open(sys.argv[2], 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(chunks[0].sample_rate)
        output.writeframes((np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes())


if __name__ == '__main__':
    main()
