# Issue #6: shopping and map API investigation

Research date: 2026-10-12. A documented API capability is not a successful integration test. Actual network evidence is identified separately below.

## Shopping sources

| Source | Authentication / cost | Store-specific information | Coverage and limitations | Decision |
|---|---|---|---|---|
| [Kroger Public APIs](https://developer.kroger.com/documentation/public/getting-started/quick-start) | Application client ID/secret; OAuth client credentials, `product.compact` for product reads. Current account quota and pricing must be checked in the developer account; no numeric quota verified. | Locations API supplies retailer location IDs; Products search uses `filter.locationId` for branch price/availability fields when supplied. | Kroger participating US banners, not all supermarkets. Inventory may be absent. Promotions may require eligibility; no delivery fee or cart guarantee. | Optional adapter implemented; registration blocked by “exceeded the number of retries allowed.” No successful authenticated request claimed. |
| [Open Prices](https://openfoodfacts.github.io/open-prices/topics/core/) | Public read GET requests succeeded without account or API key; no charge for tested reads. No service-level guarantee or fixed quota verified. Cache and bound requests. | A recorded price links product/barcode, exact location ID / OSM object, observation date and proof ID. | Community-contributed historical observations; incomplete geographic coverage. Does not prove present price, stock, delivery availability or complete assortment. | Default historical-products source, selected with user approval after Kroger registration failure. Keep historical observations distinct from current offers. |
| [Open Food Facts](https://openfoodfacts.github.io/openfoodfacts-server/api/) | Public catalog reads; identifying User-Agent and endpoint-specific rate limits. | Barcode, product name, packaging, nutrition/labels if contributed. | Product catalog alone does not establish branch availability or price. Labels are community data, not independently certified. | Useful enrichment. Open Prices already embeds linked catalog metadata; no unrelated catalog result is represented as store stock. |

Open Prices [license/data guidance](https://openfoodfacts.github.io/open-prices/guides/data/) specifies ODbL attribution and sharing obligations. The sample extracts here identify their source; no proprietary Kroger response is combined into an exported Open Prices dataset.

## Maps sources

| Source | Authentication / pricing | Useful endpoints | Limits / decision |
|---|---|---|---|
| [Geoapify](https://apidocs.geoapify.com/) | Project API key. [Free plan](https://www.geoapify.com/pricing/): 3,000 credits/day, up to 5 requests/s, no credit card; simple requests generally cost one credit. Recheck before deployment. | Forward geocoding, Places supermarket search, Routing for walking/bicycle/driving. | Selected. Requires Geoapify/data attribution. Bus-vehicle routing is not public-transit service. This adapter explicitly rejects BUS/RIDESHARE rather than fabricating fares or schedules. |
| [Google Maps Platform](https://developers.google.com/maps/billing-and-pricing/pricing) | Cloud project, enabled APIs, key and billing. Per-SKU free usage and tiered metering; exact cost depends on requested fields/SKU. | [Nearby Search](https://developers.google.com/maps/documentation/places/web-service/nearby-search), geocoding, [Routes](https://developers.google.com/maps/documentation/routes/route-opt). | Alternative for broader routes/places coverage. Requires account/billing setup; not tested or implemented here. Places does not supply store shelf inventory. |

## Actual request evidence

- `samples/openprices-usd.json`: successful unauthenticated `GET /api/v1/prices?currency=USD&size=2&order_by=-date`; two actual records with product, exact location, date, regular/discount distinction and proof IDs. Sample store: Whole Foods Market, 150 East McKinley Avenue, Sunnyvale, CA.
- `samples/openprices-sunnyvale.json`: successful nearby locations query at the public store coordinates within 1 km, four records returned (one department store and three supermarkets).
- `samples/openprices-ann_arbor.json`: successful nearby locations query at Ann Arbor city center within 5 km, **zero results**. This is a coverage limitation, not an API error and not a claim that the city has no supermarkets.
- Kroger: registration retry limit; no credentials, hence no authenticated sample. Synthetic tests are explicitly labeled and never presented as live evidence.
- Geoapify: successfully verified geocoding of a public Sunnyvale store address, nearby supermarket search and separate outbound/return walking routes. `samples/live-verification.json` records all six successful integration steps including the bridge from geocoded coordinates to Open Prices locations. No keys or key-bearing request URLs are saved.
- Google Maps: not tested; no configured project/key/billing. This investigation does not create paid accounts.

## Flow and validation boundaries

1. User enters address; geocode returns candidate addresses. User confirms one before nearby search.
2. Query nearby locations within the requested radius. Preserve original provider and stable location identifier. Never associate stock by store name alone.
3. Query a supported location's product data. A map-only POI is explicitly marked as lacking product access. Empty provider results remain empty.
4. Display source, branch, observation time, currency, inventory uncertainty and evidence link if available. Historical observations cannot become fresh offers merely because they were fetched today.
5. User confirms product matching. Verified/current offers can enter the deterministic planner only with usable transport, opening hours, package weight and user cost assumptions. No guessed shipping fees, transit fares or dietary compatibility.
6. Optional LLM recommendation flow: feed the validated request and computed plan facts/source-qualified observations into an explanation step. Recommendations must preserve historical/current distinctions and never imply unknown inventory is available. The active UI currently uses computed explanations and an LLM intent parser; authenticated model evaluation requires a configured LLM key.
7. Invalidate old proposals on address, mode, need or constraint changes. Mark accepted plans for review. Replayed feedback is idempotent.

The application distinguishes runnable integration code, synthetic contract tests and actual provider calls. A full live checkout/cart integration, universal store inventory and scheduled refresh are outside this prototype.
