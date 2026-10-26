"""Evil Mode supervisor tests. They never download the GGUF."""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import textwrap
import time
import urllib.error
import urllib.request
from pathlib import Path

import llama_supervisor

ROOT = Path(__file__).resolve().parent
GIBIBYTE = 1024**3


def test_memory_policy() -> None:
    assert llama_supervisor.must_unload_other(16 * GIBIBYTE)
    assert llama_supervisor.must_unload_other(8 * GIBIBYTE)
    assert llama_supervisor.must_unload_other(0)
    assert llama_supervisor.must_unload_other(16 * GIBIBYTE + 1) is False


def test_arguments_are_the_prd_command() -> None:
    args = llama_supervisor.build_arguments(
        executable="/opt/llama-server",
        model="/models/qwen.gguf",
        port=27123,
        api_key="local-secret",
    )
    assert args == [
        "/opt/llama-server",
        "--host",
        "127.0.0.1",
        "--port",
        "27123",
        "--model",
        "/models/qwen.gguf",
        "--alias",
        "evil",
        "--ctx-size",
        "8192",
        "--parallel",
        "1",
        "--jinja",
        "--reasoning",
        "off",
        "--api-key",
        "local-secret",
    ]
    try:
        llama_supervisor.build_arguments(
            executable="llama-server",
            model="m.gguf",
            port=1,
            api_key="k",
            host="0.0.0.0",
        )
    except ValueError:
        return
    raise AssertionError("non-loopback bind was accepted")


def test_idle_uses_the_injected_clock() -> None:
    clock = {"now": 100.0}

    def read() -> float:
        return clock["now"]

    class Alive:
        def poll(self):
            return None

        def terminate(self):
            return None

        def wait(self, timeout=0):
            return 0

        def kill(self):
            return None

    def popen(*_args, **_kwargs):
        return Alive()

    supervisor = llama_supervisor.Supervisor(
        executable="llama-server",
        model="m.gguf",
        api_key="k",
        parent_pid=os.getpid(),
        support=Path("/tmp/prometh-llama-idle"),
        port=9,
        idle_seconds=600,
        popen=popen,
        clock=read,
    )
    supervisor.start()
    clock["now"] = 699
    assert supervisor.idle_due() is False
    clock["now"] = 700
    assert supervisor.idle_due() is True
    supervisor.stop()


def test_tool_round_trip_and_parent_death(tmp: Path) -> None:
    mock = tmp / "llama-server"
    mock.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env python3
            import json, sys
            from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

            args = sys.argv
            port = int(args[args.index("--port") + 1])
            key = args[args.index("--api-key") + 1]
            host = args[args.index("--host") + 1]
            if host != "127.0.0.1":
                sys.exit(2)

            class Handler(BaseHTTPRequestHandler):
                def log_message(self, fmt, *a):
                    return

                def do_POST(self):
                    if self.headers.get("Authorization") != f"Bearer {key}":
                        self.send_response(401)
                        self.end_headers()
                        return
                    length = int(self.headers.get("Content-Length", "0"))
                    body = json.loads(self.rfile.read(length) or b"{}")
                    messages = body.get("messages") or []
                    if any(item.get("role") == "tool" for item in messages):
                        message = {"role": "assistant", "content": "It is 22 C in Buenos Aires. [1]"}
                    else:
                        message = {
                            "role": "assistant",
                            "content": "",
                            "tool_calls": [{
                                "id": "call_1",
                                "type": "function",
                                "function": {
                                    "name": "web_search",
                                    "arguments": "{\\"query\\":\\"weather Buenos Aires\\"}",
                                },
                            }],
                        }
                    payload = {
                        "id": "chatcmpl-test",
                        "choices": [{"index": 0, "message": message, "finish_reason": "tool_calls"}],
                    }
                    raw = json.dumps(payload).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(raw)))
                    self.end_headers()
                    self.wfile.write(raw)

            ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
            """
        ),
        encoding="utf-8",
    )
    mock.chmod(0o755)
    parent = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    support = tmp / "support"
    secret = "round-trip-secret"
    supervisor = llama_supervisor.Supervisor(
        executable=str(mock),
        model=str(tmp / "Qwen3.5-9B-heretic-v2-Q4_K_M.gguf"),
        api_key=secret,
        parent_pid=parent.pid,
        support=support,
        idle_seconds=600,
    )
    try:
        supervisor.start()
        endpoint = json.loads((support / "endpoint.json").read_text(encoding="utf-8"))
        assert endpoint["host"] == "127.0.0.1"
        assert endpoint["alias"] == "evil"
        assert endpoint["apiKey"] == secret
        assert oct((support / "endpoint.json").stat().st_mode & 0o777) == "0o600"
        assert listeners(supervisor.port) == ["127.0.0.1"]
        first = post_chat(supervisor.port, secret, [{"role": "user", "content": "weather"}])
        tool_calls = first["choices"][0]["message"]["tool_calls"]
        assert tool_calls[0]["function"]["name"] == "web_search"
        second = post_chat(
            supervisor.port,
            secret,
            [
                {"role": "user", "content": "weather"},
                first["choices"][0]["message"],
                {"role": "tool", "tool_call_id": "call_1", "content": "22 C"},
            ],
        )
        assert "[1]" in second["choices"][0]["message"]["content"]
        refused = urllib.request.Request(
            f"http://127.0.0.1:{supervisor.port}/v1/chat/completions",
            data=b"{}",
            method="POST",
        )
        try:
            urllib.request.urlopen(refused, timeout=2)
        except urllib.error.HTTPError as error:
            assert error.code == 401
        else:
            raise AssertionError("missing api key was accepted")
        os.kill(parent.pid, signal.SIGKILL)
        parent.wait(timeout=2)
        deadline = time.time() + 3
        while time.time() < deadline:
            if supervisor.process is None or supervisor.process.poll() is not None:
                return
            time.sleep(0.1)
        raise AssertionError("llama child survived its parent")
    finally:
        supervisor.stop()
        if parent.poll() is None:
            parent.kill()


def post_chat(port: int, secret: str, messages: list) -> dict:
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps({"model": "evil", "messages": messages}).encode(),
        headers={"Authorization": f"Bearer {secret}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        return json.loads(response.read().decode())


def listeners(port: int) -> list[str]:
    found = []
    needle = f":{port:04X}"
    for path in (Path("/proc/net/tcp"), Path("/proc/net/tcp6")):
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").splitlines()[1:]:
            parts = line.split()
            if len(parts) < 4 or parts[3] != "0A":
                continue
            local = parts[1]
            if not local.endswith(needle):
                continue
            address = local.split(":")[0]
            if address in {"0100007F", "00000000000000000000000001000000"}:
                found.append("127.0.0.1")
            else:
                found.append(address)
    return found


def main() -> None:
    tmp = Path("/tmp/prometh-llama-test")
    if tmp.exists():
        subprocess.run(["rm", "-rf", str(tmp)], check=True)
    tmp.mkdir()
    test_memory_policy()
    test_arguments_are_the_prd_command()
    test_idle_uses_the_injected_clock()
    test_tool_round_trip_and_parent_death(tmp)
    print(json.dumps({"passed": True, "tests": 4, "llamaCpp": llama_supervisor.LLAMA_CPP_REF}))


if __name__ == "__main__":
    main()
