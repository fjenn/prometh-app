# Web UI → Mac backing

Upstream: fjenn/Prometh, web at 1962c28. The React UI and CSS ship inside WKWebView; no SwiftUI screen is used when `webUI` is on. “Wired” below describes the implementation; interactive/model verification is performed by the supervisor, not by launching the app from this task.

| Screen/component/state | Backing in the Mac build |
| --- | --- |
| App / light, dark, system themes | Upstream App and styles; native appearance persisted through `settings.sync`; WK under-page color matches the initial theme |
| Onboarding Welcome / capability choice / Back / Continue | Upstream Onboarding and actions; actual native selected capabilities and model catalog, MacSpecs device probe; browser-only explanatory copy adjusted |
| Evil reveal, onboarding and in-chat sheet | Upstream EvilReveal; native Evil preparation and `PromethStore.setMode` / existing llama supervisor |
| Preparation rows: queued, preparing, downloading, checking, ready, paused, cancelled, failed; continue while other models prepare | PreparationCoordinator snapshots/events; pause, cancel, resume, retry bridge methods; native catalog model names and sizes |
| Turbo onboarding tile | Same glass prep-card classes, native Apple silicon status; browser flag tutorial replaced on Mac |
| Empty “What do you want to make possible?” | Upstream Workspace; local persisted chats/native first-run import |
| Header, conversation title, conversation actions, LoadIndicator | Upstream header; real `/health` warm check and reactive native model load percentage/state; native generated titles via metadata events; rename/delete/export routed natively |
| Sidebar, chat list, search, New chat, “Your AI is getting ready” | Upstream sidebar and state; persistent WK localStorage plus native session mapping; actual prep state |
| Composer, plus menu, file chips, image mode, mode menu, enabled skills, warming | Upstream Composer/actions; native model/preparation state and mode; native WK file-picker delegate; text files carried into native turn, image attachments imported with their original format through native ChatViewModel |
| Mic / recording / transcribing | Native VoiceAudioRecorder + Silero frames; upstream VoiceDetector, Whisper via NativAudioClient; native microphone authorization |
| Voice orb / VoiceLayer, muted, listening, hearing, thinking, speaking, interruption, barge-in | Upstream VoiceLayer and voice action state machine; native capture/Silero/Whisper/Kokoro; web audio player and real echo-aware turn detector; native chat harness for replies |
| User bubble, attachments, Edit sheet | Upstream UI; native session edit/resend path and file-backed image blobs |
| Assistant “Prometh · Writing”, blank streaming caret, markdown, Copy, Regenerate, read-aloud, tokens/s | Upstream renderer/actions; native harness events, reasoning stripped before rendering, native clipboard, edit/resend for regeneration, Kokoro, native decode metrics where supplied |
| Search sources row | Additive NativeMessageExtras, using existing acts/buttons/hair/tint styles; real native SourceLink values; links open through native navigation delegate |
| Connector approval (Allow once / Always allow / Don’t allow), running/declined/succeeded/failed | Additive NativeMessageExtras; native ConnectorCard IDs and existing PromethStore approval/decline methods; no synthetic approvals |
| Image job shimmer/canvas/text/bar/Cancel | Original ImageJob gen-card; native FLUX image generation with selected model/auth; cancellation through URLSession task; no simulated progress (0 until result where no progress is supplied) |
| Image ArtifactCard, preview, Save, Edit/version | Original ArtifactCard/ArtifactPreview; files in app support WebBlobs via scoped scheme (native tool MediaAssets are mapped into the same original ArtifactCard), native NSSavePanel; original prompt-based edit behavior creates a new generation and keeps the original |
| VideoNote replacement: generating/progress/cancel | NativeVideoJob uses the same gen-card/canvas/bar/button structure; real PromethMediaWorker progress and task cancellation |
| Video result/player/Save/Edit | Artifact-card style native extension with HTML video and byte-range scheme responses; native Save dialog, native trim worker; resulting versions persisted with turn extras |
| Settings Appearance | Original appearance pane; native Snapshot appearance plus web theme |
| Settings Capabilities / model selection | Original capability rows/prep controls; added native model picker uses PromethModelPicker options and store.chooseModel; native model size/status, actual downloads |
| Settings Turbo | Same settings pane/tile classes; native acceleration/specs, browser instructions remain in upstream fallback code but are not shown on Mac |
| Settings Privacy/data/about/storage/export/restart/reset/delete downloads | Original pane with Mac-specific copy; real app-owned file byte count, native export/save; reset uses native session deletion and web state reset; confirmed model deletion cancels preparations and unloads engines before removing app-owned models |
| Settings Customize entry | Existing Settings nav button styling; closes Settings and opens the same Customize modal used by the unchanged sidebar button, preserving the selected Plugins/Tools/Skills tab |
| Customize Plugins | Native ToolkitCatalogModel catalog/status/search/refresh/connect/disconnect, retaining upstream row/button styles; actual authorization errors shown |
| Customize Tools | Original attachment toggle synced to native; real native web-search toggle; native harness retains its tool visibility and permission policy |
| Customize Skills / add/edit/import/toggle/delete | Original forms/actions; skills persisted in WK state and native SkillRecords; native harness uses the existing prompt additions |
| Sheets, menus, toasts, confirmation dialogs, errors | Upstream Overlay components; native errors delivered through typed request/reply bridge and existing error/toast state |
| Artifact and attachment sheets | Original Media components; scoped file URLs and native Save handling |
| Other-tab state | Original startup locking retained when WK supports navigator.locks; one web view per window remains the intended operating mode |
| Menu shortcuts: New chat ⇧⌘O, Settings ⌘, / Customize | Native commands → bridge menu event → existing web actions/store |
| SwiftUI fallback | All existing SwiftUI views retained; disable `prometh.flags.webUI` to select original PromethRootView |

## Persistence and boundaries

- Web Snapshot and turn extras persist in the default WK website data store; generated/attached blob bytes live in app support `WebBlobs`. Native harness conversations remain in the existing native session store. Web chat IDs map to native session IDs in UserDefaults.
- Existing native chats are imported when the web chat list is empty; native source/connector/media extras are imported too. Native historical attachment chips are not fully reconstructed in that import.
- Image editing preserves the web app’s prompt-based regeneration behavior; it does not perform native pixel-conditioned edits. Dedicated image generation has cancellation but the endpoint supplies no intermediate percentages.
- Video progress reflects only events the native worker emits; no interpolation. Hardware/model generation, microphone access, WK rendering, authorization sign-in and save dialogs require supervisor live checks.
- Browser WebLLM, Transformers.js, Kokoro.js and ONNX workers are retained as upstream source for resync/typechecking but excluded by the native Vite resolver from the shipped execution graph. No browser model files or ONNX wasm are bundled.

## Phase 3 verification fixes

- Source rows stretch to the full assistant column, wrap at the existing 6px gap, and truncate each inherited-color chip to one line within 260px. Source activation uses validated HTTP(S) URLs through `browser.open` → `NSWorkspace.open`; the WK document never navigates away.
- Plugin icons use Composio's HTTPS logo URL with the existing white/10px provider icon frame and a visible initial during loading or after failure. Image CSP explicitly allows HTTPS. Connected apps sort before other apps, alphabetically within each group.
- Chat capability text now polls native `/health` while mounted and shows the actual loaded model (including its catalog size only when identified). The safe-chat picker is labelled “Preferred safe chat” to distinguish configuration from resident state. No model selection or server restart occurs while reading status.
- Startup native warm-up runs in the background and never disables typing/Send. A regression test builds the real native-resolved action graph and confirms draft clearing and user/streaming-assistant append before any native chat reply.
- Phase 3 gates build Debug only. Running Release, its video job, Release build products, and `/Applications/Prometh.app` are intentionally left untouched.

Phase 3b: video progress now follows real job stdout/log stages (load 10%, denoise steps toward 80%, VAE 85%, output 100%); duplicate/older stages are ignored, including in the web event adapter. Existing gen-card markup/CSS is unchanged. FLUX remains final-response-only because its current HTTP path exposes no per-job step stream.
