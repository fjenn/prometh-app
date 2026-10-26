# SearXNG source

Prometh runs SearXNG unmodified, as a separate process bound to 127.0.0.1. It is not linked into the app binary.

| Input | Pin |
|---|---|
| Upstream | https://github.com/searxng/searxng |
| Commit | `1412926f5c80ffabc90719450578eb98fda9e161` |
| Source URL | https://github.com/searxng/searxng/tree/1412926f5c80ffabc90719450578eb98fda9e161 |
| Archive | https://github.com/searxng/searxng/archive/1412926f5c80ffabc90719450578eb98fda9e161.tar.gz |
| Granian | 2.7.9 (BSD-3-Clause), installed from `requirements.lock` |
| Interpreter in `versions.env` | CPython 3.12.13, python-build-standalone tag `20260623` |
| Lock | `requirements.lock` (hash-locked; copied with `scripts/build-bundle.sh` from mermaid-searxng) |
| License | AGPL-3.0, `LICENSE-AGPL` |

`versions.env` is the mermaid-searxng pin file copied at implementation time. Its CPython tag is `20260623`. The Prometh reference provisioner also mentions python-build-standalone `20260508` for the same CPython 3.12.13. The SearXNG bundle uses the tag recorded in this `versions.env`.

Install from the git commit. Do not install the PyPI package named `searxng`; that package is an unofficial fork.

```bash
python -m pip install --require-hashes -r PromethRuntime/searxng/requirements.lock
python -m pip install --use-pep517 --no-build-isolation --no-deps <checkout of SEARXNG_REF>
python -m granian --interface wsgi --host 127.0.0.1 --port "$PORT" searx.webapp:application
```

`scripts/build-bundle.sh` builds the relocatable interpreter bundle. `scripts/prometh/provision-runtime.py` installs the same commit into a gitignored virtualenv for development and Linux checks.
