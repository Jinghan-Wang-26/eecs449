# Real-store and entered-delivery comparisons

Real stores can compare a single-store visit, a two-store trip, delivery-only,
and a mixed delivery/shopping plan. Allocation, fee validation, scheduling and
ranking rules live in Jac. Python handles provider requests and orchestration.

## Try it locally

1. Start the app with the pinned project environment (`jac start main.jac`).
   Select **Real stores**, confirm an address, add shopping needs, and save travel
   modes, free time, carrying limit and budget in **Preferences**. Save tax and
   whole-trip driving cost estimates if you want complete driving totals.
2. Open **Plans & stores → Compare store options**. With Kroger and
   Geoapify configured, the app checks up to three retailer branches and assigns
   each need to one branch. Two-store options show home → first store → second
   store → home, including 20 minutes of shopping at each store.
3. For delivery, open the merchant's checkout yourself. Enter your address,
   exact products and quantities, and select an available delivery window.
   Copy its amounts into **Compare a delivery checkout quote**. Select only the
   needs in that checkout basket, record the public merchant URL, and confirm
   address coverage, product requirements and all charges. Do not paste a private
   checkout-session link or credentials.
4. Enter merchandise subtotal, delivery fee, service fee, other fees, tax, tip,
   applied discount and minimum order. Explicit zero means checkout confirmed no
   charge; blank means **Unknown**. A quote with missing or unconfirmed fees is
   saved but cannot become an accepted delivery option. The minimum is compared
   to the entered merchandise subtotal; confirm any merchant-specific eligibility
   rule at checkout. Times are entered in your browser timezone and stored with
   a timezone offset.
5. Click **Compare store options** again. A quote covering the entire
   list can produce delivery-only options; a quote covering part of it can
   produce mixed options. You must be free at home for the entire delivery
   window. Shopping may finish before it or start after it.
6. Review item assignments, product sizes, route legs, total costs and unknowns.
   **Lowest estimated total**, **Least active time** and **Balanced** label the
   eligible complete options in this bounded search. Historical observations do
   not enter current-price totals. Different product selections are disclosed;
   savings against a single-store option are shown only for identical SKUs.
7. Check the ordinary review box. If delivery is included, also recheck merchant
   checkout and check the delivery confirmation box. Acceptance re-queries each
   assigned branch without the product cache. Changed price, stock or product
   details require another review; lookup failures and stockouts block acceptance.
   Comparison labels are cleared after a refresh until recommendations are run
   again. **Accepting only saves a plan; place any delivery order yourself.**
8. Record actual purchases/received items afterward. Acceptance does not remove
   needs or report purchases. Starting a new shopping plan clears current delivery
   quotes while retaining existing accepted-plan purchase history.

## Evidence and limits

- Delivery quotes are **USER-ENTERED CHECKOUT QUOTE / NOT API VERIFIED**, with
  merchant URL, entry time, expiry, exact covered needs and delivery window.
  They expire after 30 minutes or at window start, whichever is earlier. Address,
  quantity, product specification or dietary changes invalidate the binding.
  Refreshing retailer prices cannot renew a manual quote; use **Update from
  checkout** and re-enter confirmations after checking the merchant again.
- Save up to three quotes. Each option uses at most one complete quote and two
  physical stores. A quote cannot be split or combined with another quote:
  basket-level fees and discounts may change if its items change. Current manual
  quote input supports up to six distinct needs.
- Up to three retailer branches are queried, with at most ten returned product
  variants per need. The existing conservative matcher chooses one product per
  need/branch. The optimizer compares assignments of these chosen products and
  both store orders; it does not search all products, all stores, or reserve stock.
- Route evidence covers every directed segment and a return home. Supported
  regular hours are checked; missing/unsupported hours remain Unknown. Road
  durations are current estimates, not forecasts. TheRide segments use dated
  static schedules, verified walks and up to two transfers per segment, respecting
  a lower saved limit. Multi-stop transit uses bounded earliest-arrival searches;
  a failed search is not proof that no transit journey exists.
- Accumulated retail net weight is checked against the carrying limit. Delivered
  items are not carried. Missing weights and packaging remain unverified.
- Delivery charges are counted once. Retail tax and driving costs are saved user
  estimates; bus fare remains Unknown. Missing amounts never become free. An
  unknown full total cannot receive the lowest-total label.
- Balanced ranking uses estimated total plus saved hourly time value × active
  minutes / 60, after eligibility/coverage checks. Active time includes shopping,
  travel and waits during the trip plus a fixed 10-minute allowance for placing a
  delivery order. The whole delivery receipt window is a home-availability
  constraint, not counted as active effort. This estimate is not measured
  merchant fulfillment time.
- A quoted future delivery slot is not reserved. No delivery coverage API,
  automatic checkout/order, payment, dynamic cancellation or live transit
  prediction has been added. No additional credentials are required for manual
  checkout entry; retailer and route credentials remain server-side.

## Verification

```bash
.venv/bin/python -m unittest discover -s tests -p 'test_*.py'
.venv/bin/jac test
.venv/bin/jac build main.jac
# Optional real, read-only API calls at the public Michigan Union address:
.venv/bin/python scripts/verify_comparisons.py
```

On 2026-10-27, 110 Python and 136 Jac tests passed. New coverage checks assignments,
continuous road and bus trips, return deadlines, store hours, carrying weight,
fee completeness, quote expiry/binding, delivery conflicts and acceptance review.
An isolated Chromium graph verified quote input, local datetime conversion,
persistence, a mixed plan, both acknowledgements, acceptance without purchase,
editing confirmation resets, and mobile layout without overflow or page errors.
Browser delivery amounts were synthetic fixtures, not actual merchant quotes.

A separate authenticated production probe at Michigan Union returned a two-store
Kroger option with rice at Plymouth Road and milk at Washtenaw Avenue, a continuous
64-minute driving/shopping trip and a successful uncached product recheck.
The displayed total used explicitly supplied test tax/driving estimates; no
personal shopping graph or order was changed. See
[sanitized provider evidence](samples/multistore-verification.json). This validates
one example, not exhaustive coverage or a claim that two stores are always better.
