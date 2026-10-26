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


def main() -> None:
    key = "test-key-" + uuid.uuid4().hex
    tmp = Path("/tmp/prometh-composio-test")
    if tmp.exists():
        import shutil
        shutil.rmtree(tmp)
    tmp.mkdir()
    broker = Broker()
    broker.expected_key = key
    port = broker.serve()
    anyio.run(session_checks, tmp, broker, port, key)
    print(json.dumps({"passed": True, "tests": 1, "mcp": "2.3.0", "executeWithoutApproval": 0}))


if __name__ == "__main__":
    import os
    main()
