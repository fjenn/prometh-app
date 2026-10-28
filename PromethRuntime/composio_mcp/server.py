"""stdio MCP server for Prometh connectors.

The Composio API key is read at call time from COMPOSIO_API_KEY or
~/.config/prometh/composio.env. It is never printed, logged, or returned.
Execute calls are refused unless the app adds an approval token after the
user agrees. With no broker URL, search and execute call Composio's API.
"""

from __future__ import annotations

import argparse
import hmac
import json
import logging
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

from mcp.server.mcpserver import MCPServer

logging.disable(logging.INFO)
for _logger_name in ("httpx", "httpcore", "mcp", "urllib3"):
    logging.getLogger(_logger_name).setLevel(logging.CRITICAL)

COMPOSIO_API = "https://backend.composio.dev/api/v3.1"
TOOLKITS = {
    "gmail": "gmail",
    "outlook": "outlook",
    "google drive": "googledrive",
    "googledrive": "googledrive",
    "github": "github",
}


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


def redact(text: str, secret: str) -> str:
    if secret and secret in text:
        return text.replace(secret, "[redacted]")
    return text


def api_base() -> str:
    override = os.environ.get("PROMETH_COMPOSIO_API_BASE", "").strip()
    return (override or COMPOSIO_API).rstrip("/")


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


def composio_request(
    method: str,
    path: str,
    api_key: str,
    payload: dict | None = None,
    query: dict | None = None,
) -> dict:
    if not api_key:
        return {"ok": False, "error": "Connectors are not configured."}
    url = api_base() + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("x-api-key", api_key)
    if payload is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode()
    except urllib.error.HTTPError as error:
        detail = redact(error.read().decode(errors="replace"), api_key)[:400]
        return {"ok": False, "error": f"composio status {error.code}", "detail": detail}
    except urllib.error.URLError:
        return {"ok": False, "error": "composio unreachable"}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return {"ok": False, "error": "composio returned an unreadable response"}
    if not isinstance(parsed, dict):
        return {"ok": True, "data": parsed}
    if "ok" not in parsed:
        parsed["ok"] = parsed.get("error") in (None, "")
    return parsed


def toolkit_from_query(query_text: str) -> str:
    lowered = query_text.lower()
    for name in ("google drive", "gmail", "outlook", "github"):
        if name in lowered:
            return TOOLKITS[name]
    return ""


def composio_search(query_text: str, user_id: str, api_key: str, toolkit_hint: str = "") -> dict:
    query = {"query": query_text, "limit": "8", "toolkit_versions": "latest"}
    toolkit = toolkit_slug(toolkit_hint) if toolkit_hint else toolkit_from_query(query_text)
    if toolkit:
        query["toolkit_slug"] = toolkit
    result = composio_request(
        "GET",
        "/tools",
        api_key,
        query=query,
    )
    items = result.get("items") if isinstance(result.get("items"), list) else []
    if result.get("ok") is False and not items:
        return result
    tools: list[str] = []
    summaries: list[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        slug = item.get("slug")
        if not isinstance(slug, str) or not slug:
            continue
        tools.append(slug)
        description = item.get("description") if isinstance(item.get("description"), str) else ""
        summaries.append({"slug": slug, "description": description, "input_parameters": item.get("input_parameters", {})})
    tools, summaries = pin_known_tool(query_text, toolkit, tools, summaries, api_key)
    return {"ok": True, "tools": tools, "items": summaries, "user_id": user_id}


def pin_known_tool(
    query_text: str,
    toolkit: str,
    tools: list[str],
    summaries: list[dict],
    api_key: str,
) -> tuple[list[str], list[dict]]:
    """Surface the authenticated-user repo list when that is what was asked."""
    lowered = query_text.lower()
    if toolkit not in ("", "github"):
        return tools, summaries
    asks_for_repos = any(word in lowered for word in ("repo", "repos", "repositor"))
    asks_to_list = any(word in lowered for word in ("list", "my", "show", "what"))
    if not asks_for_repos or not asks_to_list:
        return tools, summaries
    preferred = "GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER"
    if preferred not in tools:
        pinned = composio_request(
            "GET",
            "/tools",
            api_key,
            query={"tool_slugs": preferred, "toolkit_versions": "latest"},
        )
        found = pinned.get("items") if isinstance(pinned.get("items"), list) else []
        if not any(isinstance(item, dict) and item.get("slug") == preferred for item in found):
            return tools, summaries
        tools = [preferred, *tools]
        summaries = [
            {"slug": preferred, "description": "List repositories for the authenticated user", "input_parameters": next(item.get("input_parameters", {}) for item in found if item.get("slug") == preferred)},
            *summaries,
        ]
    else:
        tools = [preferred, *[item for item in tools if item != preferred]]
    return tools[:8], summaries[:8]


def composio_execute(tool: str, arguments: dict, user_id: str, api_key: str) -> dict:
    if not tool or any(mark in tool for mark in ("/", "?", "#", " ")):
        return {"ok": False, "error": "unknown tool", "executed": False}
    result = composio_request(
        "POST",
        "/tools/execute/" + urllib.parse.quote(tool),
        api_key,
        {"user_id": user_id, "arguments": arguments, "version": "latest"},
    )
    failed = result.get("successful") is False or result.get("ok") is False
    result["ok"] = not failed
    result["executed"] = True
    return result


def toolkit_slug(name: str) -> str:
    value = name.strip().lower()
    slug = TOOLKITS.get(value, value)
    return slug if slug and all(c.isascii() and (c.isalnum() or c in "_-") for c in slug) else ""


def ensure_auth_config(toolkit: str, api_key: str) -> dict:
    listed = composio_request(
        "GET",
        "/auth_configs",
        api_key,
        query={"toolkit_slug": toolkit, "limit": "20"},
    )
    items = listed.get("items") if isinstance(listed.get("items"), list) else []
    for item in items:
        if not isinstance(item, dict) or not item.get("id"):
            continue
        toolkit_info = item.get("toolkit")
        slug = toolkit_info.get("slug") if isinstance(toolkit_info, dict) else None
        if slug in (None, toolkit):
            return {"ok": True, "auth_config_id": item["id"]}
    created = composio_request(
        "POST",
        "/auth_configs",
        api_key,
        {
            "toolkit": {"slug": toolkit},
            "auth_config": {"type": "use_composio_managed_auth", "credentials": {}},
        },
    )
    config = created.get("auth_config")
    config_id = config.get("id") if isinstance(config, dict) else None
    if not config_id:
        return {"ok": False, "error": created.get("error") or "Could not prepare the connection."}
    return {"ok": True, "auth_config_id": config_id}


def create_link(toolkit: str, user_id: str, api_key: str) -> dict:
    if not toolkit:
        return {"ok": False, "error": "Unknown app."}
    prepared = ensure_auth_config(toolkit, api_key)
    if not prepared.get("ok"):
        return prepared
    linked = composio_request(
        "POST",
        "/connected_accounts/link",
        api_key,
        {"auth_config_id": prepared["auth_config_id"], "user_id": user_id},
    )
    url = linked.get("redirect_url")
    if not isinstance(url, str) or not url:
        return {"ok": False, "error": linked.get("error") or "The authorization page was not returned."}
    return {
        "ok": True,
        "redirect_url": url,
        "connected_account_id": linked.get("connected_account_id"),
    }


def connection_status(toolkit: str, user_id: str, api_key: str) -> dict:
    if not toolkit:
        return {"ok": False, "error": "Unknown app.", "status": "disconnected"}
    listed = composio_request(
        "GET",
        "/connected_accounts",
        api_key,
        query={"toolkit_slugs": toolkit, "user_ids": user_id, "limit": "20"},
    )
    items = listed.get("items") if isinstance(listed.get("items"), list) else []
    if listed.get("ok") is False and not items:
        listed["status"] = "disconnected"
        return listed
    status = "disconnected"
    account_id = None
    for item in items:
        if not isinstance(item, dict):
            continue
        current = str(item.get("status") or "").upper()
        account_id = item.get("id") or account_id
        if current == "ACTIVE":
            return {"ok": True, "status": "connected", "connected_account_id": item.get("id")}
        if current in {"EXPIRED", "FAILED"}:
            status = "expired"
            account_id = item.get("id")
        elif current in {"INITIATED", "INITIALIZING", "PENDING", "PENDING_AUTH"} and status != "expired":
            # OAuth started but the owner has not finished sign-in yet.
            status = "pending"
            account_id = item.get("id") or account_id
    return {"ok": True, "status": status, "connected_account_id": account_id}


def disconnect_account(toolkit: str, user_id: str, api_key: str) -> dict:
    current = connection_status(toolkit, user_id, api_key)
    account = current.get("connected_account_id")
    if not isinstance(account, str) or not account:
        return {"ok": True, "status": "disconnected"}
    deleted = composio_request(
        "DELETE",
        "/connected_accounts/" + urllib.parse.quote(account),
        api_key,
    )
    if deleted.get("ok") is False:
        return deleted
    return {"ok": True, "status": "disconnected"}


def paginated_items(path: str, api_key: str, query: dict) -> list[dict]:
    items: list[dict] = []
    seen: set[str] = set()
    while True:
        result = composio_request("GET", path, api_key, query=query)
        if result.get("ok") is False:
            raise ValueError(result.get("error") or "Could not load the catalog.")
        page = result.get("items")
        if not isinstance(page, list):
            raise ValueError("The connection service returned an invalid catalog.")
        items.extend(item for item in page if isinstance(item, dict))
        cursor = result.get("next_cursor")
        if not cursor:
            return items
        if not isinstance(cursor, str) or cursor in seen:
            raise ValueError("The connection service repeated a catalog page.")
        seen.add(cursor)
        query = {**query, "cursor": cursor}


def toolkit_catalog(user_id: str, api_key: str) -> dict:
    try:
        items = paginated_items("/toolkits", api_key, {"limit": "1000", "type": "all", "sort_by": "alphabetically", "user_id": user_id})
        return {"ok": True, "items": items}
    except ValueError as error:
        return {"ok": False, "error": str(error)}


def all_connection_statuses(user_id: str, api_key: str) -> dict:
    try:
        items = paginated_items("/connected_accounts", api_key, {"user_ids": user_id, "limit": "100"})
    except ValueError as error:
        return {"ok": False, "error": str(error)}
    statuses: dict[str, str] = {}
    rank = {"disconnected": 0, "pending": 1, "expired": 2, "connected": 3}
    for item in items:
        toolkit = item.get("toolkit") or {}
        slug = toolkit.get("slug") if isinstance(toolkit, dict) else None
        if not slug:
            continue
        raw = str(item.get("status") or "").upper()
        status = "connected" if raw == "ACTIVE" else "expired" if raw in {"EXPIRED", "FAILED"} else "pending" if raw in {"INITIATED", "INITIALIZING", "PENDING", "PENDING_AUTH"} else "disconnected"
        if rank[status] >= rank.get(statuses.get(slug, "disconnected"), 0):
            statuses[slug] = status
    return {"ok": True, "statuses": statuses}


def public_payload(payload: dict, api_key: str) -> str:
    text = json.dumps(payload)
    return redact(text, api_key)


def build_server(approval_file: Path, broker: str, install_file: Path) -> MCPServer:
    server = MCPServer("prometh-composio")
    user_id = install_id(install_file)

    @server.tool(name="connectors_search", description="Find actions in a connected app. Include the app name in query or its toolkit slug (for example github). Returns action input schemas; use those fields in connectors_execute arguments_json.")
    def connectors_search(query: str, toolkit: str = "") -> str:
        api_key = load_api_key()
        if broker:
            result = broker_request(
                broker,
                "/tools/search",
                {"query": query, "user_id": user_id},
                api_key,
            )
        else:
            result = composio_search(query, user_id, api_key, toolkit)
        return public_payload(result, api_key)

    @server.tool(
        name="connectors_execute",
        description=(
            "Run one connected-app action. Leave approval_token empty. "
            "Prometh fills it only after the user approves."
        ),
    )
    def connectors_execute(tool: str, arguments_json: str = "{}", approval_token: str = "") -> str:
        api_key = load_api_key()
        if not tokens_match(approval_token, read_token(approval_file)):
            return public_payload(
                {"ok": False, "error": "approval required", "executed": False},
                api_key,
            )
        try:
            arguments = json.loads(arguments_json) if arguments_json else {}
        except json.JSONDecodeError:
            return public_payload({"ok": False, "error": "arguments_json must be a JSON object, without extra escaping.", "executed": False}, api_key)
        if not isinstance(arguments, dict):
            return public_payload({"ok": False, "error": "arguments_json must be a JSON object.", "executed": False}, api_key)
        if broker:
            result = broker_request(
                broker,
                "/tools/execute",
                {"user_id": user_id, "tool": tool, "arguments": arguments},
                api_key,
            )
            result["executed"] = True
        else:
            result = composio_execute(tool, arguments, user_id, api_key)
        return public_payload(result, api_key)

    return server


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--approval-file", default="")
    parser.add_argument("--broker", default="")
    parser.add_argument("--install-file", required=True)
    parser.add_argument("--catalog", action="store_true")
    parser.add_argument("--connections", action="store_true")
    parser.add_argument("--link", default="")
    parser.add_argument("--status", default="")
    parser.add_argument("--disconnect", default="")
    args = parser.parse_args()
    user_id = install_id(Path(args.install_file))
    api_key = load_api_key()
    if args.catalog or args.connections:
        payload = toolkit_catalog(user_id, api_key) if args.catalog else all_connection_statuses(user_id, api_key)
        sys.stdout.write(public_payload(payload, api_key) + "\n")
        return
    if args.link or args.status or args.disconnect:
        name = args.link or args.status or args.disconnect
        toolkit = toolkit_slug(name)
        if args.link:
            payload = create_link(toolkit, user_id, api_key)
        elif args.disconnect:
            payload = disconnect_account(toolkit, user_id, api_key)
        else:
            payload = connection_status(toolkit, user_id, api_key)
        sys.stdout.write(public_payload(payload, api_key) + "\n")
        return
    if not args.approval_file:
        raise SystemExit("approval file is required")
    build_server(Path(args.approval_file), args.broker, Path(args.install_file)).run(transport="stdio")


if __name__ == "__main__":
    main()
