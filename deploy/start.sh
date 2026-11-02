#!/bin/bash
set -euo pipefail

# A dedicated Render disk stores both user identities and shopping graph data.
# The root entry step only prepares its mount; both services run as uid 10001.
if [[ "$(id -u)" == 0 ]]; then
    install -d -o cartcompass -g cartcompass "${JAC_DATA_PATH:-/var/data}/.jac/data"
    exec gosu cartcompass "$0" "$@"
fi

export PORT="${PORT:-10000}"
if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65535 || PORT == 8081 )); then
    echo 'PORT must be between 1024 and 65535, excluding the internal port 8081.' >&2
    exit 1
fi
if [[ "${LLM_BACKEND:-api}" != api ]]; then
    echo 'Cloud deployment requires LLM_BACKEND=api; the local Codex login is not included.' >&2
    exit 1
fi
# Public shared demo: no website password is required.
jac_pid=''
proxy_pid=''
cleanup() {
    trap - EXIT TERM INT
    if [[ -n "$proxy_pid" ]]; then kill "$proxy_pid" 2>/dev/null || true; fi
    if [[ -n "$jac_pid" ]]; then kill "$jac_pid" 2>/dev/null || true; fi
    wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT

jac start main.jac --port 8081 &
jac_pid=$!
# Do not expose a healthy public listener until the backend can serve the app.
python - <<'PY'
import time
import urllib.error
import urllib.request
for attempt in range(120):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8081/', timeout=2) as response:
            if response.status == 200:
                break
    except (OSError, urllib.error.URLError):
        pass
    time.sleep(1)
else:
    raise SystemExit('Jac did not become ready; check the startup log.')
PY
caddy run --config /app/deploy/Caddyfile --adapter caddyfile &
proxy_pid=$!
# Stop the other service if either child exits, so the platform can restart us.
set +e
wait -n "$jac_pid" "$proxy_pid"
status=$?
set -e
exit "$status"
