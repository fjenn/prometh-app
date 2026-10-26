# Upstream seams

Edits to upstream Nativ files are limited to the rows below. Each code edit is marked `// PROMETH-SEAM: <id>`.

| ID | File | Why |
|---|---|---|
| S1 | `Configuration/Signing.xcconfig` | `NATIV_PRODUCT_NAME = Prometh`, `NATIV_BUNDLE_IDENTIFIER = studio.prometh.Prometh`. `DEVELOPMENT_TEAM` stays overridable from git-ignored `Signing.local.xcconfig`. |
| S1 | `project.yml` | Display name Prometh. `PRODUCT_MODULE_NAME` stays `Nativ` so existing `@testable import Nativ` tests keep compiling. Prometh sources, resources, test targets, the Prometh scheme, and the PromethRuntime copy script (S3). |
| S1 | `Configuration/Nativ-Info.plist` | App icon `AppIcon.icns`. Microphone and audio prompts say Prometh. Display name still follows `$(NATIV_PRODUCT_NAME)`. |
| S1 | `Extensions/VoiceDictation/Runtime/VoiceDictationExtensionRuntime.swift` | ExtensionKit host matches `studio.prometh.Prometh`. |
| S2 | Support-directory call sites listed below | `appendingPathComponent("Nativ")` became `PromethIdentity.appendingSupportDirectory(to:)`, which also honors `PROMETH_SUPPORT_DIR`. |
| S2 | Keychain, launchd, and notification identifiers | `dev.local.Nativ…` services and launch-agent labels now use `PromethIdentity.bundleIdentifier`, so Prometh does not read Nativ's keychain or rewrite Nativ's launch agents. Bundle-scoped `nativ.*` UserDefaults keys stay, because the new bundle id already isolates them. |
| S2 | `Sources/Nativ/Features/Files/FileReadAccessPolicy.swift` | File search still blocks `Application Support/Nativ` and also blocks `Application Support/Prometh`. |
| S2 | `PythonDistribution/Overlay/nativ_server.py` | Analytics and routine-trigger paths default to Prometh and honor `PROMETH_SUPPORT_DIR` / `MLX_PLATFORM_ANALYTICS_DB_PATH`. |
| S3 | `project.yml` | `Sources/Prometh`, `PromethTests`, `PromethUITests`, runtime copy phase. |
| S4 | `Sources/Nativ/Main.swift` | `promethShell` (default on) presents `PromethRootView` instead of `NativWindowRoot`. The shell receives the app delegate's `NativModel`. |
| S4 | `Sources/Nativ/AppDelegate.swift` | Menu bar extra only when `menuBarExtra` is on. Routines only when `routines` is on. Last window closes the Prometh shell. Support directory is created on launch. `model` is visible to the Prometh shell. |
| S4 | `Sources/Nativ/Features/Windowing/NativApplicationCommands.swift` | With `promethShell` on, New chat, Settings, and Customize post to the Prometh shell. With the flag off, the Nativ commands are unchanged. |
| S10 | `Sources/Nativ/SoftwareUpdater.swift`, `AppDelegate.swift` | `start()` returns immediately unless `sparkleUpdater` is on (default off). |
| S11 | `Sources/Nativ/NativSettings.swift` `launchEnvironment` | When `PROMETH_OFFLINE=1`, the mlx-vlm child gets `HF_HUB_OFFLINE=1` and HTTP(S) proxies pointed at `http://127.0.0.1:9`. Loopback stays in `NO_PROXY`. This does not change the Mac's network. |
| S5 | `Sources/Nativ/Features/Browsing/WebSearchProvider.swift`, `WebBrowsingProviderClient.swift`, `WebBrowsingRuntime.swift`, `WebSearchSettingsView.swift` | `local` page reader, `configurationKind: .none`, keyless. |
| S6 | `Sources/Nativ/Features/Browsing/Providers/SearXNGBrowsingProvider.swift` | `prometh-embedded` sentinel resolves to the per-launch loopback URL. The provider fetches 8 results, dedupes, and sorts by score. |
| S8 | `Sources/Nativ/Features/Chat/ChatToolRegistry.swift` | When the Prometh shell is on, and the process is not an XCTest host, advertised native tools pass through `PromethToolVisibility`. |
| S7 | `Sources/Nativ/Features/Chat/ChatViewModel.swift` | `ChatEndpointResolver` (nil unless Prometh installs it) rewrites the queued host, port, API key, and model for an Evil chat. A dropped llama-server connection uses the human interruption string. Metrics fetches stay `try?`. |
| S12 | `Sources/Nativ/AppDelegate.swift` | When the Prometh shell is on, and the process is not XCTest, an empty or 8-bit image model id becomes the catalog 4-bit FLUX.2 Klein id. `ImageGenerationViewModel.fallbackModelID` is unchanged. The dictation model becomes Whisper large-v3-turbo when it is empty or Parakeet. Parakeet preparation is skipped while the shell is on. |
| S13 | `Sources/Nativ/Features/Chat/ChatToolRegistry.swift` | `generate_video` is advertised only when the Prometh shell is on, video is enabled, and the process is not XCTest. The handler stays compiled. |
| S9 | `Sources/Nativ/Features/Chat/ChatViewModel.swift`, `Tools/ChatWebSearchTool.swift` | Citation and persona sections, and the `<search_results>` block. The block is omitted under XCTest so existing JSON fixtures stay exact. |
| note | `Sources/Nativ/Features/VoiceCapture/Parakeet/ParakeetTranscriber.swift` | The loaded CoreAI session is stored as `Any`. XCTest realizes every class, and completing `Session` metadata jumps through CoreAI, which is not installed on macOS 26. Loading and transcription still use the real session. |

## S2 support-directory files

- `Sources/Nativ/NativSettings.swift`
- `Sources/Nativ/Utilities/Formatting.swift`
- `Sources/Nativ/Features/Artifacts/ArtifactStore.swift`
- `Sources/Nativ/Features/Artifacts/ArtifactSearchIndex.swift`
- `Sources/Nativ/Features/Chat/ChatSessionStore.swift`
- `Sources/Nativ/Features/Chat/ChatProjectStore.swift`
- `Sources/Nativ/Features/ImageGeneration/ImageGenerationViewModel.swift`
- `Sources/Nativ/Features/MCP/MCPHostManager.swift`
- `Sources/Nativ/Features/Models/HuggingFaceCache.swift`
- `Sources/Nativ/Features/Extensions/NativKitLibrary.swift`
- `Sources/Nativ/Features/Extensions/NativExtensionPlatform.swift`
- `Sources/Nativ/Features/Extensions/VoiceDictationExtension.swift`
- `Sources/Nativ/Features/Extensions/CustomTool.swift`
- `Sources/Nativ/Features/Dashboard/NativAnalyticsStore.swift`
- `Sources/Nativ/Features/Integrations/IntegrationServices.swift`
- `Sources/Nativ/Features/Routines/RoutineStore.swift`
- `Sources/Nativ/Features/Routines/RoutineScheduler.swift`
- `Sources/Nativ/Features/Routines/RoutineLaunchAgent.swift`
- `Sources/Nativ/Features/VoiceCapture/VoiceAudioRecorder.swift`
- `Sources/Nativ/Features/VoiceCapture/AudioCaptureLibrary.swift`
- `Sources/Nativ/Features/VoiceCapture/AudioAnalyticsStore.swift`
- `Sources/Nativ/Features/SystemMonitor/SystemMonitorStore.swift`
- `Sources/Nativ/Features/Files/FileReadConfigurationView.swift`
- `Sources/Nativ/Features/Files/FileWriteConfigurationView.swift`
- `Sources/Nativ/Features/Browsing/WebSearchProvider.swift`
- `Sources/Nativ/Features/SystemMonitor/SystemTelemetry.swift` (`Nativ/Diagnostics`)
- `Sources/Nativ/Features/Chat/ChatSearchStore.swift` (`Nativ/Chat/Search.sqlite`)
- `Sources/Nativ/Features/VoiceCapture/Parakeet/ParakeetModelStore.swift` (`Nativ/SpeechModels`)

`NativTests` compiles `PromethIdentity.swift`, `PromethFlags.swift`, `PromethToolVisibility.swift`, and `CitationMarkup.swift` because those upstream files are built into the test bundle directly.
