# Judge polish 2 — remaining defects (2026-10-27)

Host: Apple M5 Max. Branch `prometh`. Follow-up after reviewer pass on `~/Desktop/Prometh-judges` screenshots. Target: finish by ~10:30 AM BA before noon judge send.

## Defects fixed

| # | Defect | Fix | Evidence |
|---|---|---|---|
| 1 | Image-edit reply ended `dusk. ``.` after attachment-ID scrub | `PromethTranscript.scrubInternals` strips empty inline code / empty `()` `[]`, UUID wrappers in backticks, “view it using the attachment ID…”, and remapper leftovers like “available on and.” | Unit: `testVisibleReplyScrubsEmptyCodeSpanLeftByAttachmentID` (exact `dusk. ``.` string). Live AX on image chat: `I have edited the picture to depict the scene at dusk.` — no backticks / IDs. `final-image-edit.png` |
| 2 | Composer kept sent trim prompt after send (force-sync / empty-binding guard) | Clear UI draft before `deliver`; `ComposerDraftSync.shouldApply` forces empty binding after a previously bound draft; UITest asserts empty draft after send | Unit: `testComposerClearsAfterSendButProtectsAXPaste`. UITest in `PromethWorkspaceUITests`. `final-video-after-trim.png` shows `Message Prometh` placeholder only |
| 3 | Sidebar cluttered with repeated test chats | Backed up conversation store to `~/Desktop/Prometh-conversation-backup-20261027-075833` (kept). Temporarily installed one curated chat per flow for screenshots, then restored full 68-session history | Clean 6-row sidebar in all `final-*.png`; backup directory retained |

## Screenshots re-taken

Into `Docs/progress/macverify/` (and copied to `~/Desktop/Prometh-judges/`):

`final-chat`, `final-search` (BBC `[1]` + AP `[2]` Sources; body chips `[1]`/`[2]`), `final-image` (Version 1), `final-image-edit` (Version 2 + clean dusk line), `final-video` (Version 1 · 5.0 s), `final-video-after-trim` (Version 2 · 2.0 s + empty composer), `final-voice`, `final-evil` (Evil Mode header + composer).

Visual / AX checks: Prometh branding only; no Nativ chrome; no raw `` / attachment UUIDs; composer placeholder when empty.

## Gates

| Gate | Result |
|---|---|
| `./scripts/prometh/build.sh` | **PASS** |
| `make verify` | **PASS** |
| `xcodebuild … -only-testing:PromethTests` | **PASS** — 56 tests, 0 failures |
| `xcodebuild … -only-testing:PromethUITests` | **PASS** — 6 tests, 0 failures |

## Package

- Release ad-hoc signed `Prometh.app` → `~/Desktop/Prometh-judges/Prometh.zip` (624M; SHA-256 `39a4feb62dd9bd1f9fb7f68f95445290430e3c71f9f709d16c2a72dc0331bbe8`)
- Screenshots refreshed in the same folder (incl. `final-video-after-trim`)
- `Docs/JUDGES.md` screenshot list updated to include after-trim
- Conversation backup path: `~/Desktop/Prometh-conversation-backup-20261027-075833` (do not delete); live store restored to 68 sessions

## Notes

- Nativ features were not deleted; unused surfaces stay hidden.
- Pushed to `origin/prometh` only (no force-push).
- Never printed `~/.config/prometh/composio.env`.
