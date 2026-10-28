"""Pinned local Kokoro. CLI compatibility plus a resident JSON-lines worker."""
import contextlib
import json
import sys
from pathlib import Path
import numpy as np
import wave


def main():
    import tempfile
    import shutil
    import espeakng_loader
    # espeak's data-path buffer cannot hold long app bundle paths.
    alias_root = tempfile.TemporaryDirectory(prefix='pv-', dir='/tmp')
    alias = Path(alias_root.name) / 'espeak-ng-data'
    shutil.copytree(espeakng_loader.get_data_path(), alias)
    espeakng_loader.get_data_path = lambda: str(alias)
    with contextlib.redirect_stdout(sys.stderr):
        from mlx_audio.tts.utils import load_model
        model = load_model(Path(sys.argv[1]))

    def render(text, output, voice):
        if not text.strip():
            raise ValueError('No text to speak')
        if voice not in {'af_heart', 'af_bella', 'af_nicole', 'bf_emma', 'am_michael', 'bm_george'}:
            raise ValueError('Unknown voice')
        # The caller sends sentences individually; don't wait for the entire LLM reply.
        with contextlib.redirect_stdout(sys.stderr):
            chunks = list(model.generate(text, voice=voice, lang_code=voice[0]))
        if not chunks:
            raise ValueError('Kokoro generated no audio')
        audio = np.concatenate([np.array(c.audio).reshape(-1) for c in chunks])
        with wave.open(str(output), 'wb') as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(chunks[0].sample_rate)
            wav.writeframes((np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes())

    if sys.argv[2] != '--serve':
        render(sys.stdin.read(), sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'af_heart')
        return
    print(json.dumps({'ready': True}), flush=True)
    for line in sys.stdin:
        try:
            item = json.loads(line)
            render(item['text'], item['output'], item.get('voice', 'af_heart'))
            print(json.dumps({'ok': True}), flush=True)
        except Exception:
            # Do not include words or private paths in protocol/errors.
            print(json.dumps({'ok': False, 'error': 'Speech synthesis failed.'}), flush=True)


if __name__ == '__main__':
    main()
