# Judge polish — defect fixes (2026-10-27)

Host: Apple M5 Max. Branch `prometh`. Fixes after reviewer pass on Phase C judge screenshots.

## Defects fixed

| # | Defect | Fix | Evidence |
|---|---|---|---|
| 1 | Composer placeholder overlapped typed draft | `ComposerEditor` tracks `hasContent` from the NSTextView; placeholder hides when draft **or** view text is non-empty. Chat switches force-sync the view so leftover characters cannot outlive an empty binding. | `polish-placeholder-fixed.png`, `polish-v1-before-trim.png` (pixel check: grey-beyond-dark = 0) |
| 2 | Chat trim refused (“cannot edit video”) | Added `trim_video` tool (registered with `generate_video`), wired to `PromethMediaWorker.trimLatest`, persona instructs the model to call it, cards render Version 2 while keeping the original. | `final-video.png` (Version 1 · 5.0 s, 832×480), `final-video-after-trim.png` (Version 2 · 2.0 s + success reply); clip `clip-2DEAEB46-….mp4` duration 2.0 s |
| 3 | Image-edit reply leaked attachment UUID | `PromethToolResultSanitizer` scrubs tool JSON before the model sees it; persona forbids internals; `PromethTranscript.scrubInternals` strips UUIDs from displayed assistant text. Tests added. | `final-image-edit.png` (AX: `620E9990` / `attachment ID` count = 0); `PromethTranscriptTests.testToolResultSanitizerHidesAttachmentIDs`, `testVisibleReplyScrubsAttachmentIDs` |
| 4 | Window/sidebar titles showed raw `**` markdown | `PromethConversationTitle` runs `stripMarkdown` on **all** title paths (first prompt, stored, custom). | `final-search.png` header “Use bold…” (not `**bo`); `polish-title-done.png` “one bold word…”; unit tests in `PromethTranscriptTests` |
| 5 | Review of voice/chat/evil/search | No Nativ chrome or other leaked internals found; placeholder/title issues covered above. | `final-voice.png`, `final-chat.png`, `final-evil.png`, `final-search.png` |

## Gates

| Gate | Result |
|---|---|
| `./scripts/prometh/build.sh` | PASS |
| `make verify` | PASS (re-run before package) |
| `xcodebuild … -only-testing:PromethTests` | PASS (53+ tests incl. new scrub/title/trim cases) |
| `xcodebuild … -only-testing:PromethUITests` | PASS (re-run before package) |

## Notes

- Nativ features were not deleted; unused surfaces stay hidden.
- `trim_video` prefers original `Media/*.mp4` over `clip-*` so chat trim uses the full source.
- Pushed to `origin/prometh` only (no force-push).
