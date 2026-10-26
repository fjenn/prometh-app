# M3: Catalog-backed preparation

## What landed

Chat preparation downloads the catalog `safe` model (Gemma 4 E4B · Safe) at revision `475b9088d29754a3379866cf5aeb6b41acd313c2` into `PROMETH_SUPPORT_DIR/Models`. Each file is hashed (sha256, or git-blob sha1 when `sha256` is empty), stored once under `Models/blobs`, and hardlinked into the model folder and the Hugging Face hub snapshot. `refs/main` is the full revision. The inference child receives that hub as `HF_HUB_CACHE`.

Pause and resume use `curl --continue-at -` into `*.partial`. A forced failure (`PROMETH_PREP_FAIL_ONCE=1` or `--prometh-selftest prep-fail`) shows "Preparation interrupted. Try again." and Retry starts again. Low disk uses `PROMETH_SIMULATED_FREE_BYTES` against the catalog size plus the 8 GB headroom. "Download / verify" re-fetches a file whose hash no longer matches.

Seam S11 (`PROMETH_OFFLINE=1`) points the inference child at `http://127.0.0.1:9` and sets `HF_HUB_OFFLINE=1`. Wi-Fi stays on.

## NativTests compared with upstream `6ef4ba92`

Worktree: `git worktree add --detach /tmp/nativ-base 6ef4ba92a9a0dc72b1a2e9e4a1e0dca8e7d048e3`. The seven cases that failed in the M1 report were rebuilt there (`** TEST BUILD SUCCEEDED **`) and run with the same destination. `git diff --stat 6ef4ba92 --` those test files and `ChatGitWorktree.swift` is empty.

| Case | Upstream base | Prometh tree |
|---|---|---|
| `ChatGitWorktreeTests.testGitChangeObserverSeesNestedEditsAndWorktreeBranchChangesAndStops` | Failed. First run: line 156 only, "Worktree Git metadata changed" (11.648s). Rerun the same day: line 148, "Nested file changed" (9.602s). | Failed. Line 148 and line 156 (13.875s). Rerun: same two lines (12.614s). |
| `ChatTranscriptScrollingTests.testSendingAndBulkStreamingAfterVeryTallReplies` | Passed (4.900s) | Passed (4.946s) |
| `ChatWorkBrowserTests.testFailedNavigationDoesNotReturnOrPublishThePreviousPageAndCanRecover` | Failed, line 264 (0.612s) | Failed, line 264 (0.577s) |
| `ChatWorkSessionTests.testAgentCanRecoverFromAnUnavailableWebsiteInTheSameTab` | Failed (0.154s) | Failed, `ChatWorkTests.swift:1127` twice and unwrap at 1138 (0.156s) |
| `MarkdownSelectionTests` three drag cases | Passed | Passed (0.101s, 0.075s, 0.060s) |

The scrolling and markdown failures from M1 do not reproduce on the base or on this tree. The git-observer miss is FSEvents timing in unmodified upstream code: the base rerun failed the nested-file wait that its first run had passed. No Prometh change touches that observer. The browser and session failures match the base.

Prometh command (exit 65, the three pre-existing failures above):

```
xcodebuild test-without-building -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:NativTests/ChatGitWorktreeTests/testGitChangeObserverSeesNestedEditsAndWorktreeBranchChangesAndStops \
  -only-testing:NativTests/ChatTranscriptScrollingTests/testSendingAndBulkStreamingAfterVeryTallReplies \
  -only-testing:NativTests/ChatWorkBrowserTests/testFailedNavigationDoesNotReturnOrPublishThePreviousPageAndCanRecover \
  -only-testing:NativTests/ChatWorkSessionTests/testAgentCanRecoverFromAnUnavailableWebsiteInTheSameTab \
  -only-testing:NativTests/MarkdownSelectionTests/testDraggingPastViewportAutoscrollsWithoutMountingTheDocument \
  -only-testing:NativTests/MarkdownSelectionTests/testDraggingThroughEquationListCreatesQuote \
  -only-testing:NativTests/MarkdownSelectionTests/testReverseDragAndShiftClickExtendExistingSelection
```

## Acceptance

Disk before the 5.18 GB download (`df -h /`): `1.8Ti` size, `1.3Ti` available. Wi-Fi stayed on (`networksetup -getairportpower en0` → `Wi-Fi Power (en0): On`). The fresh profile was `PROMETH_SUPPORT_DIR=/tmp/prometh-m3-support` plus an empty `HF_HUB_CACHE=/tmp/prometh-m3-hf-empty`. Neither `/Applications/Nativ.app` nor `~/Library/Application Support/Nativ` was used.

| Check | Result |
|---|---|
| `scripts/prometh/build.sh` | `** BUILD SUCCEEDED **`, ad-hoc signed `Prometh.app`. Exit 0. |
| `make verify` | Exit 0. Python 3.12.13, `mlx_vlm.server`, `nativ_server`. |
| `PromethTests` + `PromethUITests` | `** TEST EXECUTE SUCCEEDED **`, `PROMETH_EXIT:0`. CatalogTests 5 passed, including pause/resume and corrupt re-download. Foundation 5 passed. UI: shell 12.793s and 3.910s, welcome 16.223s, workspace chat 65.864s. |
| Fresh Chat download | `catalog-chat.json` `passed: true`. Eight files, all `matched: true`, revision `475b9088d29754a3379866cf5aeb6b41acd313c2`. Hub `refs/main` is that revision. Blob, model folder, and snapshot share inodes (`nlink` 3). `HF_HUB_CACHE` stayed empty. |
| Friendly names | Rows say "Chat", "Downloading…", "Paused", "Preparation interrupted. Try again.", "Talk and write". No repository id on screen. |
| Open chat | Enables at Chat Ready (`openChatEnabled: true`, screenshot `chat-ready.png`). |
| Pause / resume | Logged `pause path=model.safetensors offset=517961490` (about 10% of 5,179,239,349 bytes) and `resume path=model.safetensors offset=517961490`. |
| Forced failure | Log `stage=failed reason=injected` and the row "Preparation interrupted. Try again." Retry then downloaded. |
| Low disk | `PROMETH_SIMULATED_FREE_BYTES=1000000000`. Cards say "Not enough space for chat/voice/images/video." Continue still moves to step 3 / 4. |
| Corruption | Flipped byte 123 of `tokenizer_config.json`. "Download / verify" logged `corrupt removed` and re-downloaded. `prep-corrupt.json` `passed: true`. |
| Offline reply | `PROMETH_OFFLINE=1`. Reply: "Hello there, greetings to you." Probe: `BLOCKED URLError`. `offline-chat.json` `passed: true`. |

`PromethTests` / `PromethUITests` invocation:

```
xcodebuild test-without-building -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethTests -only-testing:PromethUITests
```

Offline method: the Mac's network is unchanged. `PROMETH_OFFLINE=1` sets the mlx child `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, `HF_DATASETS_OFFLINE=1`, `HF_ENDPOINT` / `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` to `http://127.0.0.1:9`, and `NO_PROXY=127.0.0.1,localhost,::1`. A separate Python process with the same proxy prints `BLOCKED`. The self-test waits until the server is running and the model is no longer loading, then sends.

The prepared model is kept at `/tmp/prometh-m3-support` for the later chat milestones. `/tmp/nativ-base`, `/tmp/nativ-base-dd`, and `/tmp/prometh-m3-lowdisk` are removed after this report.

## Screenshots

`low-disk-capabilities.png`, `low-disk-after-continue.png`, `prep-interrupted.png`, `downloading.png`, `paused.png`, `chat-ready.png`, `corrupt-verify.png`, `offline-reply.png`.

## Design decisions to review

Carried from M2, unchanged:

- Privacy sentence starts "Local models run…". The reference starts "Models run…".
- Sizes use two decimals (`5.18 GB`, `13.40 GB`, `9.80 GB`).
- A 960-wide window measures 960×682.
- Connectors stay hidden when no broker is configured.
- Preparation rows use the capability name, not a repository id.

## Known gap

`make verify` is the Python distribution check in this Makefile, not the full NativTests suite. The Nativ comparison above is the suite run for this milestone. Three upstream cases still fail, on the base as well as here.
