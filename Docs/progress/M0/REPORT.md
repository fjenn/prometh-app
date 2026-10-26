# M0: ECC (cursor, no hooks) + upstream provenance

Date: 26 Oct 2026. Branch: `prometh`. No application source changes.

## What was done

1. Confirmed remotes: `origin` = `https://github.com/fjenn/prometh-app.git`, `upstream` = `https://github.com/Blaizzy/nativ.git`. Fetched upstream. `HEAD` was already `prometh` at `6ef4ba92a9a0dc72b1a2e9e4a1e0dca8e7d048e3`.
2. Installed ECC project-locally from `~/Projects/Coding/ECC` (`25278e7d7b6cf6e6a4e7a6c8e10f14ff22f0eb5b`) with `--target cursor --no-hooks swift python typescript`. Dry-run first. `hooks-runtime` was excluded. `hookConsent` is `declined`.
3. Wrote `Docs/UPSTREAM.md` (same directory as `docs/` on this case-insensitive volume).
4. Cloned the design reference to `~/Projects/Coding/Prometh-reference` at `1962c288c37583a3c812e247e18d2d3513989968`. The clone is outside this repo.
5. `make xcode-build` builds unmodified Nativ. The first attempt failed because the Metal toolchain was not installed (`cannot execute tool 'metal'`). Installed it with `xcodebuild -downloadComponent MetalToolchain` (Metal Toolchain 27A266a) and rebuilt. XcodeGen reordered two targets in `project.pbxproj`; that diff was restored so this commit does not touch the Xcode project.

## Acceptance

| Check | Result |
|---|---|
| `git rev-parse --abbrev-ref HEAD` | `prometh` |
| `git merge-base HEAD upstream/main` | `6ef4ba92a9a0dc72b1a2e9e4a1e0dca8e7d048e3` |
| `.cursor/rules/common-*.mdc`, `swift-*.mdc`, `python-*.mdc`, `typescript-*.mdc` | present (26 matching files) |
| `.cursor/agents/ecc-*.md` | present (71 files) |
| `.cursor/ecc-install-state.json` | present |
| `.cursor/hooks.json` and `.cursor/hooks/` | absent |
| `git diff upstream/main -- LICENSE` | empty |
| `make xcode-build` | `** BUILD SUCCEEDED **` in 145s. Product `Nativ.app`, `CFBundleIdentifier=dev.local.Nativ`, `CFBundleDisplayName=Nativ` |

Skill packages ship their own `skills/*/hooks/` scripts. Those are not `.cursor/hooks.json` or `.cursor/hooks/`, and the hooks runtime module was not installed.

Working tree additions for this milestone are `.cursor/` and `Docs/` (`PRD.md`, `UPSTREAM.md`, this report). A local `.prometh-logs/` directory already existed and is not part of the commit. The full `xcode-build` log was 4.7 MB; `xcode-build.tail.txt` keeps the success marker.

## Timings

- ECC install: under 1s (files copied from the local ECC checkout).
- Metal toolchain download: 87s, 838.9 MB.
- `make xcode-build` after the toolchain install: 145s.

## Known gaps

- None for M0. The Metal toolchain is a machine prerequisite, now installed.
