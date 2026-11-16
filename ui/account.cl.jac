"""Account gate: workspace components mount only after server validation."""
import from '@jac/runtime' { jacSetToken, jacLogout }
import from .chat { ChatApp }
import from .theme { AppStyles }


def:pub AccountApp -> JsxElement {
    has account: dict = {}, checking: bool = True, busy: bool = False,
        signup: bool = False, username: str = "", password: str = "",
        confirmation: str = "", notice: str = "";

    async def check_session -> None {
        token = localStorage.getItem("jac_token");
        if not token { account = {}; checking = False; return; }
        try {
            response = await fetch("/user/info", {"headers": {"Authorization": "Bearer " + token}, "cache": "no-store"});
            if localStorage.getItem("jac_token") != token { window.location.reload(); return; }
            if response.status == 401 {
                jacLogout(); account = {}; notice = "Your session expired. Please sign in again.";
            } elif response.ok {
                payload = await response.json();
                account = payload["data"];
                notice = "";
            } else { notice = "Could not check your account. Please retry."; }
        } except Exception { notice = "Cannot connect to the server. Please retry."; }
        checking = False;
    }

    can with [] entry {
        check_session();
        listener = lambda e: any {
            if e.key == "jac_token" or e.key == None { window.location.reload(); }
        };
        page_listener = lambda e: any { if e.persisted { window.location.reload(); } };
        window.addEventListener("storage", listener);
        window.addEventListener("pageshow", page_listener);
        return lambda {
            window.removeEventListener("storage", listener);
            window.removeEventListener("pageshow", page_listener);
        };
    }

    async def submit(e: FormEvent) -> None {
        e.preventDefault();
        if busy { return; }
        notice = "";
        if signup and password != confirmation { notice = "Passwords do not match."; return; }
        busy = True;
        name = username.strip().toLowerCase();
        identity = {"type": "username", "value": name};
        credential = {"type": "password", "password": password};
        try {
            if signup {
                response = await fetch("/user/register", {"method": "POST", "headers": {"Content-Type": "application/json"}, "body": JSON.stringify({"identities": [identity], "credential": credential})});
                payload = await response.json();
                if not response.ok {
                    err = payload.get("error", {});
                    notice = err.get("message", "Could not create this account. Check your username and password.") if isinstance(err, dict) else str(err);
                    busy = False; return;
                }
                signup = False;
            }
            response = await fetch("/user/login", {"method": "POST", "headers": {"Content-Type": "application/json"}, "body": JSON.stringify({"identity": identity, "credential": credential})});
            if response.ok {
                payload = await response.json();
                jacSetToken(payload["data"]["token"]);
                password = ""; confirmation = "";
                # A full remount clears pending requests, response caches, and
                # all shopping state from any previous account on this browser.
                window.location.reload();
            } else {
                notice = "Unable to sign in. Check your username and password. After repeated attempts, wait 15 minutes.";
            }
        } except Exception { notice = "Cannot connect to the server. Please retry."; }
        busy = False;
    }

    async def sign_out -> None {
        if busy { return; }
        busy = True; notice = "";
        token = localStorage.getItem("jac_token");
        try {
            response = await fetch("/walker/LogoutSession", {"method": "POST", "headers": {"Content-Type": "application/json", "Authorization": "Bearer " + (token or "")}, "body": JSON.stringify({"token": token or ""})});
            payload = await response.json();
            revoked = response.ok and payload.get("data", {}).get("reports", [])[0]?.signed_out == True;
            if revoked or response.status == 401 {
                if localStorage.getItem("jac_token") == token { jacLogout(); }
                account = {}; password = ""; confirmation = "";
                window.location.reload();
            } else { notice = "Could not sign out on the server. Please retry."; }
        } except Exception { notice = "Cannot connect to sign out. Please retry."; }
        busy = False;
    }

    if account.get("username") {
        return <ChatApp username={account["username"]} on_sign_out={sign_out} signout_pending={busy} account_notice={notice} />;
    }
    return <div className="account-shell">
        <AppStyles />
        <header className="account-brand"><a className="brand" href="/" aria-label="CartCompass home"><span className="brand-icon" aria-hidden="true">↗</span>CartCompass</a></header>
        <main className="account-card">
            <span className="account-eyebrow">YOUR SHOPPING, ORGANIZED</span>
            <h1>{"Create your account" if signup else "Welcome to CartCompass"}</h1>
            <p className="account-intro">Sign in to keep your shopping lists, addresses, plans and spending history in your own workspace.</p>
            {if checking { <p role="status">Checking your session…</p>; }}
                {if not checking and notice { <p className="inline-alert" role="alert">{notice}</p>; }}
                {if not checking and localStorage.getItem("jac_token") {
                    <button type="button" className="go" onClick={lambda e: MouseEvent { checking = True; check_session(); }}>Retry connection</button>;
                }}
                {if not checking and not localStorage.getItem("jac_token") {
                    <form className="account-form" onSubmit={submit}>
                        <label htmlFor="account-username">Username<input id="account-username" name="username" autoComplete="username" required={True} minLength={3} maxLength={64} value={username} onChange={lambda e: ChangeEvent { username = e.target.value; }} placeholder="Choose a username" /></label>
                        <label htmlFor="account-password">Password<input id="account-password" name="password" type="password" autoComplete={"new-password" if signup else "current-password"} required={True} minLength={12 if signup else 1} maxLength={128} value={password} onChange={lambda e: ChangeEvent { password = e.target.value; }} /></label>
                        {if signup {
                            <small>Use 12–128 characters. A long, unique passphrase works well.</small>
                            <label htmlFor="account-confirm">Confirm password<input id="account-confirm" name="confirmPassword" type="password" autoComplete="new-password" required={True} value={confirmation} onChange={lambda e: ChangeEvent { confirmation = e.target.value; }} /></label>
                        }}
                        <button type="submit" className="go cta" disabled={busy}>{"Please wait…" if busy else "Create account" if signup else "Sign in"}</button>
                    </form>
                    <div className="account-switch"><span>{"Already have an account?" if signup else "New here?"}</span><button type="button" className="text-button" disabled={busy} onClick={lambda e: MouseEvent { signup = not signup; notice = ""; password = ""; confirmation = ""; }}>{"Sign in" if signup else "Create an account"}</button></div>
                }}
            <p className="account-footnote">Your account starts with a private shopping workspace. Previous shared demo data stays separate.</p>
        </main>
    </div>;
}
