#!/usr/bin/env python3
# Adapted from local-deep-research
# src/local_deep_research/research_library/downloaders/extraction/pipeline.py (MIT).
# Prometh runs this as a separate process. It does not modify SearXNG.
"""On-device page reader. Listens on 127.0.0.1 only."""

from __future__ import annotations

import json
import re
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, build_opener, HTTPRedirectHandler

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)
MAX_REDIRECTS = 5
TIMEOUT = 10
MAX_BYTES = 2_000_000
SENSITIVE_QUERY = {
    "access_token", "api_key", "apikey", "auth", "authorization", "key",
    "password", "secret", "signature", "sig", "token",
}


def _ipv4(host: str) -> list[int] | None:
    parts = host.split(".")
    if len(parts) != 4:
        return None
    octets: list[int] = []
    for part in parts:
        if not part.isdigit():
            return None
        value = int(part)
        if value > 255:
            return None
        octets.append(value)
    return octets


def _public_ipv4(octets: list[int]) -> bool:
    first, second = octets[0], octets[1]
    if first in (0, 10, 127) or first >= 224:
        return False
    if first == 100 and 64 <= second <= 127:
        return False
    if first == 169 and second == 254:
        return False
    if first == 172 and 16 <= second <= 31:
        return False
    if first == 192 and (second == 168 or (second == 0 and octets[2] == 0)):
        return False
    if first == 198 and 18 <= second <= 19:
        return False
    return True


def policy_allows(url: str) -> bool:
    """Refuse private hosts and credential queries before any fetch."""
    parsed = urlparse(url.strip())
    if parsed.scheme not in ("http", "https"):
        return False
    if parsed.username or parsed.password:
        return False
    host = (parsed.hostname or "").lower().strip("[]")
    if not host or host in ("localhost", "localhost.localdomain"):
        return False
    if host.endswith((".localhost", ".local", ".internal", ".lan", ".home")):
        return False
    octets = _ipv4(host)
    if octets is not None and not _public_ipv4(octets):
        return False
    if ":" in host and (host == "::1" or host.startswith(("fc", "fd", "fe8", "fe9", "fea", "feb"))):
        return False
    query_names = [item.split("=", 1)[0].lower() for item in parsed.query.split("&") if item]
    if any(name in SENSITIVE_QUERY for name in query_names):
        return False
    return "." in host or octets is not None


class _Redirects(HTTPRedirectHandler):
    def __init__(self) -> None:
        super().__init__()
        self.hops = 0

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.hops += 1
        if self.hops > MAX_REDIRECTS or not policy_allows(newurl):
            raise URLError(f"redirect refused: {newurl}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url: str) -> tuple[int, str, str]:
    if not policy_allows(url):
        raise URLError("URL refused by policy")
    opener = build_opener(_Redirects())
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml"})
    with opener.open(request, timeout=TIMEOUT) as response:
        status = getattr(response, "status", 200) or 200
        final = response.geturl()
        if not policy_allows(final):
            raise URLError(f"final URL refused by policy: {final}")
        raw = response.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raw = raw[:MAX_BYTES]
        charset = response.headers.get_content_charset() or "utf-8"
        return status, final, raw.decode(charset, errors="replace")


def _text_of(html: str) -> str:
    stripped = re.sub(r"(?is)<(script|style).*?>.*?</\1>", " ", html)
    stripped = re.sub(r"(?s)<[^>]+>", " ", stripped)
    return re.sub(r"\s+", " ", stripped).strip()


def _field(document: object, name: str) -> str | None:
    if isinstance(document, dict):
        value = document.get(name)
    else:
        value = getattr(document, name, None)
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def extract(html: str, url: str) -> tuple[str, str | None, str | None, str]:
    """Return text, title, published, extractor name. First usable result wins."""
    try:
        import trafilatura

        downloaded = trafilatura.bare_extraction(
            html,
            url=url,
            favor_precision=True,
            include_comments=False,
            include_links=False,
        )
        text = _field(downloaded, "text") if downloaded is not None else None
        if text and len(text) >= 200:
            return text, _field(downloaded, "title"), _field(downloaded, "date"), "trafilatura"
    except Exception:
        traceback.print_exc()

    try:
        from newspaper import Article

        article = Article(url)
        article.set_html(html)
        article.parse()
        if article.text and len(article.text.strip()) >= 200:
            published = article.publish_date.date().isoformat() if article.publish_date else None
            return article.text.strip(), article.title or None, published, "newspaper4k"
    except Exception:
        traceback.print_exc()

    try:
        from readability import Document

        document = Document(html)
        text = _text_of(document.summary() or "")
        if len(text) >= 200:
            return text, document.short_title() or None, None, "readability-lxml"
    except Exception:
        traceback.print_exc()

    try:
        import justext

        paragraphs = justext.justext(html, justext.get_stoplist("English"))
        kept = [p.text for p in paragraphs if not p.is_boilerplate]
        text = "\n".join(kept).strip()
        if len(text) >= 200:
            return text, None, None, "justext"
    except Exception:
        traceback.print_exc()

    plain = _text_of(html)
    return plain, None, None, "plain"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("reader " + (fmt % args) + "\n")

    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?", 1)[0] == "/healthz":
            self._send(200, {"ok": True})
            return
        self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.split("?", 1)[0] != "/extract":
            self._send(404, {"ok": False, "error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(min(length, 8192))
        try:
            job = json.loads(raw.decode("utf-8"))
            url = str(job["url"])
        except Exception:
            self._send(400, {"ok": False, "error": "invalid request"})
            return
        try:
            status, final, html = fetch(url)
            text, title, published, extractor = extract(html, final)
            self._send(200, {
                "ok": True,
                "status": status,
                "url": final,
                "title": title,
                "published": published,
                "text": text,
                "extractor": extractor,
            })
        except Exception as error:
            self._send(200, {"ok": False, "error": str(error), "url": url})


def main() -> None:
    host = "127.0.0.1"
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"LISTENING {server.server_address[1]}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
