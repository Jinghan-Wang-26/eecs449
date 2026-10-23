# Issue #8 implementation and verification

This table maps the 17 README checklist items to implementation and verification evidence. Read [setup](SETUP_LIVE.md) and [API research](ISSUE6_API_RESEARCH.md) for the historical-price scope and remaining external-service verification requirements.

| # | Task | Implementation / evidence |
|---|---|---|
| 1 | Core profile, interests, plan objects | `models/profile.jac`, `interest.jac`, `plan.jac`; persistent graph and model tests. |
| 2 | Product/store/offer/item/leg/event/reminder nodes and edges | `models/catalog.jac`, `events.jac`, `graph.jac`; graph/catalog/feedback tests. Historical observations live separately in `ShoppingWorkspace.historical_prices`, not `Offer`. |
| 3 | Eleven shopping walkers | `server/walkers.jac`, imported from `main.jac`: update_profile, update_interest, refresh_offers, build_candidates, plan_shopping, plan_action, feedback, discover_products, check_reminders, sync, chat. Wrappers use the requesting root and shared validated operations. `build_candidates` returns ranked proposals rather than an unbounded raw candidate dump. |
| 4 | Natural language to structured needs | `ai/intents.py`, `harness/agent.jac`; bounded JSON parser for profile/needs/address/feedback/store lookup. Validate fields, numeric ranges and transport/time values; explicitly requested profile/need updates save automatically and missing inputs are collected conversationally. Offline parser and graph confirmation tests pass. Real Chinese/English extraction verified through the optional local Codex backend; API mode still requires `LLM_API_KEY`. |
| 5 | Mock dataset | `data/mock/catalog.json`: four fictional stores, twelve products, thirty offers. Kept separate from real-provider data; fixed raw fixture dates with application-only demo rebasing and persisted-expiry migration. |
| 6 | Basket cost | `planning/cost.jac`: eligible discounts, tax, fees, tips and travel; `pricing.py` supplies package and normalized unit prices with membership eligibility and snapshot display; tests include membership and unknown fees. |
| 7 | Hard constraints | `planning/constraints.jac`, `inputs.jac`: budget, carry, time, modes, transfers, windows, freshness, dietary evidence. Missing mass/route/tax assumptions block optional current-offer live planning. |
| 8 | In-store/delivery/mixed ranking | `planning/candidates.jac`: cost/convenience/balanced, bounded channel count and 20,000 candidate/combination limits. Mock scenarios verify all channels. Historical observations cannot supply live delivery fees or prices. |
| 9 | Plan lifecycle | `planning/lifecycle.jac`, `server/workflows.jac`: UUID keys, mode-specific selection, acceptance/cancellation, partial outcomes, review after changes. Reject expired quotes at acceptance. |
| 10 | Feedback and sync | `feedback/apply.jac`, `sync/engine.jac`: validated batches, persistent event IDs, no duplicate application, coalesced replan and explicit review of accepted plans. Live public API rejects injected offer updates. |
| 11 | Reminders | `notify/reminders.jac`: replenishment, target price and restock, cooldown, quiet hours, snooze/ignore/dismiss and deduplication. Manual refresh; no background scheduler. Historical price evidence does not trigger current-price/stock reminders. |
| 12 | Discovery | `interests/discovery.jac`: catalog-based, dietary/dislike filtering, weekly limit, reason and confirmation. Hidden when its product belongs to another data mode. |
| 13 | Configuration | `app.toml`, `app_settings.py`, `.env.example`; mode/timezone/planning/reminder settings plus server-only provider credentials. |
| 14 | AI use with deterministic arithmetic | Intent extraction and follow-up intent routing in `ai/intents.py`; `ai/matching.py` ranks returned candidates by name/brand/size evidence and explains mismatches; confirmations are explicit; `ai/explanations.py` asks the model to select computed fact IDs and renders only authoritative values, with deterministic fallback. The LLM does not generate prices, route times, stock, diet compatibility, or arithmetic. Local Codex model acceptance is recorded below; optional retailer/API credentials remain separate. |
| 15 | Profile/interest/plan UI | `ui/workspace.cl.jac`, `shopping.cl.jac`, `history.cl.jac`: profile/needs editing, mode switch, address confirmation, nearby stores, paginated historical product evidence, route estimate, proposals and purchase outcomes. Browser tested with real Geoapify/Open Prices responses. |
| 16 | Tests | 99 Jac tests and 54 Python tests (153 total), plus a GitHub Actions test/build workflow. Synthetic fixtures are labeled; actual network evidence under `docs/samples` is separate. Frontend build and browser checks described below. |
| 17 | Chat integration | `server/chat.jac` calls `harness/agent.jac`; validated profile/need updates use the shared operations automatically; persistent conversational state asks for missing inputs and generates plans when ready. Feedback stays pending and plan acceptance/purchases are never automatic. Missing-key path verified in the earlier browser run; authenticated local Codex extraction, confirmation, planning and grounded explanation verified. Legacy `take_turn` / identity pipeline helpers remain for backward compatibility, not the active UI route. |

## Verification recorded on 2026-10-12

- Offline suite: 75 Jac tests and 18 Python tests passed (93 total).
- `jac build main.jac`: successful with pinned Jac 0.16.7 / jac-client 0.3.25.
- Browser: profile saved, rice quantity 2 saved, two feasible demo options shown, plan accepted, purchase completed; no browser exceptions.
- Real browser: public Sunnyvale address resolved and confirmed, nearby stores loaded, Open Prices products and proof links displayed; current price/inventory labeled unknown.
- Live probe: geocoding, map POIs, Open Prices nearby locations, location-bound product records and walking round trip all succeeded. `scripts/verify_live.py` reproduces the public-address example.
- LLM: no local credential; schema/validation/confirmation tested offline, missing-key behavior verified. Configure a compatible LLM to verify actual Chinese/English extraction and full chat turns.

## Remaining scope boundaries

Open Prices is historical, contributor-dependent and incomplete: Ann Arbor's tested radius returned zero records. It satisfies the user-approved source-evidence scope, not a promise of real-time store inventory. Kroger authenticated access is optional and remains unverified. Real transit schedules, retailer checkout, background notifications, multi-user deployment/login UI and distributed coordination are not implemented. The demo graph/plan lifecycle remains usable without external accounts.

## Follow-up verification (2026-10-21 America/New_York)

- Fixed demo expiry without changing raw fixture dates or real-source timestamps. Current-clock and 2030 tests build plans; expired quotes still fail at the planner layer before explicit mock renewal.
- Unit prices use compatible dimensions and eligible membership prices. UI and plan snapshots distinguish package cost from normalized cost; missing fields remain unknown.
- Offline suites: 82 Jac + 33 Python tests passed. `jac build main.jac` passed. CI is configured for pull requests and `main`, but GitHub-hosted execution awaits pushing the workflow.
- Local Codex login: two real bilingual intent cases passed; sanitized usage evidence is in `samples/llm-verification.json`. The first exploratory response exposed an ambiguous transport schema, which was clarified before the successful run.
- `LLM_BACKEND=codex jac run scripts/verify_chat.jac`: real intent left the graph unchanged until confirmation; confirmation generated a proposed plan; a follow-up explanation selected authoritative computed facts. No automatic acceptance or purchase. The initial test with the default 15-minute walk limit correctly produced no feasible rice plan; the detached test now explicitly uses a 30-minute limit.
- Browser (isolated local graph): package/unit prices visible, feasible plan generated and accepted, purchase marked completed; no page exceptions. Your saved shopping data was not used for this check.
- `scripts/verify_llm.py` additionally contains ten bilingual cases for optional evaluation. Only the recorded two-case subset and graph flow were executed; no claim of ten-case or paid API acceptance.

Remaining issues outside this change: real public-transit timetables (#3), target-area current inventory/price coverage (#2), optional Kroger access, and deployment/background jobs. #6 is a research/acceptance deliverable; this change does not claim to add live retailer inventory or close GitHub issues automatically.

## Real-address visit recommendations (2026-10-21)

`planning/visits.py`, `server/visits.jac`, and `ui/visits.cl.jac` add confirmed device/typed location, radius selection, historical product matching, ranked nearby visits, walking/cycling/driving routes, free-time checks, acceptance/cancellation, persistent per-item outcomes and input/route invalidation. Live chat's confirmed `plan` intent uses the same workflow; explanations render evidence and constraints directly. This extends tasks 3, 7, 9, 10, 14, 15 and 17 under the agreed historical-data scope.

137 offline tests pass (89 Jac + 48 Python); the frontend build passes. The fixed public-address HTTP probe verifies real geocoding/reverse geocoding, historical rice/dairy-milk matches and eligible routes. [Walkthrough and scope](REAL_STORE_VISITS.md), [sanitized actual-provider evidence](samples/store-visits-verification.json).

Real visit options are single-store alternatives with unknown current costs/stock/hours; they do not establish live cost optimization, delivery feasibility or public-transit timetables. Existing demo/current-offer planning remains separate. No GitHub issue was automatically closed.

Browser acceptance used a separate temporary graph: permitted device location and typed address confirmation, three real-store options, required acknowledgment, acceptance, rice purchase, milk not-found feedback, persistence after reload, and denied-location fallback all passed. The final browser check had no page exceptions. User shopping data was not modified by these checks.

## Conversational collection and automatic form updates

`harness/agent.jac` and `ai/conversation.py` track an active planning request and its current question. Follow-up replies update the profile/needs through shared validated operations, including WATCH-to-NEED promotion only when explicitly requested as a purchase. Context carries saved values, current question, local date/time and address candidates. A unique high-confidence precise address is saved; ambiguous/coarse results require a numbered reply in chat. A failed replacement-address lookup prevents using the old address accidentally. Once prerequisites are met, planning runs and a grounded store summary is returned in chat. Profile-only updates outside an active planning conversation do not force a new search.

Missing price history or an unset real-mode budget does not block a location-only visit; unsupported BUS-only travel and missing free time are explicitly requested instead of being silently changed. Saved walking/carry defaults remain in effect unless the user changes them. “Stop planning” stops gathering while preserving saved information and accepted visits. Feedback and acceptance still require confirmation. Older confirmation-based evidence above describes the previous behavior.

Offline tests: 99 Jac + 54 Python pass; frontend build passes. New tests cover multi-turn collection, automatic form values, ambiguous/failed addresses, unsupported travel, watched needs, invalid model input, explicit feedback and stopping a conversation.

Real-browser verification (isolated graph, public Sunnyvale address): four actual Codex extraction calls covered Chinese needs, address/profile values, an ambiguous-address selection and a short free-time reply. Budget, transport, walk limit and time fields updated automatically; three real-provider store options appeared both in chat and the panel, without setup confirmation. Reload retained the profile and plans; no page exceptions. [Sanitized evidence](samples/conversation-verification.json). This test did not edit the user's saved shopping data.
