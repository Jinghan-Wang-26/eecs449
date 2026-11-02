# Issue #2: product price and availability coverage in Ann Arbor

**Status (2026-10-31):** the authenticated run is complete. Within 8 km of the Michigan Union, **all ten representative needs have current prices and stock indications at all four Kroger branches**, while Open Prices has **no contributed locations within 20 km**. 17 other grocery stores on the map, including the nearest one, have no product source. Kroger rate limits were verified from API response headers.

> **Kroger keys required to reproduce.** The run needs Kroger application keys (`KROGER_CLIENT_ID`, `KROGER_CLIENT_SECRET`) in a local `.env`; see [section 2](#2-how-to-run-the-coverage-query). Without them the script still runs Open Prices, reports Kroger as `not_run`, and exits with status 1. Never commit `.env` or paste the keys into docs, issues or chat.

This document answers issue #2 for the target area. API selection and the original research are in [ISSUE6_API_RESEARCH.md](ISSUE6_API_RESEARCH.md); Kroger account setup is in [CURRENT_PRICES.md](CURRENT_PRICES.md).

| Issue #2 asks for | Answered in |
|---|---|
| Access requirements, usage restrictions, rate limits and costs | [1. Access and limits](#1-access-restrictions-rate-limits-and-cost) |
| Query representative products at stores in the target area | [2. How to run](#2-how-to-run-the-coverage-query), [3. Scope](#3-representative-needs-stores-and-matching), [4. Results](#4-results) |
| Coverage of package size, price, availability, fulfillment channel and timestamps | [4. Field completeness](#field-completeness-of-matched-rows) |
| Missing information and fallback options | [5. Gaps and fallbacks](#5-missing-information-and-fallbacks) |

## 1. Access, restrictions, rate limits and cost

| Source | Access | Restrictions relevant to CartCompass | Rate limits | Cost |
|---|---|---|---|---|
| Kroger Products + Locations APIs | Developer application; OAuth2 client credentials with `product.compact` scope ([setup](CURRENT_PRICES.md#credentials-and-account-setup)). Keys stay server-side in `.env`. | Prices and stock are returned only for a specific branch (`filter.locationId`). Kroger-family banners only. No delivery fees or checkout. The cart API needs a customer login and is not used. | Verified 2026-10-31 from the `RateLimit-*` response headers of authenticated calls: **Products 10,000 calls/day, Locations 5,000 calls/day** per application, resetting at 00:00 UTC. A default coverage run uses about 41 Products calls and 1 Locations call. The adapter retries one HTTP 429, then reports "rate limit reached" | No charge observed: registering the application and creating Production credentials asked for no payment details, and the responses carry no billing information. |
| Open Prices | Public reads, no key. | Community-contributed historical records under ODbL; attribution required. They never prove a current price or current stock. | No quota documented or verified ([ISSUE6](ISSUE6_API_RESEARCH.md)); the script keeps requests bounded. | Free for the tested reads. |
| Geoapify Places (map-only stores) | Project API key. | Store locations only; no product data. Attribution required. | Free plan: 3,000 credits/day, 5 requests/s ([ISSUE6](ISSUE6_API_RESEARCH.md); recheck before deployment). | Free plan. |

## 2. How to run the coverage query

1. Use the project environment: `source .venv/bin/activate` (pinned `jaclang==0.16.7`).
2. Put the team's Kroger application keys in the local `.env`. The slots already exist in `.env.example`:

   ```dotenv
   KROGER_CLIENT_ID=
   KROGER_CLIENT_SECRET=
   GEOAPIFY_API_KEY=        # optional: lists supermarkets with no product source
   ```

   `python scripts/check_credentials.py` reports which keys are configured, without printing them.
3. Run:

   ```bash
   python scripts/coverage_matrix.py
   # options: --needs "milk,eggs" --radius-m 8000 --max-kroger 5 --max-openprices 5
   #          --sources kroger,openprices,map --out-dir /tmp/cartcompass-coverage
   python scripts/coverage_matrix.py --from-json /tmp/cartcompass-coverage/collection.json   # re-render offline
   ```

| Output | Contents | Commit? |
|---|---|---|
| `collection.json` | Every normalized product row returned, per store and need. | No. Keep it local; it is large. |
| `summary.json` | Matrix, per-need rollup, field completeness, gaps, match samples. | Yes, as `docs/samples/coverage-ann-arbor.json`, after review. |
| `matrix.md` | The same summary as Markdown tables. | Paste into [section 4](#4-results). |

**Request budget with the defaults:** Kroger uses 1 token + 1 location search + 5 branches × 10 needs = 52 calls. Open Prices uses at most 1 + 5 × 8 = 41 calls. Geoapify uses 1 call.

**Exit status:** 0 when every enabled source ran. 1 when a source lacked credentials or failed. Sources disabled with `--sources` count as deliberate.

**Privacy:** the default origin is the Michigan Union, a public landmark. Do not pass a home address with `--lat/--lon/--label`. Credentials and request URLs are never written to the output.

## 3. Representative needs, stores and matching

- **Needs:** the ten demo categories: milk, eggs, rice, laundry detergent, dish soap, paper towels, yogurt, coffee, tofu and soy sauce. They include the README example (milk, eggs, rice, detergent) and mix dairy, staples, heavy household goods and specialty items.
- **Stores:** the five nearest Kroger branches within 8 km, every Open Prices location within 8 km, and (with Geoapify) supermarkets that neither source covers.
- **Same query and rules as the app:** Kroger searches use the app's own request (`filter.locationId`, `filter.fulfillment=ais`, 10 results). Rows are judged with `planning/retail.jac` `suitable` (current quotes) and `planning/visits.py` `match_record` (historical records). A `U` cell therefore means the source had candidates that the app would not offer, which points to a search-term or matching-rule gap rather than missing data.

## 4. Results

### Open Prices: no coverage (checked 2026-10-31)

`GET /api/v1/locations/nearby` around the Michigan Union returned **0 locations at 8 km and at 20 km** ([evidence](samples/openprices-ann_arbor-coverage.json)). The 2026-10-12 check at the city centre within 5 km also returned zero ([earlier sample](samples/openprices-ann_arbor.json)). This is a gap in contributed data, not an API error, and it does not mean the area has no supermarkets.

**Consequence:** in Ann Arbor, Kroger is the only product source. Stores of other chains can appear only as location-only visits.

### Kroger: need × store matrix

Authenticated run on 2026-10-31 22:01 UTC, after the store-merge fix below, 8 km around the Michigan Union, default needs and limits ([summary](samples/coverage-ann-arbor.json)). Counts in parentheses are matched product variants.

| Need | Kroger - Westgate (3.4 km) | Kroger - Plymouth Nixon (4.2 km) | Kroger - Washtenaw (4.7 km) | Kroger - Carpenter Packard (6.1 km) |
|---|---|---|---|---|
| milk | C (8) | C (8) | C (9) | C (8) |
| eggs | C (10) | C (10) | C (10) | C (10) |
| rice | C (10) | C (10) | C (10) | C (10) |
| laundry detergent | C (9) | C (9) | C (9) | C (9) |
| dish soap | C (10) | C (10) | C (10) | C (10) |
| paper towels | C (7) | C (7) | C (7) | C (7) |
| yogurt | C (10) | C (10) | C (10) | C (10) |
| coffee | C (10) | C (10) | C (10) | C (10) |
| tofu | C (10) | C (10) | C (10) | C (10) |
| soy sauce | C (10) | C (10) | C (10) | C (10) |

Only four Kroger branches lie within 8 km, so 40 of the 50 budgeted product searches were used.

Legend: `C` current branch unit price and an in-stock/low-stock indication; `C?` current price, but stock unknown or out; `M` current match without a unit price (sold by weight or price missing); `H` historical record only; `U` candidates returned, but none pass the app matching rules; `0` no candidates; `ERR` lookup failed; `-` not queried.

### Field completeness of matched rows

| Source | package_size | weight | price | availability | fulfillment | timestamp |
|---|---|---|---|---|---|---|
| Kroger (377 rows) | 377 (100%) | 114 (30%) | 369 (98%) | 363 (96%) | 377 (100%): in-store, curbside and delivery flags on every row | Query time only (see section 5) |
| Open Prices | No rows in area | No rows in area | No rows in area | Always unknown (by design) | None | Contributor's record date |

### Gaps reported by the run and match review

**Stores without product evidence.** 18 Geoapify supermarket POIs within 8 km have no product source: Target Grocery (0.5 km), Kanbu Asian Mart, People's Food Co-op, By The Pound, Busch's Fresh Food Market, Gordon Food Service, Arbor Farms Market, Trader Joe's, ALDI, two Whole Foods Market locations, Plum Market, Harvest Market, Tsai Grocery, Way 1 Supermarket, Meijer, Patel Brothers, and one entry that is not a store:

- **Fixed: duplicate Kroger entries.** The first run (21:14 UTC) listed 20 unlinked POIs, including two map entries named "Kroger" 6 m and 37 m from the Westgate and Plymouth Nixon branches. Geoapify formats addresses as "Kroger, 400 South Maple Road, ...", so the street-number check in `merge_stores`, which read only a leading number, never matched. `street_number` now reads the first address part that starts with a house number ([test](../tests/test_providers.py)). The app's nearby-store list used the same function, so it also showed these branches twice, once with current prices and once as location-only.
- **Not fixed in code: "Vertical Media Solutions"** (3,078 m) carries the same `shop=supermarket` tag in OpenStreetMap as real supermarkets, so no data signal distinguishes it. A name blocklist would not generalise. The fix belongs upstream: correct the tag in OpenStreetMap.

So 17 genuine grocery stores, including the nearest one (Target Grocery), have no product data.

**Match review (all 60 samples of each run checked by hand on 2026-10-31).** Every sampled product is a plausible match for its need. Rice matched long-grain white rice (32 oz and 5 lb), not the instant pouch from the 2026-10-27 run. Observations:

- **Missing price on out-of-stock items:** rows without a price are out of stock (8 in each run), for example "Kroger Grade A Large White Eggs" 12 and 18 ct at three branches. The cheapest store-brand eggs were unavailable everywhere sampled, and the available option was Simple Truth cage-free eggs at $5.49.
- **Single-serve versus multipack:** yogurt matched both a 6 oz single cup ($0.80) and a 4 x 5.3 oz pack ($5.29). Both are valid, but per-package prices are not comparable without the unit price.
- **Variant spread:** dish soap ranged from 19 fl oz to 67 fl oz ($2.99 to $10.49), and paper towels from 2 to 6 rolls. The package size the user wants matters more than the name match.
- **Price differences between branches:** the same Kroger 2% gallon milk was $3.09 at Westgate and Washtenaw and $3.39 at Plymouth Nixon.

## 5. Missing information and fallbacks

These are properties of the adapters, so they hold regardless of the run. "Proposed" marks a fallback that is not implemented yet.

| Missing or weak information | Effect in CartCompass | Fallback |
|---|---|---|
| No Open Prices records in Ann Arbor | No historical evidence; non-Kroger stores have no product data. | Location-only visits, labelled as such. Proposed: separately labelled user receipts or manual observations. |
| Kroger returns no observation time | The query time is recorded; quotes are treated as valid for 30 minutes. | Uncached recheck (`product_at`) before a visit is accepted. |
| Items sold by weight have no unit price | Shown as `M`; the item's cost stays unknown. | Proposed: show the reported price with a "sold by weight" note and ask the user for a quantity. |
| Stock is a coarse level (`HIGH`/`LOW`/out) or absent | Absent stock stays `UNKNOWN`, never "in stock". `LOW` may not cover the requested quantity. | The user confirms in store. Proposed: rank `HIGH` above `LOW`. |
| Weight is parsed only from kg/g/lb/oz labels | `gal`, `fl oz` and count labels leave weight unknown, so the carry limit cannot be checked. | Unknown weight stays visible. Proposed: a per-category weight table for common liquids. |
| In-store search only, 10 results per term | Delivery-only items and lower-ranked variants are not seen. | Delivery uses manual quotes ([MULTISTORE_DELIVERY.md](MULTISTORE_DELIVERY.md)). Proposed: more specific search terms per need (for example "whole milk"). |
| No delivery fees or slots in the public API | Delivery cannot be priced automatically. | User-entered checkout quotes, labelled as not API-verified. |
| No dietary certification | `suitable` rejects every Kroger row when the user has dietary restrictions. | Rejection is kept. Proposed: list the products for manual review. |
| Name matching can accept the wrong form | Example from the 2026-10-27 run: "rice" matched "90 Second Jasmine Rice Pouch, 8.8 oz" ([sample](samples/current-prices-verification.json)). | The user reviews product selections before acceptance. Proposed: extend the exclusion lists after reviewing the matrix samples. |

## Remaining steps to close #2

- [x] Access requirements, restrictions, rate limits and costs documented (Kroger limits verified from response headers on 2026-10-31).
- [x] Open Prices coverage checked in the target area.
- [x] Missing information and fallbacks documented.
- [x] Run `scripts/coverage_matrix.py` with the Kroger keys; fill in section 4 (2026-10-31).
- [x] Save the reviewed `summary.json` as `docs/samples/coverage-ann-arbor.json`.
- [x] Deduplicate map POIs against API branches (`street_number` fix, 2026-10-31).
- [ ] Follow-up, not required for #2: a per-category weight table for liquids (weight is known for only 30% of rows); report the mis-tagged OpenStreetMap POI.
