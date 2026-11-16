"""Recipe panel operations: dish ideas, the open recipe, adding ingredients and undo.

Network lookups happen only in `recipe_feed` and `recipe_open`; the panel's
periodic view reads the stored results. Nothing is added to the list until the
user selects ingredients.
"""
import json;
import from pathlib { Path }
import from integrations.providers { ProviderError }
import from integrations.mealdb { by_ingredient, by_category, search, lookup }
import from planning.recipes { make_draft, draft_view, selection, rank_dishes, missing_count, list_signature, servings_value, CATEGORY_CHIPS }
import from models.profile { UserProfile }
import from models.events { ShoppingWorkspace }
import from models.interest { InterestStatus }
import from models.catalog { Product }
import from models.graph { Has, owned, items_of, catalog_of }
import from server.workflows { save_need, invalidate_plans, mode_of }

glob FEATURED: Path = Path(__file__).resolve().parent.parent / "data" / "recipes_featured.json",
     VEGETARIAN: list[str] = ["vegetarian", "vegan"];

def list_items(p: UserProfile) -> list {
    return [str(n.product_spec["type"]) for n in items_of(p) if n.plannable()];
}

def demo_categories(p: UserProfile) -> any {
    if mode_of(p) != "mock" { return None; }
    cat = catalog_of(p);
    return sorted({prod.category for prod in [cat ->:Has:->][?:Product]});
}

def vegetarian(p: UserProfile) -> bool {
    return any([str(d).casefold() in VEGETARIAN for d in p.dietary]);
}

def featured(p: UserProfile) -> list {
    dishes = json.loads(FEATURED.read_text())["dishes"];
    if vegetarian(p) { dishes = [d for d in dishes if d["category"] in ["Vegetarian", "Vegan", "Breakfast", "Dessert"]]; }
    return [d | {"uses": []} for d in dishes];
}

def safe_by_ingredient(name: str) -> list {
    try { return by_ingredient(name); }
    except ProviderError { return []; }
}

"""Dish ideas for the list, a category chip or a search. Falls back to the
featured dishes when the list is empty or TheMealDB is unavailable."""
def build_feed(p: UserProfile, data: dict, now: str) -> dict {
    items = list_items(p);
    query = str(data.get("query", "") or "").strip()[:60];
    category = str(data.get("category", "") or "");
    if category and category not in CATEGORY_CHIPS { raise ValueError("Unknown dish category."); }
    feed = {"signature": list_signature(items, list(p.dietary)), "query": query, "category": category,
            "dishes": [], "hero": None, "error": "", "updated_at": now};
    try {
        if query {
            feed["dishes"] = [d | {"uses": []} for d in search(query)][:12];
            feed["label"] = f'Results for "{query}"';
        } elif category {
            feed["dishes"] = [d | {"uses": []} for d in by_category(category)][:12];
            feed["label"] = category + " dishes";
        } elif items {
            allowed = {d["id"] for d in by_category("Vegetarian")} if vegetarian(p) else None;
            feed["dishes"] = rank_dishes(items, safe_by_ingredient, allowed, 8);
            feed["label"] = "Cook with what you're buying";
        }
    } except ProviderError as err {
        feed["error"] = "Dish ideas are unavailable right now (" + str(err) + "). Showing popular dishes.";
    }
    if not feed["dishes"] and not query {
        feed["dishes"] = featured(p);
        feed["label"] = "Popular dishes";
    }
    feed["label"] = feed.get("label") or "Popular dishes";
    if feed["dishes"] and feed["dishes"][0]["uses"] {
        hero = dict(feed["dishes"][0]);
        try { hero["missing"] = missing_count(lookup(hero["id"]), items); }
        except ProviderError { hero["missing"] = None; }
        feed["hero"] = hero;
    }
    return feed;
}

def recipe_operation(p: UserProfile, action: str, data: dict, now: str, cfg: dict) -> str {
    state = owned(p, ShoppingWorkspace);
    if action == "recipe_feed" {
        state.recipe_feed = build_feed(p, data, now);
        return "";
    }
    if action == "recipe_open" {
        try { recipe = lookup(str(data.get("id", ""))); }
        except ProviderError as err { raise ValueError("This recipe could not be loaded: " + str(err)); }
        state.recipe_draft = make_draft(recipe, data.get("servings", 4));
        return "";
    }
    if action == "recipe_find" {
        # The assistant names a dish; open the best TheMealDB match for review.
        query = str(data.get("query", "") or "").strip();
        try { found = search(query) if query else []; }
        except ProviderError as err { raise ValueError("Recipes are unavailable right now: " + str(err)); }
        if not found { raise ValueError(f'I could not find a recipe for "{query}". Try another name, or browse dish ideas on your list.'); }
        state.recipe_draft = make_draft(lookup(found[0]["id"]), data.get("servings", 4));
        return f"Opened {found[0]['name']} for {state.recipe_draft['servings']} servings.";
    }
    if action == "recipe_close" {
        state.recipe_draft = {};
        return "";
    }
    if not state.recipe_draft and action in ["recipe_servings", "recipe_add"] {
        raise ValueError("Open a recipe first.");
    }
    if action == "recipe_servings" {
        state.recipe_draft = state.recipe_draft | {"servings": servings_value(data.get("servings"))};
        return "";
    }
    if action == "recipe_add" {
        view = draft_view(state.recipe_draft, list_items(p), demo_categories(p));
        specs = selection(view, list(data.get("items", [])), len(list_items(p)), cfg["max_active_needs"]);
        before = set(list_items(p));
        for spec in specs { save_need(p, {"category": spec["category"], "qty": spec["qty"]}); }
        invalidate_plans(p, "Shopping needs changed.");
        added = [s["category"] for s in specs if s["category"] not in before];
        state.recipe_links = state.recipe_links | {s["category"]: view["name"] for s in specs};
        state.last_recipe_add = {"dish": view["name"], "added": added, "at": now};
        state.recipe_draft = {};
        state.recipe_feed = {};
        return f"Added {len(specs)} ingredient{'s' if len(specs) != 1 else ''} for {view['name']}.";
    }
    if action == "recipe_undo" {
        last = state.last_recipe_add;
        if not last { raise ValueError("Nothing to undo."); }
        for item in items_of(p) {
            if item.plannable() and item.product_spec.get("type") in last["added"] { item.status = InterestStatus.ARCHIVED; }
        }
        invalidate_plans(p, "Shopping needs changed.");
        state.recipe_links = {k: v for (k, v) in state.recipe_links.items() if k not in last["added"]};
        state.last_recipe_add = {};
        state.recipe_feed = {};
        return f"Removed the ingredients added for {last['dish']}.";
    }
    raise ValueError("Unknown recipe operation.");
}

"""What the panel shows. Reads stored state only; no network."""
def recipe_view(p: UserProfile, cfg: dict) -> dict {
    state = owned(p, ShoppingWorkspace);
    items = list_items(p);
    feed = state.recipe_feed;
    stale = not feed or (not feed.get("query") and not feed.get("category") and feed.get("signature") != list_signature(items, list(p.dietary)));
    return {"feed": feed, "stale": stale, "signature": list_signature(items, list(p.dietary)), "chips": CATEGORY_CHIPS,
            "draft": draft_view(state.recipe_draft, items, demo_categories(p)) if state.recipe_draft else None,
            "links": {k: v for (k, v) in state.recipe_links.items() if k in items},
            "last_add": state.last_recipe_add, "list_size": len(items), "limit": cfg["max_active_needs"],
            "attribution": {"name": "TheMealDB", "url": "https://www.themealdb.com/"}};
}
