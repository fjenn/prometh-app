#!/usr/bin/env python3
"""Run a command and sample peak phys_footprint / RSS while it runs.

Writes a JSON summary to --out and mirrors key lines to stdout.
Does not invent numbers: values come from /usr/bin/time -l and/or sample loops.
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


def _parse_time_l(text: str) -> dict:
    out = {}
    for line in text.splitlines():
        lower = line.strip().lower()
        if "maximum resident set size" in lower:
            # macOS time -l: "12345678  maximum resident set size"
            parts = line.strip().split()
            if parts:
                out["max_rss_bytes"] = int(parts[0])
        if "peak memory footprint" in lower:
            parts = line.strip().split()
            if parts:
                out["peak_footprint_bytes"] = int(parts[0])
    return out


def _sample_footprint(pid: int, stop: threading.Event, samples: list) -> None:
    while not stop.is_set():
        try:
            # footprint -p prints phys_footprint among other lines.
            proc = subprocess.run(
                ["footprint", "-p", str(pid)],
                capture_output=True,
                text=True,
                timeout=2,
            )
            text = proc.stdout + proc.stderr
            for line in text.splitlines():
                if "phys_footprint" in line.lower() or "Footprint:" in line:
                    # Prefer numeric tokens that look like byte counts / with units
                    samples.append({"t": time.time(), "line": line.strip()})
        except Exception as exc:  # noqa: BLE001 — sampler must never kill the job
            samples.append({"t": time.time(), "error": str(exc)})
        stop.wait(1.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--cwd", type=Path, default=None)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("missing command", file=sys.stderr)
        return 2

    time_log = args.out.with_suffix(args.out.suffix + ".time.txt")
    # /usr/bin/time -l wraps the real command.
    wrapped = ["/usr/bin/time", "-l", *command]
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    print(f"[measure] label={args.label}", flush=True)
    print(f"[measure] cmd={' '.join(command)}", flush=True)
    start = time.time()
    child = subprocess.Popen(
        wrapped,
        cwd=str(args.cwd) if args.cwd else None,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    stop = threading.Event()
    samples: list = []
    # Sample the inner process group leader (time's child is hard; sample `time` pid tree).
    sampler = threading.Thread(target=_sample_footprint, args=(child.pid, stop, samples), daemon=True)
    sampler.start()
    stdout, stderr = child.communicate()
    stop.set()
    sampler.join(timeout=3)
    elapsed = time.time() - start
    stderr_text = stderr.decode("utf-8", errors="replace")
    stdout_text = stdout.decode("utf-8", errors="replace")
    time_log.write_text(stderr_text)
    parsed = _parse_time_l(stderr_text)
    # Also try to find MLX peak lines in stdout/stderr of the job
    mlx_peaks = []
    for stream in (stdout_text, stderr_text):
        for line in stream.splitlines():
            if "peak memory" in line.lower() or "mlx" in line.lower() and "gi" in line.lower():
                mlx_peaks.append(line.strip())

    summary = {
        "label": args.label,
        "command": command,
        "exit_code": child.returncode,
        "elapsed_s": round(elapsed, 3),
        "time_l": parsed,
        "max_rss_gib": round(parsed["max_rss_bytes"] / (1024**3), 3) if "max_rss_bytes" in parsed else None,
        "peak_footprint_gib": round(parsed["peak_footprint_bytes"] / (1024**3), 3) if "peak_footprint_bytes" in parsed else None,
        "mlx_peak_lines": mlx_peaks[-20:],
        "footprint_samples": samples[-30:],
        "stdout_tail": "\n".join(stdout_text.splitlines()[-40:]),
        "stderr_tail": "\n".join(stderr_text.splitlines()[-40:]),
    }
    args.out.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: summary[k] for k in ("label", "exit_code", "elapsed_s", "max_rss_gib", "peak_footprint_gib")}, indent=2), flush=True)
    return child.returncode


if __name__ == "__main__":
    sys.exit(main())
