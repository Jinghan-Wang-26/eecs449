"""No subprocesses or network calls in these transport regression tests."""
import json
import unittest
from unittest.mock import patch
from pathlib import Path
from ai import codex_local
from ai.intents import complete_json, parse_request
from integrations.providers import ProviderError


class CodexTransportTests(unittest.TestCase):
    def test_codex_is_opt_in_and_unknown_backend_rejected(self):
        with patch("ai.intents.credentials", return_value={}):
            with self.assertRaisesRegex(ProviderError, "LLM_API_KEY"):
                parse_request("buy rice")
        with patch("ai.intents.credentials", return_value={"LLM_BACKEND": "bad"}):
            with self.assertRaises(ProviderError): complete_json([])
        with patch("ai.intents.credentials", return_value={"LLM_BACKEND": "codex"}), patch("ai.codex_local.codex_json", return_value={"intent": "update", "needs": [{"category": "rice", "qty": 2}]}):
            self.assertEqual(parse_request("two rice")["needs"][0]["qty"], 2)

    def test_missing_cli_is_actionable(self):
        with patch("ai.codex_local.shutil.which", return_value=None):
            with self.assertRaisesRegex(ProviderError, "not installed"): codex_local.codex_json([])

    def test_no_shell_keys_or_project_context_forwarded(self):
        class FakeProcess:
            returncode = 0
            def __init__(self, args, **kwargs):
                self.args, self.kwargs = args, kwargs
                Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps({"json": '{"intent":"explain"}'}))
            def communicate(self, prompt, timeout):
                return None, None
        with patch("ai.codex_local.shutil.which", return_value="/usr/bin/codex"), patch.dict("os.environ", {"LLM_API_KEY": "test-secret", "CODEX_API_KEY": "test-secret", "GEOAPIFY_API_KEY": "test-secret"}), patch("ai.codex_local.subprocess.Popen", side_effect=FakeProcess) as run:
            self.assertEqual(codex_local.codex_json([]), {"intent": "explain"})
            args = run.call_args.args[0]
            env = run.call_args.kwargs["env"]
            self.assertNotIn("test-secret", env.values())
            self.assertIn("--ignore-user-config", args)
            self.assertIn("--ephemeral", args)
            self.assertEqual(args[args.index("--sandbox") + 1], "read-only")
            self.assertNotIn("shell", run.call_args.kwargs)
            for feature in ("shell_tool", "apps", "multi_agent", "hooks", "remote_plugin"):
                index = args.index(feature)
                self.assertEqual(args[index - 1], "--disable")

    def test_invalid_api_envelopes_fail_closed(self):
        for value in ({}, {"choices": []}, {"choices": [{"message": {"content": "[]"}}]}, {"choices": [{"message": {"content": "invalid"}}]}):
            with patch("ai.intents.credentials", return_value={"LLM_API_KEY": "test"}), patch("ai.intents.request_json", return_value=value):
                with self.assertRaises(ProviderError): parse_request("buy rice")
