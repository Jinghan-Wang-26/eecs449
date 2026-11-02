# Issue #8 implementation and verification

## Current retailer workflow (2026-10-27)

Kroger branch snapshots now connect address search, shopping-list matching, route and
scheduled bus planning, and uncached quote rechecks before acceptance. Changed prices
or selections require another explicit review; errors never reuse stale quotes.
See [CURRENT_PRICES.md](CURRENT_PRICES.md) for credential setup, limitations and tests.
Authenticated production queries and a scheduled-bus shopping visit with an
uncached quote recheck passed on 2026-10-27; see
[actual provider evidence](samples/current-prices-verification.json). Earlier
Open Prices examples below remain historical.


**Current transit update (2026-10-27):** scheduled TheRide bus visits are now supported; see [TRANSIT.md](TRANSIT.md). Earlier verification entries below describe their dated snapshots.

This table maps the 17 README checklist items to implementation and verification evidence. Read [setup](SETUP_LIVE.md) and [API research](ISSUE6_API_RESEARCH.md) for the historical-price scope and remaining external-service verification requirements.

| # | Task | Implementation / evidence |
|---|---|---|
| 1 | Core profile, interests, plan objects | `models/profile.jac`, `interest.jac`, `plan.jac`; persistent graph and model tests. |
| 2 | Product/store/offer/item/leg/event/reminder nodes and edges | `models/catalog.jac`, `events.jac`, `graph.jac`; graph/catalog/feedback tests. Historical observations live separately in `ShoppingWorkspace.historical_prices`, not `Offer`. |
| 3 | Eleven shopping walkers | `server/walkers.jac`, imported from `main.jac`: update_profile, update_interest, refresh_offers, build_candidates, plan_shopping, plan_action, feedback, discover_products, check_reminders, sync, chat. Wrappers use the requesting root and shared validated operations. `build_candidates` returns ranked proposals rather than an unbounded raw candidate dump. |
| 4 | Natural language to structured needs | `ai/intents.py`, `harness/agent.jac`; bounded JSON parser for profile/needs/address/feedback/store lookup. Validate fields, numeric ranges and transport/time values; explicitly requested profile/need updates save automatically and missing inputs are collected conversationally. Offline parser and graph confirmation tests pass. Real Chinese/English extraction verified through the optional local Codex backend; API mode still requires `LLM_API_KEY`. |
| 5 | Mock dataset | `data/mock/catalog.json`: four fictional stores, twelve products, thirty offers. Kept separate from real-provider data; fixed raw fixture dates with application-only demo rebasing and persisted-expiry migration. |
| 6 | Basket cost | `planning/cost.jac`: eligible discounts, tax, fees, tips and travel; `pricing.jac` supplies package and normalized unit prices with membership eligibility and snapshot display; tests include membership and unknown fees. |
| 7 | Hard constraints | `planning/constraints.jac`, `inputs.jac`: budget, carry, time, modes, transfers, windows, freshness, dietary evidence. Missing mass/route/tax assumptions block optional current-offer live planning. |
| 8 | In-store/delivery/mixed ranking | Demo: `planning/candidates.jac`. Real mode: `planning/multistore.jac`, `delivery.jac` and `itineraries.jac` compare single/two-store trips and user-entered checkout quotes. Continuous routes, full basket fees, home availability and acceptance rechecks are covered. Delivery is not API verified; see [walkthrough and evidence](MULTISTORE_DELIVERY.md). |
| 9 | Plan lifecycle | `planning/lifecycle.jac`, `server/workflows.jac`: UUID keys, mode-specific selection, acceptance/cancellation, partial outcomes, review after changes. Reject expired quotes at acceptance. |
| 10 | Feedback and sync | `feedback/apply.jac`, `sync/engine.jac`: validated batches, persistent event IDs, no duplicate application, coalesced replan and explicit review of accepted plans. Live public API rejects injected offer updates. |
| 11 | Reminders | `notify/reminders.jac`: replenishment, target price and restock, cooldown, quiet hours, snooze/ignore/dismiss and deduplication. Manual refresh; no background scheduler. Historical price evidence does not trigger current-price/stock reminders. |
| 12 | Discovery | `interests/discovery.jac`: catalog-based, dietary/dislike filtering, weekly limit, reason and confirmation. Hidden when its product belongs to another data mode. |
| 13 | Configuration | `app.toml`, `app_settings.py`, `.env.example`; mode/timezone/planning/reminder settings plus server-only provider credentials. |
| 14 | AI use with deterministic arithmetic | Intent extraction and follow-up intent routing in `ai/intents.py`; `ai/matching.py` ranks returned candidates by name/brand/size evidence and explains mismatches; confirmations are explicit; `ai/explanations.py` asks the model to select computed fact IDs and renders only authoritative values, with deterministic fallback. The LLM does not generate prices, route times, stock, diet compatibility, or arithmetic. Local Codex model acceptance is recorded below; optional retailer/API credentials remain separate. |
| 15 | Profile/interest/plan UI | `ui/workspace.cl.jac`, `shopping.cl.jac`, `history.cl.jac`: profile/needs editing, mode switch, address confirmation, nearby stores, paginated historical product evidence, route estimate, proposals and purchase outcomes. Browser tested with real Geoapify/Open Prices responses. |
| 16 | Tests | 136 Jac tests and 110 Python tests (246 total, 2026-10-27), plus a GitHub Actions test/build workflow. Synthetic fixtures are labeled; actual network evidence under `docs/samples` is separate. Frontend build and browser checks described below. |
| 17 | Chat integration | `server/chat.jac` calls `harness/agent.jac`; validated profile/need updates use the shared operations automatically; persistent conversational state asks for missing inputs and generates plans when ready. Feedback stays pending and plan acceptance/purchases are never automatic. Missing-key path verified in the earlier browser run; authenticated local Codex extraction, confirmation, planning and grounded explanation verified. Legacy `take_turn` / identity pipeline helpers remain for backward compatibility, not the active UI route. |

## Verification recorded on 2026-10-12

- Offline suite: 75 Jac tests and 18 Python tests passed (93 total).
- `jac build main.jac`: successful with pinned Jac 0.16.7 / jac-client 0.3.25.
- Browser: profile saved, rice quantity 2 saved, two feasible demo options shown, plan accepted, purchase completed; no browser exceptions.
- Real browser: public Sunnyvale address resolved and confirmed, nearby stores loaded, Open Prices products and proof links displayed; current price/inventory labeled unknown.
- Live probe: geocoding, map POIs, Open Prices nearby locations, location-bound product records and walking round trip all succeeded. `scripts/verify_live.py` reproduces the public-address example.
- LLM: no local credential; schema/validation/confirmation tested offline, missing-key behavior verified. Configure a compatible LLM to verify actual Chinese/English extraction and full chat turns.

## Remaining scope boundaries

Open Prices is historical, contributor-dependent and incomplete: Ann Arbor's tested radius returned zero records. It satisfies the user-approved source-evidence scope, not a promise of real-time store inventory. Kroger production access and scheduled TheRide visits are now verified in the 2026-10-27 update above. Retailer checkout, live transit predictions, background notifications, multi-user deployment/login UI and distributed coordination are not implemented. The demo graph/plan lifecycle remains usable without external accounts.

## Follow-up verification (2026-10-21 America/New_York)

- Fixed demo expiry without changing raw fixture dates or real-source timestamps. Current-clock and 2030 tests build plans; expired quotes still fail at the planner layer before explicit mock renewal.
- Unit prices use compatible dimensions and eligible membership prices. UI and plan snapshots distinguish package cost from normalized cost; missing fields remain unknown.
- Offline suites: 82 Jac + 33 Python tests passed. `jac build main.jac` passed. CI is configured for pull requests and `main`, but GitHub-hosted execution awaits pushing the workflow.
- Local Codex login: two real bilingual intent cases passed; sanitized usage evidence is in `samples/llm-verification.json`. The first exploratory response exposed an ambiguous transport schema, which was clarified before the successful run.
- `LLM_BACKEND=codex jac run scripts/verify_chat.jac`: real intent left the graph unchanged until confirmation; confirmation generated a proposed plan; a follow-up explanation selected authoritative computed facts. No automatic acceptance or purchase. The initial test with the default 15-minute walk limit correctly produced no feasible rice plan; the detached test now explicitly uses a 30-minute limit.
- Browser (isolated local graph): package/unit prices visible, feasible plan generated and accepted, purchase marked completed; no page exceptions. Your saved shopping data was not used for this check.
- `scripts/verify_llm.py` additionally contains ten English cases for optional evaluation (translated after the original multilingual checks). Only the recorded two-case subset and graph flow were executed; no claim of ten-case or paid API acceptance.

Remaining issues outside this change: real public-transit timetables (#3), target-area current inventory/price coverage (#2), optional Kroger access, and deployment/background jobs. #6 is a research/acceptance deliverable; this change does not claim to add live retailer inventory or close GitHub issues automatically.

## Real-address visit recommendations (2026-10-21)

`planning/visits.py`, `server/visits.jac`, and `ui/visits.cl.jac` add confirmed device/typed location, radius selection, historical product matching, ranked nearby visits, walking/cycling/driving routes, free-time checks, acceptance/cancellation, persistent per-item outcomes and input/route invalidation. Live chat's confirmed `plan` intent uses the same workflow; explanations render evidence and constraints directly. This extends tasks 3, 7, 9, 10, 14, 15 and 17 under the agreed historical-data scope.

137 offline tests pass (89 Jac + 48 Python); the frontend build passes. The fixed public-address HTTP probe verifies real geocoding/reverse geocoding, historical rice/dairy-milk matches and eligible routes. [Walkthrough and scope](REAL_STORE_VISITS.md), [sanitized actual-provider evidence](samples/store-visits-verification.json).

Real visit options are single-store alternatives with unknown current costs/stock/hours; they do not establish live cost optimization, delivery feasibility or public-transit timetables. Existing demo/current-offer planning remains separate. No GitHub issue was automatically closed.

Browser acceptance used a separate temporary graph: permitted device location and typed address confirmation, three real-store options, required acknowledgment, acceptance, rice purchase, milk not-found feedback, persistence after reload, and denied-location fallback all passed. The final browser check had no page exceptions. User shopping data was not modified by these checks.

## Conversational collection and automatic form updates

`harness/agent.jac` and `ai/conversation.jac` track an active planning request and its current question. Follow-up replies update the profile/needs through shared validated operations, including WATCH-to-NEED promotion only when explicitly requested as a purchase. Context carries saved values, current question, local date/time and address candidates. A unique high-confidence precise address is saved; ambiguous/coarse results require a numbered reply in chat. A failed replacement-address lookup prevents using the old address accidentally. Once prerequisites are met, planning runs and a grounded store summary is returned in chat. Profile-only updates outside an active planning conversation do not force a new search.

Missing price history or an unset real-mode budget does not block a location-only visit; unsupported BUS-only travel and missing free time are explicitly requested instead of being silently changed. Saved walking/carry defaults remain in effect unless the user changes them. “Stop planning” stops gathering while preserving saved information and accepted visits. Feedback and acceptance still require confirmation. Older confirmation-based evidence above describes the previous behavior.

Offline tests: 99 Jac + 54 Python pass; frontend build passes. New tests cover multi-turn collection, automatic form values, ambiguous/failed addresses, unsupported travel, watched needs, invalid model input, explicit feedback and stopping a conversation.

Real-browser verification (isolated graph, public Sunnyvale address): four actual Codex extraction calls covered Chinese needs, address/profile values, an ambiguous-address selection and a short free-time reply. Budget, transport, walk limit and time fields updated automatically; three real-provider store options appeared both in chat and the panel, without setup confirmation. Reload retained the profile and plans; no page exceptions. [Sanitized evidence](samples/conversation-verification.json). This test did not edit the user's saved shopping data.

## Initial Jac migration (2026-10-23)

Moved three independent business-rule modules to Jac: `ai/conversation.jac` (missing fields, follow-up questions and grounded summaries), `integrations/validation.jac` (profile/need validation and normalization), and `pricing.jac` (package and unit-price calculations). Their Python implementations were removed; this is not a Jac wrapper around Python business logic. Existing Jac callers keep the same module paths. Remaining Python entrypoints explicitly enable Jac's import hook using `import jaclang`.

105 Jac tests and 54 Python tests pass (159 total), including six new Jac regression tests for bilingual values, provider notices, unknown/zero historical prices, and invalid numeric/time inputs. The frontend build passes. An additional local comparison against the pre-migration Python modules covered 590 cases with identical returned values and exception types/messages; temporary baseline copies are outside the repository. No model/provider requests were needed for this migration verification.

External API adapters, model transport/intent extraction, real-store matching/ranking and some utility modules remain Python. Migrating those larger integrations is a separate follow-up; this change keeps the application behavior intact.


## Reliability and real-store completion (2026-10-26)

Implemented the #14 partial-update fix through the model schema, Jac validation, graph merge and chat workflow. Unspecified constraints persist; explicit removal is supported. Specification changes revoke old confirmed matches. Added Jac dated scheduling, exact-identity map-hours enrichment, preparation time after provider completion, and stale-departure rejection. Visits now record full/partial purchase quantities and optional actual spending, preserve outstanding needs and support subsequent recommendations. Server-side bounded conversation history restores after reload and can be cleared independently of the shopping profile.

Validation: 113 Jac + 67 Python tests (180 total), frontend build, two actual bilingual model extraction cases, a public-address provider check, and an isolated browser walkthrough. Browser checks cover dated hours, acceptance, partial quantities, spending, reload, missing-model error persistence and clearing the transcript without deleting plans. Fixtures are explicitly synthetic; real HTTP evidence uses a public Sunnyvale address. No personal shopping graph was used.

These changes improve #8 tasks 4, 7, 9, 10, 15, 16 and 17 and implement #14's acceptance criteria. They do not close GitHub issues automatically or implement real transit, live stock, delivery, background jobs or hosted multi-user operation. The original issue checklist is an old snapshot; use [current product gaps](PRODUCT_GAPS.md) to distinguish implemented behavior from the remaining vision.

## Explicit new shopping plan entry

Added a visible **New shopping plan** button with its effects stated beside it. The Jac operation starts an empty list and fresh conversation, preserves the profile, pauses previous needs, cancels unfinished plans, and retains accepted real-visit purchase history. Previous needs can be restored explicitly. Adding the same category afresh resets trip-specific quantity/specifications/snoozing instead of silently inheriting the old trip. Request IDs prevent duplicate retries from clearing newly entered needs. Clearing chat remains a separate action.

Eight additional detached-graph regression cases cover list isolation, accepted-plan replacement, purchase preservation, default specifications, restoration, retries, invalid requests, separate users, mock plans, watch/replenishment behavior and the next chat turn. Current suite: 121 Jac + 67 Python tests (188 total).


### English interface and workspace layout (2026-10-26)

The Jac client now uses a responsive workspace with My list, Plans & stores and Preferences tabs alongside a persistent assistant. New shopping plan remains a prominent header action; demo simulation and historical real-store evidence have distinct labels. Tabs support keyboard navigation. New chat-generated plans and pending confirmations surface in Plans & stores. Assistant templates and model instructions now use English, including legacy language preferences. Authored examples and fixtures use English; the older conversation verification artifact is explicitly labeled as editorial summaries of its original run, not new model evidence.

Validation: 121 Jac and 67 Python tests, client build, and an isolated Chromium walkthrough of desktop/mobile layouts, preferences, real-visit acceptance, partial purchases, fresh lists, history/restore, demo comparison and chat controls. No new paid model or live-provider calls were made for this interface update.


### Scheduled bus visits (2026-10-27)

TheRide GTFS now supports Ann Arbor/Ypsilanti outbound and return shopping journeys, with service-date exceptions, walking connections, transfer limits, a boarding buffer, and shopping/free-time checks. The core calendar and routing rules are implemented in `planning/transit.jac`; `integrations/transit.py` handles official feed I/O and verified pedestrian adapters. New English itinerary cards show scheduled bus numbers, stops, walks, waits, source/version and unknown fares. BUS-only chat requests proceed to planning instead of asking the user to switch transport. Changing a transfer limit invalidates stale visits.

A real public-address HTTP check found 62/23 and 23/62 journeys between Michigan Union and Kroger on Plymouth Road. Live predictions, detours and fare calculations remain unavailable. This implements the scheduled-journey part of #3 and extends #8's route/time feasibility; no GitHub issue is automatically closed.


Validation: 125 Jac + 86 Python tests (211 total), client build, isolated desktop/mobile bus-workflow checks with no page errors, and the separately recorded real public-address HTTP probe passed. No paid LLM calls were needed for this transit update.


### Real multi-store and entered-delivery comparisons (2026-10-27)

Real mode now compares branch-bound current prices across up to two physical stores, with directional inter-store travel, shopping time, return deadlines, cumulative carrying weight and scheduled bus support. Manual checkout quotes bind the exact basket/address, require complete fees and a fitting receipt window, and remain explicitly unverified by API. Mixed plans avoid the delivery window; acceptance rechecks each retailer branch and requires separate checkout reconfirmation. No order is placed. See [implementation, walkthrough and validation](MULTISTORE_DELIVERY.md).

This extends tasks 6–10 and 14–17. The real two-store API probe and separately synthetic delivery/browser checks passed. Older single-store-only and demo-only statements above describe their dated snapshots. Automatic checkout, additional retailer coverage and larger optimization searches remain open; no GitHub issue was closed automatically.

## Background reminders, notifications and spending budget (2026-10-31)

Extends tasks 11 (reminders), 13 (configuration), 15 (UI) and 16 (tests), and completes the Phase 2 roadmap item "scheduled refresh, notification deduplication, and quiet hours".

- **Scheduled checks:** `server/background.jac` registers a Jac `@schedule` function that runs every minute on the server's scheduler thread. Each tick opens a request-style context per user root, as the HTTP server does. For users who opted in, it runs the panel's refresh every `background_check_minutes` (`app.toml`, default 30), skipping quiet hours, then commits. A write conflict with a concurrent request defers that user's check to the next tick. Scheduled callables are excluded from the public API.
- **Email delivery:** `notify/delivery.jac` (rules) and `integrations/channels.py` (SMTP, stdlib only) send one digest email per check, each reminder at most once, nothing during quiet hours, with exponential backoff (5 minutes doubling to 6 hours). Changing the address resets its receipts. A phone's mail app shows these as notifications, so no extra app is needed. SMS and app push are not implemented. Setup: [NOTIFICATIONS.md](NOTIFICATIONS.md).
- **Ledger and budget:** `budget/ledger.jac` records manual expenses and actual amounts paid on store visits, with request-id idempotency, corrections that keep history, voiding instead of deletion, ISO-week totals in the configured timezone, a category breakdown and four weeks of history. Open plans whose known current cost exceeds this week's remaining budget get an advisory note. Historical reference prices are never used, and acceptance and the planners' weekly-budget checks are unchanged.
- **UI:** a Budget tab, background and channel settings with test buttons, a reminder banner with optional browser notifications, and an error banner for failed panel operations.
- **Store merge fix:** `merge_stores` missed retailer branches whose Geoapify address starts with the store name, so the nearby-store list showed two Ann Arbor Kroger branches twice. `street_number` now reads the first address part that starts with a house number.

Validation: 156 Jac and 132 Python tests (288 total), plus the client build. `scripts/verify_e2e.py` passed 16 HTTP steps against an isolated server and a local fake SMTP server, once with fresh data and once on a copy of an existing local graph. The steps covered the ledger, idempotent retry, correction, future-date rejection, budget notes on demo plans, an in-app reminder, a test email, the scheduled digest email, no repeat email on the next tick, persistence across a restart and a clean server log. The copied-graph run found that retrying an undated expense a second later was rejected as a conflicting entry; the retry now keeps the first recorded date, with a regression test. A real test email was then sent through Gmail SMTP (port 587, STARTTLS, app password) on 2026-10-31; the scheduled digest path itself was verified against the local fake server. Headless Chrome at 390 px wide showed no horizontal overflow on any of the four tabs.

## Real-store rules in Jac and current-price labelling (2026-10-31)

- `planning/visit_rules.jac` now holds the real-store business rules that were in `planning/visits.py`: historical evidence matching (aliases, derivative exclusions, brand/size, dietary tags, record dates), bounded store choice, route choice, the single-store proposal (reference subtotal, weight, blockers, warnings, explanation) and post-lookup rescheduling. `planning/visits.py` keeps provider calls, concurrency and timing, with the same public functions, so callers and test patches are unchanged.
- Parity: 14,001 randomized cases compared the pre-migration Python module with the migrated version and returned identical results and exceptions, including NaN, infinite, boolean and string values in numeric fields. 3,000 of them were built to match, so the priced, weighed, carry-limit and budget-warning paths were covered. The comparison script and the baseline copy stayed outside the repository. `scripts/verify_current_prices.py` then passed against the real Kroger, Geoapify and TheRide sources (a bus visit to a Kroger branch).
- The Real stores banner said "today's prices and stock are unknown" even with Kroger configured. It now states current Kroger prices when Kroger credentials are present and keeps the historical wording otherwise. The recommendation button is renamed **Compare store options** to match **Compare plans** in demo mode.
