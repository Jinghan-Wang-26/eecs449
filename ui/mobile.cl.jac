"""Installable mobile shell. Personal data always requires the online Jac API."""
import from .account { AccountApp }
import from .language { install_english_ui }


def:pub MobileApp -> JsxElement {
    has online: bool = True, installed: bool = False, prompt_event: any = None,
        installing: bool = False, install_notice: str = "";

    can with [] entry {
        remove_language_handlers = install_english_ui();
        online = navigator.onLine;
        display = window.matchMedia("(display-mode: standalone)");
        installed = display.matches or navigator.standalone == True;
        connection = lambda e: any { online = navigator.onLine; };
        capture_prompt = lambda e: any {
            e.preventDefault(); prompt_event = e; install_notice = "";
        };
        app_installed = lambda e: any {
            installed = True; prompt_event = None; install_notice = "";
            document.getElementById("mobile-install-dialog")?.close();
        };
        display_changed = lambda e: any { installed = e.matches or navigator.standalone == True; };
        window.addEventListener("online", connection);
        window.addEventListener("offline", connection);
        window.addEventListener("beforeinstallprompt", capture_prompt);
        window.addEventListener("appinstalled", app_installed);
        display.addEventListener("change", display_changed);
        if window.isSecureContext and navigator.serviceWorker {
            navigator.serviceWorker.register("/cartcompass-sw.js", {"scope": "/", "updateViaCache": "none"}).catch(lambda error: any {
                install_notice = "Installation could not be prepared. Reload while connected and try again.";
            });
        }
        return lambda {
            remove_language_handlers();
            window.removeEventListener("online", connection);
            window.removeEventListener("offline", connection);
            window.removeEventListener("beforeinstallprompt", capture_prompt);
            window.removeEventListener("appinstalled", app_installed);
            display.removeEventListener("change", display_changed);
        };
    }

    async def install -> None {
        if installing { return; }
        if not prompt_event {
            document.getElementById("mobile-install-dialog").showModal(); return;
        }
        installing = True;
        event = prompt_event;
        prompt_event = None;
        try {
            await event.prompt();
            choice = await event.userChoice;
            install_notice = "Follow your browser's installation steps." if choice.outcome == "accepted" else "You can install later from your browser menu.";
        } except Exception {
            install_notice = "Use your browser menu to install CartCompass.";
        }
        installing = False;
    }

    return <div className="mobile-frame notranslate" lang="en" translate="no">
        {if not installed {
            <aside className="mobile-app-bar" aria-label="Mobile app">
                <span>Take CartCompass with you</span>
                <button type="button" onClick={install} disabled={installing or not online}>{"Opening…" if installing else "Install app"}</button>
            </aside>
        }}
        {if install_notice and not installed { <p className="mobile-install-notice" role="status">{install_notice}</p>; }}
        {if not online {
            <aside className="mobile-offline" role="status">
                <strong>You are offline</strong>
                <span>Displayed plans may be out of date. Reconnect before changing your list, checking prices or confirming a plan. Nothing is queued for submission.</span>
            </aside>
        }}
        <fieldset className="mobile-content" disabled={not online} aria-label="Shopping workspace">
            <AccountApp />
        </fieldset>
        <dialog id="mobile-install-dialog" className="mobile-install-dialog" aria-labelledby="mobile-install-title">
            <form method="dialog"><button className="ghost" aria-label="Close installation help" autoFocus={True}>Close</button></form>
            <img src="/static/mobile/icon-192.png" width="56" height="56" alt="" />
            <h2 id="mobile-install-title">CartCompass on your home screen</h2>
            <p>Use your shopping assistant in its own window. Sign in with the same account to access your lists and plans.</p>
            <ol>
                <li><strong>iPhone / iPad:</strong> Open this site in Safari. Tap Share, then Add to Home Screen. Enable Open as Web App if shown, then tap Add.</li>
                <li><strong>Android:</strong> Open this site in Chrome. Tap the browser menu, then Install app or Add to Home screen.</li>
                <li><strong>Desktop:</strong> Use Chrome or Edge and select the install icon in the address bar, if available.</li>
            </ol>
            {if not window.isSecureContext {
                <p className="inline-alert">Installation requires HTTPS. Use the deployed HTTPS address on your phone. A computer's localhost is only available on that computer.</p>;
            }}
            <p className="mobile-help-note">If the install option is missing, open this site directly in a supported browser, check that it uses HTTPS, and check whether it is already installed. Shopping and account actions need an internet connection.</p>
        </dialog>
    </div>;
}
