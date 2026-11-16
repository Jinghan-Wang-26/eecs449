"""TheMealDB recipes and photos. Public recipe data only; no prices or stock.

Key: MEALDB_API_KEY in .env (default "1", the documented development and
education key). Images are only taken from URLs the API returns, so the page
never builds image paths from user text. Attribution: TheMealDB.
"""
import re;
import from urllib.parse { quote }
import from integrations.providers { credentials, request_json, cached, ProviderError }

glob SITE: str = "https://www.themealdb.com",
     MEAL_IMAGE: str = "https://www.themealdb.com/images/media/meals/",
     DAY: int = 86400;

def api_key -> str {
    key = str(credentials().get("MEALDB_API_KEY", "") or "1").strip();
    if not re.fullmatch(r"[A-Za-z0-9]{1,40}", key) { raise ProviderError("MEALDB_API_KEY has an invalid format."); }
    return key;
}

def get(endpoint: str, params: dict) -> list {
    url = f"{SITE}/api/json/v1/{api_key()}/{endpoint}";
    data = cached("mealdb", [endpoint, params], lambda() : request_json(url, params=params, timeout=10), DAY);
    meals = data.get("meals") if isinstance(data, dict) else None;
    return meals if isinstance(meals, list) else [];
}

"""Thumbnail at a documented size, or "" when the API sent an unexpected URL."""
def meal_image(url: any, size: str = "medium") -> str {
    text = str(url or "");
    if not re.fullmatch(r"https://www\.themealdb\.com/images/media/meals/[A-Za-z0-9_.-]+\.(jpg|png)", text) { return ""; }
    return text + "/" + size if size in ["small", "medium", "large"] else text;
}

def ingredient_image(name: str) -> str {
    clean = re.sub(r"[^A-Za-z0-9 ]", "", name).strip().replace(" ", "_");
    return f"{SITE}/images/ingredients/{quote(clean)}-small.png" if clean else "";
}

def summary(meal: dict) -> dict {
    return {"id": str(meal.get("idMeal", "")), "name": str(meal.get("strMeal", "")).strip(),
            "image": meal_image(meal.get("strMealThumb"), "medium"), "thumb": meal_image(meal.get("strMealThumb"), "small")};
}

def ingredient_query(name: str) -> str {
    return re.sub(r"[^a-z0-9]+", "_", name.casefold()).strip("_");
}

def by_ingredient(name: str) -> list {
    query = ingredient_query(name);
    return [summary(m) for m in get("filter.php", {"i": query})] if query else [];
}

def by_category(category: str) -> list {
    return [summary(m) for m in get("filter.php", {"c": category})];
}

def search(text: str) -> list {
    query = text.strip()[:60];
    return [summary(m) for m in get("search.php", {"s": query})] if query else [];
}

"""A full recipe: ingredients with their free-text measures, category and source link."""
def lookup(meal_id: str) -> dict {
    if not re.fullmatch(r"\d{1,8}", str(meal_id)) { raise ProviderError("Unknown recipe."); }
    found = get("lookup.php", {"i": meal_id});
    if not found { raise ProviderError("Recipe not found."); }
    meal = found[0];
    ingredients = [];
    for i in range(1, 21) {
        name = str(meal.get(f"strIngredient{i}") or "").strip();
        if name {
            ingredients.append({"name": name, "measure": str(meal.get(f"strMeasure{i}") or "").strip(), "image": ingredient_image(name)});
        }
    }
    return summary(meal) | {"category": str(meal.get("strCategory") or ""), "area": str(meal.get("strArea") or ""),
                            "ingredients": ingredients, "source": f"{SITE}/meal/{meal_id}"};
}
