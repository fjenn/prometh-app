#!/usr/bin/env python3
"""Refresh selected catalog entries using public HF blob metadata (no tokens).

LFS files use their SHA-256; ordinary files use Git blob SHA-1, exactly as
CatalogDownloader verifies them. URLs always contain an immutable commit.
"""
import argparse
import json
from pathlib import Path
from urllib.request import urlopen
from urllib.parse import quote

CATALOG = Path(__file__).resolve().parents[2] / 'Sources/Prometh/Resources/model-catalog.json'


def entry(model_id, name, repo, runtime, memory, capability, paths=None, enabled=True):
    with urlopen(f'https://huggingface.co/api/models/{repo}?blobs=true', timeout=45) as response:
        info = json.load(response)
    files = []
    for blob in info['siblings']:
        path = blob['rfilename']
        if paths is not None:
            if path not in paths:
                continue
        elif not (path.endswith(('.json', '.safetensors', '.jinja', '.txt', '.model')) and not path.startswith('samples/')):
            continue
        lfs = blob.get('lfs')
        algorithm = 'sha256' if lfs else 'git-blob-sha1'
        digest = lfs['sha256'] if lfs else blob['blobId']
        files.append(dict(path=path, size=blob['size'], hashAlgorithm=algorithm, hash=digest,
                          sha256=digest if lfs else None, oid=None if lfs else digest,
                          contentID=f'{algorithm}:{digest}',
                          url=f'https://huggingface.co/{repo}/resolve/{info["sha"]}/{quote(path)}'))
    if not files or (paths is not None and set(paths) != {f['path'] for f in files}):
        raise ValueError(f'Missing files for {repo}: {paths}')
    return dict(id=model_id, name=name, capability=capability, repo=repo, runtime=runtime,
                enabled=enabled, workingMemoryGB=memory, revision=info['sha'], files=files,
                downloadBytes=sum(f['size'] for f in files))


def update(entries):
    catalog = json.loads(CATALOG.read_text())
    by_id = {m['id']: m for m in entries}
    catalog['models'] = [by_id.pop(m['id'], m) for m in catalog['models']] + list(by_id.values())
    CATALOG.write_text(json.dumps(catalog, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--voice', action='store_true')
    args = parser.parse_args()
    if args.voice:
        update([
            entry('kokoro', 'Kokoro 82M', 'mlx-community/Kokoro-82M-bf16', 'mlx-audio', 0.8, 'Voice',
                  ['config.json', 'kokoro-v1_0.safetensors', 'voices/af_heart.safetensors']),
            entry('stt-base', 'Whisper base', 'mlx-community/whisper-base-asr-fp16', 'mlx-audio', 0.6, 'Voice option'),
            entry('vad', 'Silero VAD v5', 'onnx-community/silero-vad', 'onnxruntime', 0.05, 'Voice',
                  ['onnx/model.onnx', 'LICENSE']),
        ])
