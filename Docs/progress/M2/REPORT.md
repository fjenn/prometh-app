# M2: Onboarding, workspace, and settings wired to Nativ chat

## What landed

- Prometh onboarding, workspace, composer, settings, and customize screens from the reference UI, talking to `PromethStore`.
- Conversations are Nativ chat sessions on the same `NativModel` and local server. Return sends, Stop cancels, and edit, regenerate, copy, rename, search, delete, and export use the Nativ session store.
- Drafts and per-chat mode are stored in `state-v1.json`. A fresh `PROMETH_SUPPORT_DIR` still shows Welcome. An untouched auto-created empty session stays out of the sidebar until the user starts it.
- Voice, images, video, and Evil preparation say they are not ready. Connectors stay hidden unless `PROMETH_BROKER_URL` or a saved broker URL is set.
- Nativ features stay compiled. The Prometh command menu is behind `promethShell`.

## Acceptance

| Check | Result |
|---|---|
| `scripts/prometh/build.sh` | exit 0. Ad-hoc signed `Prometh.app`. |
| `make verify` | exit 0. Python 3.12.13, `mlx_vlm.server`, `nativ_server`. |
| Welcome XCUITest | passed (16.0s). Exact Welcome copy, step `1 / 4`, Back keeps Images selected, total goes from `5.18 GB` to `9.80 GB`. |
| Chat XCUITest | passed (63.7s). Return sends "Say hello in five words." and a streamed reply appears. Stop shows "Stopped". Edit, regenerate, copy, rename, search, delete confirmation, export, and relaunch restore the draft. Sidebar, composer, send, mode, and settings tab identifiers exist. The window walk does not contain the forbidden labels. |
| Design tokens and repo-id scan | `PromethTests` 5 passed. No repository id in `Text` / `Label` strings outside the collapsed Details disclosure. |
| Screenshots | 960×682 and 1280×860, Light and Dark, for Welcome, capabilities, workspace, and settings. Preparing at 1280×860 Light. `scripts/prometh/compare.sh` wrote side-by-side images under `pairs/`. |

`PromethTests` and `PromethUITests`: 9 passed, 0 failed. `NativTests` were not re-run. The 13 failures recorded in the M1 report are unchanged and sit outside these seams. The command-menu edit keeps the previous Nativ actions when `promethShell` is off.

## Discrepancies against the reference screenshots

The reference app was built with `Prometh-reference/Prometh/build.sh` into `/tmp/prometh-ref/Prometh.app` and was not committed. Layout and copy match on Welcome, the empty workspace, and Settings › Appearance.

1. **Connectors.** Preparing does not show "Connect your apps". No broker is configured, which is the M2 rule. The reference always shows Gmail, Outlook, Google Drive, and GitHub.
2. **Repository ids.** The reference preparation row shows `mlx-community/gemma-4-e4b-it-4bit` while it downloads. Prometh shows "Waiting" and keeps that id out of the accessibility tree. The Evil weight line stays inside the collapsed Details disclosure.
3. **Sizes.** Cards and the selected total use two decimal places (`5.18 GB`, `13.40 GB`, and `9.80 GB` after Images). The acceptance test requires the 4.62 GB step to be exact. The reference formatter shows the selected total as `5.2 GB` and Video as `13.4 GB`.
4. **Privacy sentence.** It starts "Local models run…" so the forbidden label "Models" is absent. The reference starts "Models run…".
5. **960-wide height.** Both apps measure 960×682. The 650-point minimum content height plus the title bar does not fit in 680. 1280×860 matches.
6. **Preparation.** M2 does not download weights. The row stays on Waiting / Resume. The reference starts the catalog download immediately.

## Known gap

The first Prometh launches in M1 wrote one Nativ diagnostics file before the support path was moved. Later launches, including this milestone, use `~/Library/Application Support/Prometh/`.
