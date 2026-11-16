"""Recipe rules and panel operations. TheMealDB is replaced with fixtures; no network."""
import os;
import re;
import from app_settings { get_settings }
import tempfile;
import from unittest.mock { patch }
import from models.profile { UserProfile }
import from models.interest { InterestPool }
import from models.graph { Owns }
import from server.shopping { shopping_operation }
import from integrations.providers { ProviderError }
import from integrations.mealdb { meal_image, ingredient_image }
import from planning.recipes { parse_measure, packages, make_draft, draft_view, selection, rank_dishes }

glob NOW: str = "2026-11-14T10:00:00-05:00",
     SHAKSHUKA: dict = {"id": "52963", "name": "Shakshuka", "image": "https://www.themealdb.com/images/media/meals/g373701551450225.jpg/medium",
        "thumb": "", "category": "Vegetarian", "area": "Egyptian", "source": "https://www.themealdb.com/meal/52963",
        "ingredients": [{"name": "Olive Oil", "measure": "1 tbs", "image": ""}, {"name": "Red Onions", "measure": "2 chopped", "image": ""},
                        {"name": "Cherry Tomatoes", "measure": "800g", "image": ""}, {"name": "Eggs", "measure": "4", "image": ""},
                        {"name": "Coriander", "measure": "Chopped, to garnish", "image": ""}, {"name": "Feta", "measure": "Spinkling", "image": ""}]},
     DISHES: dict = {"eggs": [{"id": "1", "name": "Kedgeree"}, {"id": "2", "name": "Pancakes"}],
                     "milk": [{"id": "1", "name": "Kedgeree"}, {"id": "2", "name": "Pancakes"}],
                     "rice": [{"id": "1", "name": "Kedgeree"}, {"id": "3", "name": "Congee"}]};

def shopper(items: list = ["eggs", "rice"]) -> UserProfile {
    p = UserProfile(data_mode="live", transport=["WALK"], free_windows=["SAT 14:00-17:00"], weekly_budget=80);
    p +>:Owns:+> InterestPool();
    for name in items { shopping_operation(p, "save_interest", {"category": name, "qty": 1}, NOW); }
    return p;
}

def dishes_for(name: str) -> list {
    return [d | {"image": "", "thumb": ""} for d in DISHES.get(name, [])];
}

def fails(f: any) -> bool {
    try { f(); } except ValueError { return True; }
    return False;
}

test "measures parse into amounts and units" {
    assert parse_measure("800g") == {"amount": 800.0, "unit": "g", "note": ""};
    assert parse_measure("1 1/2 cups")["amount"] == 1.5 and parse_measure("1 1/2 cups")["unit"] == "cup";
    assert parse_measure("2 chopped") == {"amount": 2.0, "unit": "piece", "note": "chopped"};
    assert parse_measure("Chopped")["amount"] is None;
}

test "packages round up to whole units" {
    assert packages("Eggs", 6.0, "piece")["qty"] == 1 and packages("Eggs", 13.0, "piece")["qty"] == 2;
    assert packages("Cherry Tomatoes", 1200.0, "g")["qty"] == 3;
    assert packages("Milk", 500.0, "ml")["label"] == "1 gal";
    assert packages("Olive Oil", 1.0, "tbsp")["qty"] == 1;
    assert packages("Red Onions", 250.0, "piece")["qty"] == 20;
}

test "scaling and grouping follow the current list" {
    view = draft_view(make_draft(SHAKSHUKA, 6), ["eggs", "rice"], None);
    to_buy = {r["key"]: r for r in view["groups"]["to_buy"]};
    assert sorted(to_buy) == ["cherry tomatoe", "feta", "red onion"];
    assert to_buy["red onion"]["amount"] == "3 · chopped" and to_buy["cherry tomatoe"]["qty"] == 3;
    assert [r["key"] for r in view["groups"]["on_list"]] == ["egg"];
    assert sorted([r["key"] for r in view["groups"]["at_home"]]) == ["coriander", "olive oil"];
    demo = draft_view(make_draft(SHAKSHUKA, 4), [], ["eggs", "milk"]);
    assert [r["key"] for r in demo["groups"]["to_buy"]] == ["egg"] and len(demo["groups"]["unavailable"]) == 5;
    assert fails(lambda: make_draft(SHAKSHUKA, 13));
}

test "selection respects allowed rows and the list limit" {
    view = draft_view(make_draft(SHAKSHUKA, 4), ["eggs"], None);
    assert [s["category"] for s in selection(view, ["feta", "olive oil"], 1, 15)] == ["feta", "olive oil"];
    assert fails(lambda: selection(view, ["egg"], 1, 15));
    assert fails(lambda: selection(view, [], 1, 15));
    assert fails(lambda: selection(view, ["feta", "red onion"], 14, 15));
}

test "dishes rank by how many list items they use" {
    ranked = rank_dishes(["eggs", "milk", "rice"], dishes_for, None);
    assert [(d["name"], len(d["uses"])) for d in ranked] == [("Kedgeree", 3), ("Pancakes", 2), ("Congee", 1)];
    assert [d["name"] for d in rank_dishes(["eggs", "rice"], dishes_for, {"3"})] == ["Congee"];
}

test "image URLs come only from TheMealDB" {
    assert meal_image("https://www.themealdb.com/images/media/meals/abc123.jpg", "small").endswith("abc123.jpg/small");
    assert meal_image("https://evil.example/x.jpg") == "" and meal_image("javascript:alert(1)") == "";
    assert ingredient_image("Red Onions") == "https://www.themealdb.com/images/ingredients/Red_Onions-small.png";
}

test "feed ranks list dishes and falls back when the API fails" {
    p = shopper(["eggs", "rice"]);
    assert shopping_operation(p, "view", {}, NOW)["recipes"]["stale"];
    with patch("server.recipes.by_ingredient", side_effect=dishes_for), patch("server.recipes.lookup", return_value=SHAKSHUKA) {
        out = shopping_operation(p, "recipe_feed", {}, NOW)["recipes"];
    }
    assert [d["name"] for d in out["feed"]["dishes"]][:1] == ["Kedgeree"] and out["feed"]["hero"]["missing"] == 4;
    assert not out["stale"];
    with patch("server.recipes.by_category", side_effect=ProviderError("timed out")) {
        out = shopping_operation(p, "recipe_feed", {"category": "Chicken"}, NOW)["recipes"];
    }
    assert out["feed"]["error"] != "" and out["feed"]["label"] == "Popular dishes" and len(out["feed"]["dishes"]) == 8;
    assert fails(lambda: shopping_operation(p, "recipe_feed", {"category": "Unknown"}, NOW));
}

test "open, scale, add with links, and undo only what was added" {
    p = shopper(["eggs", "rice"]);
    with patch("server.recipes.lookup", return_value=SHAKSHUKA) {
        shopping_operation(p, "recipe_open", {"id": "52963", "servings": 4}, NOW);
    }
    out = shopping_operation(p, "recipe_servings", {"servings": 6}, NOW)["recipes"];
    assert out["draft"]["servings"] == 6 and len(out["draft"]["groups"]["to_buy"]) == 3;
    out = shopping_operation(p, "recipe_add", {"items": ["cherry tomatoe", "feta"]}, NOW);
    assert out["message"] == "Added 2 ingredients for Shakshuka.";
    names = {i["category"]: i["qty"] for i in out["interests"] if i["status"] == "ACTIVE"};
    assert names == {"eggs": 1, "rice": 1, "cherry tomatoes": 3, "feta": 1};
    assert out["recipes"]["links"] == {"cherry tomatoes": "Shakshuka", "feta": "Shakshuka"} and out["recipes"]["draft"] is None;
    out = shopping_operation(p, "recipe_undo", {}, NOW);
    assert sorted([i["category"] for i in out["interests"] if i["status"] == "ACTIVE"]) == ["eggs", "rice"];
    assert out["recipes"]["links"] == {} and fails(lambda: shopping_operation(p, "recipe_undo", {}, NOW));
}

test "the list limit is configurable and enforced for recipes" {
    p = shopper(["eggs"]);
    with patch("server.recipes.lookup", return_value=SHAKSHUKA) {
        shopping_operation(p, "recipe_open", {"id": "52963"}, NOW);
    }
    folder = tempfile.mkdtemp();
    path = os.path.join(folder, "app.toml");
    with open(path, "w") as f { f.write(re.sub(r"(?m)^max_active_needs = \d+$", "max_active_needs = 2", open("app.toml").read())); }
    with patch.dict("os.environ", {"CARTCOMPASS_SETTINGS": path}) {
        assert fails(lambda: shopping_operation(p, "recipe_add", {"items": ["feta", "red onion"]}, NOW));
        assert shopping_operation(p, "recipe_add", {"items": ["feta"]}, NOW)["recipes"]["list_size"] == 2;
        assert fails(lambda: shopping_operation(p, "save_interest", {"category": "rice", "qty": 1}, NOW));
    }
    assert shopping_operation(p, "save_interest", {"category": "rice", "qty": 1}, NOW)["recipes"]["limit"] == get_settings()["max_active_needs"];
}

def recipe_intent(dish: str, servings: int) -> dict {
    return {"intent": "recipe", "dish": dish, "servings": servings, "profile": {}, "needs": [], "address": "", "question": "", "store_id": ""};
}

test "the assistant opens a recipe for review without adding anything" {
    import from harness.agent { handle_request }
    p = shopper(["eggs"]);
    with patch("harness.agent.parse_request", return_value=recipe_intent("shakshuka", 6)),
         patch("server.recipes.search", return_value=[{"id": "52963", "name": "Shakshuka"}]),
         patch("server.recipes.lookup", return_value=SHAKSHUKA) {
        reply = handle_request(p, "I want to cook shakshuka for 6", []);
    }
    assert reply.startswith("Here is Shakshuka for 6 servings. I suggest buying 3 ingredients; 1 already on your list.");
    out = shopping_operation(p, "view", {}, NOW);
    assert out["recipes"]["draft"]["name"] == "Shakshuka" and [i["category"] for i in out["interests"]] == ["eggs"];
    with patch("harness.agent.parse_request", return_value=recipe_intent("unknown dish", 2)), patch("server.recipes.search", return_value=[]) {
        assert fails(lambda: handle_request(p, "cook unknown dish", []));
    }
}

test "recipe intents are validated" {
    import from ai.intents { validate_intent }
    ok = validate_intent({"intent": "recipe", "dish": "chicken curry", "servings": 2});
    assert ok["dish"] == "chicken curry" and ok["servings"] == 2;
    assert validate_intent({"intent": "recipe", "dish": "pancakes"})["servings"] == 4;
    assert fails(lambda: validate_intent({"intent": "recipe", "dish": "curry", "servings": 20}));
    assert fails(lambda: validate_intent({"intent": "recipe", "dish": ""}));
    assert fails(lambda: validate_intent({"intent": "recipe", "dish": "番茄炒蛋"}));
}

test "an ingredient listed twice becomes one row" {
    recipe = SHAKSHUKA | {"ingredients": [{"name": "Coriander", "measure": "Handful", "image": ""}, {"name": "Coriander", "measure": "1 tsp", "image": ""},
                                          {"name": "Rice", "measure": "300g", "image": ""}, {"name": "rice", "measure": "200g", "image": ""}]};
    view = draft_view(make_draft(recipe, 4), [], None);
    rows = {r["key"]: r for r in view["groups"]["to_buy"]};
    assert sorted(rows) == ["coriander", "rice"] and len(view["groups"]["to_buy"]) == 2;
    assert rows["rice"]["amount"] == "500 g" and rows["rice"]["qty"] == 2;
    assert rows["coriander"]["amount"] == "handful + 1 tsp";
}
