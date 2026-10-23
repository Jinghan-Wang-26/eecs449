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
3. Save `rice` and `milk` as **Need**, one package each. Chinese aliases include 大米/米、牛奶、鸡蛋、咖啡、酸奶、豆腐.
4. In **Real-store shopping visits**, choose a radius and click **Recommend stores for my list**. The public address `150 E McKinley Avenue, Sunnyvale, CA 94086` with a 1 km radius has verified contributed data. Other locations may have little or no coverage.
5. Review store address, matching products, observation dates, proof links, suggested weekly window, round-trip duration, warnings, and directions. Each option visits one store. A window is a weekly template, not a booking or a check of store opening hours.
6. Acknowledge unknown current prices, stock and opening hours, then **Accept store visit**. Mark each item **Bought requested quantity**, **Not found at visit**, or **Skip this item**. Buying updates the normal need/replenishment workflow; missing/skipped items stay needed. Reporting absence does not create a global out-of-stock assertion. Reloading preserves the visit.
7. If needs, address or constraints change, cancel/rebuild the old visit. Expired routes prevent new acceptance; an already accepted visit can still report outcomes if its inputs have not changed.

## Evidence and ranking

The search checks at most six nearby stores, first considering up to four locations linked to Open Prices; it returns up to three alternatives. Each historical lookup checks two recent pages of 20 records, plus one page for each of up to six recognized food categories. This is bounded coverage, not a complete assortment search. Category, brand, size and available diet labels constrain matches; derivative/plant-milk false positives are excluded for plain milk. A suggested product still requires user suitability confirmation.

Ranking prioritizes route/time/carry eligibility, then number of needs with historical matches, then travel duration and distance. Walking limits, saved free-time windows and known excessive carrying weight can prevent acceptance. Missing product weights remain unknown. Walking, cycling and driving are supported; transit and rideshare estimates remain unsupported. Geoapify route estimates expire and are not traffic or opening-hours guarantees.

For barcode `PRODUCT` observations, Open Prices leaves `price_per` null; the recorded price is treated as a product-unit price, while the raw field is retained. See the [upstream data rules](https://github.com/openfoodfacts/open-prices/discussions/319). Unknown/non-package units, discounted records and non-USD prices are excluded from reference subtotals. USD references use the latest matching observation per need and exclude tax, fees and transport. They cannot prove today's budget feasibility and are not used as current `Offer` objects. Current inventory, current prices and store opening hours always remain unverified.

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

1. “帮我生成购物计划，我要买两包米。” — needs save immediately; missing starting address is requested.
2. Supply your address and any preferences, such as budget, walking limit and transport. They appear in the profile automatically. If geocoding returns several possible places, reply “第一个地址” or the appropriate number.
3. When asked for free time, reply naturally, for example “周六下午两点到五点。” The saved field becomes `SAT 14:00-17:00`.
4. The planner runs as soon as the required information is present. Chat shows stores, requested quantities, travel/time estimates, historical evidence coverage and any blocking constraints; the panel shows detailed cards. No **Confirm changes** click is needed for setup.

The application never changes BUS-only to walking silently. Saved default limits (15 minutes walking, 6 kg carrying) remain until changed. Historical pricing can be unknown; a real-mode budget is optional, with clear unknown-cost warnings. A new shopping need stated in chat is treated as **Need**, including an item previously tracked as **Watch**. Saying “stop planning” pauses questions without cancelling accepted visits. Purchases and accepting a visit remain explicit actions.

The current question and collected fields persist server-side, so short replies still have context after page reload. The visible chat transcript itself remains browser-session state. Ordinary profile updates outside an active planning conversation save without launching a new provider search.
