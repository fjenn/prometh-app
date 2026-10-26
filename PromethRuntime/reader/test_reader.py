"""Policy, extractor chain, and citation-contract tests for the on-device reader."""

from __future__ import annotations

import json
from pathlib import Path

import reader_server

ROOT = Path(__file__).resolve().parents[2]


def test_policy_matches_nativ_cases() -> None:
    refused = [
        "http://127.0.0.1/private",
        "http://127.0.0.1./private",
        "http://0x7f.0.0.1/private",
        "http://192.168.1.1/",
        "http://192.168.1.4/private",
        "http://[::1]/private",
        "https://service.internal/data",
        "https://user:secret@example.com/a",
        "https://example.com?access_token=secret",
        "https://example.com?token=abc",
        "file:///etc/passwd",
        "http://localhost/x",
    ]
    for url in refused:
        assert reader_server.policy_allows(url) is False, url
    assert reader_server.policy_allows("https://example.com/article")
    assert reader_server.policy_allows("https://en.wikipedia.org/wiki/Apple_Inc.")


def test_extractor_chain_falls_through(monkeypatch: object | None = None) -> None:
    html = """
    <html><head><title>Kept</title></head>
    <body><article><h1>Kept</h1><p>%s</p></article></body></html>
    """ % ("Readable sentence about apples. " * 20)
    text, title, _published, name = reader_server.extract(html, "https://example.com/a")
    assert name == "trafilatura", name
    assert title
    assert "apples" in text.lower()

    short = "<html><head><title>Tiny</title></head><body><p>Hi.</p></body></html>"
    plain, _title, _published, plain_name = reader_server.extract(short, "https://example.com/tiny")
    assert plain_name == "plain"
    assert "Hi" in plain


def test_chain_continues_when_trafilatura_fails() -> None:
    import trafilatura

    original = trafilatura.bare_extraction

    def broken(*_args, **_kwargs):
        raise RuntimeError("forced")

    trafilatura.bare_extraction = broken
    try:
        html = """
        <html><head><title>Fallback Title</title></head>
        <body><article><h1>Fallback Title</h1><p>%s</p></article></body></html>
        """ % ("A longer paragraph about orchards and harvests. " * 25)
        text, title, _published, name = reader_server.extract(html, "https://example.com/fallback")
    finally:
        trafilatura.bare_extraction = original
    assert name != "trafilatura"
    assert len(text) >= 200
    assert title == "Fallback Title"


def test_shell_page_is_short() -> None:
    html = "<html><body><div id='app'>Enable JavaScript to continue.</div></body></html>"
    text, _title, _published, name = reader_server.extract(html, "https://example.com/app")
    assert len(text) < 500
    assert name == "plain"


def test_local_server_refuses_private_url() -> None:
    url = "http://127.0.0.1:9/private"
    assert reader_server.policy_allows(url) is False
    try:
        reader_server.fetch(url)
    except Exception as error:
        message = str(error).lower()
        assert "refused" in message or "policy" in message
        return
    raise AssertionError("private URL was fetched")


def test_nativ_limits_stay_in_source() -> None:
    service = (ROOT / "Sources/Nativ/Features/Browsing/WebReadService.swift").read_text()
    selector = (ROOT / "Sources/Nativ/Features/Browsing/WebReadContentSelector.swift").read_text()
    assert "maximumCharactersPerPage = 6_000" in service
    assert "maximumTotalCharacters = 20_000" in service
    assert "maximumURLs = 4" in service
    assert '[content omitted]' in selector or '"[content omitted]"' in selector


def test_citation_contract_matches_swift_fixture() -> None:
    swift = (ROOT / "Tests/PromethTests/PromethSearchTests.swift").read_text()
    assert 'title="Apple &amp; Pear"' in swift
    assert 'index="1"' in swift
    assert "[1][3]" in swift


if __name__ == "__main__":
    test_policy_matches_nativ_cases()
    test_extractor_chain_falls_through()
    test_chain_continues_when_trafilatura_fails()
    test_shell_page_is_short()
    test_local_server_refuses_private_url()
    test_nativ_limits_stay_in_source()
    test_citation_contract_matches_swift_fixture()
    print(json.dumps({"passed": True, "tests": 7}))
