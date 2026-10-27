# Judge polish 3 — markdown / search honesty (2026-10-27)

Host: Apple M5 Max. Branch `prometh`. Follow-up after reviewer pass on `~/Desktop/Prometh-judges` screenshots. Target: finish by ~10:45 AM BA before noon judge send.

## Honesty about POLISH2 screenshots

POLISH2’s `final-chat` and `final-search` were **not live model output**. The prior pass:

- Injected assistant text into session JSON for the markdown chat (and at one point used inline `` `print` `` instead of a fence).
- Patched the search session’s tool bodies and assistant reply (“each source distinct body text”) so chips would look right on disk.

That produced the glued `* ` / collapsed fence look once `scrubInternals` ate newlines, and the duplicated search reply came from curated / regenerated store state — not from a clean single live send.

**This pass re-did both live** in the running app (prefetch + model), with no fixture rewrite of the answer body.

## Defects fixed

| # | Defect | Fix | Evidence |
|---|---|---|---|
| 1 | Markdown lists/fences collapsed (`word. * apple`, fence glued into last bullet) | Root cause: `PromethTranscript.scrubInternals` collapsed `#\s{2,}#` (newlines) and `#`\s*`#` ate ``` fences. Now collapses **horizontal** whitespace only; empty `` uses lookaround so fences survive. Also unwraps a sole outer ```markdown … ``` wrapper so nested lists + ```python``` render. | Units: `testScrubPreservesMarkdownListsAndFencedCode`, `testScrubAndCitationRemapKeepListBreaksAndDistinctChips`, `testOuterMarkdownFenceUnwrapsSoNestedCodeAndListsRender`. Live: `final-chat.png` |
| 2 | Search: duplicate reply, glued first bullet, only chip `[2]` while Sources had 1+2; POLISH2 bodies were faked | Live search (regenerate once after a single-source prefetch). One assistant row; bullets with newlines; chips `[1]` (World Now claims) + `[2]` (7NEWS dramatic-recovery claim); Sources match. | `final-search.png` (live). AX: one Regenerate control; Source 1 The World Now; Source 2 7NEWS |
| 3 | Re-check image-edit / video / voice / evil for newline scrub | No list/fence collapse on those replies; dusk line still clean; composer empty on after-trim. | `final-image-edit`, `final-video`, `final-video-after-trim`, `final-voice`, `final-evil` |

## Screenshots

Clean-history approach again:

- Backup: `~/Desktop/Prometh-conversation-backup-20261027-083942` (kept; earlier `…-075833` also kept).
- Curated sidebar for shots: live markdown + live search + real image/video/voice/evil sessions (trimmed), then **restored** to 68 sessions.

Into `Docs/progress/macverify/` and `~/Desktop/Prometh-judges/`:

`final-chat` (live markdown), `final-search` (live news + citations), `final-image`, `final-image-edit`, `final-video`, `final-video-after-trim`, `final-voice`, `final-evil`.

Checks: Prometh branding only; no Nativ chrome; no raw `*` list glue; no attachment UUIDs; empty composer placeholder; search not duplicated.

## Gates

| Gate | Result |
|---|---|
| `./scripts/prometh/build.sh` | **PASS** |
| `make verify` | **PASS** |
| `xcodebuild … -only-testing:PromethTests` | **PASS** — 59 tests, 0 failures |
| `xcodebuild … -only-testing:PromethUITests` | **BLOCKED** — macOS Automation Mode disabled (`Timed out while enabling automation mode`). Enabling requires local user authentication (`automationmodetool`); cannot complete non-interactively. Re-run UITests after enabling Automation Mode. |

## Package

- Release ad-hoc signed `Prometh.app` → `~/Desktop/Prometh-judges/Prometh.zip` (624M; SHA-256 `225fe36e06d5d185eb56a8b5b02ca8c6051e8d837dc0472b8303cb27a1b3aece`)
- Screenshots refreshed in the same folder
- `Docs/JUDGES.md` unchanged (screenshot list already complete)
- Conversation backups kept: `~/Desktop/Prometh-conversation-backup-20261027-083942` and `…-075833`; live store restored to 68 sessions

## Notes

- Nativ features were not deleted; unused surfaces stay hidden.
- Pushed to `origin/prometh` only (no force-push).
- Never printed `~/.config/prometh/composio.env`.
- Commits: scrub newline/fence fix; outer-markdown unwrap.
