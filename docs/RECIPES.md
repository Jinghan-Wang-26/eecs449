# Dish ideas and recipe ingredients

The **List** step shows dish ideas with photos. A shopper can open a recipe, choose servings, and add the ingredients they still need to the shopping list. Nothing is added until they press **Add**, and **Undo** removes what that add created.

## What the shopper sees

1. **Cook something** at the top of the List step:
   - a large **Cook tonight** photo for the dish that uses the most list items,
   - a row of dish cards, each saying which list items it uses,
   - a search box and category chips (Chicken, Vegetarian, Pasta, Seafood, Breakfast, Dessert).
   The section can be hidden; the choice is remembered in the browser.
2. **Recipe sheet** (a bottom sheet on phones, a dialog on desktop): photo, servings stepper, and ingredients grouped as
   - **To buy** (preselected),
   - **Already on your list**,
   - **Probably at home** (pantry staples and optional garnishes, not preselected),
   - **Not in demo data** (demo mode only; these cannot be added).
   Each row shows the scaled amount and an estimated package count. The button shows how many items will be added. If the list would exceed `max_active_needs`, the button is disabled and says how many more fit.
3. After adding, a toast offers **Undo** for ten seconds. List items show which dish they are for.
   Every list item shows an ingredient photo with its package count; items without a TheMealDB image (for example laundry detergent) show a local illustration.
4. In the assistant, "I want to cook shakshuka for 6" opens the same sheet. The assistant never adds ingredients by itself.

## How it works

| Part | File |
|---|---|
| TheMealDB lookups, image URL checks, 24-hour cache | `integrations/mealdb.jac` |
| Measure parsing, scaling, package estimates, grouping, ranking, limit check | `planning/recipes.jac` |
| Panel actions `recipe_feed`, `recipe_open`, `recipe_find`, `recipe_servings`, `recipe_add`, `recipe_undo`, `recipe_close` | `server/recipes.jac` |
| `recipe` chat intent (dish, servings) | `ai/intents.jac`, `harness/agent.jac` |
| UI | `ui/recipe.cl.jac`, styles in `ui/theme.cl.jac` |
| Fallback dishes when the list is empty or the API is down | `data/recipes_featured.json` |

- **Ranking:** each list item is looked up by ingredient; dishes are ranked by how many list items they use. Vegetarian and vegan profiles only see TheMealDB's Vegetarian category.
- **Network:** only `recipe_feed`, `recipe_open` and `recipe_find` call TheMealDB. The panel's periodic refresh reads stored results, and ideas are refreshed when the list changes.
- **Measures:** amounts are parsed by rules ("800g", "1 1/2 cups", "2 chopped"). Recipes are assumed to serve 4, and the sheet says the size is estimated. An ingredient listed twice is merged into one row.
- **Packages** are estimates: eggs by the dozen, weights in 1 lb packs, milk by the gallon, other liquids by the litre, counted produce by count, spoons and pinches as one package.
- **List limit:** `max_active_needs` in `app.toml` (default 15, allowed 1-30). It also bounds retailer lookups per store.

## Data source and terms

Recipes and photos come from [TheMealDB](https://www.themealdb.com/). The free development key `1` is documented for development and educational use; releasing an app publicly on an app store requires a paid supporter key. Set `MEALDB_API_KEY` in `.env` to use another key. The UI credits TheMealDB on the dish ideas and the recipe sheet.

Photos load directly from themealdb.com in the shopper's browser, with no referrer. Only image URLs returned by the API are used. If a photo fails to load, a local illustration is shown. The PWA service worker does not cache these images.

## Tests

```bash
jac test tests/test_recipes.jac
```

The tests replace TheMealDB with fixtures and cover measure parsing, package estimates, scaling and grouping, duplicate ingredients, selection and the list limit, ranking, image URL checks, API failure fallback, add with links, undo, the assistant flow and intent validation.
