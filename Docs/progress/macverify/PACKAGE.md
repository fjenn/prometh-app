# Phase C — judge package

Host: Apple M5 Max, 128 GB, macOS 26.6.2, arm64. Branch `prometh`. Package built 2026-10-27 (America/Argentina/Buenos_Aires) for Finn’s noon BA judge send.

## Polish

- Conversation titles derived from the first prompt now strip markdown markers (`**`, `__`, `` ` ``, `#`, `~~`) before truncation (`PromethConversationTitle.stripMarkdown`).
- Unit test: `PromethTranscriptTests.testGeneratedTitleStripsMarkdownMarkers`.
- Nativ features were not deleted; unused surfaces stay hidden.

## Gates (all exit 0)

| Gate | Result |
|---|---|
| `./scripts/prometh/build.sh` | **PASS** — Debug `Prometh.app` built and ad-hoc signed |
| `make verify` | **PASS** — bundled `mlx_vlm.server` + `nativ_server` import OK |
| `xcodebuild … -only-testing:PromethTests` | **PASS** — 49 tests, 0 failures |
| `xcodebuild … -only-testing:PromethUITests` | **PASS** — 6 tests, 0 failures |

## Release app

- Built: `xcodebuild -scheme Nativ -configuration Release NATIV_PRODUCT_NAME=Prometh`
- Path: `build/NativDevelopmentDerivedData/Build/Products/Release/Prometh.app` (~1.7 GB on disk)
- Signed: `codesign --force --deep -s -` (adhoc, `studio.prometh.Prometh`)
- Bundled runtime check: `Contents/Resources/PromethRuntime/media/media_worker.py` present (cancel/`done` return path included), plus `composio_mcp`, `llama`, `media`, `reader`, `searxng`, `voice`
- Launch: opened Release build; window titled Prometh; screenshot `Docs/progress/macverify/release-launch.png`

## Judge folder

Path: `~/Desktop/Prometh-judges/`

| Item | Notes |
|---|---|
| `Prometh.zip` | `ditto -c -k --sequesterRsrc --keepParent Prometh.app Prometh.zip` |
| Zip size | **624M** (654,367,996 bytes) |
| SHA-256 | `5586d77d310470c0338e2a184cb0f13c0ad57b070f6c1d1a8e284194576e0a04` |
| `JUDGES.md` | Same content as `Docs/JUDGES.md` |
| Screenshots | `final-chat`, `final-search`, `final-image`, `final-image-edit`, `final-video`, `final-voice`, `final-evil` |

## Docs / git

- `Docs/JUDGES.md` added (install, try list, hardware from catalog / project settings).
- Root `README.md` rewritten for Prometh; credits Nativ (MIT) as the base.
- Pushed to `origin/prometh` only (no force-push, no releases, no other branches).
