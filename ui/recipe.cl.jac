"""Dish ideas with photos, the recipe sheet and the undo toast.

Photos load straight from TheMealDB without a referrer and fall back to a local
illustration. Nothing joins the list until the shopper presses Add.
"""

import from "react-dom" { createPortal }

glob DISH_FALLBACK: str = "/static/illustrations/dish.svg",
     INGREDIENT_FALLBACK: str = "/static/illustrations/ingredient.svg";

def fallback(e: any, src: str) -> None {
    if e.target.dataset.fallback != "1" { e.target.dataset.fallback = "1"; e.target.src = src; }
}

def uses_text(dish: dict) -> str {
    uses = dish.get("uses", []);
    return ("Uses " + uses[:2].join(", ") + (" +" + str(len(uses) - 2) if len(uses) > 2 else "")) if len(uses) > 0 else dish.get("category", "");
}

def hero_extra(hero: dict) -> str {
    missing = hero.get("missing", None);
    if missing is None { return ""; }
    return " · everything else is on your list" if missing == 0 else " · " + str(missing) + " more to buy";
}

def:pub RecipeIdeas(recipes: dict, busy: bool, operate: any) -> JsxElement {
    has query: str = "", tried: str = "", hidden: bool = False;

    can with [] entry {
        try { hidden = window.localStorage.getItem("cartcompass-hide-ideas") == "1"; } except Exception { hidden = False; }
    }
    # Fetch ideas once per list version; a failed lookup is not retried until the list changes.
    can with (recipes["stale"], recipes["signature"], busy) entry {
        if recipes["stale"] and not busy and tried != recipes["signature"] {
            tried = recipes["signature"];
            operate("recipe_feed", {});
        }
    }

    def toggle() -> None {
        hidden = not hidden;
        try { window.localStorage.setItem("cartcompass-hide-ideas", "1" if hidden else "0"); } except Exception { query = query; }
    }

    def search(e: FormEvent) -> None {
        e.preventDefault();
        if query.strip() != "" { operate("recipe_feed", {"query": query.strip()}); }
    }

    feed = recipes.get("feed", {}) or {};
    dishes = feed.get("dishes", []) or [];
    hero = feed.get("hero", None);
    rest = dishes[1:] if hero else dishes;
    active = feed.get("category", "") or ("search" if feed.get("query", "") else "list");

    if hidden {
        return <section className="recipe-ideas collapsed" aria-label="Dish ideas">
            <button type="button" className="text-button" onClick={lambda e: MouseEvent { toggle(); }}>🍳 Show dish ideas</button>
        </section>;
    }
    return <section className="recipe-ideas" aria-label="Dish ideas">
        <div className="recipe-head"><span className="section-eyebrow">COOK SOMETHING</span><button type="button" className="text-button" onClick={lambda e: MouseEvent { toggle(); }}>Hide</button></div>
        {if hero {
            <button type="button" className="recipe-hero" disabled={busy} onClick={lambda e: MouseEvent { operate("recipe_open", {"id": hero["id"], "servings": 4}); }}>
                <img src={hero["image"] or DISH_FALLBACK} alt={hero["name"]} loading="lazy" referrerPolicy="no-referrer" onError={lambda e: any { fallback(e, DISH_FALLBACK); }} />
                <span className="recipe-hero-shade" aria-hidden="true"></span>
                <span className="recipe-hero-cta">View recipe →</span>
                <span className="recipe-hero-text">
                    <small>COOK TONIGHT</small>
                    <strong>{hero["name"]}</strong>
                    <span>{"Uses " + hero["uses"][:2].join(" and ") + " from your list" + hero_extra(hero)}</span>
                </span>
            </button>
        }}
        <form className="recipe-search" onSubmit={search} role="search">
            <input aria-label="Search for a dish" placeholder="What are you cooking?" maxLength="60" value={query} onChange={lambda e: ChangeEvent { query = e.target.value; }} />
            <button type="submit" disabled={busy or query.strip() == ""}>Search</button>
        </form>
        <div className="recipe-chips" role="group" aria-label="Dish categories">
            <button type="button" className={"recipe-chip on" if active == "list" else "recipe-chip"} aria-pressed={active == "list"} disabled={busy} onClick={lambda e: MouseEvent { query = ""; operate("recipe_feed", {}); }}>For your list</button>
            {[<button key={chip} type="button" className={"recipe-chip on" if active == chip else "recipe-chip"} aria-pressed={active == chip} disabled={busy} onClick={lambda e: MouseEvent { operate("recipe_feed", {"category": chip}); }}>{chip}</button> for chip in recipes["chips"]]}
        </div>
        {if feed.get("error", "") != "" { <p className="recipe-note">{feed["error"]}</p> }}
        {if len(dishes) == 0 and recipes["stale"] { <p className="recipe-note" role="status">Finding dish ideas for your list…</p> }}
        {if len(rest) > 0 {
            <div>
                <div className="recipe-row-title"><b>{feed.get("label", "Dish ideas")}</b></div>
                <div className="recipe-cards">{[<button key={dish["id"]} type="button" className="recipe-card" disabled={busy} onClick={lambda e: MouseEvent { operate("recipe_open", {"id": dish["id"], "servings": 4}); }}>
                    <img src={dish.get("thumb", "") or DISH_FALLBACK} alt="" loading="lazy" referrerPolicy="no-referrer" onError={lambda e: any { fallback(e, DISH_FALLBACK); }} />
                    <span className="recipe-card-name">{dish["name"]}</span>
                    {if uses_text(dish) != "" { <span className="recipe-badge">{uses_text(dish)}</span> }}
                </button> for dish in rest]}</div>
            </div>
        } elif feed.get("query", "") != "" {
            <p className="recipe-note">{"No dishes found for \"" + feed["query"] + "\". Try a simpler name, like curry or pasta."}</p>
        }}
        <p className="recipe-credit">Dish ideas and photos: <a href="https://www.themealdb.com/" target="_blank" rel="noreferrer">TheMealDB</a></p>
    </section>;
}

def:pub RecipeSheet(recipes: dict, busy: bool, operate: any) -> JsxElement {
    has chosen: dict = {}, shown: str = "", more: bool = False;
    draft = recipes.get("draft", None);

    # Open the native dialog for a new recipe and preselect the suggested ingredients.
    can with (draft["id"] if draft else "") entry {
        el = document.getElementById("recipe-sheet");
        if not draft {
            if el and el.open { el.close(); }
            shown = "";
            return;
        }
        if shown != draft["id"] {
            picks = {};
            for row in draft["groups"]["to_buy"] { picks[row["key"]] = True; }
            chosen = picks; shown = draft["id"]; more = False;
        }
        if el and not el.open { el.showModal(); }
    }

    def toggle(key: str) -> None {
        updated = Object.assign({}, chosen);
        updated[key] = not chosen.get(key, False);
        chosen = updated;
    }

    def close() -> None {
        if recipes.get("draft", None) { operate("recipe_close", {}); }
    }

    def row(item: dict, selectable: bool, note: str) -> any {
        on = selectable and chosen.get(item["key"], False);
        body = [<img key="i" src={item["image"] or INGREDIENT_FALLBACK} alt="" loading="lazy" referrerPolicy="no-referrer" onError={lambda e: any { fallback(e, INGREDIENT_FALLBACK); }} />,
                <span key="t" className="ing-text"><b>{item["name"]}</b><small>{note or item["amount"]}</small></span>,
                <span key="p" className="ing-pack">{item["label"]}</span>];
        if not selectable { return <li key={item["key"]} className="ing-row muted">{body}</li>; }
        return <li key={item["key"]} className={"ing-row on" if on else "ing-row"}><label><input type="checkbox" checked={on} disabled={busy} onChange={lambda e: ChangeEvent { toggle(item["key"]); }} />{body}</label></li>;
    }

    if not draft { return <dialog id="recipe-sheet" className="recipe-sheet"></dialog>; }
    groups = draft["groups"];
    keys = [r["key"] for r in groups["to_buy"].concat(groups["at_home"]) if chosen.get(r["key"], False)];
    room = recipes["limit"] - recipes["list_size"];
    too_many = len(keys) > room;
    return <dialog id="recipe-sheet" className="recipe-sheet" aria-labelledby="recipe-title" onClose={lambda e: any { close(); }}>
        <div className="sheet-pic">
            <img src={draft["image"] or DISH_FALLBACK} alt={draft["name"]} referrerPolicy="no-referrer" onError={lambda e: any { fallback(e, DISH_FALLBACK); }} />
            <button type="button" className="sheet-close" aria-label="Close recipe" onClick={lambda e: MouseEvent { close(); }}>✕</button>
        </div>
        <div className="sheet-body">
            <h2 id="recipe-title">{draft["name"]}</h2>
            <p className="sheet-meta">{[x for x in [draft["category"], draft["area"]] if x].join(" · ")} · <a href={draft["source"]} target="_blank" rel="noreferrer">Full recipe ↗</a></p>
            <div className="servings">
                <div><b>Servings</b><small>{"Recipe serves about " + str(draft["base_servings"]) + " (estimated)"}</small></div>
                <div className="stepper">
                    <button type="button" aria-label="Fewer servings" disabled={busy or draft["servings"] <= 1} onClick={lambda e: MouseEvent { operate("recipe_servings", {"servings": draft["servings"] - 1}); }}>−</button>
                    <output aria-live="polite">{draft["servings"]}</output>
                    <button type="button" aria-label="More servings" disabled={busy or draft["servings"] >= 12} onClick={lambda e: MouseEvent { operate("recipe_servings", {"servings": draft["servings"] + 1}); }}>+</button>
                </div>
            </div>
            <h3 className="ing-group">{"To buy · " + str(len(groups["to_buy"]))}</h3>
            {if len(groups["to_buy"]) == 0 { <p className="recipe-note">Everything this recipe needs is on your list or probably at home.</p> }}
            <ul className="ing-list">{[row(item, True, "") for item in groups["to_buy"]]}</ul>
            {if len(groups["on_list"]) > 0 {
                <p className="ing-fold"><b>Already on your list</b>{" · " + [r["name"] + " (" + r["amount"] + ")" for r in groups["on_list"]].join(", ")}</p>
            }}
            {if len(groups["at_home"]) > 0 {
                <details className="ing-more" open={more} onToggle={lambda e: any { more = e.target.open; }}>
                    <summary><b>Probably at home</b>{" · " + str(len(groups["at_home"])) + " · tap to add any you need"}</summary>
                    <ul className="ing-list">{[row(item, True, item["why"] + " · " + item["amount"]) for item in groups["at_home"]]}</ul>
                </details>
            }}
            {if len(groups["unavailable"]) > 0 {
                <p className="ing-fold"><b>Not in demo data</b>{" · " + [r["name"] for r in groups["unavailable"]].join(", ")}</p>
            }}
        </div>
        <div className="sheet-footer">
            {if too_many { <p className="recipe-note">{"Your list holds " + str(recipes["limit"]) + " items. You can add " + str(Math.max(room, 0)) + " more."}</p> }}
            <button type="button" className="go sheet-add" disabled={busy or len(keys) == 0 or too_many} onClick={lambda e: MouseEvent { operate("recipe_add", {"items": keys}); }}>{"Add " + str(len(keys)) + (" item" if len(keys) == 1 else " items") + " to my list"}</button>
            <p className="recipe-credit">Recipe and photos: <a href="https://www.themealdb.com/" target="_blank" rel="noreferrer">TheMealDB</a></p>
        </div>
    </dialog>;
}

def:pub RecipeToast(recipes: dict, busy: bool, operate: any) -> JsxElement {
    has seen: str = "", primed: bool = False, visible: bool = False;
    last = recipes.get("last_add", {}) or {};

    # Show for ten seconds after each add; Undo removes only what that add created.
    can with (last.get("at", "")) entry {
        stamp = last.get("at", "");
        # The first render records what was already there; only later adds show the toast.
        if not primed { primed = True; seen = stamp; return; }
        if stamp == "" { visible = False; seen = ""; return; }
        if stamp != seen {
            seen = stamp; visible = True;
            timer = setTimeout(lambda { visible = False; }, 10000);
            return lambda { clearTimeout(timer); };
        }
    }

    if not visible or not last.get("dish", "") { return <span></span>; }
    # The shopping panel is a size container, which would pin a fixed toast to the
    # panel instead of the screen; render it on the body instead.
    return createPortal(<div className="recipe-toast" role="status">
        <span>{"✓ Added " + str(len(last.get("added", []))) + " items for " + last["dish"]}</span>
        <button type="button" disabled={busy} onClick={lambda e: MouseEvent { visible = False; operate("recipe_undo", {}); }}>Undo</button>
    </div>, document.body);
}
