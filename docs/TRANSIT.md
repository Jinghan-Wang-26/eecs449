# Scheduled TheRide bus shopping visits

CartCompass can plan a dated **Ann Arbor/Ypsilanti TheRide** round trip from a confirmed real address to a nearby store. Bus visits use the agency's published GTFS schedule, including service calendars and date exceptions. They are not live arrival predictions. Retailer snapshots and historical Open Prices evidence are labeled separately.

## Use it locally

1. Keep `GEOAPIFY_API_KEY` in your local `.env`; it verifies address and pedestrian routes. No new transit account or key is required for the public schedule file. Conversation still requires the existing model configuration; structured controls do not.
2. Confirm an address in the service area. Add shopping needs on the **List** step.
3. Under **Preferences**, select **Bus** under **How you travel**, save your available hours, maximum walking minutes and maximum bus transfers per travel segment. The search supports at most two transfers; a saved limit of zero or one is respected. If the saved limit is larger, only journeys with at most two transfers are searched.
4. On the **Options** step, click **Compare store options**, or ask the assistant to plan the trip. For example: `Plan a bus shopping trip for milk and rice. I can shop Saturday from 2 pm to 6 pm, walk up to 15 minutes per leg, and make at most one transfer each way.`
5. Choose **Review route** to see the trip drawn in time order with its key departure and return times; **Show all steps** lists the separate **To the store** and **Back to your starting address** directions. Each direction lists walking, waiting, bus numbers, headsigns, boarding/alighting stops and transfer counts. Review uncertainties before accepting.

The first bus lookup downloads and parses the official timetable. Map requests can make this slower than walking-only planning. A schedule with no valid return is blocked; a missing service, failed walking lookup or expired feed never becomes a fictional bus trip or silently changes BUS-only travel to another mode.

## Data and routing behavior

- Official feed: [TheRide developer page and terms](https://www.theride.org/business/software-developers), [GTFS ZIP](https://www.theride.org/sites/default/files/google/google_transit.zip). Data is cached under ignored `.jac/transit/`, refreshed on use after 24 hours, and not served stale if that refresh fails. The publisher requires updates within three business days; daily refresh while the feature is in use is stricter. Agency branding/logos are not bundled.
- The trip must fall inside published feed coverage. The planner reads `calendar.txt` and `calendar_dates.txt`, boarding/alighting restrictions, and stop-level prohibited/minimum-time transfers. GTFS times beyond 24:00 remain attached to their service date; elapsed-time conversion follows the agency timezone and DST rules.
- Jac implements calendar selection, bounded ride-round routing, transfer/boarding constraints, dated availability and the shopping interval. Python handles downloading/parsing CSV and map HTTP requests. Unsupported trip-specific transfer rules fail explicitly. Frequency-based, on-demand and malformed/untimed trips are excluded instead of inventing exact departures.
- The search checks the next eight calendar dates, up to eight access stops with scheduled service in the selected window within 1.2 km at each end, and at most two transfers per direction. Transfer candidates include four nearby stops within 150 m per stop plus explicit GTFS pairs. Provisional platform links are internal search bounds; selected links must be replaced with real pedestrian routes and the timetable searched again before acceptance. A bounded verification limit prevents unlimited provider calls. This is not an exhaustive regional journey planner.
- Access and egress walking are checked in both directions against the saved per-leg walking limit. A two-minute boarding/transfer buffer and any larger GTFS minimum transfer time are required. Transfers forbidden by the feed are excluded.
- A visit allows 20 minutes of shopping, fits supported recorded store opening hours when available, and returns before the saved availability ends. Unknown or complex opening hours remain explicitly unknown. Waiting before the return walk may be outside the store after shopping. Slow lookups cannot slide a fixed bus departure to a non-existent time.
- Plans show feed version, download time, service dates and source links. Recommendations expire after at most 15 minutes or earlier walking/feed expiry; refresh before departure. Actual delays, cancellations, detours, crowding, accessibility guarantees and fares are unavailable. Consult [TheRide alerts](https://www.theride.org/rider-alerts). Walking paths are map estimates, not accessibility audits.

## Verification

Offline checks cover service exceptions, prohibited boarding/alighting, missed buses, transfer buffers/limits/forbidden pairs, verified platform walking, after-midnight and DST handling, missed returns, closed stores, expiry, slow-provider handling, and graph acceptance/invalidation.

```bash
.venv/bin/python -m unittest discover -s tests -p 'test_*.py'
.venv/bin/jac test
.venv/bin/jac build main.jac
# Opt-in external requests, using two fixed public Ann Arbor locations:
.venv/bin/python scripts/verify_transit.py --output /tmp/cartcompass-transit.json
```

A real HTTP check on 2026-10-27 resolved Michigan Union and Kroger on Plymouth Road, used TheRide feed `S1000302` (2026-08-23 through 2027-01-30), and found routes 62/23 outbound and 23/62 back, with one transfer each way. It verified the walking connections, including the return platform transfer. The recorded example took 122 minutes including shopping and had 16 minutes of walking. This is a dated verification example, not a promise that the same buses are available now. Sanitized evidence is in [the transit verification sample](samples/transit-verification.json).


Final local validation: **125 Jac tests + 86 Python tests (211 total)** passed. The client build and isolated Chromium checks passed for itinerary legs, outbound/return details, explicit acceptance, reload, mobile overflow, transfer-limit invalidation, and missing-return rejection, with no page exceptions. Browser checks used synthetic timetable data; the real HTTP verification above is separate.


## Weekend access-stop fix (2026-10-27)

The earlier search spent its four-stop access budget on the nearest map stops
before checking whether they had service on the shopping date. Near Hubbard +
Stone, the nearest stops had no Saturday-afternoon service; a more distant stop
served by route 22 was never queried. This produced false negative bus results.

Single-store and multi-store searches now identify boarding/alighting stops from
actual dated trip instances within each free-time window before selecting up to
eight nearby access stops. Walking routes remain verified against the saved limit;
no time, walking or transfer preference is silently relaxed. Diagnostics distinguish
no scheduled service, unavailable walking access, no fitting outbound connection,
and an outbound connection without a fitting return. These remain bounded searches.

Regression tests cover nearby inactive stops, weekday/weekend service, time-of-day
selection, pickup/dropoff restrictions, distinct return failures and multi-store
access. Full validation: 115 Python + 136 Jac tests. The real public-stop probe is
reproducible without a residential address:

```bash
.venv/bin/python scripts/verify_transit.py --scenario weekend --output /tmp/weekend-bus.json
```

See [weekend verification](samples/transit-weekend-verification.json) for the dated
HTTP result. The original Michigan Union probe remains the default scenario.
