"""Connection regressions for a host with unreachable IPv6 provider addresses."""
import socket
import ssl
import unittest
from unittest.mock import Mock, patch
from integrations import http_transport as h

V4 = (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.1', 443))
V6 = (socket.AF_INET6, socket.SOCK_STREAM, 6, '', ('2001:db8::1', 443, 0, 0))


class HTTPTransportTests(unittest.TestCase):
    def test_ipv4_succeeds_without_waiting_for_unreachable_ipv6(self):
        sock = Mock()
        with patch.object(h.socket, 'getaddrinfo', return_value=[V6, V4]), \
             patch.object(h.socket, 'socket', return_value=sock) as factory:
            self.assertIs(h.connect(('provider.test', 443)), sock)
        factory.assert_called_once_with(socket.AF_INET, socket.SOCK_STREAM, 6)
        sock.connect.assert_called_once_with(V4[4])
        self.assertEqual(sock.settimeout.call_args_list[0].args, (3,))
        sock.close.assert_not_called()

    def test_ipv6_remains_available_when_ipv4_fails(self):
        failed, working = Mock(), Mock()
        failed.connect.side_effect = TimeoutError()
        with patch.object(h.socket, 'getaddrinfo', return_value=[V6, V4]), \
             patch.object(h.socket, 'socket', side_effect=[failed, working]):
            self.assertIs(h.connect(('provider.test', 443), source_address=('', 0)), working)
        failed.close.assert_called_once()
        working.connect.assert_called_once_with(V6[4])
        working.bind.assert_called_once_with(('', 0))

    def test_tcp_budget_is_shared_across_addresses(self):
        sock = Mock()
        sock.connect.side_effect = TimeoutError()
        with patch.object(h.socket, 'getaddrinfo', return_value=[V4, V4, V6]), \
             patch.object(h.socket, 'socket', return_value=sock) as factory, \
             patch.object(h.time, 'monotonic', side_effect=[0, 0, 3, 6]):
            with self.assertRaises(TimeoutError):
                h.connect(('provider.test', 443), timeout=5)
        self.assertEqual(factory.call_count, 2)
        self.assertEqual([c.args[0] for c in sock.settimeout.call_args_list], [3, 2])
        self.assertEqual(sock.close.call_count, 2)

    def test_ipv6_only_host_and_failed_sockets(self):
        sock = Mock()
        with patch.object(h.socket, 'getaddrinfo', return_value=[V6]), \
             patch.object(h.socket, 'socket', return_value=sock):
            self.assertIs(h.connect(('provider.test', 443)), sock)
            sock.connect.side_effect = OSError('unreachable')
            with self.assertRaises(OSError):
                h.connect(('provider.test', 443))
        sock.close.assert_called_once()

    def test_tls_verification_and_system_connector_are_preserved(self):
        original = socket.create_connection
        connection = h.HTTPSConnection('provider.test')
        self.assertTrue(connection._context.check_hostname)
        self.assertEqual(connection._context.verify_mode, ssl.CERT_REQUIRED)
        self.assertIs(connection._create_connection, h.connect)
        self.assertIs(socket.create_connection, original)

    def test_opener_installs_scoped_handlers_and_preserves_proxy_handler(self):
        real_build = h.urllib.request.build_opener
        with patch.object(h.urllib.request, 'build_opener', wraps=real_build) as build, \
             patch.object(h.urllib.request.OpenerDirector, 'open', return_value='response') as open_request:
            self.assertEqual(h.urlopen('https://provider.test', timeout=7), 'response')
        self.assertIsInstance(build.call_args.args[0], h.HTTPHandler)
        self.assertIsInstance(build.call_args.args[1], h.HTTPSHandler)
        open_request.assert_called_once_with('https://provider.test', timeout=7)
        opener = real_build(h.HTTPHandler(), h.HTTPSHandler())
        self.assertTrue(any(isinstance(x, h.urllib.request.ProxyHandler) for x in opener.handlers)
                        or not h.urllib.request.getproxies())
