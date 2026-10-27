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

# Full-process cold peaks (2026-10-27 night), including VAE/RIFE.
# ceil(peak GiB * 1.10 * 2) / 2; evidence: media-tiers/full-run-summary-fix.json.
MEDIA_MEMORY_GB = {
    'images': 6.0,
    'images-9b': 13.5,
    'video': 15.0,
    'video-5b': 17.5,
    'video-14b': 25.0,
}


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
                enabled=enabled, workingMemoryGB=MEDIA_MEMORY_GB.get(model_id, memory), revision=info['sha'], files=files,
                downloadBytes=sum(f['size'] for f in files))


def update(entries):
    catalog = json.loads(CATALOG.read_text())
    by_id = {m['id']: m for m in entries}
    catalog['models'] = [by_id.pop(m['id'], m) for m in catalog['models']] + list(by_id.values())
    CATALOG.write_text(json.dumps(catalog, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--voice', action='store_true')
    parser.add_argument('--chat', action='store_true')
    parser.add_argument('--media', action='store_true')
    args = parser.parse_args()
    if args.voice:
        update([
            entry('kokoro', 'Kokoro 82M', 'mlx-community/Kokoro-82M-bf16', 'mlx-audio', 0.8, 'Voice',
                  ['config.json', 'kokoro-v1_0.safetensors', 'voices/af_heart.safetensors']),
            entry('stt-base', 'Whisper base', 'mlx-community/whisper-base-asr-fp16', 'mlx-audio', 0.6, 'Voice option'),
            entry('vad', 'Silero VAD v5', 'onnx-community/silero-vad', 'onnxruntime', 0.05, 'Voice',
                  ['onnx/model.onnx', 'LICENSE']),
        ])

    if args.chat:
        update([
            entry('safe-qwen9b', 'Qwen3.5 9B', 'mlx-community/Qwen3.5-9B-4bit', 'mlx-vlm', 9, 'Chat option'),
            entry('safe-qwen4b', 'Qwen3.5 4B', 'mlx-community/Qwen3.5-4B-4bit', 'mlx-vlm', 5.5, 'Chat option'),
            entry('safe-qwen2b', 'Qwen3.5 2B', 'mlx-community/Qwen3.5-2B-4bit', 'mlx-vlm', 3, 'Chat option'),
            entry('safe-llama1b', 'Llama 3.2 1B Instruct', 'mlx-community/Llama-3.2-1B-Instruct-4bit', 'mlx-lm', 1.8, 'Chat option'),
            entry('evil-4b', 'Qwen3.5 4B Heretic', 'darrellbest/Qwen3.5-4B-Heretic-GGUF', 'llama.cpp', 4.5, 'Evil option',
                  ['Qwen3.5-4B-Heretic-Q4_K_M.gguf']),
        ])

    if args.media:
        # Skip ema/ DiT duplicate — generation uses the root mlx_dit checkpoint.
        def video_paths(repo):
            with urlopen(f'https://huggingface.co/api/models/{repo}?blobs=true', timeout=45) as response:
                return [
                    blob['rfilename'] for blob in json.load(response)['siblings']
                    if not blob['rfilename'].startswith('ema/')
                    and blob['rfilename'].endswith(('.json', '.safetensors', '.txt', '.model', '.pth', '.pt'))
                ]
        update([
            entry('images-9b', 'FLUX.2 Klein 9B · 8-bit', 'mlx-community/flux2-klein-9b-8bit', 'mflux', MEDIA_MEMORY_GB['images-9b'], 'Images option'),
            entry('video-14b', 'FastMetal 14B QAD', 'FastVideo/FastMetal-14B-QAD', 'fastvideo', MEDIA_MEMORY_GB['video-14b'], 'Video option',
                  video_paths('FastVideo/FastMetal-14B-QAD')),
            entry('video-5b', 'FastMetal 5B QAD', 'FastVideo/FastMetal-5B-QAD', 'fastvideo-mlx', MEDIA_MEMORY_GB['video-5b'], 'Video option',
                  video_paths('FastVideo/FastMetal-5B-QAD'), enabled=True),
        ])
