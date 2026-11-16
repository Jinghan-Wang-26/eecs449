"""Account security adapter for the pinned Jac 0.16.7 user/root store.

Keep Jac's HTTP authentication and graph ownership. Harden its default password
and token storage here, without changing the installed runtime. Import this
module before serving requests. Sessions are persistent, hashed, and revocable.
"""
import hashlib;
import hmac;
import secrets;
import time;
import re;
import os;
import from jaclang { JacRuntime as Jac }
import from jaclang.runtimelib.server { UserManager, AuthHandler }
import from jaclang.runtimelib.transport { TransportResponse, Meta }
import from jaclang.jac0core.constant { Constants }
import from models.graph { profile_of }


def username_value(value: str) -> str {
    return value.strip().lower() if isinstance(value, str) else "";
}

def valid_username(value: str) -> bool {
    return bool(re.fullmatch("[a-z0-9][a-z0-9_.@+-]{2,63}", value)) and value not in ["guest", Constants.GUEST.value];
}

def password_error(password: str) -> str {
    if not isinstance(password, str) or len(password) < 12 or len(password) > 128 {
        return "Use a password between 12 and 128 characters.";
    }
    return "";
}

def hash_password(password: str) -> str {
    salt = secrets.token_hex(16);
    digest = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex();
    return "scrypt$" + salt + "$" + digest;
}

def verify_password(password: str, encoded: str) -> bool {
    if not isinstance(password, str) or len(password) > 128 { return False; }
    try {
        if encoded.startswith("scrypt$") {
            parts = encoded.split("$");
            digest = hashlib.scrypt(password.encode(), salt=bytes.fromhex(parts[1]), n=16384, r=8, p=1).hex();
            return hmac.compare_digest(digest, parts[2]);
        }
        # Existing named accounts upgrade on their next successful login.
        return len(encoded) == 64 and hmac.compare_digest(hashlib.sha256(password.encode()).hexdigest(), encoded);
    } except (ValueError, IndexError) { return False; }
}

def token_hash(token: str) -> str {
    return hashlib.sha256(token.encode()).hexdigest();
}

def ensure_sessions(manager: any) -> None {
    manager._ensure_connection();
    with manager._lock {
        manager._conn.execute("CREATE TABLE IF NOT EXISTS cartcompass_sessions (token_hash TEXT PRIMARY KEY, username TEXT NOT NULL, expires_at REAL NOT NULL)");
        manager._conn.execute("CREATE INDEX IF NOT EXISTS cartcompass_sessions_user ON cartcompass_sessions(username)");
        manager._conn.execute("CREATE TABLE IF NOT EXISTS cartcompass_login_attempts (username TEXT PRIMARY KEY, attempts INTEGER NOT NULL, window_start REAL NOT NULL)");
        manager._conn.commit();
    }
}

def create_account(self: any, username: str, password: str) -> dict {
    name = username_value(username);
    # Jac creates an internal guest to serve the public login page. Never allow
    # that principal to authenticate or receive a session, including old tokens.
    if name == Constants.GUEST.value {
        return self._cartcompass_original_create(name, secrets.token_urlsafe(48));
    }
    if not valid_username(name) { return {"error": "Use a username of 3-64 letters, numbers, dots, underscores or hyphens."}; }
    error = password_error(password);
    if error { return {"error": error}; }
    ensure_sessions(self);
    with self._lock {
        if self.user_exists(name) { return {"error": "This username is unavailable."}; }
        encoded = hash_password(password);
        # The native helper creates a Jac-owned root. Its temporary credential
        # is random, never returned, and cannot authenticate via this adapter.
        result = self._cartcompass_original_create(name, secrets.token_urlsafe(48));
        if result.get("error") { return result; }
        self._conn.execute("UPDATE users SET password_hash=? WHERE username=?", (encoded, name));
        self._conn.commit();
        return {"username": name, "root_id": result["root_id"]};
    }
}

def authenticate_account(self: any, username: str, password: str) -> dict | None {
    name = username_value(username);
    if not valid_username(name) or not isinstance(password, str) or len(password) > 128 { return None; }
    ensure_sessions(self);
    now = time.time();
    with self._lock {
        self._conn.execute("DELETE FROM cartcompass_login_attempts WHERE window_start < ?", (now - 900,));
        attempts = self._conn.execute("SELECT attempts FROM cartcompass_login_attempts WHERE username=?", (name,)).fetchone();
        if attempts and attempts[0] >= 8 { self._conn.commit(); return None; }
        row = self._conn.execute("SELECT password_hash, root_id FROM users WHERE username=?", (name,)).fetchone();
        # Equal KDF work for absent accounts, without storing their password.
        encoded = row[0] if row else "scrypt$" + "00" * 16 + "$" + "00" * 64;
        valid = verify_password(password, encoded);
        if not row or not valid {
            self._conn.execute("INSERT INTO cartcompass_login_attempts VALUES (?, 1, ?) ON CONFLICT(username) DO UPDATE SET attempts=attempts+1", (name, now));
            self._conn.commit();
            return None;
        }
        if not row[0].startswith("scrypt$") {
            self._conn.execute("UPDATE users SET password_hash=? WHERE username=?", (hash_password(password), name));
        }
        token = secrets.token_urlsafe(32);
        self._conn.execute("DELETE FROM cartcompass_sessions WHERE expires_at <= ?", (now,));
        self._conn.execute("INSERT INTO cartcompass_sessions VALUES (?, ?, ?)", (token_hash(token), name, now + 43200));
        self._conn.execute("DELETE FROM cartcompass_login_attempts WHERE username=?", (name,));
        self._conn.commit();
        return {"username": name, "root_id": row[1], "token": token};
    }
}

def validate_session(self: any, token: str) -> str | None {
    if not isinstance(token, str) or len(token) < 32 or len(token) > 128 { return None; }
    ensure_sessions(self);
    with self._lock {
        row = self._conn.execute("SELECT s.username FROM cartcompass_sessions s JOIN users u ON u.username=s.username WHERE s.token_hash=? AND s.expires_at>?", (token_hash(token), time.time())).fetchone();
    }
    return row[0] if row and valid_username(row[0]) else None;
}

def change_password(self: any, username: str, current_password: str, new_password: str) -> dict {
    error = password_error(new_password);
    if error { return {"error": error}; }
    ensure_sessions(self);
    with self._lock {
        row = self._conn.execute("SELECT password_hash FROM users WHERE username=?", (username,)).fetchone();
        if not row or not verify_password(current_password, row[0]) { return {"error": "Current password is incorrect."}; }
        self._conn.execute("UPDATE users SET password_hash=? WHERE username=?", (hash_password(new_password), username));
        self._conn.execute("DELETE FROM cartcompass_sessions WHERE username=?", (username,));
        self._conn.commit();
    }
    return {"username": username, "message": "Password changed. Sign in again on your devices."};
}

def keep_username(self: any, current_username: str, new_username: str) -> dict {
    return {"error": "Username changes are not supported."};
}

def account_info(self: any, token: str) -> any {
    username = self.user_manager.validate_token(token);
    if not username {
        return TransportResponse.fail(code="UNAUTHORIZED", message="Sign in to continue.", meta=Meta(extra={"http_status": 401}));
    }
    # Do not reflect bearer credentials in the information endpoint.
    return TransportResponse.success(data={"username": username, "root_id": self.user_manager.get_root_id(username)}, meta=Meta(extra={"http_status": 200}));
}

def account_manager -> any {
    return Jac.get_user_manager(base_path=os.getcwd());
}

"""Only the authenticated user's own root may enter a shopping operation."""
def require_account(r: any) -> dict {
    ctx = Jac.get_context();
    if r.__jac__.id != ctx.user_root.id { raise ValueError("This workspace belongs to another account."); }
    manager = account_manager();
    manager._ensure_connection();
    with manager._lock {
        row = manager._conn.execute("SELECT username FROM users WHERE root_id=?", (ctx.user_root.id.hex,)).fetchone();
    }
    if not row or not valid_username(row[0]) { raise ValueError("Sign in to access your shopping workspace."); }
    return {"username": row[0], "root_id": ctx.user_root.id.hex};
}

def account_profile(r: any) -> any {
    require_account(r);
    return profile_of(r);
}

walker SessionInfo {
    can run with Root entry { report require_account(here); }
}

walker LogoutSession {
    has token: str = "";
    can run with Root entry {
        account = require_account(here);
        manager = account_manager();
        ensure_sessions(manager);
        with manager._lock {
            manager._conn.execute("DELETE FROM cartcompass_sessions WHERE token_hash=? AND username=?", (token_hash(self.token), account["username"]));
            manager._conn.commit();
        }
        report {"signed_out": True};
    }
}

def install_account_security -> None {
    if getattr(UserManager, "_cartcompass_installed", False) { return; }
    setattr(UserManager, "_cartcompass_original_create", UserManager.create_user);
    setattr(UserManager, "create_user", create_account);
    setattr(UserManager, "authenticate", authenticate_account);
    setattr(UserManager, "validate_token", validate_session);
    setattr(UserManager, "update_password", change_password);
    setattr(UserManager, "update_username", keep_username);
    setattr(AuthHandler, "get_user_info", account_info);
    setattr(UserManager, "_cartcompass_installed", True);
}

with entry { install_account_security(); }
