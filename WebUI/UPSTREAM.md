# Upstream web UI

Source: https://github.com/fjenn/Prometh — `web/`, commit `1962c28`.

Copied without node_modules, dist, public/models or generated public/ort. The reference repository is read-only. No new CSS or visual design system was introduced.

## Changed upstream files

| File | Reason |
| --- | --- |
| `index.html` | Explicit image CSP permits self, HTTPS Composio logos, data/blob and native-scheme image assets. |
| `package.json` | Mac postinstall applies the retained patch but does not copy browser ONNX runtime binaries into public assets. |
| `src/main.tsx` | Await native hydration before mounting React, avoiding an onboarding/theme flash on prepared Macs. |
| `src/startup.ts` | Menu/state/title events, native settings persistence, native initialization hooks, and a non-blocking native health warm-up (Phase 3). |
| `src/state/actions.ts` | Native harness turn context; Phase 4 voice timing, 550ms endpoint wait and parallel standby capture; real video dispatch, native rename/delete/export/reset/download deletion; existing exported action names/signatures retained. |
| `src/ui/Onboarding.tsx` | Mac execution/storage copy and one native performance tile hook; all onboarding layout and Evil reveal retained. |
| `src/ui/Settings.tsx` | Native plugins/models/search/performance hooks; hide browser image quality selector on Mac; Mac privacy/storage/about copy and native storage query; omit browser logout; Phase 3 shows the actual health-reported chat model separately from the preferred model; Phase 3c adds a Settings nav entry that opens the existing Customize modal without duplicating its content. |
| `src/ui/Workspace.tsx` | Two additive native component hooks: video job replacement and sources/connector/media extras under assistant replies; Phase 3 stretches the assistant column independently of streamed text width. |
| `test/vad.test.ts` | Phase 4 runs the existing echo/barge-in/turn-taking regressions against the Mac VAD adapter. |
| `vite.config.ts` | Relative asset base, native engine resolver, and bundled resource output directory. |

## Added files

- `INVENTORY.md` — Native integration inventory.
- `src/native/audio.ts` — Typed native engine/bridge/UI adapter.
- `src/native/blobs.ts` — Typed native engine/bridge/UI adapter.
- `src/native/bridge.ts` — Typed native engine/bridge/UI adapter.
- `src/native/catalog.ts` — Typed native engine/bridge/UI adapter.
- `src/native/device.ts` — Typed native engine/bridge/UI adapter.
- `src/native/encoding.ts` — Typed native engine/bridge/UI adapter.
- `src/native/llm.ts` — Typed native engine/bridge/UI adapter.
- `src/native/media.ts` — Typed native engine/bridge/UI adapter.
- `src/native/prep.ts` — Typed native engine/bridge/UI adapter.
- `src/native/reasoning.ts` — Typed native engine/bridge/UI adapter.
- `src/native/state.ts` — Typed native engine/bridge/UI adapter.
- `src/native/ui/MessageExtras.tsx` — Typed native engine/bridge/UI adapter.
- `src/native/ui/Settings.tsx` — Typed native engine/bridge/UI adapter.
- `src/native/ui/Video.tsx` — Typed native engine/bridge/UI adapter.
- `src/native/video.ts` — Typed native engine/bridge/UI adapter.
- `test/native-bridge.test.ts` — Native regression tests.
- `test/native-reasoning.test.ts` — Native regression tests.

- `src/native/presentation.ts` — Phase 3 native presentation/send regression support.
- `test/native-presentation.test.ts` — Phase 3 native presentation/send regression support.
- `test/native-send.test.ts` — Phase 3 native presentation/send regression support.
- `test/fixtures/native-send.ts` — Phase 3 native presentation/send regression support.

- `test/native-settings.test.ts` — Phase 3c Settings-to-Customize navigation and shared tabs regression.
- `test/fixtures/native-settings.ts` — Real native-resolved Settings/Customize test entry.

## Resync invariants

`src/styles.css`, `src/App.tsx`, `src/state/types.ts`, `src/state/store.ts`, `src/ui/Icon.tsx`, `src/ui/Markdown.tsx`, `src/ui/Media.tsx`, and `src/ui/Overlay.tsx` remain byte-identical. All original engine files remain byte-identical. The native resolver redirects their importers to src/native implementations; the browser workers are never in the shipping module graph.

The generated bundle is tracked under `Sources/Prometh/Resources/WebUI/`. Rebuild with `scripts/prometh/build-webui.sh`. Xcode needs no Node installation when using the checked-in bundle. Browser engine npm dependencies remain installed for unchanged upstream TypeScript typechecking; they are not included in the Mac bundle.

## Phase 3 polish

Source chips use existing `btn btn-bordered` / `acts` geometry with full-column width, 6px wrap gap, single-line truncation and inherited color; clicks call the native browser bridge. Plugin logos retain the upstream provider icon geometry, display an initial while loading/on error, and use HTTPS URLs from ToolkitCatalog; connected apps sort first. Runtime chat identity is fetched read-only from native `/health` and mapped to the catalog rather than reusing a potentially stale preference label. Composer health warm-up no longer sets the blocking web `warming` state. No changes to upstream `src/styles.css`, `src/App.tsx`, `src/state/types.ts`, or `src/state/store.ts`.

Phase 3b changes only the added native video event adapter (monotonic percent guard) and generated bundle; no further upstream UI/state/CSS files changed. Native/Python workers forward actual job log stages rather than interpolating elapsed time.

## License

The web UI source comes from Finn Jennen's own repository (`fjenn/Prometh`, `web/`, commit `1962c28`). It is reused here by the same owner. The upstream repository has no LICENSE file, so it is not relicensed: it keeps the same terms as this repository. Third-party npm dependencies keep their own licenses as listed in `package-lock.json` and in `node_modules/*/LICENSE`. For example, `@mlc-ai/web-llm` is Apache-2.0, and `patches/@mlc-ai+web-llm+0.2.84.patch` is a local modification of it. No dependency source is vendored into the app bundle except what Vite compiles into `Sources/Prometh/Resources/WebUI/assets`.

## Phase 4 voice latency

No visual/CSS changes. `src/state/actions.ts` has additive native voice timing hooks, forwards the voice flag, uses the 550ms endpoint wait and opens standby capture concurrently with the reply. Legacy `/diag/voice` fetches were replaced by native timing records. Native adapters now split speech incrementally (`src/native/sentences.ts`), reuse the resident Kokoro worker (`media.ts`), preserve capture startup frames and watch missing frames (`audio.ts`), and use a Mac VAD copy (`src/native/vad.ts`) that does not calibrate an initial speech frame as room noise. `src/native/voice-latency.ts` handles per-turn timing IDs; native `llm.ts` carries those IDs and the voice flag. New tests: `test/native-voice.test.ts`, `test/native-speech.test.ts`, `test/fixtures/native-speech.ts`. All original upstream engine/UI/CSS files retain their previous resync status; only actions changed further.

Phase 4 also extends `test/native-send.test.ts` / its existing fixture to verify that Listening waits for native warm-up and actual microphone startup. Native media waits for speech/prompt readiness before capture. Native Player records first audio only after its running context clock reaches the source start; upstream Player/VoiceLayer markup and CSS remain unchanged.
