# Phase B — end-to-end re-verify (final)

Host: Apple M5 Max, 128 GB, macOS 26.6.2, arm64. Branch `prometh`. Time zone: America/Argentina/Buenos_Aires. Verified morning of 2026-10-27 before Finn’s noon BA send.

Gates: `scripts/prometh/build.sh` 0 · `make verify` 0 · `xcodebuild … -only-testing:PromethTests` 0 (48) · `xcodebuild … -only-testing:PromethUITests` 0 (6). App was quit before every rebuild (avoids the DYLD `NativServerKit` crash).

Composio sign-in remains deferred (see `Docs/progress/BLOCKED.md`). Key was never printed.

## Flow table

| Flow | Result | Screenshot | Notes |
|---|---|---|---|
| Plain chat + markdown | **PASS** | `final-chat.png` | Bold, fruit bullets, `print("hello")` code block. Sidebar/header title from first prompt (`Show markdown: one…`). Prometh branding only. |
| News / web search + citations | **PASS** | `final-search.png` | Non-empty answer; chips `[1]`/`[2]`; Sources cards The World Now + 7NEWS; full answer + Sources row visible. Claims checked against live page HTML (Gaza 1000 days / Oleshky weeds / Cambodia / Azogues on [1]; Pike / dramatic on [2]). |
| Attach image + PDF | **PASS** | `final-attach.png` | Both chips attached; answer: blue mug, PDF title **Ferry Notes**, quote *The harbor stays quiet until the first bell.* Product fixes: multi-select open panel; Safe Mode vision flag so image sends are not dropped. |
| Image generate | **PASS** | `final-image.png` | Glass house / Atlantic sunrise; Version 1 card; FLUX generate `ok:true`. |
| Image edit (same chat) | **PASS** | `final-image-edit.png` | Dusk edit; Version 2; `edit_image` `ok:true`. |
| Video ~832×480 ~5 s + trim + cancel | **PASS** | `final-video.png` (+ `final-video-cancel.png`, `final-video-trimming.png`) | Generated `661BBABD-….mp4` **832×480**, **5.06 s**. Cancel session tool: `{"ok":false,"cancelled":true}`. UI trim 1.0–3.1 s → `clip-4F7401B8-….mp4` **2.125 s**. Fixed `media_worker.py` exiting after `done` (was hanging Swift on stdout EOF). Chat trim *prompts* are refused by the model; trim is via Preview → Edit video → Create new version. |
| Voice dictate / speak / Interrupt / Pocket TTS | **PASS** (with mic note) | `final-voice.png` (+ `final-voice-layer.png`) | Reply “Four.”; Voice layer Listening/Speaking; Interrupt clicked. Pocket TTS path used by `speak()`. Live mic: TCC has `studio.prometh.prototype` and `io.github.blaizzy.nativ`, **not** `studio.prometh.Prometh` — Finn must allow Microphone for Prometh in System Settings for real dictation. Fix: `readAloud` opens the voice layer so Interrupt is visible. |
| Evil Mode in-app | **PASS** | `final-evil.png` | Mode menu → Evil Mode; header + composer show Evil Mode; reply exactly `Evil mode is on.` |

## Design check (all final-*.png)

| Check | Result |
|---|---|
| Prometh branding / no Nativ UI or wording | PASS |
| No lorem / placeholder / debug chrome | PASS |
| No raw entities (`&amp;` etc.) | PASS |

## Product fixes landed this pass

1. **Multi-select attachments** — `chooseAttachment` allows multiple files and document UTTypes (`PromethStore.swift`).
2. **Vision on Safe sends** — stop hardcoding `languageModelSupportsVision: false` so image+text messages actually send.
3. **Video worker exit** — `media_worker.py` returns after generate/trim `done` so the app is not stuck on “Making the clip…”.
4. **Read-aloud opens voice layer** — `PromethVoice.readAloud` sets `isOpen` so Interrupt/Mute appear during Pocket TTS.

## Finn still has to

- Allow **Microphone** for **Prometh** (`studio.prometh.Prometh`) in System Settings → Privacy & Security if live dictation is demoed.
- Finish Composio / GitHub sign-in if connectors are demoed (not a blocker for the table above).
