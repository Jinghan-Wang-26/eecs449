"""Read-only cloud deployment probe; never submits a plan or invokes the LLM."""
import argparse
import json
import urllib.error
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url', help='HTTPS service URL, or loopback HTTP for local rehearsal')
    args = parser.parse_args()
    base = args.url.rstrip('/')
    parsed = urllib.parse.urlsplit(base)
    if (parsed.username or parsed.password or parsed.query or parsed.fragment
        or parsed.path or not parsed.hostname
        or not (parsed.scheme == 'https' or
                parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1', '::1'))):
        parser.error('Use a bare HTTPS service URL (HTTP is allowed only for loopback).')
    # Keep probes on the requested origin.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    opener = urllib.request.build_opener(NoRedirect())

    def request(path, body=None):
        headers = {}
        if body is not None:
            headers['Content-Type'] = 'application/json'
        req = urllib.request.Request(base + path, headers=headers,
                                     data=None if body is None else json.dumps(body).encode())
        try:
            with opener.open(req, timeout=30) as response:
                return response.status, response.read(2_000_000)
        except urllib.error.HTTPError as exc:
            return exc.code, b''

    checks = {}
    try:
        checks['health'] = request('/healthz')[0] == 200
        code, page = request('/')
        checks['public_page'] = code == 200 and b'<html' in page.lower()
        code, payload = request('/walker/ChatHistory', body={})
        history = json.loads(payload) if code == 200 else {}
        checks['public_history'] = code == 200 and history.get('ok') is True and isinstance(history.get('data', {}).get('reports'), list)
    except (OSError, ValueError):
        print('Deployment probe failed to connect or received an invalid response. No credentials were printed.')
        return 1
    print(json.dumps(checks, indent=2))
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
