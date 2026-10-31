# Issue #2: product price and availability coverage in Ann Arbor

**Status (2026-10-31):** the coverage script and its offline tests are ready. Open Prices was checked live and has **no contributed locations within 20 km** of the origin. The authenticated Kroger run is **pending**; sections marked `PENDING` are filled in from that run.

> **Kroger keys required.** Every `PENDING` result below needs the team's Kroger application keys (`KROGER_CLIENT_ID`, `KROGER_CLIENT_SECRET`) in a local `.env`; see [section 2](#2-how-to-run-the-coverage-query). Without them the script still runs Open Prices, reports Kroger as `not_run`, and exits with status 1. Never commit `.env` or paste the keys into docs, issues or chat.

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
| Kroger Products + Locations APIs | Developer application; OAuth2 client credentials with `product.compact` scope ([setup](CURRENT_PRICES.md#credentials-and-account-setup)). Keys stay server-side in `.env`. | Prices and stock are returned only for a specific branch (`filter.locationId`). Kroger-family banners only. No delivery fees or checkout. The cart API needs a customer login and is not used. | `PENDING` (needs a login to the team's Kroger developer account, not the API keys): copy the Products and Locations quotas from the portal. The documentation pages render client-side and could not be read automatically on 2026-10-31; [ISSUE6](ISSUE6_API_RESEARCH.md) did not verify a number either. The adapter retries one HTTP 429, then reports "rate limit reached". | `PENDING`: confirm in the same portal. |
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

`PENDING` (requires Kroger keys): paste the "Need x store matrix" section of `matrix.md` here after the authenticated run.

Legend: `C` current branch unit price and an in-stock/low-stock indication; `C?` current price, but stock unknown or out; `M` current match without a unit price (sold by weight or price missing); `H` historical record only; `U` candidates returned, but none pass the app matching rules; `0` no candidates; `ERR` lookup failed; `-` not queried.

### Field completeness of matched rows

| Source | package_size | weight | price | availability | fulfillment | timestamp |
|---|---|---|---|---|---|---|
| Kroger | `PENDING` (keys) | `PENDING` (keys) | `PENDING` (keys) | `PENDING` (keys) | `PENDING` (keys) | Query time only (see section 5) |
| Open Prices | No rows in area | No rows in area | No rows in area | Always unknown (by design) | None | Contributor's record date |

### Gaps reported by the run and match review

`PENDING` (requires Kroger keys): paste "Gaps found by this run", "Stores without product evidence" and "Match review samples" from `matrix.md` here. Review every sample by hand.

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

- [x] Access requirements, restrictions and costs documented (Kroger quota and cost `PENDING` from the portal).
- [x] Open Prices coverage checked in the target area.
- [x] Missing information and fallbacks documented.
- [ ] Run `scripts/coverage_matrix.py` with the Kroger keys; fill in the `PENDING` sections of section 4.
- [ ] Save the reviewed `summary.json` as `docs/samples/coverage-ann-arbor.json`.
