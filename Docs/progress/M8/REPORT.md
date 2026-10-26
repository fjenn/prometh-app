# M8: Composio connectors via MCP

## What landed

- `PromethRuntime/composio_mcp/server.py` is a stdio MCP server (`mcp==2.3.0`, hash-locked). It exposes `connectors_search` and `connectors_execute`.
- The API key is read at call time from `COMPOSIO_API_KEY` or `~/.config/prometh/composio.env`. It is not printed, not logged, and not stored on `MCPServerConfig.environment`.
- Execute is refused unless `approval_token` matches the mode-0600 file the app writes. A guessed token does not reach the broker. After the in-app sheet, `PromethConnectorApproval.stamp` overwrites any model-supplied token.
- The sheet title is "Approve connected-app action". Approve calls `confirmToolConsent`. Deny, or dismissing the sheet while the tool is still waiting, calls `denyToolConsent`.
- The server is registered as catalog id `prometh.composio` only when a broker URL is set (`PROMETH_BROKER_URL` or Customize › Advanced / Plugins). With no URL, onboarding, Customize › Plugins, and the composer plugins menu stay hidden.
- One install id is kept in Keychain service `studio.prometh.Prometh.connectors` and mirrored to a mode-0600 file the server reads.
- `scripts/prometh/provision-runtime.py --composio` installs the lock into `PromethRuntime/composio_mcp/.venv`, which is gitignored.

## Linux tests

Provision, then the mock broker (the key in that run is a throwaway value created in `/tmp` and is not printed):

```
python3 scripts/prometh/provision-runtime.py --composio
PROMETH_MCP_PYTHON=PromethRuntime/composio_mcp/.venv/bin/python \
  PromethRuntime/composio_mcp/.venv/bin/python PromethRuntime/composio_mcp/test_composio.py
```

```
{"passed": true, "tests": 1, "mcp": "2.3.0", "executeWithoutApproval": 0}
```

Search returned `GITHUB_LIST_REPOS`. Execute with token `true` did not increment the broker. Execute with the app token did, and the broker saw the expected Authorization header. The install id file is mode 0600 and matches the id sent to search. `swiftc` is not installed, so `PromethConnectorTests` was not executed.

## Live broker

`COMPOSIO_API_KEY` is unset and `~/.config/prometh/composio.env` is absent. No broker URL is configured. The live GitHub connect needs a browser. That item is recorded in `Docs/progress/BLOCKED.md`. The rest of M8 is not stubbed.

## PENDING MAC VERIFICATION

```
python3 scripts/prometh/provision-runtime.py --composio
scripts/prometh/build.sh
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethTests/PromethConnectorTests
```

With no broker URL: no "Connect your apps" panel, no Plugins tab, no connector composer action.

With `PROMETH_BROKER_URL` (or the Advanced field) and `~/.config/prometh/composio.env` mode 600:

- Customize › Plugins lists Gmail, Outlook, Google Drive, and GitHub.
- `MCPHostManager` shows catalog id `prometh.composio` running.
- Connect GitHub reaches Connected after the browser step.
- "List my GitHub repositories" shows "Approve connected-app action". Approve returns the result. Deny leaves the broker execute log unchanged.
- Disconnect is reflected in Customize and the composer.

`make verify` was not run here.
