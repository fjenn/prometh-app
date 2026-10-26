"""stdio MCP server for Prometh connectors.

The Composio API key is read at runtime from COMPOSIO_API_KEY or
~/.config/prometh/composio.env. It is never printed. Execute calls are
refused unless the app adds an approval token after the user agrees.
"""

from __future__ import annotations

import argparse
import hmac
import json
import logging
import os
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from mcp.server.mcpserver import MCPServer

logging.disable(logging.INFO)


def load_api_key() -> str:
    environment = os.environ.get("COMPOSIO_API_KEY", "").strip()
    if environment:
        return environment
    override = os.environ.get("PROMETH_COMPOSIO_ENV", "").strip()
    path = Path(override) if override else Path.home() / ".config" / "prometh" / "composio.env"
    if not path.is_file():
        return ""
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        name, value = stripped.split("=", 1)
        if name.strip() == "COMPOSIO_API_KEY":
            return value.strip().strip('"').strip("'")
    return ""


def install_id(path: Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        current = path.read_text(encoding="utf-8").strip()
        if current:
            return current
    value = str(uuid.uuid4())
    path.write_text(value + "\n", encoding="utf-8")
    os.chmod(path, 0o600)
    return value


def read_token(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def tokens_match(supplied: object, expected: str) -> bool:
    if not isinstance(supplied, str) or not expected:
        return False
    return hmac.compare_digest(supplied.encode(), expected.encode())


def broker_request(broker: str, path: str, payload: dict, api_key: str) -> dict:
    if not broker:
        return {"ok": False, "error": "Connectors are not configured."}
    request = urllib.request.Request(
        broker.rstrip("/") + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    if api_key:
        request.add_header("Authorization", f"Bearer {api_key}")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return {"ok": False, "error": f"broker status {error.code}"}
    except urllib.error.URLError:
        return {"ok": False, "error": "broker unreachable"}


def build_server(approval_file: Path, broker: str, install_file: Path) -> MCPServer:
    server = MCPServer("prometh-composio")
    user_id = install_id(install_file)

    @server.tool(name="connectors_search", description="Find actions the user can run in a connected app.")
    def connectors_search(query: str) -> str:
        result = broker_request(
            broker,
            "/tools/search",
            {"query": query, "user_id": user_id},
            load_api_key(),
        )
        return json.dumps(result)

    @server.tool(
        name="connectors_execute",
        description=(
            "Run one connected-app action. Leave approval_token empty. "
            "Prometh fills it only after the user approves."
        ),
    )
    def connectors_execute(tool: str, arguments_json: str = "{}", approval_token: str = "") -> str:
        if not tokens_match(approval_token, read_token(approval_file)):
            return json.dumps({"ok": False, "error": "approval required", "executed": False})
        try:
            arguments = json.loads(arguments_json) if arguments_json else {}
        except json.JSONDecodeError:
            arguments = {}
        if not isinstance(arguments, dict):
            arguments = {}
        result = broker_request(
            broker,
            "/tools/execute",
            {"user_id": user_id, "tool": tool, "arguments": arguments},
            load_api_key(),
        )
        result["executed"] = True
        return json.dumps(result)

    return server


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--approval-file", required=True)
    parser.add_argument("--broker", default="")
    parser.add_argument("--install-file", required=True)
    args = parser.parse_args()
    build_server(Path(args.approval_file), args.broker, Path(args.install_file)).run(transport="stdio")


if __name__ == "__main__":
    main()
