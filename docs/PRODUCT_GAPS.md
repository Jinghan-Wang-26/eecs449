# Current capabilities and next milestones

## Current retailer workflow (2026-10-27)

Kroger branch snapshots now connect address search, shopping-list matching, route and
scheduled bus planning, and uncached quote rechecks before acceptance. Changed prices
or selections require another explicit review; errors never reuse stale quotes.
See [CURRENT_PRICES.md](CURRENT_PRICES.md) for credential setup, limitations and tests.
Authenticated production queries and a scheduled-bus shopping visit with an
uncached quote recheck passed on 2026-10-27; see
[actual provider evidence](samples/current-prices-verification.json). Earlier
Open Prices examples below remain historical.


Updated 2026-10-27. The README design is broader than the working local prototype.

## Completed in this reliability update

1. Partial chat edits preserve omitted product constraints; explicit clearing is supported. Both intent extraction and the shared graph path are tested. Changed specs revoke stale product confirmations.
2. Jac scheduling uses concrete dates, address timezone, both route directions, available time and supported regular opening hours. Slow provider requests cannot leave a departure in the past. Unknown hours and future traffic are explicit.
3. Actual purchase quantities and optional spending are recorded separately from historical evidence. Remaining quantities survive and can be replanned. Identical retries do not subtract twice.
4. The latest 40 chat turns persist in the user's workspace. Clearing the transcript preserves shopping state. This remains a local single-user UI; Jac root scoping is not a hosted multi-user acceptance claim.
5. An explicit new-plan button starts an empty list and conversation, pauses previous needs with an optional restore action, and preserves accepted-visit purchase snapshots. Clearing chat remains separate.
6. Offline regression coverage, real provider/model probes and browser checks are recorded in `samples/reliability-verification.json`.

7. Scheduled TheRide round trips now include dated departures, walking, waits and transfer limits. Jac routing and actual HTTP verification are described in [TRANSIT.md](TRANSIT.md).

## Remaining work, in suggested order

| Priority | Gap | Verifiable milestone |
|---|---|---|
| Later | Live transit updates and wider coverage (#3) | Scheduled TheRide round trips are implemented and verified at public Ann Arbor locations. Next: incorporate authenticated real-time cancellations/delays, additional agencies and broader transfer searches without treating static schedules as live predictions. |
| Next | Target-area product evidence (#2) | Publish an anonymized coverage matrix for representative needs and stores ([script, method and status](ISSUE2_COVERAGE.md); Open Prices has no Ann Arbor locations, Kroger run pending). Preserve location-only fallbacks. Consider separately labeled user receipt/manual observations; do not promise current availability from history. |
| Next | One-off trip constraints | Extract “this trip only” without overwriting long-term preferences. Current chat availability is a recurring weekly template; displayed trip dates are the next fitting occurrence, not a dated appointment. |
| Later | Complete spending/budget | Add an actual-purchase ledger, correction workflow and weekly remaining budget. Current recorded totals are partial observations, not a full basket quote or budget guarantee. |
| Later | Automated delivery and broader optimization | Two-store current-price trips and manually entered checkout quotes now support real-mode comparisons ([walkthrough](MULTISTORE_DELIVERY.md)). Next: authorized merchant checkout/slot APIs, wider retailer coverage and larger route searches. Manual quotes are not API verified; no orders are placed. |
| Later | Background reminders | Add a scheduler and opted-in delivery channel with timezone/cooldown/retry handling. Historical price records must not trigger current-stock or current-price promises. |
| Before public launch | Accounts and operations | Login UI, multi-user isolation tests, deployed model API, request limits, concurrent-update handling, backups and recovery, latency/cost monitoring. Local Codex transport is for trusted local use. |
| Course alignment | More Jac business rules | Move remaining real-store matching/ranking from `planning/visits.py` to Jac with regression coverage. New scheduling and purchase rules in this update already use Jac. |

## Evidence and reproduction

```bash
source .venv/bin/activate
python -m unittest discover -s tests -p 'test_*.py'
jac test
jac build main.jac
# Optional external requests; requires your existing provider/model configuration:
python scripts/verify_store_visits.py --output /tmp/store-visits.json
python scripts/verify_partial_updates.py --output /tmp/partial-updates.json
```

The recorded browser test used an isolated temporary graph with synthetic store/route records. It checked regular-hours display, explicit acceptance, buying two of three packages, reported spending, purchase/chat persistence after reload, a visible missing-model error, and clearing chat while keeping the plan. It had no page exceptions. Real-provider and real-model probes are separate evidence; this is not an automated live-LLM browser evaluation of every scenario.

Map-hours source: [Geoapify Place Details](https://apidocs.geoapify.com/docs/place-details/). Conservative syntax handling follows the [OSM opening-hours specification](https://wiki.openstreetmap.org/wiki/Key:opening_hours/specification); unsupported rules remain unknown.
