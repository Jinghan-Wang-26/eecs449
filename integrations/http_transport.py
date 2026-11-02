"""Scoped HTTP transport for provider calls on partially connected dual-stack hosts.

Prefer IPv4 without changing process-wide DNS/socket behavior. Keep urllib's
proxy/redirect handling and HTTPS certificate/hostname verification intact.
"""
import http.client
import socket
import time
import urllib.request


def connect(address, timeout=12, source_address=None):
    """Bound TCP attempts across resolved addresses; fall back to IPv6 if needed.

    DNS resolution and response reads retain the platform/library behavior. The
    budget here covers TCP connection attempts, not an entire planning request.
    """
    host, port = address
    addresses = socket.getaddrinfo(host, port, 0, socket.SOCK_STREAM)
    addresses.sort(key=lambda item: item[0] != socket.AF_INET)
    budget = 12 if timeout is socket._GLOBAL_DEFAULT_TIMEOUT or timeout is None else timeout
    deadline = time.monotonic() + budget
    error = OSError('No usable address returned by DNS')
    for family, kind, proto, _, destination in addresses:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Provider connection timed out') from None
        sock = None
        try:
            sock = socket.socket(family, kind, proto)
            sock.settimeout(min(3, remaining))
            if source_address:
                sock.bind(source_address)
            sock.connect(destination)
            # TLS negotiation and subsequent reads use the caller's timeout.
            sock.settimeout(budget)
            return sock
        except OSError as exc:
            error = exc
            if sock is not None:
                sock.close()
    raise error


class HTTPConnection(http.client.HTTPConnection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._create_connection = connect


class HTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._create_connection = connect


class HTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(HTTPConnection, req)


class HTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(HTTPSConnection, req, context=self._context)


def urlopen(request, timeout=12):
    # An independent opener avoids sharing mutable handlers across route workers.
    opener = urllib.request.build_opener(HTTPHandler(), HTTPSHandler())
    return opener.open(request, timeout=timeout)
