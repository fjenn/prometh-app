# M1: Identity, flags, Prometh shell

## What landed

- `PromethIdentity` (`studio.prometh.Prometh`, support folder `Prometh`, `PROMETH_SUPPORT_DIR` override).
- `PromethFlags` with compiled defaults, `prometh.flags.<name>` UserDefaults, and `--prometh-flags=none|all|a,b`. `none` is `LaunchMode.forcedOff` so it is not read as `Optional.none`.
- Seams S1, S2, S3, S4, S10. Nativ features stay compiled and are hidden by flags. See `Docs/UPSTREAM_SEAMS.md`.
- Placeholder Prometh shell (`PromethRootView`) when `promethShell` is on. Design tokens and capability sizes are in place for M2.
- Harness: `scripts/prometh/build.sh`, `launch.sh`, `screenshot.sh`, `windowid.sh`.

## Acceptance

| Check | Result |
|---|---|
| `scripts/prometh/build.sh` | exit 0. Ad-hoc signed `Prometh.app`. |
| Info.plist | `CFBundleIdentifier=studio.prometh.Prometh`, `CFBundleDisplayName=Prometh`. |
| Support isolation | Launch created `~/Library/Application Support/Prometh/`. `find ~/Library/Application Support/Nativ -newer /tmp/m1-stamp` was empty after the path fix, and again after the chat launch (`/tmp/m1-stamp2`). |
| `rg appendingPathComponent("Nativ")` | One hit, the doc comment inside `PromethIdentity.swift`. |
| Menu bar | One on-screen Prometh window, layer 0, 1280×830. No status-item window. `menuBarExtra` default is off. |
| Sparkle | `sparkleUpdater` default is off. `launch.log` has no Sparkle lines. |
| `--prometh-flags=none` | Nativ Control Panel, composer, and a real reply from `mlx-community/Qwen3.5-4B-MLX-4bit`: "Hello, I'm ready to help." Screenshot `nativ-chat.png`. |
| `make verify` | exit 0 (Python 3.12.13, `mlx_vlm.server`, `nativ_server`). |

Screenshots: `prometh-shell.png`, `nativ-control-panel.png`, `nativ-chat.png`.

## Tests

- `PromethTests`: 4 passed (`testDesignTokensMatchTheSpec`, `testFlagDefaultsAndLaunchOverrides`, `testIdentityNames`, `testSupportOverrideReplacesTheRealFolder`).
- `PromethUITests`: `testPromethShellShowsTheRootWindow` passed. `testNativShellShowsControlPanelAndAWorkingChat` passed (12.9s) after the flag fix.
- `NativTests`: 1384 executed, 2 skipped (opt-in compaction URL and Parakeet audio), 13 assertion failures in 7 cases. `SoftwareUpdaterTests` passed. Failures are outside the seams: `ChatGitWorktreeTests` file-watch timeout, `ChatTranscriptScrollingTests` viewport geometry, `ChatWorkBrowserTests` / `ChatWorkSessionTests` navigation, `MarkdownSelectionTests` drag geometry. Swift Testing follow-on: 92 tests passed.

## Known gap

The first Prometh launch, before `SystemTelemetry` / `ParakeetModelStore` / `ChatSearchStore` were switched off `Nativ/…` paths, updated `~/Library/Application Support/Nativ/Diagnostics/SystemTelemetry.sqlite3`. That file was left in place. Later launches did not touch the Nativ support folder.
