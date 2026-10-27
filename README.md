# Prometh

**AI that you own** — private, on-device chat, search with citations, image generate/edit, short video, and voice for Apple silicon Macs.

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple&logoColor=white">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-required-111111?logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white">
  <img alt="MLX" src="https://img.shields.io/badge/Powered%20by-MLX-6E5AE6">
</p>

Prometh is Finn’s local-AI Mac app. Inference and your chats stay on this Mac. Models download from Hugging Face at pinned revisions; there is no product account.

This repository is a fork of **[Nativ](https://github.com/Blaizzy/nativ)** ([MIT](LICENSE), copyright Prince Canuma and contributors). Prometh keeps Nativ’s engine (`NativServerKit`, chat tool loop, model runtimes) and ships its own UI. Upstream Nativ features that Prometh does not surface remain in the tree, hidden rather than deleted. See `NOTICE-PROMETH.md` and `Docs/LICENSES-PROMETH.md`.

## What Prometh does

| Feature | What you get |
|---|---|
| **Local chat** | Streaming Safe Mode chat (Gemma 4 E4B 4-bit via MLX) with markdown replies and persistent history. |
| **Web search + citations** | On-device SearXNG search, local page reading, citation chips and Sources. |
| **Images** | Generate and edit images locally (FLUX.2 Klein 4-bit / mflux). |
| **Video** | Short text-to-video clips (FastMetal) with cancel and trim. |
| **Voice** | Dictation and speak-aloud (Whisper + Pocket TTS) with Interrupt. |
| **Evil Mode** | Optional uncensored chat add-on (separate GGUF download). |

## Requirements

- Apple silicon Mac (`arm64`).
- macOS 26 or newer.
- Enough unified memory for the capabilities you enable (catalog working-memory estimates: Chat Safe ~8 GB, Evil ~8.5 GB, Images/Video ~6 GB, Voice STT ~2.5 GB). 16 GB certification is still pending.
- Free disk for selected model downloads (Chat ~5.18 GB, Voice ~1.84 GB, Images ~4.62 GB, Video ~13.40 GB, optional Evil ~5.63 GB) plus macOS headroom.
- Microphone permission for voice (`studio.prometh.Prometh`).

## Judges / demo package

See **[`Docs/JUDGES.md`](Docs/JUDGES.md)** for install steps (unzip → Applications → right-click Open / Open Anyway), what to try, and hardware notes. Verification notes live under `Docs/progress/macverify/`.

## Build from this fork

```sh
brew install xcodegen
./scripts/prometh/build.sh    # Debug Prometh.app, ad-hoc signed
make verify
```

Tests:

```sh
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -derivedDataPath build/NativDevelopmentDerivedData \
  -only-testing:PromethTests -destination 'platform=macOS,arch=arm64' \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO

xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -derivedDataPath build/NativDevelopmentDerivedData \
  -only-testing:PromethUITests -destination 'platform=macOS,arch=arm64' \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO
```

Release-style local app:

```sh
xcodegen generate
xcodebuild -project Nativ.xcodeproj -scheme Nativ -configuration Release \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO build
codesign --force --deep -s - \
  build/NativDevelopmentDerivedData/Build/Products/Release/Prometh.app
```

The first build can take a while because `NativServerKit` assembles a relocatable Python runtime and installs the pinned `mlx-vlm` server. Later builds reuse that bundle until inputs change.

## Documentation

- Product / planning: [`Docs/PRD.md`](Docs/PRD.md)
- Upstream seams: [`Docs/UPSTREAM.md`](Docs/UPSTREAM.md), [`Docs/UPSTREAM_SEAMS.md`](Docs/UPSTREAM_SEAMS.md)
- Licenses: [`Docs/LICENSES-PROMETH.md`](Docs/LICENSES-PROMETH.md)
- Upstream Nativ feature docs (engine reference): [`Docs/`](Docs/README.md)

## Project layout (high level)

```text
Sources/
├── Prometh/              # Prometh UI, bridge, search, media, voice
├── Nativ/                # Upstream SwiftUI surfaces (mostly hidden in Prometh shell)
├── NativServerKit/       # Embedded mlx-vlm server + clients
└── NativExtensionSDK/
PromethRuntime/           # Bundled workers (SearXNG, media_worker, voice, llama, …)
PythonDistribution/       # Relocatable server runtime assembly
Configuration/            # Bundle id studio.prometh.Prometh, signing
scripts/prometh/          # Prometh build / launch / screenshot helpers
```

---

Built on Nativ. Private by default. Runs on this Mac.
