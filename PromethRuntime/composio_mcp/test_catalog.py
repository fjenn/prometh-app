"""Catalog pagination, errors, dynamic slugs and account joining. No live credentials."""
import unittest
from unittest.mock import patch
import server


class CatalogTests(unittest.TestCase):
    def test_all_pages_and_custom_toolkit_slugs(self):
        pages = [
            {"ok": True, "items": [{"slug": "github"}], "next_cursor": "page2"},
            {"ok": True, "items": [{"slug": "custom_crm"}], "next_cursor": None},
        ]
        with patch.object(server, "composio_request", side_effect=pages) as call:
            result = server.toolkit_catalog("test-user", "test-key")
        self.assertEqual([item["slug"] for item in result["items"]], ["github", "custom_crm"])
        self.assertEqual(call.call_args_list[1].kwargs["query"]["cursor"], "page2")
        self.assertEqual(call.call_args_list[0].kwargs["query"]["type"], "all")
        for slug in ("slack", "linear", "custom_crm", "my-tool"):
            self.assertEqual(server.toolkit_slug(slug), slug)
        self.assertEqual(server.toolkit_slug("Google Drive"), "googledrive")
        self.assertEqual(server.toolkit_slug("../bad"), "")

    def test_repository_discovery_includes_schema_even_when_model_omits_app_name(self):
        tool = {"slug": "GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER", "input_parameters": {"type": "object", "properties": {"per_page": {"type": "integer"}}}}
        with patch.object(server, "composio_request", side_effect=[{"items": []}, {"items": [tool]}]):
            result = server.composio_search("list repositories authenticated user", "test-user", "test-key")
        self.assertEqual(result["tools"][0], tool["slug"])
        self.assertEqual(result["items"][0]["input_parameters"], tool["input_parameters"])

    def test_search_summaries_carry_composio_tags_for_read_write_classification(self):
        read = {"slug": "GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER", "tags": ["openWorldHint", "readOnlyHint", 7]}
        write = {"slug": "GITHUB_CREATE_AN_ISSUE", "tags": ["important", "createHint"]}
        with patch.object(server, "composio_request", side_effect=[{"items": [write, read]}]):
            result = server.composio_search("github list my repos and create issue", "test-user", "test-key")
        tags = {item["slug"]: item["tags"] for item in result["items"]}
        self.assertEqual(tags[read["slug"]], ["openWorldHint", "readOnlyHint"])
        self.assertEqual(tags[write["slug"]], ["important", "createHint"])
        self.assertEqual(result["tools"][0], read["slug"])

    def test_partial_failure_does_not_overwrite_cache_with_partial_catalog(self):
        pages = [{"ok": True, "items": [{"slug": "github"}], "next_cursor": "page2"},
                 {"ok": False, "error": "composio status 503"}]
        with patch.object(server, "composio_request", side_effect=pages):
            result = server.toolkit_catalog("test-user", "test-key")
        self.assertFalse(result["ok"])
        self.assertNotIn("items", result)
        self.assertEqual(result["error"], "composio status 503")

    def test_repeated_cursor_and_malformed_response_are_visible_errors(self):
        with patch.object(server, "composio_request", return_value={"ok": True, "items": [], "next_cursor": "same"}):
            self.assertFalse(server.toolkit_catalog("test-user", "test-key")["ok"])
        with patch.object(server, "composio_request", return_value={"ok": True}):
            self.assertFalse(server.toolkit_catalog("test-user", "test-key")["ok"])

    def test_status_join_prefers_active_account_and_paginates(self):
        pages = [{"ok": True, "items": [
            {"toolkit": {"slug": "github"}, "status": "ACTIVE"},
            {"toolkit": {"slug": "slack"}, "status": "INITIATED"}], "next_cursor": "next"},
            {"ok": True, "items": [{"toolkit": {"slug": "github"}, "status": "EXPIRED"}]}]
        with patch.object(server, "composio_request", side_effect=pages) as call:
            result = server.all_connection_statuses("test-user", "test-key")
        self.assertEqual(result["statuses"], {"github": "connected", "slack": "pending"})
        self.assertEqual(call.call_args_list[0].kwargs["query"]["user_ids"], "test-user")


if __name__ == "__main__":
    unittest.main()
