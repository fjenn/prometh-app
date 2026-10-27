#!/usr/bin/env python3
"""Derive catalog budgets from successful, full-process -fix measurements."""
from __future__ import annotations

import json
import math
import re
from pathlib import Path

OUT = Path(__file__).resolve().parent
RAM = [8, 16, 24, 32, 36, 48, 64, 128]
RUNS = {"images": [1, 2], "images-9b": [1, 2], "video": [1, 2],
        "video-5b": [3, 4], "video-14b": [1, 2]}
ORDER = {"images": ["images-9b", "images"], "video": ["video-14b", "video-5b", "video"]}
GIB = 1024**3


def read_run(model: str, run: int) -> dict:
    label = f"{model}-timed{run}-fix"
    timing = (OUT / f"{label}.time.txt").read_text()
    if not re.search(r"^EXIT:0$", timing, re.M):
        raise ValueError(f"{label} did not complete successfully")
    log = (OUT / f"{label}.log").read_text()
    if model.startswith("video") and "[Prometh] full pipeline finished" not in log:
        raise ValueError(f"{label} did not finish decode and postprocessing")
    rss = int(re.search(r"(\d+)\s+maximum resident set size", timing)[1])
    footprint = int(re.search(r"(\d+)\s+peak memory footprint", timing)[1])
    # Formatted samples (first 1.3B run) round to whole GB. Prefer the exact
    # kernel peak from time -l; only byte-format samples enter the decision.
    samples = [int(x) for x in re.findall(
        r"phys_footprint(?:_peak)?:\s*(\d+)\s+B\b",
        (OUT / f"{label}.footprint.txt").read_text(),
    )]
    mlx = [float(x) for x in re.findall(r"peak memory:\s*([\d.]+)\s+GiB", log)]
    mlx += [float(x) for x in re.findall(r'"peak_gib":\s*([\d.]+)', log)]
    peak = max(rss, footprint, max(samples, default=0), max(mlx, default=0)*GIB)
    artifact = OUT / f"{label}.{'mp4' if model.startswith('video') else 'png'}"
    if not artifact.is_file() or artifact.stat().st_size == 0:
        raise ValueError(f"{label} has no output artifact")
    return dict(label=label, maxRSSGiB=rss/GIB, peakFootprintGiB=footprint/GIB,
                sampledExactPeakGiB=max(samples)/GIB if samples else None,
                mlxPeakGiB=max(mlx, default=0), fullRunPeakGiB=peak/GIB,
                artifact=artifact.name)


def main() -> None:
    models = []
    for model, runs in RUNS.items():
        measured = [read_run(model, run) for run in runs]
        peak = max(r["fullRunPeakGiB"] for r in measured)
        working = math.ceil(peak * 1.10 * 2) / 2
        eligible = next((ram for ram in RAM if working*1.08 <= ram*0.75-1), None)
        models.append(dict(id=model, fullRunPeakGiB=peak, workingMemoryGB=working,
                           minEligibleRAM=eligible, runs=measured))
    by_id = {m["id"]: m for m in models}
    picks = {}
    for family, ids in ORDER.items():
        picks[family] = {
            str(ram): next((mid for mid in ids if by_id[mid]["workingMemoryGB"]*1.08 <= ram*0.75-1), None)
            for ram in RAM
        }
    for model in models:
        family = "video" if model["id"].startswith("video") else "images"
        model["minAutoRAM"] = next((int(ram) for ram, mid in picks[family].items() if mid == model["id"]), None)
    result = dict(formula="ceil(peak GiB * 1.10 * 2) / 2", models=models, picks=picks)
    (OUT / "full-run-summary-fix.json").write_text(json.dumps(result, indent=2) + "\n")
    print("| Model id | Real full-run peak GiB | workingMemoryGB | Minimum Mac RAM auto-pick |")
    print("|---|---:|---:|---|")
    for model in models:
        ram = f'{model["minAutoRAM"]} GB' if model["minAutoRAM"] else f'Fallback only (eligible from {model["minEligibleRAM"]} GB)'
        print(f'| `{model["id"]}` | {model["fullRunPeakGiB"]:.3f} | {model["workingMemoryGB"]:.1f} | {ram} |')


if __name__ == "__main__":
    main()
