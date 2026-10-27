# Prometh — judge notes

**Prometh** is a private, on-device AI app for Apple silicon Macs. Chat, web search with citations, image generate/edit, short video, and voice all run locally. It is a fork of [Nativ](https://github.com/Blaizzy/nativ) (MIT) with Prometh’s own UI; unused Nativ surfaces stay in the tree but stay hidden.

Everything stays on this Mac. No product account. Models download from Hugging Face at pinned revisions; inference does not leave the machine.

## Install (ad-hoc signed zip)

1. Unzip `Prometh.zip`.
2. Drag **Prometh** into **Applications**.
3. First launch: **right-click → Open** (Gatekeeper). If macOS blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway**.
4. On first run, Prometh downloads the models you select. Approximate download sizes from the pinned catalog (`Sources/Prometh/Resources/model-catalog.json` / UI labels in `Domain.swift`):

   | Capability | Download |
   |---|---|
   | Chat (Safe · Gemma 4 E4B 4-bit) | ~5.18 GB |
   | Voice (Whisper + Pocket TTS) | ~1.84 GB |
   | Images (FLUX.2 Klein 4-bit) | ~4.62 GB |
   | Video (FastMetal 1.3B) | ~13.40 GB |
   | Evil Mode add-on (optional) | ~5.63 GB |

   Keep spare free disk for macOS plus those downloads (catalog headroom policy: 8 GB; Settings copy also asks for about 12 GiB free). Download time depends on your network; the in-app ETA is live, not a fixed wall clock.

## What to try

- **Chat** — ask anything; markdown (bold, lists, code) renders in replies.
- **Search with citations** — ask for today’s news; open Sources / citation chips.
- **Image** — generate, then edit the same chat (Version cards).
- **Video** — generate a short clip; Preview → Edit video to trim; Cancel while generating.
- **Voice** — dictate or speak a reply; use **Interrupt** while speaking. macOS will prompt for **Microphone** (`studio.prometh.Prometh`). Allow it under System Settings → Privacy & Security if dictation is denied.
- **Safe / Evil Mode** — switch in the composer mode menu.

## Hardware

- **Apple silicon** only (`arm64`).
- **macOS 26** or newer (`MACOSX_DEPLOYMENT_TARGET = 26.0`).
- **RAM** — working memory varies by task (catalog: Chat Safe ~8 GB, Evil ~8.5 GB, Images/Video ~6 GB each, Voice STT ~2.5 GB). Engines unload between heavy jobs. **16 GB hardware certification is still pending** in-app; larger unified memory is safer for demos that combine chat + media.
- **Disk** — free space for selected downloads above, plus macOS headroom.

## Package contents

- `Prometh.zip` — Release `Prometh.app`, ad-hoc signed.
- Screenshots from the verified flows: `final-chat`, `final-search`, `final-image`, `final-image-edit`, `final-video`, `final-voice`, `final-evil`.
