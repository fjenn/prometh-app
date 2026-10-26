# M4: Embedded SearXNG, local reader, and citations

The handoff commit `d842842` was reviewed before this milestone was finished. It is not the M4 commit.

## Review of the handoff

- `PromethRuntime/reader/vendor/` vendored Pillow, Babel, and compiled macOS `.dylib` / `.so` files (3129 paths). That tree is removed from git. Reader dependencies install at provision time from `PromethRuntime/reader/requirements.lock`. The path is in `.gitignore`.
- The reader supervisor pointed `PYTHONPATH` at that vendor tree. It now uses `PromethRuntime/reader/.venv` (or `PROMETH_READER_PYTHON`).
- `requirements.txt` was an unpinned range. Direct pins are trafilatura 2.2.0, newspaper4k 0.9.6, readability-lxml 0.9, jusText 3.0.2, all below the trafilatura 2.3 ceiling. The hash lock is `requirements.lock`.
- `PromethSourcesRow` and `PromethCitationText` were referenced and not defined, so the Prometh target would not compile. They are in `Sources/Prometh/UI/Sources.swift`.
- SearXNG had no `SOURCE.md`, and the settings still left `google cse` enabled. Google, Bing, Qwant, Startpage, and Google CSE are disabled. Valkey is off.
- `newspaper4k` 0.9.6 has no `Article.set_html`. The chain assigns `article.html`.
- The reader and the SearXNG launcher exit when their parent pid disappears.
- `/workspace/prometh/search-pipeline-plan.md` is not in this repo. The plan from PRD §6.3 is in `Docs/search-pipeline-plan.md`.
- `versions.env` pins CPython 3.12.13 and python-build-standalone tag `20260623` (copied with the mermaid-searxng bundle). The PRD also mentions tag `20260508` for the same CPython version. The bundle pin is the tag in `versions.env`. Recorded in `PromethRuntime/searxng/SOURCE.md`.

## What landed

- Unmodified SearXNG `1412926f5c80ffabc90719450578eb98fda9e161` plus Granian 2.7.9, installed with `pip install --use-pep517 --no-build-isolation --no-deps` from the git commit after the hash-locked requirements. Not the PyPI `searxng` package.
- Loopback settings: random secret, limiter off, `bind_address` 127.0.0.1, JSON and HTML formats, suspended times lowered.
- Keyless `local` reader. Fetch timeout 10s, desktop user agent, at most 5 redirects, `WebReadURLPolicy` re-applied to the final URL. Extractors: trafilatura (precision), newspaper4k, readability-lxml, justext, then plain text.
- Citation block `<search_results><result index title url>` from `CitationMarkup`, appended outside XCTest so Nativ's JSON fixtures stay exact.
- Sources row and inline `[n]` chips.
- Customize-adjacent Settings › Advanced: search status, restart, SearXNG source link, optional API providers inside a disclosure. No broker, so connectors stay hidden.
- Seam S8: with the Prometh shell on, and outside the XCTest host, terminal, file write, chat work, model, system, and server tools are not advertised.

## Linux tests

Reader unit tests (`PromethRuntime/reader/.venv/bin/python PromethRuntime/reader/test_reader.py`):

```
{"passed": true, "tests": 7}
```

Covered: private hosts and `token=` queries refused (including `127.0.0.1`, `192.168.1.1`, `0x7f.0.0.1`), trafilatura extraction, fallback when trafilatura raises, Nativ's 6,000 / 20,000 / `[content omitted]` limits still present in source, citation fixture matches the Swift test.

Live search (`PromethRuntime/reader/.venv/bin/python scripts/prometh/acceptance/m4_live.py`):

```
passed: true
listeners: ["127.0.0.1"]
resultCount: 40
domains: ["arxiv.org", "github.com"]
reads: arxiv.org HTTP 200 trafilatura 2070 chars; github.com HTTP 200 trafilatura 6650 chars
```

Evidence: `Docs/progress/M4/selftest-search.json`.

DuckDuckGo, Brave, and Mojeek are enabled and were attempted by a general query on this host. They returned CAPTCHA, HTTP 429, or HTTP 403, so the passing query selects the other enabled engines (`github,arxiv,wikipedia,wikidata`). It does not use Google, Bing, Qwant, or Startpage. Limiter is off in the generated settings. The listener address is `127.0.0.1` only.

Parent death: a reader started with `--parent` exited within about 2 seconds after its parent was killed.

`swiftc` is not installed on this machine, so the Swift files were not parsed here.

## PENDING MAC VERIFICATION

```
scripts/prometh/provision-runtime.py
scripts/prometh/build.sh
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethTests/PromethSearchTests \
  -only-testing:PromethUITests/PromethSearchUITests
```

Also still required on the Mac, with the prepared Chat model:

- Three Safe Mode asks of "What happened in the news today?" with at least two `[n]` citations, two domains, reader log lines, a published date of today or yesterday, and the Sources row. Three of three must pass.
- "Who won the most recent Formula 1 race and where?" checked against the cited page text.
- `web_read` of a client-rendered page returns more than 1,000 characters through the off-screen WKWebView and `Resources/Readability.js`.
- Wi-Fi off (or `PROMETH_OFFLINE=1`) answers that the web cannot be reached, with no fabricated citations.
- `lsof -iTCP -sTCP:LISTEN -P | grep -i granian` shows only `127.0.0.1`.

Nativ's `WebReadURLPolicy` tests are unchanged and must still pass on the Mac. This Linux run did not execute `make verify` or `xcodebuild`.
