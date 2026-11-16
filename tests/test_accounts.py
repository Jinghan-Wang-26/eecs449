"""Security properties of the pinned-runtime account adapter (no user data)."""
import hashlib
import sqlite3
import threading
import time
import unittest
from types import SimpleNamespace

import jaclang
from server.accounts import (authenticate_account, change_password, create_account,
                             hash_password, validate_session, verify_password)


class AccountSecurityTests(unittest.TestCase):
    def setUp(self):
        self.conn = sqlite3.connect(':memory:')
        self.conn.execute('CREATE TABLE users (username TEXT PRIMARY KEY, password_hash TEXT, token TEXT, root_id TEXT)')
        self.conn.execute('INSERT INTO users VALUES (?, ?, ?, ?)',
                          ('alice', hash_password('Alice secure password!'), 'legacy-token-that-must-never-authorize', 'a' * 32))
        self.conn.execute('INSERT INTO users VALUES (?, ?, ?, ?)',
                          ('__guest__', hashlib.sha256(b'__no_password__').hexdigest(), 'old-shared-guest-token', 'b' * 32))
        self.conn.commit()
        self.manager = SimpleNamespace(_conn=self.conn, _lock=threading.RLock(), _ensure_connection=lambda: None)

    def tearDown(self):
        self.conn.close()

    def test_salted_passwords_and_wrong_password(self):
        first, second = hash_password('same test password'), hash_password('same test password')
        self.assertNotEqual(first, second)
        self.assertTrue(verify_password('same test password', first))
        self.assertFalse(verify_password('wrong test password', first))

    def test_registration_validation_is_server_side(self):
        self.assertIn('error', create_account(self.manager, 'bad name', 'long enough password'))
        self.assertIn('error', create_account(self.manager, 'alice', 'short'))

    def test_guest_cannot_login_and_old_tokens_are_rejected(self):
        self.assertIsNone(authenticate_account(self.manager, '__guest__', '__no_password__'))
        self.assertIsNone(validate_session(self.manager, 'legacy-token-that-must-never-authorize'))
        self.assertIsNone(validate_session(self.manager, 'forged-token-that-is-long-enough-to-parse'))

    def test_new_sessions_are_random_hashed_and_expire(self):
        first = authenticate_account(self.manager, ' ALICE ', 'Alice secure password!')
        second = authenticate_account(self.manager, 'alice', 'Alice secure password!')
        self.assertNotEqual(first['token'], second['token'])
        self.assertEqual(validate_session(self.manager, first['token']), 'alice')
        stored = [r[0] for r in self.conn.execute('SELECT token_hash FROM cartcompass_sessions')]
        self.assertNotIn(first['token'], stored)
        self.conn.execute('UPDATE cartcompass_sessions SET expires_at=?', (time.time() - 1,))
        self.assertIsNone(validate_session(self.manager, first['token']))

    def test_password_change_revokes_all_sessions(self):
        session = authenticate_account(self.manager, 'alice', 'Alice secure password!')
        self.assertIn('error', change_password(self.manager, 'alice', 'incorrect', 'New secure password!'))
        self.assertEqual(validate_session(self.manager, session['token']), 'alice')
        self.assertNotIn('error', change_password(self.manager, 'alice', 'Alice secure password!', 'New secure password!'))
        self.assertIsNone(validate_session(self.manager, session['token']))
        self.assertIsNotNone(authenticate_account(self.manager, 'alice', 'New secure password!'))

    def test_existing_named_password_upgrades_without_changing_root(self):
        self.conn.execute('UPDATE users SET password_hash=? WHERE username=?',
                          (hashlib.sha256(b'Legacy test password!').hexdigest(), 'alice'))
        session = authenticate_account(self.manager, 'alice', 'Legacy test password!')
        self.assertEqual(session['root_id'], 'a' * 32)
        self.assertTrue(self.conn.execute('SELECT password_hash FROM users WHERE username="alice"').fetchone()[0].startswith('scrypt$'))

    def test_repeated_failed_logins_are_temporarily_blocked(self):
        for _ in range(8):
            self.assertIsNone(authenticate_account(self.manager, 'alice', 'wrong password'))
        self.assertIsNone(authenticate_account(self.manager, 'alice', 'Alice secure password!'))
        self.conn.execute('UPDATE cartcompass_login_attempts SET window_start=?', (time.time() - 901,))
        self.assertIsNotNone(authenticate_account(self.manager, 'alice', 'Alice secure password!'))
