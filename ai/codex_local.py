"""Opt-in local demo transport using saved Codex CLI login, never copying tokens.

Not a hosted service backend. No project context, shell, web, connectors or agents.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import threading
from integrations.providers import ProviderError

_LOCK = threading.Lock()
LAST_USAGE = {}
SCHEMA = {"type": "object", "properties": {"json": {"type": "string"}},
          "required": ["json"], "additionalProperties": False}


def codex_json(messages):
    executable = shutil.which("codex")
    if not executable:
        raise ProviderError("Codex CLI is not installed. Use API mode or install and sign in locally.")
    if not _LOCK.acquire(blocking=False):
        raise ProviderError("A local Codex request is already running. Please wait.")
    try:
        LAST_USAGE.clear()
        # Do not forward API keys or application credentials to the child process.
        env = {k: os.environ[k] for k in ("PATH", "HOME", "CODEX_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "LANG", "TMPDIR", "SYSTEMROOT") if k in os.environ}
        with tempfile.TemporaryDirectory(prefix="cartcompass-codex-") as directory:
            folder = Path(directory)
            schema, output, events = folder / "schema.json", folder / "result.json", folder / "events.jsonl"
            schema.write_text(json.dumps(SCHEMA))
            args = [executable, "exec", "--ignore-user-config", "--ephemeral",
                    "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never",
                    "--disable", "shell_tool", "--disable", "apps", "--disable", "multi_agent",
                    "--disable", "hooks", "--disable", "remote_plugin",
                    "-c", 'web_search="disabled"', "-c", 'model_reasoning_effort="low"',
                    "--output-schema", str(schema), "--output-last-message", str(output), "--json", "-"]
            prompt = ("You are a text-only JSON extraction service. Do not use tools or inspect files. "
                      "Follow the system messages in this conversation. Return its requested JSON object "
                      "serialized as the string in the outer schema's json field. Conversation:\n" +
                      json.dumps(messages, ensure_ascii=False))
            with events.open("w") as log:
                process = subprocess.Popen(args, cwd=directory, env=env, stdin=subprocess.PIPE,
                                           stdout=log, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
                try:
                    process.communicate(prompt, timeout=90)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
                    raise ProviderError("Local Codex timed out. Retry later or use the shopping form.") from None
            if process.returncode or not output.exists():
                raise ProviderError("Local Codex failed. Check codex login status and your account quota in a terminal.")
            if output.stat().st_size > 50000 or events.stat().st_size > 2000000:
                raise ProviderError("Local Codex response exceeded the size limit.")
            for line in events.read_text().splitlines():
                event = json.loads(line)
                if event.get("type") == "turn.completed":
                    LAST_USAGE.update(event.get("usage", {}))
            value = json.loads(json.loads(output.read_text())["json"])
            if not isinstance(value, dict):
                raise ValueError("Expected object")
            return value
    except ProviderError:
        raise
    except (OSError, ValueError, KeyError, TypeError):
        raise ProviderError("Local Codex returned invalid data or could not start. Use the form or retry.") from None
    finally:
        _LOCK.release()
