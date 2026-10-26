#!/usr/bin/env python3
"""Live SearXNG plus on-device reader check. Binds 127.0.0.1 only."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "PromethRuntime" / "reader"))

import reader_server  # noqa: E402

SETTINGS = """
use_default_settings: true
server:
  secret_key: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  limiter: false
  public_instance: false
  bind_address: "127.0.0.1"
  image_proxy: false
search:
  formats:
    - html
    - json
valkey:
  url: false
engines:
  - name: google
    disabled: true
  - name: google news
    disabled: true
  - name: google images
    disabled: true
  - name: google videos
    disabled: true
  - name: google scholar
    disabled: true
  - name: google cse
    disabled: true
  - name: google cse images
    disabled: true
  - name: bing
    disabled: true
  - name: qwant
    disabled: true
  - name: startpage
    disabled: true
  - name: duckduckgo
    disabled: false
  - name: brave
    disabled: false
  - name: wikipedia
    disabled: false
  - name: wikidata
    disabled: false
  - name: mojeek
    disabled: false
  - name: github
    disabled: false
  - name: arxiv
    disabled: false
"""


def listeners(port: int) -> list[str]:
    found: list[str] = []
    hexport = f"{port:04X}"
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8"):
            parts = line.split()
            if len(parts) < 4 or parts[3] != "0A":
                continue
            local = parts[1]
            ip_hex, port_hex = local.split(":")
            if port_hex.upper() != hexport:
                continue
            if len(ip_hex) == 8:
                raw = bytes.fromhex(ip_hex)
                ip = ".".join(str(byte) for byte in raw[::-1])
            else:
                ip = ip_hex
            found.append(ip)
    return found


def reserve_port() -> int:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def search(port: int, query: str, engines: str) -> dict:
    # GitHub, arXiv, Wikipedia, and Wikidata are the enabled engines that answer
    # from this network. DuckDuckGo, Brave, and Mojeek are enabled in settings
    # and are recorded when they answer; this host often sees CAPTCHA or 403.
    query_string = urllib.parse.urlencode({
        "q": query,
        "format": "json",
        "engines": engines,
    })
    url = f"http://127.0.0.1:{port}/search?{query_string}"
    with urllib.request.urlopen(url, timeout=45) as response:
        return json.loads(response.read().decode())


def domains(payload: dict) -> list[str]:
    hosts: list[str] = []
    seen: set[str] = set()
    for result in payload.get("results") or []:
        host = urllib.parse.urlparse(result.get("url") or "").hostname
        if host and host not in seen:
            seen.add(host)
            hosts.append(host)
    return hosts


def main() -> None:
    python = ROOT / "PromethRuntime" / "searxng" / ".venv" / "bin" / "python"
    if not python.exists():
        raise SystemExit("missing searxng venv; run scripts/prometh/provision-runtime.py --searxng")
    settings = Path("/tmp/prometh-m4-settings.yml")
    settings.write_text(SETTINGS, encoding="utf-8")
    port = reserve_port()
    env = os.environ.copy()
    env["SEARXNG_SETTINGS_PATH"] = str(settings)
    process = subprocess.Popen(
        [
            str(python), "-m", "granian",
            "--interface", "wsgi",
            "--host", "127.0.0.1",
            "--port", str(port),
            "--workers", "1",
            "searx.webapp:application",
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    report: dict = {"port": port, "passed": False}
    try:
        deadline = time.time() + 30
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=2) as response:
                    if response.status == 200:
                        break
            except Exception:
                if process.poll() is not None:
                    output = process.stdout.read().decode(errors="replace") if process.stdout else ""
                    raise SystemExit(output[-4000:])
            time.sleep(0.25)
        else:
            raise SystemExit("healthz timed out")

        bound = listeners(port)
        report["listeners"] = bound
        if not bound or any(ip not in {"127.0.0.1", "0000000000000000000000000100007F"} for ip in bound):
            raise SystemExit(f"listener is not loopback only: {bound}")

        payload = search(port, "python programming language", "github,arxiv,wikipedia,wikidata")
        hosts = domains(payload)
        results = payload.get("results") or []
        report["query"] = "python programming language"
        report["engines"] = "github,arxiv,wikipedia,wikidata"
        report["resultCount"] = len(results)
        report["domains"] = hosts
        report["unresponsive"] = payload.get("unresponsive_engines")
        if len(results) < 5 or len(hosts) < 2:
            raise SystemExit(f"need >=5 results and >=2 domains, got {len(results)} {hosts}")
        blocked = {"google", "google cse", "bing", "qwant", "startpage"}
        used = {item.get("engine") for item in results}
        if used & blocked:
            raise SystemExit(f"relied on a disabled engine: {used & blocked}")

        reads = []
        for result in results:
            url = result.get("url") or ""
            if not reader_server.policy_allows(url):
                continue
            if any(item["url"] == url for item in reads):
                continue
            host = urllib.parse.urlparse(url).hostname
            if any(item["domain"] == host for item in reads):
                continue
            try:
                status, final, html = reader_server.fetch(url)
                text, title, published, extractor = reader_server.extract(html, final)
            except Exception as error:
                reads.append({"url": url, "error": str(error)})
                continue
            reads.append({
                "url": final,
                "domain": urllib.parse.urlparse(final).hostname,
                "status": status,
                "extractor": extractor,
                "title": title,
                "published": published,
                "chars": len(text),
            })
            if len([item for item in reads if item.get("status") == 200 and item.get("chars", 0) > 200]) >= 2:
                break
        report["reads"] = reads
        good = [item for item in reads if item.get("status") == 200 and item.get("chars", 0) > 200]
        domains_read = {item.get("domain") for item in good}
        if len(good) < 2 or len(domains_read) < 2:
            raise SystemExit(f"reader did not return two domains: {reads}")
        report["passed"] = True
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        out = ROOT / "Docs" / "progress" / "M4" / "selftest-search.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "domains": report.get("domains"), "reads": report.get("reads")}, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
