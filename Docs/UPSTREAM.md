# Upstream provenance

Prometh is a fork of [Nativ](https://github.com/Blaizzy/nativ). The engine stays Nativ's. Prometh replaces the user-facing shell and adds a small set of documented seams.

| | |
|---|---|
| Upstream | https://github.com/Blaizzy/nativ.git (`upstream`) |
| Fork | https://github.com/fjenn/prometh-app.git (`origin`) |
| Base SHA | `6ef4ba92a9a0dc72b1a2e9e4a1e0dca8e7d048e3` |
| Base commit | Merge of PR #761, 2026-10-26 16:08 UTC (13:08 ART) |
| Latest upstream release tag at fork time | `v0.4.3` |
| Working branch | `prometh` |
| Recorded | 26 Oct 2026 |

`git merge-base HEAD upstream/main` at M0 was `6ef4ba92a9a0dc72b1a2e9e4a1e0dca8e7d048e3`.

## Merging upstream

```bash
git fetch upstream
git merge upstream/main
```

Resolve conflicts only in seam files listed in `docs/UPSTREAM_SEAMS.md` (created when the first seam lands). Do not rewrite upstream files outside those seams. After the merge:

```bash
make verify
```

No upstream test may be skipped or deleted.

## ECC

Project-local ECC install (Cursor target, `--no-hooks`, languages swift, python, typescript). The global `~/.cursor` install was left unchanged.

ECC commit actually used:

```
25278e7d7b6cf6e6a4e7a6c8e10f14ff22f0eb5b
```

Recorded from `git -C ~/Projects/Coding/ECC rev-parse HEAD` on 26 Oct 2026. That matches upstream `affaan-m/ECC` main as pinned in the PRD.

## Design reference

Read-only clone: `~/Projects/Coding/Prometh-reference` (`github.com/fjenn/Prometh`), `main` = `1962c288c37583a3c812e247e18d2d3513989968`. Not a remote of this fork. Do not modify it.
