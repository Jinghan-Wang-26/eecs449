"""Regression checks for Jac's single-response public asset compatibility layer."""
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import jaclang
from jaclang import JacRuntime
from server import mobile_assets


class Response:
    def __init__(self):
        self.statuses = []
        self.headers = {}
        self.wfile = io.BytesIO()
        self.ends = 0

    def send_response(self, status):
        self.statuses.append(status)

    def send_header(self, name, value):
        self.headers[name] = value

    def end_headers(self):
        self.ends += 1


class MobileAssetsTests(unittest.TestCase):
    def test_runtime_sends_exactly_one_complete_worker_response(self):
        response = Response()
        worker = mobile_assets.ASSETS_ROOT / 'cartcompass-sw.js'
        JacRuntime.send_static_file(response, worker)
        self.assertEqual(response.statuses, [200])
        self.assertEqual(response.ends, 1)
        self.assertEqual(response.wfile.getvalue(), worker.read_bytes())
        self.assertEqual(int(response.headers['Content-Length']), len(response.wfile.getvalue()))
        self.assertIn('javascript', response.headers['Content-Type'])
        self.assertEqual(response.headers['Cache-Control'], 'no-cache')
        self.assertEqual(response.headers['X-Content-Type-Options'], 'nosniff')

    def test_manifest_has_a_browser_compatible_content_type(self):
        response = Response()
        JacRuntime.send_static_file(response, mobile_assets.ASSETS_ROOT / 'mobile/app.webmanifest')
        self.assertEqual(response.statuses, [200])
        self.assertEqual(response.headers['Content-Type'], 'application/manifest+json')

    def test_private_paths_and_symlink_escape_are_not_public(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            public = base / 'public'
            public.mkdir()
            private = base / 'private.json'
            private.write_text('{"token": "synthetic-secret"}')
            (public / 'escape.json').symlink_to(private)
            with patch.object(mobile_assets, 'ASSETS_ROOT', public):
                for candidate in [private, public / '../private.json', public / 'escape.json', public / 'missing.png']:
                    response = Response()
                    JacRuntime.send_static_file(response, candidate)
                    self.assertEqual(response.statuses, [404])
                    self.assertNotIn(b'synthetic-secret', response.wfile.getvalue())
