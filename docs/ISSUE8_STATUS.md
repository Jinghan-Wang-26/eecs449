# Issue #8 implementation and verification

This table maps the 17 README checklist items to implementation and verification evidence. Read [setup](SETUP_LIVE.md) and [API research](ISSUE6_API_RESEARCH.md) for the historical-price scope and remaining external-service verification requirements.

| # | Task | Implementation / evidence |
|---|---|---|
| 1 | Core profile, interests, plan objects | `models/profile.jac`, `interest.jac`, `plan.jac`; persistent graph and model tests. |
| 2 | Product/store/offer/item/leg/event/reminder nodes and edges | `models/catalog.jac`, `events.jac`, `graph.jac`; graph/catalog/feedback tests. Historical observations live separately in `ShoppingWorkspace.historical_prices`, not `Offer`. |
| 3 | Eleven shopping walkers | `server/walkers.jac`, imported from `main.jac`: update_profile, update_interest, refresh_offers, build_candidates, plan_shopping, plan_action, feedback, discover_products, check_reminders, sync, chat. Wrappers use the requesting root and shared validated operations. `build_candidates` returns ranked proposals rather than an unbounded raw candidate dump. |
| 4 | Natural language to structured needs | `ai/intents.py`, `harness/agent.jac`; bounded JSON parser for profile/needs/address/feedback/store lookup. Validate fields, numeric ranges and transport/time values; user confirms changes. Offline parser and graph confirmation tests pass. Real model execution needs `LLM_API_KEY`. |
| 5 | Mock dataset | `data/mock/catalog.json`: four fictional stores, twelve products, thirty offers. Kept separate from real-provider data; intentionally dated fixtures. |
| 6 | Basket cost | `planning/cost.jac`: eligible discounts, tax, fees, tips and travel; tests include membership and unknown fees. |
| 7 | Hard constraints | `planning/constraints.jac`, `inputs.jac`: budget, carry, time, modes, transfers, windows, freshness, dietary evidence. Missing mass/route/tax assumptions block optional current-offer live planning. |
| 8 | In-store/delivery/mixed ranking | `planning/candidates.jac`: cost/convenience/balanced, bounded channel count and 20,000 candidate/combination limits. Mock scenarios verify all channels. Historical observations cannot supply live delivery fees or prices. |
| 9 | Plan lifecycle | `planning/lifecycle.jac`, `server/workflows.jac`: UUID keys, mode-specific selection, acceptance/cancellation, partial outcomes, review after changes. Reject expired quotes at acceptance. |
| 10 | Feedback and sync | `feedback/apply.jac`, `sync/engine.jac`: validated batches, persistent event IDs, no duplicate application, coalesced replan and explicit review of accepted plans. Live public API rejects injected offer updates. |
| 11 | Reminders | `notify/reminders.jac`: replenishment, target price and restock, cooldown, quiet hours, snooze/ignore/dismiss and deduplication. Manual refresh; no background scheduler. Historical price evidence does not trigger current-price/stock reminders. |
| 12 | Discovery | `interests/discovery.jac`: catalog-based, dietary/dislike filtering, weekly limit, reason and confirmation. Hidden when its product belongs to another data mode. |
| 13 | Configuration | `app.toml`, `app_settings.py`, `.env.example`; mode/timezone/planning/reminder settings plus server-only provider credentials. |
| 14 | AI use with deterministic arithmetic | Intent extraction and follow-up intent routing in `ai/intents.py`; `ai/matching.py` ranks returned candidates by name/brand/size evidence and explains mismatches; confirmations are explicit; explanations come from computed plan facts. The LLM does not generate prices, route times, stock, diet compatibility, or arithmetic. No claim of live-model evaluation without credentials. |
| 15 | Profile/interest/plan UI | `ui/workspace.cl.jac`, `shopping.cl.jac`, `history.cl.jac`: profile/needs editing, mode switch, address confirmation, nearby stores, paginated historical product evidence, route estimate, proposals and purchase outcomes. Browser tested with real Geoapify/Open Prices responses. |
| 16 | Tests | Original 65 Jac tests plus 10 workflow tests and 18 Python adapter/parser contract tests. Synthetic fixtures are labeled; actual network evidence under `docs/samples` is separate. Frontend build and browser checks described below. |
| 17 | Chat integration | `server/chat.jac` calls `harness/agent.jac`; pending drafts appear in workspace and apply through the same operations. No direct model-driven mutation or purchase. Missing-key path verified in browser; authenticated LLM acceptance remains pending. Legacy `take_turn` / identity pipeline helpers remain for backward compatibility, not the active UI route. |

## Verification recorded on 2026-10-12

- Offline suite: 75 Jac tests and 18 Python tests passed (93 total).
- `jac build main.jac`: successful with pinned Jac 0.16.7 / jac-client 0.3.25.
- Browser: profile saved, rice quantity 2 saved, two feasible demo options shown, plan accepted, purchase completed; no browser exceptions.
- Real browser: public Sunnyvale address resolved and confirmed, nearby stores loaded, Open Prices products and proof links displayed; current price/inventory labeled unknown.
- Live probe: geocoding, map POIs, Open Prices nearby locations, location-bound product records and walking round trip all succeeded. `scripts/verify_live.py` reproduces the public-address example.
- LLM: no local credential; schema/validation/confirmation tested offline, missing-key behavior verified. Configure a compatible LLM to verify actual Chinese/English extraction and full chat turns.

## Remaining scope boundaries

Open Prices is historical, contributor-dependent and incomplete: Ann Arbor's tested radius returned zero records. It satisfies the user-approved source-evidence scope, not a promise of real-time store inventory. Kroger authenticated access is optional and remains unverified. Real transit schedules, retailer checkout, background notifications, multi-user deployment/login UI and distributed coordination are not implemented. The demo graph/plan lifecycle remains usable without external accounts.
