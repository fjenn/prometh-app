# Phase C — judge package (polish refresh)

Host: Apple M5 Max, 128 GB, macOS 26.6.2, arm64. Branch `prometh`. Package rebuilt 2026-10-27 (America/Argentina/Buenos_Aires) after reviewer defect fixes. See `POLISH.md`.

## Polish

- Composer placeholder hides whenever the NSTextView or draft binding has content; chat switches force-sync the editor.
- Chat `trim_video` tool trims the latest clip, keeps the original as Version 1, renders Version 2.
- Image/video tool results are sanitized before the model sees them; displayed assistant text scrubs attachment UUIDs.
- Conversation titles strip markdown on every path (`PromethConversationTitle.stripMarkdown`).
- Nativ features were not deleted; unused surfaces stay hidden.

## Gates (all exit 0)

| Gate | Result |
|---|---|
| `./scripts/prometh/build.sh` | **PASS** |
| `make verify` | **PASS** |
| `xcodebuild … -only-testing:PromethTests` | **PASS** — 54 tests, 0 failures |
| `xcodebuild … -only-testing:PromethUITests` | **PASS** — 6 tests, 0 failures |

## Release app

- Built: `xcodebuild -scheme Nativ -configuration Release NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO`
- Path: `build/NativDevelopmentDerivedData/Build/Products/Release/Prometh.app`
- Signed: `codesign --force --deep -s -` (adhoc, `studio.prometh.Prometh`)

## Judge folder

Path: `~/Desktop/Prometh-judges/`

| Item | Notes |
|---|---|
| `Prometh.zip` | `ditto -c -k --sequesterRsrc --keepParent Prometh.app Prometh.zip` |
| Zip size | **624M** (654,385,350 bytes) |
| SHA-256 | `c7a01cf335de229af5489b73b5481eafb721391346dafe211489517712f3c27a` |
| `JUDGES.md` | Same content as `Docs/JUDGES.md` (chat trim called out) |
| Screenshots | `final-chat`, `final-search`, `final-image`, `final-image-edit`, `final-video`, `final-video-after-trim`, `final-voice`, `final-evil` |

## Docs / git

- `Docs/progress/macverify/POLISH.md` records each defect → fix → evidence.
- Pushed to `origin/prometh` only (no force-push, no releases, no other branches).
