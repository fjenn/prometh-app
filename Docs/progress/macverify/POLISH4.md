# Judge polish 4 — headings / fence label / `.n` / Sources (2026-10-27)

Host: Apple M5 Max. Branch `prometh`. Follow-up after reviewer pass on POLISH3 `final-*.png`. Target: finish by ~11:15 AM BA before noon judge send.

## Defects fixed

| # | Defect | Fix | Evidence |
|---|---|---|---|
| 1 | `final-chat.png`: literal `# Example Document` | `PromethReplyMarkup` renders ATX `#`/`##`/`###` as sized semibold lines (inline-only markdown ignores headings). | Unit: `testATXHeadingsRenderWithoutHashMarkers`. Live: `final-chat.png` shows **Example Document** as a heading, no hash. |
| 2 | `final-chat.png`: fence info string `python` leaked as first code line | `PromethCodeFence.split` peels the info string; Workspace shows it as a 10 pt secondary label above the monospaced body (never as code). | Unit: `testFenceInfoStringIsNotCodeContent`. Live: `final-chat.png` — small `python` label + `print("hello")`. |
| 3 | `final-search.png`: `has.n clashes` | Root cause: attachment scrub `(?:view\|see\|open)` matched inside **seen** (all tails optional). Now requires word boundaries and an `attachment id` tail. | Unit: `testScrubDoesNotCorruptSeenIntoDotN` (exact “has seen clashes” input). Live search reply has no `.n`. |
| 4 | `final-search.png`: almost all chips `[1]`, Sources missing | Remapper keeps the model’s chip when that source clears support (so `[1]`/`[2]` stay distinct). Prefetch links/hits persist to `prefetch-sources.json` so Sources survive curated relaunch. | Unit: `testCitationRemapperKeepsDistinctChipsAcrossMultipleSources`. Live: chips `[1]`×3 + `[2]` (Pike); Sources World Now + 7NEWS visible. |

## Screenshots

Clean-history approach:

- Backup: `~/Desktop/Prometh-conversation-backup-20261027-094507` (kept; earlier backups also kept).
- Curated sidebar for shots: live markdown + live search + image/video/evil/math sessions, then **restored** to 68 sessions.

Only affected shots re-taken live (no fixture injection):

- `final-chat.png` — live text-only markdown (heading + bold + fruit bullets + python fence).
- `final-search.png` — live news search with prefetch; Sources row visible after relaunch via disk persistence.

Checks: Prometh branding only; no Nativ chrome; no raw `#` heading; fence language not monospaced code; no `.n`; distinct chips; Sources visible; empty composer; no attachment UUIDs.

## Gates

| Gate | Result |
|---|---|
| `./scripts/prometh/build.sh` | **PASS** |
| `make verify` | **PASS** |
| `xcodebuild … -only-testing:PromethTests` | **PASS** — 63 tests, 0 failures |
| `xcodebuild … -only-testing:PromethUITests` | **BLOCKED** — `automationmodetool`: Automation Mode is disabled (requires local user authentication). Did not wait or retry. |

## Package

- Release ad-hoc signed `Prometh.app` → `~/Desktop/Prometh-judges/Prometh.zip` (624M; SHA-256 `ef1bb1a43e34181bcb139d1219bde19751a0db3c854c4be596acf2135b490e97`)
- `final-chat` / `final-search` refreshed in repo and judges folder; other screenshots unchanged
- `Docs/JUDGES.md` unchanged (screenshot list already complete)
- Conversation backup kept; live store restored to 68 sessions

## Notes

- Nativ features were not deleted; unused surfaces stay hidden.
- Pushed to `origin/prometh` only (no force-push).
- Never printed `~/.config/prometh/composio.env`.
- Commits: seen-scrub fix; ATX headings + fence label; distinct chips + Sources persistence; this doc.
