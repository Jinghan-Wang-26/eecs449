"""Report configuration flags, never credential values; no network requests."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from integrations.providers import credential_status, credentials
backend = credentials().get("LLM_BACKEND", "api")
print("LLM backend: " + backend)
if backend == "codex":
    print("Local Codex mode: uses saved CLI login; LLM_API_KEY is not required.")
for name,present in credential_status().items():
    print(f'{name}: {"configured" if present else "not configured"}')
print('Open Prices: no API key required for public reads')
