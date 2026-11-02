import from .planview { short_address }

"""Where the shopper starts from. Current location first, typed address as a fallback;
the address is only saved after the shopper confirms it."""

def:pub AddressPicker(workspace: dict, busy: bool, operate: any, auto: bool = False, confirmed: any = None) -> JsxElement {
    has typed: str = "", locating: bool = False, slow: bool = False, problem: str = "", tried: bool = False, editing: bool = False;
    saved = workspace["profile"]["address"];
    candidates = workspace["address_candidates"];

    """Keep listening for a fix for up to 45 s. A Mac's first fix comes from nearby Wi-Fi and can
    be slow, and the clock keeps running while macOS asks whether the browser may use location."""
    def locate() -> None {
        problem = ""; tried = True; slow = False;
        if not navigator.geolocation { problem = "This browser cannot share your location. Type your address instead."; return; }
        locating = True;
        job = {"done": False, "watch": None, "hint": None, "limit": None};
        stop = lambda {
            job["done"] = True;
            navigator.geolocation.clearWatch(job["watch"]);
            clearTimeout(job["hint"]); clearTimeout(job["limit"]);
            locating = False; slow = False;
        };
        job["hint"] = setTimeout(lambda { slow = True; }, 8000);
        job["limit"] = setTimeout(lambda {
            if job["done"] { return; }
            stop();
            problem = "We could not get your location within 45 seconds. On a Mac, turn on Wi-Fi (Macs find their location from nearby Wi-Fi networks) and check System Settings → Privacy & Security → Location Services: Location Services and your browser must both be on. Then try again, or type your address below.";
        }, 45000);
        job["watch"] = navigator.geolocation.watchPosition(
            lambda position: any {
                if job["done"] { return; }
                stop();
                operate("device_location", {"lat": position.coords.latitude, "lon": position.coords.longitude, "accuracy_m": position.coords.accuracy});
            },
            lambda error: any {
                if job["done"] { return; }
                if error.code == 1 {
                    stop();
                    problem = "Your browser blocked location for this page. Click the icon at the left of the address bar and allow Location, and on a Mac also turn on Location Services for your browser in System Settings → Privacy & Security. Or type your address below.";
                }
                # Other errors are temporary: the watch keeps trying until the 45 s limit.
            },
            {"enableHighAccuracy": False, "maximumAge": 600000}
        );
    }

    async def choose(id: str) -> None {
        ok = await operate("confirm_address", {"id": id});
        if ok {
            editing = False; tried = False;
            if confirmed { await confirmed(); }
        }
    }

    async def look_up(e: FormEvent) -> None {
        e.preventDefault();
        problem = "";
        await operate("geocode", {"address": typed});
    }

    # Start from the current location when the shopper asked for options without an address.
    can with (auto) entry {
        if auto and not saved and len(candidates) == 0 and not tried { locate(); }
    }

    if saved and not editing and len(candidates) == 0 {
        return <div className="address-picker saved" id="chg-address">
            <span><small>Starting from</small><b>{short_address(saved)}</b><small>{saved}</small></span>
            <button type="button" onClick={lambda e: MouseEvent { editing = True; }}>Change</button>
        </div>;
    }

    return <section className="address-picker" aria-label="Where you start">
        <h3>Where will you start from?</h3>
        <p>Used to find nearby stores and walking or bus routes. Nothing is saved until you confirm it.</p>
        {if len(candidates) > 0 {
            <div className="address-confirm">
                <small>{"Is this right?" if len(candidates) == 1 else "Pick the right address"}</small>
                {[<div key={a["id"]} className="address-option"><span><b>{short_address(a["address"])}</b><small>{a["address"] + " · " + a["precision"] + (" · about " + str(Math.round(a["accuracy_m"])) + " m" if a.get("accuracy_m", None) else "")}</small></span>
                    <button type="button" className={"go" if i == 0 else ""} disabled={busy} onClick={lambda e: MouseEvent { choose(a["id"]); }}>Start from here</button></div> for (i, a) in enumerate(candidates)]}
            </div>
        }}
        <div className="address-actions">
            <button type="button" className={"go" if len(candidates) == 0 else ""} disabled={busy or locating} onClick={lambda e: MouseEvent { locate(); }}>{("Still looking…" if slow else "Finding you…") if locating else ("Use my current location" if len(candidates) == 0 else "Try my location again")}</button>
            {if saved { <button type="button" className="ghost" onClick={lambda e: MouseEvent { editing = False; }}>Keep current address</button> }}
        </div>
        {if locating and slow { <p className="search-note" role="status">Still looking. If macOS asks whether your browser may use your location, choose Allow. This can take up to 45 seconds; you can also type your address below.</p> }}
        {if problem { <div className="address-problem" role="alert">{problem}</div> }}
        <form className="address-type" onSubmit={look_up}>
            <input aria-label="Type a start address" value={typed} placeholder="Or type an address, city or ZIP code" onChange={lambda e: ChangeEvent { typed = e.target.value; }} />
            <button type="submit" disabled={busy or not typed.strip()}>Look up</button>
        </form>
    </section>;
}
