# Current retailer snapshots and shopping visits

The Real stores workflow can query Kroger branch-specific prices and availability,
match the saved list, combine it with walking/cycling/driving or scheduled TheRide
round trips, and recheck quotes before accepting a visit. Open Prices observations
remain separately labeled historical evidence. No fictional fallback is used.

**Implementation status:** authenticated production OAuth, nearby locations, product
prices/stock, a scheduled TheRide visit and an uncached product recheck passed on
2026-10-27 at a public Ann Arbor example address. See the
[actual provider evidence](samples/current-prices-verification.json). This probe
did not accept a personal plan or make a purchase. Graph acceptance/error paths
and browser interactions are separately covered by synthetic tests.

## Credentials and account setup

1. Open [Kroger Developers](https://developer.kroger.com/), sign in or register,
   and verify the account email. If registration reports a retry limit, stop
   repeated attempts, try account recovery for an existing account, or use the
   portal's Support section. This project cannot remove account restrictions.
2. In application management, create an application for this course project.
   Select the public **Product API** with `product.compact` scope and public
   **Location API**. Portal labels may change. Use client credentials for these
   server-to-server reads; customer cart/identity permissions are unnecessary.
3. Copy the application's Client ID and Client Secret into the existing local
   `.env`. Do not overwrite other settings and do not commit or share this file:

   ```dotenv
   KROGER_CLIENT_ID=your_application_client_id
   KROGER_CLIENT_SECRET=your_application_client_secret
   GEOAPIFY_API_KEY=your_existing_geoapify_key
   ```

   Client-credentials reads do not use a browser OAuth callback. If the portal
   requires a website description or URL, describe the local course application
   truthfully; do not put a secret in a URL. If the portal blocks creation, record
   the exact non-secret error for troubleshooting rather than trying invented
   callback addresses.
4. Restart the local app after configuration. The adapter reads local settings
   server-side. Missing credentials, rejected access and rate limits appear as
   notices; no key is returned to the browser. No additional LLM credential is
   needed for the structured shopping controls. Existing chat model configuration
   remains separate. Scheduled TheRide data needs no additional key.

Official references: [public API catalog](https://developer.kroger.com/api-products/),
[Products API](https://developer.kroger.com/api-products/api/product-api-public),
[getting started](https://developer.kroger.com/documentation/public/getting-started/quick-start).
The public Products 1.3.0 contract was inspected on 2026-10-27. Search uses the
case-sensitive `filter.fulfillment=ais`; the schema names `fulfillment.instore`, while an actual production response
verified on 2026-10-27 uses `fulfillment.inStore`. Both spellings are supported.
That field means the store sells the product, not that it is in stock. Only
`inventory.stockLevel` supplies the availability indication. Missing stock stays
`UNKNOWN`. Both search and exact-product rechecks pass `filter.locationId`.

## Local walkthrough

1. Start the project using the existing [setup instructions](SETUP_LIVE.md).
2. Select **Real stores**, confirm an address near a Kroger-family store, and save
   needs, package quantities, travel mode, free time and optional budget/tax.
3. Open **Plans & stores** and choose **Recommend stores for my list**. With
   credentials configured, retailer branches are checked alongside historical
   and location-only options. Review the selected product, brand, package size,
   source store, query timestamp, refresh deadline and available/unknown status.
4. Choose **Refresh prices and availability** to query again. Check the review
   box and choose **Recheck and accept store visit**. Acceptance bypasses product
   caches and rechecks the exact previous product at the same branch, plus search
   results for alternatives. A changed price, stock state or product selection
   updates the proposal and requires review and a second explicit confirmation.
   Older browser revisions cannot accept newer quote contents.
5. If the selected product is out of stock, a suitable available result may be
   proposed. It is never accepted automatically. If none is found, the visit is
   blocked; recommend stores again or change the shopping need. Provider failures
   remove old quotes and block acceptance until a successful refresh. An expired
   route or passed bus departure requires new recommendations.
6. After visiting, record purchases and actual amounts paid. Those user reports
   remain separate from provider snapshots and do not assert global inventory.

## Scope and calculations

- At most six nearby locations are checked, with at most three retailer branches.
  Real mode now compares single-store, two-store and user-entered delivery/mixed
  options, showing up to seven representative alternatives. See
  [multi-store and delivery](MULTISTORE_DELIVERY.md) for bounds and verification.
- At most eight needs per retailer and ten search results per need are queried.
  Longer lists show an explicit lookup-limit blocker. Initial searches use a
  five-minute cache; acceptance and manual refresh bypass it. Local quote validity
  is thirty minutes, not a claim about retailer update frequency.
- Matching is conservative: name tokens, explicit brand and size must fit.
  Ingredient/derivative false matches for common staples are excluded. Verified
  dietary labels are unavailable in this adapter; dietary-constrained matches
  stay unknown. The user reviews all product selections before acceptance.
- Only regular USD prices explicitly sold by `unit` enter package subtotals.
  Variable-weight or missing selling-basis prices are not multiplied by package
  counts. Discounts and loyalty offers are not assumed eligible.
- Available coverage counts `HIGH`/`LOW` indications, not exact quantities. Low
  stock may not cover the requested count. Unknown is neither free nor out of stock.
- Rank by route eligibility, available coverage, match coverage, then complete
  basket cost when available and travel time. Partial subtotals never rank as
  complete cheap baskets. Known costs over budget and known weight over the
  carrying limit block acceptance. Unknown full weight remains visible.
- Estimated trip totals require all item prices, a saved tax estimate and a
  transport cost. Tax is an estimate, not product-specific tax advice. TheRide
  fares remain unknown, so bus options show an item subtotal and unknown trip
  total. Timetables do not predict delays or future inventory.
- Opening hours, final checkout prices and future stock must still be checked.
  Refresh before departure. This feature does not reserve stock or place orders.

## Validation

```bash
.venv/bin/python -m unittest tests.test_retail_visits tests.test_providers -v
.venv/bin/jac test tests/test_retail_workflow.jac
# Opt-in authenticated probe; public Ann Arbor address, no LLM calls:
.venv/bin/python scripts/verify_current_prices.py
```

The probe writes sanitized evidence under `/tmp` and exits nonzero if credentials,
matching products, usable quotes or routes cannot be verified. It never writes
synthetic prices as actual verification. Coverage outside the recorded example and newly configured accounts still
require real API testing after setup.
