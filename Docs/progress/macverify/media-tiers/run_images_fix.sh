#!/bin/bash
# Cold CLI process, production image geometry. Existing model files stay local.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
OUTDIR="$ROOT/Docs/progress/macverify/media-tiers"
PYROOT="$ROOT/build/NativDevelopmentDerivedData/Build/Products/Release/NativServerKit.framework/Versions/A/Resources/mlx-vlm-server"
case "$1" in
  images) MODEL="$HOME/Library/Application Support/Prometh/Models/Runpod--FLUX.2-klein-4B-mflux-4bit--7ee1b3aa8178" ;;
  images-9b) MODEL="$HOME/Library/Application Support/Prometh/Models/mlx-community--flux2-klein-9b-8bit--07c85fd97195" ;;
  *) exit 2 ;;
esac
LABEL="$1-timed$2-fix"
export PYTHONNOUSERSITE=1 PYTHONUNBUFFERED=1 HF_HUB_OFFLINE=1
export MLX_VLM_MODEL_PATHS="$HOME/Library/Application Support/Prometh/Models"
if pgrep -f 'llama-server|mlx-vlm-server.*--host|nativ_server' >/dev/null; then
  echo 'Refusing measurement with chat server running' >&2
  exit 2
fi
exec "$OUTDIR/timed_run.sh" "$LABEL" -- "$PYROOT/python/bin/python3" -m mlx_vlm.generate \
  --model "$MODEL" --output-modality image --task generate \
  --prompt 'a calm ocean wave rolling onto a sandy beach at sunset, photorealistic' \
  --size 512x512 --steps 4 --seed 1024 --output "$OUTDIR/$LABEL.png"
