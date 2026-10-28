# Real-address store visits

Real stores supports address confirmation, nearby-store discovery, shopping-list evidence matching, route/time checks, ranked single-store alternatives, acceptance/cancellation, and per-item purchase outcomes. Product evidence comes only from Open Prices. Geoapify supplies geocoding, places and routes. Structured controls do not invoke an LLM or require Kroger credentials.

## Local demonstration

```bash
cd /home/yuan-epic/EECS_449_Term_project/eecs449
source .venv/bin/activate
jac start main.jac
```

Open http://localhost:8000. Restart an already-running server after updating code.

1. Select **Real stores**. Use **Use my current location** (browser permission required), or enter an address and click **Look up address**. Review the result and click **Use this address**. Device location retains the reported coordinates and displays accuracy; denied/unavailable location falls back to typed addresses. Browser geolocation requires localhost or HTTPS.
2. Expand **Your shopping profile**. For the public demonstration use budget `50`, carrying limit `6`, maximum walking minutes `45`, transport `WALK`, and free time `SAT 14:00-17:00`. Save the profile.
3. Save `rice` and `milk` as **Need**, one package each. Use English product categories; the assistant normalizes conversational input.
4. In **Real-store shopping visits**, choose a radius and click **Recommend stores for my list**. The public address `150 E McKinley Avenue, Sunnyvale, CA 94086` with a 1 km radius has verified contributed data. Other locations may have little or no coverage.
5. Review store address, matching products, observation dates, proof links, suggested weekly window, round-trip duration, warnings, and directions. Each option visits one store. Weekly availability is resolved to a dated trip in the confirmed address timezone (or an explicitly labeled configured-timezone fallback). Supported regular opening hours constrain arrival and the 20-minute store visit; holiday/complex schedules remain unverified.
6. Acknowledge unknown current prices, stock and opening hours, then **Accept store visit**. Enter **Packages bought** (including a partial quantity) and optionally **Actual amount paid**, then **Record purchase**; alternatively choose **Not found at visit** or **Skip this item**. Full purchases update the normal need/replenishment workflow; partial purchases reduce the active quantity while retaining brand/size, and missing/skipped items stay needed. After completing the visit, **Plan remaining shopping needs** generates another set of options. Reporting absence does not create a global out-of-stock assertion. Reloading preserves the visit.
7. If needs, address or constraints change, cancel/rebuild the old visit. Expired routes prevent new acceptance; an already accepted visit can still report outcomes if its inputs have not changed.

## Evidence and ranking

The search checks at most six nearby stores, first considering up to four locations linked to Open Prices; it returns up to three alternatives. Each historical lookup checks two recent pages of 20 records, plus one page for each of up to six recognized food categories. This is bounded coverage, not a complete assortment search. Category, brand, size and available diet labels constrain matches; derivative/plant-milk false positives are excluded for plain milk. A suggested product still requires user suitability confirmation.

Ranking prioritizes route/time/carry eligibility, then number of needs with historical matches, then travel duration and distance. Walking limits, saved free-time windows and known excessive carrying weight can prevent acceptance. Missing product weights remain unknown. Walking, cycling and driving are supported; transit and rideshare estimates remain unsupported. Geoapify route estimates expire and are not traffic or opening-hours guarantees.

For barcode `PRODUCT` observations, Open Prices leaves `price_per` null; the recorded price is treated as a product-unit price, while the raw field is retained. See the [upstream data rules](https://github.com/openfoodfacts/open-prices/discussions/319). Unknown/non-package units, discounted records and non-USD prices are excluded from reference subtotals. USD references use the latest matching observation per need and exclude tax, fees and transport. They cannot prove today's budget feasibility and are not used as current `Offer` objects. Current inventory and prices remain unknown. Geoapify/OpenStreetMap regular opening hours are checked only when supported; this is not confirmation of holiday hours or unexpected closures.

There is no multi-store route optimization, checkout, delivery pricing, background monitoring, or real-time inventory in this workflow. Location-only stores remain useful visit candidates with explicit missing evidence. Historical product availability never becomes a stock promise.

## Verification

```bash
python -m unittest discover -s tests -p 'test_*.py'
jac test
jac build main.jac
# Actual provider requests, no model calls, fixed public address:
python scripts/verify_store_visits.py --output /tmp/store-visits.json
```

89 Jac tests and 48 Python tests pass; the client builds successfully. Tests cover source/location isolation, future records, ambiguous units, false matches, route failure, constraints, explicit acceptance, changes/expiry, duplicate feedback and need updates. The real HTTP probe returned route-eligible Whole Foods Market, Target and Trader Joe's options; Whole Foods matched rice and dairy milk. Evidence is in [samples/store-visits-verification.json](samples/store-visits-verification.json). Live responses and rankings can change.

Data attribution: Open Prices / Open Food Facts (ODbL); map and route data: Geoapify / OpenStreetMap. Addresses are sent to Geoapify, coordinates are used for nearby searches, and selected results are saved in the local workspace. Never put private addresses or credentials in verification artifacts.

Browser acceptance used a separate temporary graph: permitted device location and typed address confirmation, three real-store options, required acknowledgment, acceptance, rice purchase, milk not-found feedback, persistence after reload, and denied-location fallback all passed. The final browser check had no page exceptions. User shopping data was not modified by these checks.

## Conversational setup

With **Real stores** selected, you can complete setup entirely in chat:

1. “Make a shopping plan for two packages of rice.” — needs save immediately; missing starting address is requested.
2. Supply your address and any preferences, such as budget, walking limit and transport. They appear in the profile automatically. If geocoding returns several possible places, reply “the first address” or the appropriate number.
3. When asked for free time, reply naturally, for example “Saturday from 2 pm to 5 pm.” The saved field becomes `SAT 14:00-17:00`.
4. The planner runs as soon as the required information is present. Chat shows stores, requested quantities, travel/time estimates, historical evidence coverage and any blocking constraints; the panel shows detailed cards. No **Confirm changes** click is needed for setup.

The application never changes BUS-only to walking silently. Saved default limits (15 minutes walking, 6 kg carrying) remain until changed. Historical pricing can be unknown; a real-mode budget is optional, with clear unknown-cost warnings. A new shopping need stated in chat is treated as **Need**, including an item previously tracked as **Watch**. Saying “stop planning” pauses questions without cancelling accepted visits. Purchases and accepting a visit remain explicit actions.

The current question and collected fields persist server-side, so short replies still have context after page reload. The latest 40 conversation turns are stored in the workspace and restored after reload. **Clear chat history** removes that transcript without clearing saved needs, the current question or plans. Ordinary profile updates outside an active planning conversation save without launching a new provider search.


## Reliability improvements (2026-10-26)

- Quantity-only chat updates preserve brand/size; brand-only updates preserve quantity/size. Explicit empty brand/size removes that constraint. Changing a specification revokes earlier product-match confirmations; quantity-only edits preserve them.
- New `planning/schedule.jac` resolves weekly availability over today plus seven days, selects the earliest fitting slot, and records departure/arrival/store departure/return with timezone offsets. Planning allows a five-minute preparation buffer after provider work completes. Passed departure times block new acceptance.
- Geoapify search metadata is retained when deduplicating an exact OpenStreetMap branch. Selected-place detail lookups are bounded to the existing maximum six candidates and cached. Different place IDs may identify the same exact OSM object; name similarity never links hours or prices.
- Supported opening-hours syntax: `24/7`, closed, weekday groups/ranges, and same-day intervals including split hours. Holiday/seasonal/overnight/overlapping rules remain unknown; no clauses are silently dropped. Ambiguous/nonexistent DST boundary times are not guessed. A regular-hours match is not a guarantee that a store will actually open.
- Per-item reported spending is user-entered USD, separate from historical prices. Totals explicitly exclude unreported amounts and transport. This is not a weekly spending ledger. Each item's outcome is final once submitted; identical retries are safe, conflicting retries are rejected.
- A partial purchase finalizes that item's outcome for this visit; its remaining quantity stays active for a subsequent visit. It does not claim the retailer was out of stock or modify provider observations.

See [verification and remaining milestones](PRODUCT_GAPS.md). Optional real-model partial-update check (two requests):

```bash
python scripts/verify_partial_updates.py --output /tmp/partial-updates.json
```

## Start a separate shopping trip

Use **New shopping plan** above the shopping workspace. It starts an empty list and a fresh conversation without requiring a model call. Your confirmed address, budget, transport, weekly availability and dietary preferences remain saved. Old NEED/REPLENISH items are paused and moved under **Previous shopping needs**, where **Restore to current list** explicitly carries an item over. Watch interests remain unchanged.

Unfinished plans are cancelled so an old accepted visit cannot block the next trip. Accepted/completed real visits and their purchase outcomes remain under **Previous visits and purchases**. New quantities, brands and sizes do not inherit the previous trip's item specifications unless you explicitly restore the old item. If you add that category afresh, its old saved-need row is reused; purchase snapshots remain separate.

**Clear chat history** only clears messages. **Recommend stores for my list** replans the current list. Neither starts an empty shopping list. After starting a new plan, simply reply in chat with this trip's items; saved profile fields are reused and missing information is requested normally.
