"""Recipe rules: dish recommendations from the shopping list, servings scaling,
package estimates and which ingredients to suggest buying.

Pure functions over data from integrations/mealdb.jac. Nothing here adds to the
list: the panel saves only the ingredients the user selects.
"""
import math;
import re;
import from fractions { Fraction }

glob DEFAULT_SERVINGS: int = 4,
     MAX_SERVINGS: int = 12,
     MAX_PACKAGES: int = 20,
     # Ingredients most kitchens already have. Exact names only: "red pepper" is produce.
     PANTRY: list[str] = ["salt", "pepper", "black pepper", "ground black pepper", "olive oil", "vegetable oil",
                          "sunflower oil", "oil", "sugar", "caster sugar", "granulated sugar", "brown sugar",
                          "water", "flour", "plain flour", "all purpose flour", "baking powder", "baking soda",
                          "bicarbonate of soda", "vinegar", "garlic", "garlic clove"],
     OPTIONAL_WORDS: list[str] = ["garnish", "to serve", "optional", "to taste"],
     UNITS: dict[str, str] = {"g": "g", "gram": "g", "grams": "g", "kg": "kg", "ml": "ml", "l": "l", "litre": "l", "liter": "l",
                              "tbs": "tbsp", "tbsp": "tbsp", "tblsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp",
                              "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp", "cup": "cup", "cups": "cup",
                              "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb", "oz": "oz", "ounce": "oz", "ounces": "oz",
                              "clove": "clove", "cloves": "clove", "pinch": "pinch", "can": "can", "cans": "can", "tin": "can",
                              "bunch": "bunch", "handful": "handful", "slice": "slice", "slices": "slice"},
     CATEGORY_CHIPS: list[str] = ["Chicken", "Vegetarian", "Pasta", "Seafood", "Breakfast", "Dessert"];

def norm(name: str) -> str {
    text = re.sub(r"\s+", " ", str(name).casefold().strip());
    return text[:-1] if text.endswith("s") and not text.endswith("ss") else text;
}

"""Amount and unit from a free-text measure like "800g", "1 1/2 cups" or "2 chopped"."""
def parse_measure(text: str) -> dict {
    raw = str(text or "").strip();
    hit = re.match(r"^\s*(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s*([A-Za-z]+)?", raw);
    if not hit { return {"amount": None, "unit": "", "note": raw.casefold()}; }
    amount = float(sum([Fraction(part) for part in hit.group(1).split()]));
    word = (hit.group(2) or "").casefold();
    unit = UNITS.get(word, "piece");
    note = raw[hit.end():].strip() if word in UNITS or not word else raw[hit.end(1):].strip();
    return {"amount": amount, "unit": unit, "note": note.casefold()};
}

def fmt(amount: float) -> str {
    return str(int(amount)) if amount == int(amount) else f"{amount:.1f}".rstrip("0").rstrip(".");
}

"""Whole packages to buy. Small amounts (spoons, cloves) are one package; counted
items are bought by count; weights and volumes round up to common sizes."""
def packages(name: str, amount: any, unit: str) -> dict {
    key = norm(name);
    if amount is None { return {"qty": 1, "label": "1 package"}; }
    if key == "egg" and unit == "piece" {
        qty = max(1, math.ceil(amount / 12));
        return {"qty": qty, "label": f"{qty} dozen"};
    }
    grams = {"g": 1, "kg": 1000, "lb": 453.6, "oz": 28.35}.get(unit);
    if grams {
        qty = max(1, math.ceil(amount * grams / 454));
        return {"qty": min(qty, MAX_PACKAGES), "label": f"{qty} × 1 lb" if qty > 1 else "1 package"};
    }
    if unit in ["ml", "l"] {
        ml = amount * (1000 if unit == "l" else 1);
        size = 3785 if key == "milk" else 1000;
        qty = max(1, math.ceil(ml / size));
        return {"qty": min(qty, MAX_PACKAGES), "label": f"{qty} {'gal' if key == 'milk' else 'L'}"};
    }
    if unit in ["piece", "can", "bunch", "slice"] {
        qty = max(1, math.ceil(amount));
        return {"qty": min(qty, MAX_PACKAGES), "label": str(min(qty, MAX_PACKAGES))};
    }
    return {"qty": 1, "label": "1 package"};
}

def servings_value(value: any) -> int {
    try { number = int(value); }
    except (TypeError, ValueError) { raise ValueError("Choose 1 to 12 servings."); }
    if not 1 <= number <= MAX_SERVINGS { raise ValueError("Choose 1 to 12 servings."); }
    return number;
}

"""A recipe draft at a serving count. TheMealDB gives no serving size, so the
recipe is assumed to serve DEFAULT_SERVINGS and the view says it is estimated."""
def make_draft(recipe: dict, servings: int) -> dict {
    rows = [];
    for row in recipe["ingredients"] {
        parsed = parse_measure(row["measure"]);
        lowered = (row["measure"] + " " + parsed["note"]).casefold();
        entry = row | parsed | {"key": norm(row["name"]), "pantry": norm(row["name"]) in [norm(x) for x in PANTRY],
                                "optional": any([w in lowered for w in OPTIONAL_WORDS])};
        # Recipes can list one ingredient twice (fresh and ground coriander): keep one row.
        same = [r for r in rows if r["key"] == entry["key"]];
        if not same { rows.append(entry); continue; }
        first = same[0];
        if first["amount"] is not None and entry["amount"] is not None and first["unit"] == entry["unit"] {
            first["amount"] = first["amount"] + entry["amount"];
        } else {
            first["note"] = (first["note"] + " + " if first["note"] else "") + (entry["measure"] or "as needed").casefold();
        }
        first["optional"] = first["optional"] and entry["optional"];
    }
    return recipe | {"ingredients": rows, "base_servings": DEFAULT_SERVINGS, "servings": servings_value(servings)};
}

"""Group a draft's ingredients against the current list. Recomputed on every view,
so it follows list changes without another recipe lookup."""
def draft_view(draft: dict, list_items: list, demo_categories: any) -> dict {
    on_list = {norm(x): x for x in list_items};
    demo = None if demo_categories is None else [norm(c) for c in demo_categories];
    factor = draft["servings"] / draft["base_servings"];
    groups = {"to_buy": [], "on_list": [], "at_home": [], "unavailable": []};
    for row in draft["ingredients"] {
        amount = None if row["amount"] is None else row["amount"] * factor;
        shown = (fmt(amount) + ("" if row["unit"] == "piece" else " " + row["unit"]) + (" · " + row["note"] if row["note"] else "")) if amount is not None else (row["note"] or row["measure"] or "As needed");
        item = {"key": row["key"], "name": row["name"].casefold(), "image": row["image"], "amount": shown}
               | packages(row["name"], amount, row["unit"]);
        if row["key"] in on_list {
            groups["on_list"].append(item | {"list_name": on_list[row["key"]]});
        } elif demo is not None and row["key"] not in demo {
            groups["unavailable"].append(item);
        } elif row["pantry"] or row["optional"] {
            groups["at_home"].append(item | {"why": "Optional" if row["optional"] else "Pantry staple"});
        } else {
            groups["to_buy"].append(item);
        }
    }
    return {k: draft[k] for k in ["id", "name", "image", "category", "area", "source", "servings", "base_servings"]}
           | {"groups": groups, "estimated_servings": True};
}

"""Validated selections become list specs. Only to-buy and at-home rows can be chosen."""
def selection(view: dict, chosen: list, list_size: int, limit: int) -> list {
    allowed = {row["key"]: row for row in (view["groups"]["to_buy"] + view["groups"]["at_home"])};
    picked = [];
    for key in chosen {
        if key not in allowed { raise ValueError("That ingredient can no longer be added. Reopen the recipe."); }
        if key not in [p["key"] for p in picked] { picked.append(allowed[key]); }
    }
    if not picked { raise ValueError("Choose at least one ingredient."); }
    room = limit - list_size;
    if len(picked) > room {
        raise ValueError(f"Your list holds at most {limit} items, so you can add {max(room, 0)} more. Deselect some ingredients.");
    }
    return [{"key": p["key"], "category": p["name"], "qty": p["qty"]} for p in picked];
}

"""Rank dishes by how many list items they use; ties by name. `lookup` maps an
ingredient to dish summaries; `allowed` (ids) applies a dietary category."""
def rank_dishes(list_items: list, lookup: any, allowed: any, limit: int = 7) -> list {
    scores: dict = {};
    for item in list_items {
        for dish in lookup(item) {
            if allowed is not None and dish["id"] not in allowed { continue; }
            entry = scores.get(dish["id"], dish | {"uses": []});
            if item not in entry["uses"] { entry["uses"] = entry["uses"] + [item]; }
            scores[dish["id"]] = entry;
        }
    }
    return sorted(list(scores.values()), key=lambda d: dict: (-len(d["uses"]), d["name"]))[:limit];
}

def missing_count(recipe: dict, list_items: list) -> int {
    have = [norm(x) for x in list_items];
    return len([r for r in recipe["ingredients"] if norm(r["name"]) not in have and norm(r["name"]) not in [norm(x) for x in PANTRY]]);
}

def list_signature(list_items: list, dietary: list) -> str {
    return "|".join(sorted([norm(x) for x in list_items])) + "#" + ",".join(sorted(dietary));
}
