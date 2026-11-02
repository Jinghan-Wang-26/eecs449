# UI redesign plan: Motion Desk (v3.2)

Status: implemented 2026-11-01 in one change rather than eight PRs (see [§11](#11-implementation-notes)).
Prototype: [Motion Desk v3.2](https://claude.ai/artifact/EAN566koTzFyf8NBx6VJ4U) (private to the owner; share it from the page before sending the link).

This plan turns the current two-column workspace (`ui/chat.cl.jac`, `ui/shopping.cl.jac`, `ui/workspace.cl.jac`, `ui/visits.cl.jac`) into a trip-centred layout. **Every action the current UI offers stays available.** The redesign is front-end only. No walker, planner or data-model change is required; one optional server addition is listed at the end.

## 1. Goals and non-goals

Goals:

- Show one main thing per screen, with one primary button, following the trip: **List → Options → Route → Shop**.
- Put the deciding numbers first (estimated total, active time, carried weight, budget left), each with its evidence label.
- Make the interest pool (NEED / REPLENISH / WATCH / DISCOVER) visible without competing with the list.
- Connect chat and workspace: when a reply changes the plan, show what changed and where.
- Give the product a distinctive look through a small set of meaningful motions.

Non-goals:

- New planning rules, data sources or delivery automation.
- Hiding unknowns. Every Unknown, user estimate and user-entered quote stays labelled as it is today.
- Live-transit styling. Nothing may animate like a real-time bus position or countdown.

## 2. Target layout

```
┌ top bar: brand · Trips ▾ · Budget · Preferences · Demo/Real stores · + New trip ┐
├──────────────── workspace (≈60%) ───────────────┬──── assistant (≈40%) ────────┤
│ TripBar: name · status · 3 stats · prefs · Edit │ header + orb                  │
│ StageNav: List · Options · Route · Shop         │ messages + change cards       │
│ stage body (one primary action)                 │ suggestions + composer        │
│ footer: evidence time · sources                 │                               │
└─────────────────────────────────────────────────┴───────────────────────────────┘
```

Under 740 px, the two columns become a **Plan / Assistant** segmented control. The Assistant tab shows a count of unread replies, and a one-line preview of the latest reply appears at the bottom.

Budget and Preferences move from tabs to top-bar views that open in place of the stage body.

## 3. Screen-by-screen mapping to existing data

All fields below already exist in the `ShoppingAction` snapshot (`server/shopping.jac`, `workspace_view`) unless marked *new (client)*.

### 3.1 TripBar (`ui/tripbar.cl.jac`, new)

| Slot | Source |
|---|---|
| Title | "Your first trip" until the list has items; otherwise the trip name (*new (client)*: "Saturday groceries" from the first free window, else "Shopping trip") |
| Status pill | Derived stage (§4): `BUILDING LIST`, `n OPTIONS FIT`, `READY TO ACCEPT`, `NEEDS REVIEW`, `SHOPPING`, `COMPLETE` |
| Stats | Per stage. List: item count, budget left. Options/Route: selected plan `estimated_total`, `known_net_weight_kg` vs `profile.carry_limit_kg`, budget left. Shop: picked count, carried weight, basket estimate. Complete: reported paid, spent this week, left |
| Budget left | `snapshot.budget.remaining` ("Not set" when `weekly_budget` is 0). It is never reduced by plan estimates |
| Preferences line | `profile.free_windows`, `profile.transport`, `profile.max_transfers`, `profile.carry_limit_kg`; **Edit** opens Preferences |

In real mode, the List stage has no known weight yet: product weights come from quotes. The weight stat stays hidden until a plan exists, and a stat never shows a value that has no source.

### 3.2 List stage (`ui/shopping.cl.jac`)

- The current list rows stay, with the quantity stepper and the Pause / Purchased actions.
- The quick-add form shrinks to one inline row, and the full form opens on demand.
- **Interest strip** (*new component* `ui/interests.cl.jac`): up to three cards, showing only items that need attention:
  - REPLENISH due within 3 days, using the reminder from `snapshot.reminders` with kind `REPLENISH`;
  - a WATCH item whose `PRICE_DROP` / `RESTOCK` reminder is active;
  - DISCOVER items from `snapshot.discoveries`, with their `reason`.
  
  The actions are the existing `discovery` and `reminder` operations. A "+n not due" link opens the full list, which is today's *Discoveries & reminders* content.
- Primary button: **Find shopping options** runs `recommend_visits` in real mode and `plan` in demo mode, then switches to Options.
- A new background reminder appears as a dismissible toast. This replaces the current banner but uses the same `seen_reminders` logic.
- **Background checks, desktop notifications and email settings move to Preferences → Reminders**, unchanged.

### 3.3 Options stage (`ui/plancard.cl.jac`, new; used by `visits.cl.jac`)

The options are split into three groups:

| Group | Rule |
|---|---|
| Recommended (expanded card) | The `accept_allowed` plan labelled `Balanced` in `comparison_labels`. Otherwise, the first `accept_allowed` plan in server order |
| Alternatives (one-line rows) | Other `accept_allowed` plans; at most two visible |
| Folded | Plans with `blockers`, grouped by first blocker, e.g. "2 options are over your 8 kg limit". Plans with an unknown total that cannot be accepted, e.g. "Delivery only needs a checkout quote for all items" |

Recommended card, top to bottom:

1. **Reason sentence** (*new (client)*), built only from known numbers. For example: "Costs $0.53 more than Westgate, but takes 17 min less." The comparison partner is the plan labelled `Lowest estimated total` (or `Least active time`). If either total or time is unknown, fall back to the label text.
2. Three aligned metrics: `estimated_total` (Unknown if null), `active_min`, `known_net_weight_kg` / carry limit.
3. A time strip whose segments are proportional to the route legs (walk / wait / bus / shop / order allowance).
4. A cost breakdown: `retail_subtotal`, `delivery_total` labelled **your entered quote**, transport labelled **your estimate** (from `profile.transport_cost`), and `tax_rate` as the saved estimate.
5. Labels (`comparison_labels`) and evidence: "Kroger – Washtenaw · checked {quote_checked_at} · stock not reserved".
6. Budget note from `workspace.budget_notes`, shown only when the server returns one.

Address lookup, nearby stores, historical prices, the optional Kroger query and the delivery-quote form stay in a **Details** fold under the cards. They are moved, not removed.

Demo mode uses the same card with `plan.total`, `plan.minutes`, `plan.weight`, `plan.strategy` and `plan.explanation`.

### 3.4 Route stage (`ui/routeline.cl.jac`, new)

- **RouteLine** (SVG) draws one row per direction or segment, using either source:
  - `route.outbound` / `route.returning` legs for single-store bus trips (`TransitItinerary` data);
  - `route.segments[].legs` for multi-store and mixed trips (`StoreItinerary` data).
  
  Leg width is proportional to minutes. Colours: walk grey, wait light, bus blue with the route badge, shop green.
- **Key times** row: leave home, first bus, store arrival, return bus, home. After a change, each value shows the previous one struck through (§6.2).
- **Carry check**: retail items stacked by `weight_kg × qty` against `carry_limit_kg`. Delivered items appear in a separate dashed box with the delivery window.
- The existing full leg lists stay under **Show all steps**, as today's `<details>`.
- Primary button: **Continue** goes to acceptance.

### 3.5 Accept and review (`visits.cl.jac`, restructured)

These are the same two checkboxes and the same request as today:

- "I reviewed the product matches and unknowns…" (`acknowledged`)
- "I rechecked merchant checkout…" (`delivery_ack`, only when `plan.delivery_quote`), with the quote's `valid_until` shown as an amber time chip

The delivery window is shown as information only, because planning already checked home availability.

The button keeps the current label **Recheck and accept**. It stays disabled until the required boxes are ticked. **Nothing is ticked automatically, and no animation suggests a confirmation.**

The response decides what happens next:

- Accepted with no `quote_changes`: go straight to Shop.
- `quote_changes` or `review_reason` present: on the same screen, expand a review box listing each change as old → new. Then show **Accept with new prices** (repeat `accept` with the new `quote_revision`) and **Back to options**. The checkboxes reset, as they do now, because they are keyed by `quote_revision`.

### 3.6 Shop stage (`ui/instore.cl.jac`, new)

- **Picked** is local state only: *new (client)*, per `plan.key + category`, saved in `localStorage` inside try/catch so it survives a phone reload. Picking calls no server action and does not touch the budget.
- The TripBar shows **Picked n / m**, **In your bags** (sum of picked weights) and **Basket estimate** (sum of picked `current_amount`). This is never shown as "paid".
- Delivery items appear as a to-do with "Open merchant ↗" (`delivery_quote.source_url`) and the existing statement that no order is placed.
- Primary button: **Checked out? Record purchase** opens the Record sheet.

### 3.7 Record purchase (sheet inside `instore.cl.jac`)

- One row per item with `outcome == "PENDING"`:
  - packages bought, prefilled with `qty`;
  - amount paid, prefilled with `current_amount`;
  - a **Not found** toggle.
  
  Picked items are prefilled as bought; unpicked items as Not found.
- **Save purchases** awaits one `visit_action` / `outcome` call per row, using today's payload: `PURCHASED` when bought = qty, `PARTIAL` when fewer, `NOT_FOUND` when toggled.
- `server/visits.jac` already writes `actual_paid` to the ledger with id `visit:{plan}:{category}`. Retrying is therefore safe.
- If a call fails, stop and show which rows were saved. Saved rows stop being `PENDING`, so reopening the sheet lists only what is left.
- Afterwards, show the Complete summary: items recorded, total reported paid, `budget.remaining` and outstanding delivery payments. Offer **Record delivery payment** (opens Budget → Record an expense, prefilled) and **View budget**.

### 3.8 Budget and Preferences views

- **Budget**: today's `BudgetPanel`, restyled. The four-week chart and ledger stay here.
- **Preferences**: today's profile form. These fields change from free text to controls; the payload sent to `update_profile` stays the same:
  - transport → toggle chips;
  - free time → day + time-range rows;
  - dietary and memberships → chips.
  
  The Reminders section (moved from List) contains background checks, desktop notifications and email.

## 4. Stage derivation (client)

```text
first_use  = no list items and no address
stage      = List     if no open plans
           = Options  if open plans and none accepted
           = Route    if user selected a plan (local) and it is PROPOSED
           = Shop     if a plan is ACCEPTED / IN_PROGRESS (or NEEDS_REVIEW → Route with review box)
           = Complete if the newest visit is COMPLETED in this trip
```

The user can always click an earlier stage. The stage shown never changes server state.

## 5. Chat ↔ workspace link (no server change)

`SendMessage` returns text only, so changes are detected on the client:

1. In `ShoppingPanel.operate`, before replacing `snapshot`, diff the old and new values of a fixed watch list: `profile.free_windows`, `profile.budget`, `profile.carry_limit_kg`, `profile.transport`, the list items, the selected plan's `estimated_total`, `known_net_weight_kg`, `route.departure_at` / return arrival, and the set of plan keys.
2. Dispatch `window` event `workspace-changed` with `[{field, label, before, after, target_id}]`.
3. `ChatApp` listens and inserts an **ephemeral change card** under the latest assistant message: "Changed · Leave home 2:05 → 3:05 PM". Change cards are not saved to chat history.
4. Elements that can change carry `id={"chg-" + field}`. This lets the highlight (and, in full motion, the beam) find them.

The existing behaviour stays: a new plan or pending request still switches the workspace to Options.

The raw-JSON *Confirm chat request* card becomes a readable list built from `pending_intent` (field → new value), with the same Confirm / Discard actions.

## 6. Visual system and motion

### 6.1 Tokens (`ui/theme.cl.jac`)

These extend the current palette rather than replace it:

```
--ink #17251d   --muted #627068   --line #e1e7df   --paper #fff   --bg #eef2ed
--green #1d5a3f --green-deep #123d2b --mint #e1efe5 --glow #7af0b4
--amber #94580a --amber-bg #fff3dc --bus #2a6fcf --walk #b3bdb5 --shop #2f8a5a --hl #fff0a3
```

Semantic colours (over limit, needs review, user-entered) are separate from the accent.

**Font decision needed.** `theme.cl.jac` currently states "No external fonts or assets". The prototype uses Bricolage Grotesque (display numbers) and Figtree (UI). There are two options:

- (a) Keep system fonts, using `font-variant-numeric: tabular-nums` and heavier weights for numbers.
- (b) Add a Google Fonts `@import` with full fallbacks.

We recommend (a) for PR 1 and revisiting (b) once the layout is in.

### 6.2 Motion inventory

| Motion | Where | Spec | Accessibility |
|---|---|---|---|
| Fade-in | Stage body, messages | 0.35–0.6 s, 4–14 px rise, 40–70 ms stagger | Off under reduced motion |
| Change highlight | Any `chg-*` target | Background flash, fades in 2 s | Value is final from the first frame |
| Aurora | TripBar background only | Two blurred radial blobs, 16–22 s alternate loop | The only ambient motion; off under reduced motion |
| Odometer | TripBar stats | Digits roll to the new value in 0.55 s, 30 ms per-digit stagger | Visible digits `aria-hidden`; a visually hidden span holds the final value |
| Route draw | RouteLine | Each leg path draws with `stroke-dashoffset`, 0.7–0.9 s, in trip order; only when the route changes | Static when reduced |
| Change beam | Chat change card → `chg-*` target | 12 px glow dot, 0.9–1.1 s arc, `pointer-events: none` | Skipped when reduced or target missing |
| Carry stack | Carry check | Item blocks drop in order with slight overshoot | Off when reduced |
| First-use headline | TripBar on first use | Words rise in sequence, once | Text is present in the DOM from the start |
| Hover spotlight | Plan cards | Radial highlight follows the pointer | Pointer devices only |

Excluded: live-bus movement or countdowns, auto-ticked checkboxes, any animation on a confirmation control, and looping motion outside the TripBar.

Everything is CSS keyframes plus small effects:

- `can with (value) entry` drives the odometer.
- `element.animate` drives the beam.

No animation library is added. A single `@media (prefers-reduced-motion: reduce)` block disables all of it.

## 7. File changes

| File | Change |
|---|---|
| `ui/chat.cl.jac` | Replace header + `page-intro` with the top bar; two-column grid; mobile Plan/Assistant control; listen for `workspace-changed`; render change cards; assistant orb |
| `ui/chat.impl.jac` | Track unread replies for the mobile badge; no protocol change |
| `ui/shopping.cl.jac` | Replace tabs with StageNav + top-bar views; stage derivation; interest strip; reminder toast; move reminder and email settings to Preferences |
| `ui/shopping.impl.jac` | Snapshot diff and `workspace-changed` dispatch in `operate`; a `record_purchases` helper that awaits sequential `visit_action` calls |
| `ui/workspace.cl.jac` | Split: Preferences form (chips and time ranges) and a Details fold for address, stores, historical prices and the Kroger query |
| `ui/visits.cl.jac` | Use PlanCard / PlanRow / folds; restructured accept and review block; the per-item outcome form moves into the Record sheet |
| `ui/transit.cl.jac`, `ui/itinerary.cl.jac` | Kept as the "Show all steps" detail |
| `ui/delivery.cl.jac` | Unchanged form; reached from the folded "needs a quote" row and from Details |
| `ui/budget.cl.jac` | Restyle only |
| `ui/theme.cl.jac` | Tokens, new component styles, keyframes, reduced-motion block |
| New: `ui/tripbar.cl.jac`, `ui/stagenav.cl.jac`, `ui/odometer.cl.jac`, `ui/interests.cl.jac`, `ui/plancard.cl.jac`, `ui/routeline.cl.jac`, `ui/instore.cl.jac` | Components above |

Jac client notes: JSX attributes follow React naming. SVG presentation attributes are camelCase (`strokeWidth`, `strokeDasharray`), and inline styles use camelCase keys, as in the existing `style={{"whiteSpace": "pre-wrap"}}`. Wrap every `localStorage` access in try/except.

## 8. Delivery plan (one PR each)

1. **Shell**: top bar, TripBar without motion, StageNav, Budget/Preferences as views, reminder settings moved. Every existing control is still reachable.
2. **Options**: PlanCard, reason sentence, alternatives, folds, Details fold, readable chat confirmation.
3. **Route**: RouteLine, key times, carry check.
4. **Accept → Shop → Record**: restructured acceptance, picked state, Record sheet, Complete summary.
5. **Interests and Preferences controls**: interest strip, toast, chips and time ranges.
6. **Chat link**: snapshot diff, change cards, highlight targets.
7. **Motion**: aurora, odometer, route draw, beam, carry stack, first-use headline, spotlight, reduced-motion pass.
8. **Mobile**: Plan/Assistant control, unread badge, preview, thumb-reach buttons.

PRs 1–6 are useful without motion. PR 7 can be dropped or trimmed without affecting behaviour.

## 9. Verification

For every PR:

- `.venv/bin/jac build main.jac`, `.venv/bin/jac test`, `.venv/bin/python -m unittest discover -s tests -p 'test_*.py'`.
- `python scripts/verify_e2e.py` still passes (ledger, reminders, email).
- Headless Chrome at 390 px and 1280 px: no horizontal overflow and no console errors, in both demo and real modes.
- Keyboard: StageNav arrow keys work as today's tablist; focus is visible; every primary button is reachable.

Scenario walkthroughs (demo mode, plus one real-mode run with Kroger keys):

- New user: first-use → add items → options.
- Over the carry limit: overweight plans fold; a mixed plan is recommended.
- Leave later via chat: change card appears; key times show old → new; highlight lands on the leave time.
- Accept with an expired or changed quote: the review box lists `quote_changes`; boxes reset; accept again.
- Shop: picking changes neither `budget.spent` nor the ledger; Record with one changed price, one partial and one not-found item; ledger entries match; retrying after a forced failure creates no duplicates.
- Reduced motion on: no animation runs; all values read correctly with VoiceOver, and the odometer reads the final value only.

## 10. Optional server addition

If client-side diffs prove brittle, `SendMessage` could also return `{"reply": str, "changes": [...]}` from the workflow layer. This changes the walker's report shape and every caller (`chat.impl.jac`, tests), so it is out of scope for this plan.

## 11. Implementation notes

Implemented 2026-11-01. New components: `ui/planview.cl.jac` (shared plan facts and change detection), `ui/tripbar.cl.jac` (TripBar, Odometer, StageNav), `ui/interests.cl.jac`, `ui/options.cl.jac`, `ui/routeline.cl.jac`, `ui/instore.cl.jac`. `ui/visits.cl.jac` is split into VisitSearch, VisitDetails (read-only), AcceptPanel and VisitHistory. No server code changed.

Differences from the plan above:

- **Fonts:** system fonts only, as `theme.cl.jac` required; option (b) in §6.1 was not taken.
- **Stage title:** derived from the first saved free window ("Saturday shopping"), otherwise "Your shopping trip".
- **Record purchase** lists delivered items too, with a **Record later** choice, because a visit only becomes `COMPLETED` when every item has an outcome.
- **Acceptance** keeps exactly the two existing checkboxes. Delivery-window home availability is shown as information only, because planning already checked it.
- **`operate`** now returns whether the request succeeded and takes an optional `source`. `"chat"` triggers the snapshot diff and the `workspace-changed` event.

Jac client pitfalls found while building it:

- A local variable with the same name as a `has` field compiles to that field's setter. A local `days` in a render helper caused an infinite render loop (React error #301).
- `d.get("k")` returns `undefined` for a missing key, but `is None` compiles to `=== null`. Write `d.get("k", None)` before comparing with `None`.
- Inside `{if …}` blocks, expression statements in lambdas are wrapped in `__jac_view_kids.push(...)`. This is harmless in click handlers, but keep side effects in named functions.

Verified 2026-11-01:

- `jac build`, `jac test` and the 132 Python tests pass.
- Headless Chrome with an isolated server and demo data: List, Options, Route, Shop, Budget, Preferences (saving updates the profile) and a 390 px phone width without horizontal overflow.
- Real-store run at the public Michigan Union address, with read-only Kroger, Geoapify and TheRide lookups: options with server labels, the route line with key times, acceptance with the checkbox, in-store picking that leaves the budget unchanged, and Record purchase writing exactly the entered amounts to the ledger. Items not found stay on the list.
- A simulated chat-driven profile change shows a change card, a beam and highlights.
- A real LLM chat turn was not exercised.

## 12. Conversation-first start and next-step buttons (2026-11-01)

A follow-up after reviewing the redesign with new users in mind:

- **Conversation first.** While the list is empty and there are no plans, the workspace stays hidden and the assistant fills the page. A new user sees one question ("What do you need to buy?"), a large input, three example requests and two links: *I'd rather add items myself* and, in real-store mode, *Try it with sample stores*. The workspace slides in as soon as the first item or plan exists, when the user opens Budget or Preferences, or from *Open the workspace* under the chat input. On phones, the conversation stays in view when the workspace first appears, and the Plan tab is flagged.
- **Next-step buttons.** Under the conversation, the assistant offers one to three actions that match the trip's state. Examples: *Find shopping options*, *Set when I'm free*, *Set where I'm starting from*, *Use {recommended plan}*, *Review and accept this plan*, *Open my in-store list* and *See my budget*. A button runs the same workspace operation as the matching control. *Review and accept* only moves focus to the acceptance controls; it never accepts or ticks anything. The buttons are hidden while the assistant's last message ends with a question, because answering it is the next step.
- **Mechanics.** No server change. `ShoppingPanel` publishes a `workspace-summary` event (`ready`, `empty`, `mode`, `actions`) and runs `cartcompass-action` events. `ChatApp` decides the layout from the summary and falls back to the normal layout if no summary arrives within 2.5 s.
- **Verified.** On a fresh data directory with a real model call: the welcome page appeared, the first message added three items, the workspace slid in with an *Added to list* change card, and the buttons stayed hidden while the assistant asked for free time. With seeded items, the buttons moved the workspace through Options and Route, and focus landed on *Accept plan*. *New trip* returns to the conversation-first layout. The 390 px welcome page has no horizontal overflow.

## 13. Start address in Preferences, a simpler Options step (2026-11-01)

- **Why "Use my current location" seemed to do nothing.** The browser refused geolocation (error code 1, *User denied Geolocation*), and the only feedback was one line of grey text. The server side (`device_location`) works. On macOS the usual cause is that Location Services is off for the browser, or the site is set to *Block*.
- **`ui/address.cl.jac` (AddressPicker).** It offers the current location first and a typed address as a fallback. Each geolocation error code gets a visible explanation with the fix. Candidates show the street part first (reverse geocoding can lead with a place name such as "Panda Express"), and the address is saved only after **Start from here**. It lives at the top of **Preferences** and, in real-store mode, on the Options step only while no address is saved.
- **Current location by default.** In real-store mode without an address, *Find shopping options* (or the *Use my current location* next step) opens Options and asks for the location right away. After the shopper confirms the address, store options are compared automatically.
- **Options now holds only the decision:**
  - the recommended plan, alternatives and folded ineligible plans;
  - one line "From {street} · within {radius} · Change address" with *Compare again*;
  - a folded *About these results* and *Have a delivery checkout quote?*
  
  Nearby stores, historical prices and the Kroger product query moved to **Preferences → Advanced**. The long data-source banner moved to a tooltip on the footer.
- **Clearer numbers.** When the full total is unknown but store prices are known, cards show "Items · fare unknown $X" with a link to add the fare. Only a plan the shopper accepted pulls the workspace to *Review what changed*; a proposed plan that went stale stays in the list with a *Review* button.
- **Verified:**
  - Denied location shows the explanation.
  - A stubbed location leads to a candidate card, then **Start from here**, then three real Kroger and TheRide options with no extra click.
  - Demo-data screenshot regression passes, and `jac build` and `jac test` pass.
  - `tests/test_coverage.py::test_kroger_uses_app_query_and_keeps_fulfillment_flags` fails on the committed code as well (unrelated to the UI; likely date-dependent fixtures after 2026-11-01).

## 14. Demo mode removed

- The app always plans with real stores. `app.toml` defaults to `data_mode = "live"`; the Demo data / Real stores switch, *Try it with sample stores*, the demo Shop list and all demo branches in the plan cards, route and trip bar are gone. `planview.is_live`, `demo_labels`, `demo_summary` and `DemoShop` were deleted.
- A profile saved in the old demo mode is switched to real stores once, when the workspace first loads (`ShoppingPanel`, effect on `data_mode`).
- The backend keeps `set_mode` and the fixture catalog in `data/mock/` for offline tests: the Jac tests create profiles with `data_mode="mock"`, and `scripts/verify_e2e.py` writes `data_mode = "mock"` into its isolated settings file.

## 15. Accuracy and agent replies

- Chat log items no longer shrink (`.chat-log > * { flex-shrink:0 }`); change cards were squashed to a sliver in long conversations.
- `key_times` adds **Home** from `route.return_at` for single-store routes, and the trip bar reads leave/home by label (`trip_ends`) instead of the last entry, which was the store departure.
- Unknown values are never summed as zero: `tally` / `tally_label` show "Unknown" when nothing is known and "≥ x" when some values are missing (carry check, You carry, In your bags, basket estimate). A partly unknown weight is never shown in the green "fits" tone.
- Step ticks follow real progress (items, a chosen plan, an accepted plan, a recorded trip), not the step being viewed.
- Recording purchases: unticked items default to *Record later*, not *Not found*; the paid amount starts empty with the listed price as a hint, with a *Use listed prices for empty amounts* shortcut; the save line states what will be recorded.
- `ai/conversation.plan_summary` leads with the same recommendation as the Options step, gives one line per other usable option and folds blocked options into their reasons. With no product evidence, both chat and the Options card say the route fits but products are not confirmed.
- Current location watches for a fix for up to 45 s instead of one 15 s attempt (a Mac's first Wi-Fi fix is slow, and the macOS permission prompt runs down the clock). After 8 s it says it is still looking and points at the macOS prompt; at 45 s it explains the Wi-Fi and Location Services checks. A denial stops at once.
