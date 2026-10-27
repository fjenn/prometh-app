# Prometh — judge notes

**Prometh** is a private, on-device AI app for Apple silicon Macs. Chat, web search with citations, image generate/edit, short video, and voice all run locally. It is a fork of [Nativ](https://github.com/Blaizzy/nativ) (MIT) with Prometh’s own UI; unused Nativ surfaces stay in the tree but stay hidden.

Everything stays on this Mac. No product account. Models download from Hugging Face at pinned revisions; inference does not leave the machine.

## Install (ad-hoc signed zip)

1. Unzip `Prometh.zip`.
2. Drag **Prometh** into **Applications**.
3. First launch: **right-click → Open** (Gatekeeper). If macOS blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway**.
4. On first run, Prometh picks the biggest model that fits your Mac’s unified memory (budget ≈ 75% of RAM − 1 GiB, 8% margin) and downloads it. Approximate top-tier downloads on a large Mac:

   | Capability | Default pick on big Macs | Download (order of) |
   |---|---|---|
   | Chat (Safe) | Qwen3.5 9B 4-bit MLX | ~6–9 GB |
   | Chat (Evil, optional) | Qwen3.5 9B Heretic GGUF | ~5.6 GB |
   | Voice listening | Whisper large-v3-turbo (base on small Macs) | ~1.5 GB+ |
   | Voice speaking | Kokoro 82M (Pocket kept hidden) | ~0.3 GB |
   | Images | FLUX.2 Klein 9B 8-bit (4-bit 4B on mid Macs) | ~18 GB / ~4.6 GB |
   | Video | FastMetal 14B when installed (1.3B fallback) | ~27 GB / ~13 GB |

   Settings shows which model was picked and why; you can override. Keep spare free disk (catalog headroom: 8 GB). Download time depends on your network; the in-app ETA is live.

## What to try

- **Chat** — ask anything; markdown renders in replies. Hover a user bubble → **Edit** to change it in place and regenerate (Cancel / Send; Esc / ⌘↩).
- **Search with citations** — ask for today’s news; open Sources / citation chips.
- **Image** — generate, then edit the same chat (Version cards). Bigger Macs use FLUX.2 Klein 9B.
- **Video** — generate a short clip (~832×480, ~5 s); ask in chat to trim (keeps Version 1), or Preview → Edit video. Bigger Macs prefer FastMetal 14B when downloaded.
- **Voice** — open Voice; speak (or play speech through speakers). Silero VAD ends the turn; Whisper transcribes; Kokoro speaks the reply. Speak again while Kokoro talks to **barge in** (Interrupt). Allow **Microphone** for `studio.prometh.Prometh`.
- **Connectors** — Settings → Connectors: Connect Gmail / Google Drive / GitHub opens the Composio OAuth page in your browser, shows **Waiting for sign-in…**, then **Connected**. After you sign in, ask chat to list recent mail or Drive files.
- **Safe / Evil Mode** — switch in the composer mode menu.

## Hardware

- **Apple silicon** only (`arm64`).
- **macOS 26** or newer (`MACOSX_DEPLOYMENT_TARGET = 26.0`).
- **RAM** — picker budgets by physical memory (tested at 8 / 16 / 24 / 36 / 64 / 128 GB). Owner verification was on an M5 Max 128 GB Mac.
- **Disk** — free space for selected downloads above, plus macOS headroom.

## Package contents

- `Prometh.zip` — Release `Prometh.app`, ad-hoc signed.
- Screenshots from the verified flows: `final-chat`, `final-search`, `final-image`, `final-image-edit`, `final-video`, `final-video-after-trim`, `final-voice`, `final-evil`.
