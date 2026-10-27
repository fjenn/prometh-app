"""Mocked connector MCP tests. They never print the API key."""

from __future__ import annotations

import json
import os
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import anyio
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client

ROOT = Path(__file__).resolve().parent
SERVER = ROOT / "server.py"


class Broker:
    def __init__(self) -> None:
        self.search = 0
        self.execute = 0
        self.saw_key = False
        self.expected_key = ""

    def serve(self) -> int:
        broker = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                return

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length) or b"{}")
                header = self.headers.get("Authorization", "")
                if broker.expected_key and header == f"Bearer {broker.expected_key}":
                    broker.saw_key = True
                if self.path == "/tools/search":
                    broker.search += 1
                    payload = {"ok": True, "tools": ["GITHUB_LIST_REPOS"], "user_id": body.get("user_id")}
                elif self.path == "/tools/execute":
                    broker.execute += 1
                    payload = {"ok": True, "repos": ["prometh-app"]}
                else:
                    payload = {"ok": False}
                raw = json.dumps(payload).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        return int(httpd.server_address[1])


def tool_text(result) -> str:
    parts = []
    for block in result.content:
        text = getattr(block, "text", None)
        if text:
            parts.append(text)
    return "\n".join(parts)


async def session_checks(tmp: Path, broker: Broker, port: int, key: str) -> None:
    approval = tmp / "approval"
    approval.write_text("app-minted-token\n", encoding="utf-8")
    install = tmp / "install-id"
    env = os.environ.copy()
    env["PROMETH_COMPOSIO_ENV"] = str(tmp / "composio.env")
    env["COMPOSIO_API_KEY"] = ""
    (tmp / "composio.env").write_text(f"COMPOSIO_API_KEY={key}\n", encoding="utf-8")
    os.chmod(tmp / "composio.env", 0o600)
    params = StdioServerParameters(
        command=os.environ["PROMETH_MCP_PYTHON"],
        args=[
            str(SERVER),
            "--approval-file",
            str(approval),
            "--broker",
            f"http://127.0.0.1:{port}",
            "--install-file",
            str(install),
        ],
        env=env,
    )
    async with stdio_client(params) as streams:
        async with ClientSession(streams[0], streams[1]) as session:
            await session.initialize()
            listed = await session.list_tools()
            names = sorted(tool.name for tool in listed.tools)
            assert names == ["connectors_execute", "connectors_search"], names
            search = json.loads(tool_text(await session.call_tool("connectors_search", {"query": "github repos"})))
            assert search["ok"] is True
            assert "GITHUB_LIST_REPOS" in search["tools"]
            refused = json.loads(tool_text(await session.call_tool(
                "connectors_execute",
                {"tool": "GITHUB_LIST_REPOS", "arguments_json": "{}", "approval_token": "true"},
            )))
            assert refused["executed"] is False
            assert broker.execute == 0
            approved = json.loads(tool_text(await session.call_tool(
                "connectors_execute",
                {
                    "tool": "GITHUB_LIST_REPOS",
                    "arguments_json": "{}",
                    "approval_token": "app-minted-token",
                },
            )))
            assert approved["executed"] is True
            assert broker.execute == 1
            assert broker.saw_key is True
            user_id = search["user_id"]
    again = install.read_text(encoding="utf-8").strip()
    assert again == user_id
    assert install.stat().st_mode & 0o777 == 0o600
    log = tmp / "server-stdout-not-used"
    log.write_text(json.dumps({"refused": refused, "approved_executed": approved["executed"]}), encoding="utf-8")
    assert key not in log.read_text(encoding="utf-8")


class DirectAPI:
    def __init__(self) -> None:
        self.search = 0
        self.execute = 0
        self.saw_key = False
        self.expected_key = ""

    def serve(self) -> int:
        api = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                return

            def _send(self, payload: dict) -> None:
                raw = json.dumps(payload).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self):
                header = self.headers.get("x-api-key", "")
                if api.expected_key and header == api.expected_key:
                    api.saw_key = True
                if self.path.startswith("/api/v3.1/tools"):
                    api.search += 1
                    self._send({"items": [{"slug": "GITHUB_LIST_REPOS", "description": "List repositories"}]})
                    return
                self._send({"ok": False})

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                header = self.headers.get("x-api-key", "")
                if api.expected_key and header == api.expected_key:
                    api.saw_key = True
                if self.path.startswith("/api/v3.1/tools/execute/"):
                    api.execute += 1
                    self._send({"successful": True, "data": {"repos": ["prometh-app"]}})
                    return
                self._send({"ok": False})

        httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        return int(httpd.server_address[1])


async def direct_checks(tmp: Path, api: DirectAPI, port: int, key: str) -> None:
    approval = tmp / "approval"
    approval.write_text("app-minted-token\n", encoding="utf-8")
    install = tmp / "install-id"
    env = os.environ.copy()
    env["PROMETH_COMPOSIO_ENV"] = str(tmp / "composio.env")
    env["COMPOSIO_API_KEY"] = ""
    env["PROMETH_COMPOSIO_API_BASE"] = f"http://127.0.0.1:{port}/api/v3.1"
    (tmp / "composio.env").write_text(f"COMPOSIO_API_KEY={key}\n", encoding="utf-8")
    os.chmod(tmp / "composio.env", 0o600)
    params = StdioServerParameters(
        command=os.environ["PROMETH_MCP_PYTHON"],
        args=[
            str(SERVER),
            "--approval-file",
            str(approval),
            "--install-file",
            str(install),
        ],
        env=env,
    )
    async with stdio_client(params) as streams:
        async with ClientSession(streams[0], streams[1]) as session:
            await session.initialize()
            search = json.loads(tool_text(await session.call_tool("connectors_search", {"query": "github repos"})))
            assert search["ok"] is True
            assert "GITHUB_LIST_REPOS" in search["tools"]
            refused = json.loads(tool_text(await session.call_tool(
                "connectors_execute",
                {"tool": "GITHUB_LIST_REPOS", "arguments_json": "{}", "approval_token": "true"},
            )))
            assert refused["executed"] is False
            assert api.execute == 0
            approved = json.loads(tool_text(await session.call_tool(
                "connectors_execute",
                {
                    "tool": "GITHUB_LIST_REPOS",
                    "arguments_json": "{}",
                    "approval_token": "app-minted-token",
                },
            )))
            assert approved["executed"] is True
            assert approved["ok"] is True
            assert api.execute == 1
            assert api.saw_key is True
    log = tmp / "direct-log"
    log.write_text(json.dumps({"approved_executed": approved["executed"]}), encoding="utf-8")
    assert key not in log.read_text(encoding="utf-8")


def status_mapping_checks() -> None:
    import server as composio_server

    original = composio_server.composio_request

    def fake(_method, _path, _api_key, body=None, query=None):
        items = fake.items  # type: ignore[attr-defined]
        return {"ok": True, "items": items}

    fake.items = [{"id": "acct-1", "status": "INITIATED"}]
    composio_server.composio_request = fake  # type: ignore[assignment]
    try:
        pending = composio_server.connection_status("github", "user-1", "key")
        assert pending["status"] == "pending", pending
        fake.items = [{"id": "acct-2", "status": "ACTIVE"}]
        connected = composio_server.connection_status("gmail", "user-1", "key")
        assert connected["status"] == "connected", connected
        fake.items = [{"id": "acct-3", "status": "EXPIRED"}]
        expired = composio_server.connection_status("googledrive", "user-1", "key")
        assert expired["status"] == "expired", expired
    finally:
        composio_server.composio_request = original


def main() -> None:
    key = "test-key-" + uuid.uuid4().hex
    tmp = Path("/tmp/prometh-composio-test")
    if tmp.exists():
        import shutil
        shutil.rmtree(tmp)
    tmp.mkdir()
    status_mapping_checks()
    broker = Broker()
    broker.expected_key = key
    port = broker.serve()
    anyio.run(session_checks, tmp, broker, port, key)
    direct = DirectAPI()
    direct.expected_key = key
    direct_port = direct.serve()
    direct_tmp = tmp / "direct"
    direct_tmp.mkdir()
    anyio.run(direct_checks, direct_tmp, direct, direct_port, key)
    print(json.dumps({"passed": True, "tests": 3, "mcp": "2.3.0", "executeWithoutApproval": 0}))


if __name__ == "__main__":
    import os
    main()
