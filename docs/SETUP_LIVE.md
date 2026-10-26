# Run CartCompass with real locations and historical store prices

## Local setup

Use Python 3.13 and this repository's pinned virtual environment:

```bash
cd /home/yuan-epic/EECS_449_Term_project/eecs449
source .venv/bin/activate
pip install -r requirements.txt
# Only for a new installation; preserve an existing .env:
test -f .env || cp .env.example .env
python scripts/check_credentials.py
jac start
```

Open http://localhost:8000. This is a local, single-user course demo; anonymous requests use the local root. Do not expose the development server as a shared production service. Jac authenticated API roots can isolate users, but a login UI and deployment hardening are not included.

## Credentials

**Geoapify** is required for typing an address, finding mapped stores and routing. At [MyProjects](https://myprojects.geoapify.com/), create a project, open **API keys**, and copy its key into the local `.env`:

```dotenv
GEOAPIFY_API_KEY=your_local_key
```

The [official project steps](https://myprojects.geoapify.com/help/projects/) automatically create the first key. Use an appropriate server-side IP restriction if you have a stable outbound IP; browser referrer restrictions do not match server-side requests. Keep attribution visible. Free quota is described in [the research report](ISSUE6_API_RESEARCH.md).

**Open Prices** needs no account/key for the public reads implemented here. It is the default source of historical store product/price records. It does not provide current inventory, current shelf prices, complete store assortment, delivery charges or a shopping cart. Missing coverage stays visible.

**Kroger** is optional. Leave `KROGER_CLIENT_ID` and `KROGER_CLIENT_SECRET` blank while registration is blocked. No repeated signup attempts are necessary for the default workflow. If an application is obtained later, the adapter supports client-credentials Products/Locations calls and uses `filter.locationId`. It does not need a customer login/redirect for read-only client-credentials requests. Never enter secrets as callback URLs. Authenticated Kroger responses still need live verification; synthetic tests alone are not access approval.

**Chat** optionally needs an OpenAI-compatible LLM provider configured with `LLM_API_KEY`, `LLM_BASE_URL` and `LLM_MODEL`. The example uses DeepSeek. The structured profile, interest and plan controls work without this key. The LLM extracts validated changes; explicitly stated needs/profile values save automatically, missing required information is requested in chat, and completing the answers triggers planning. Feedback and plan acceptance still require confirmation. Pricing and constraint arithmetic remain deterministic. API credentials are never sent in model context. Text the user types into chat is sent to their configured LLM provider, so only include address details there intentionally.

### Use the existing local Codex login (no new model API key)

This local-only option was tested with Codex CLI 0.154.0 signed in through ChatGPT. In your ignored `.env`, set:

```dotenv
LLM_BACKEND=codex
```

Run `codex login status`; if necessary, run `codex login` and sign in through the browser. Restart `jac start`. In this mode `LLM_API_KEY`, `LLM_BASE_URL` and `LLM_MODEL` are not used. No login tokens are copied into the project. The CLI uses its default model with low reasoning effort; user CLI configuration is not loaded.

Codex requests consume the quota/billing associated with the CLI login. This is not an unlimited free API. Two measured intent calls used 20,623 input tokens and 139 output tokens in total; CLI context adds overhead, so these figures are not equivalent to a direct API estimate. Use the structured controls for repeated price/planner tests. A request may take several seconds, has a 90-second timeout and is not automatically retried. Only one local Codex request runs at a time.

The adapter runs in a temporary directory with an ephemeral session and read-only sandbox. Shell, web search, connectors, hooks, remote plugins and agent delegation are disabled. It does not pass application/API secrets to the process. Prompts and supplied shopping context still go to the model service. Keep this backend on a trusted local computer; do not expose it as a public/hosted service or put your Codex login in GitHub Actions.

Official references: [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode), [authentication and billing](https://learn.chatgpt.com/docs/auth).

To use a conventional API later, set `LLM_BACKEND=api`:

- `LLM_API_KEY`: secret identifying the model-service account and billing project.
- `LLM_BASE_URL`: provider's compatible API base address, without `/chat/completions`.
- `LLM_MODEL`: provider's exact model identifier.

The `.env.example` retains DeepSeek API defaults. ChatGPT/Codex login credentials are not interchangeable with a Platform API key. The API transport has offline contract coverage; no new paid API account was used for this change.

If a key was shared in chat, replace it in the provider console and update only the local `.env`. Restart the server after a change to ensure old environment values are replaced. `.env` is ignored by Git; do not commit it or paste its contents into an issue.

## Real-address demonstration

1. In **Shopping workspace**, choose **Real stores**.
2. Enter the public demonstration address `150 E McKinley Avenue, Sunnyvale, CA 94086`, click **Look up address**, and confirm the intended result with **Use this address**.
3. Click **Find nearby supermarkets**. A store can have historical prices, optional Kroger product access, or location information only.
4. Click **View historical products** on Whole Foods or another Open Prices location. Each record displays observation date, currency, discount conditions, source and supporting evidence. Pagination browses up to 100 pages, 20 records each; the text filter filters the current page only.
5. Click **Estimate walk** for a Geoapify round-trip estimate. This is not a transit timetable. BUS/RIDESHARE are intentionally unsupported by the routing adapter.
6. For a real shopping visit, save profile/free time and needs, choose a radius under **Real-store shopping visits**, and click **Recommend stores for my list**. Review historical evidence and unknowns, accept a visit, then record purchase/not-found/skipped outcomes. See the [complete real-address walkthrough](REAL_STORE_VISITS.md). Historical records remain excluded from the current-price optimizer.

On 2026-10-12, the public Sunnyvale example returned records, while Ann Arbor city center within 5 km returned none from Open Prices. Mapped supermarkets can still appear in areas without price contributions. This is a coverage limitation, not a claim that the stores lack products.

Optional Kroger live plans require confirmed product matches, fresh prices, store opening hours, a supported route, package weight, tax estimate, and (for a car) transport-cost estimate. Missing information does not become zero. Net package mass is an estimate for carrying weight; enter a conservative packed weight when necessary. Dietary requirements require evidence; the Kroger adapter does not infer dietary labels from names. Historical Open Prices labels likewise are not certified dietary advice.

## Reproduce evidence and tests

```bash
python scripts/verify_live.py
python -m unittest discover -s tests -p 'test_*.py' -v
jac test
jac build main.jac
```

`verify_live.py` uses only the fixed public address above. It writes sanitized normalized evidence to `docs/samples/live-verification.json` and exits nonzero on a blocked step; it does not print credentials. Live results can change. Offline fixtures in tests are labeled synthetic and never replace real API responses in the application.

In-memory provider caches expire: address 24h, nearby places 15min, product/price records 5min, routes 15min. Cache keys are hashes; tokens and raw responses are not written to disk by the adapter. Saved user workspace/history and graph data persist through Jac. GET retry is bounded to one retry for temporary failures/429; writes and OAuth are not automatically retried.

## Demo freshness and unit prices

Raw `data/mock/catalog.json` timestamps stay fixed for reproducible historical tests. Application loading explicitly rebases only fictional quotes to local midnight, preserving their observation ages and validity durations (seven days for the current fixture). Expired saved **mock** quotes renew on opening the workspace, comparing plans or confirming a chat request. **Refresh shopping tools** also renews simulated observations. Same-day refreshes are idempotent. User stock feedback is preserved; live/historical source dates are never rewritten, and stale real offers still fail freshness checks. Low-level `load_mock(cat)` intentionally preserves raw fixture dates; use `load_mock(cat, now=...)` for a dated demo.

Choose a category, then expand **Compare package and unit prices**. USD package prices and normalized prices appear together: mass per kg, volume per L, count per piece. US gallons/fluid ounces are used; ordinary ounces mean mass. Only eligible memberships affect the displayed price. Unknown price/size, unsupported units and ambiguous multipacks stay unavailable; the application never converts mass to volume. Taxes, transport and fees remain in the basket total. Plan item prices use their planning-time snapshots.

To demo without external services: select **Demo data**, save budget `80`, carrying limit `20`, transport `WALK,BUS` and free time `SAT 14:00-17:00`; add one package of rice, expand unit-price comparison and click **Compare plans**. Accept a plan, then mark its item bought. The default maximum walking segment is 15 minutes: the mock rice store has an 18-minute walk, so allow BUS or explicitly ask chat to set a larger walking limit.

## Model acceptance and CI

These commands invoke real models and consume quota; they are **not** part of automatic tests:

```bash
# Two fixed English extraction cases (stops on the first failure):
python scripts/verify_llm.py --limit 2
# Detached synthetic user: real chat -> automatic save/plan -> grounded explanation.
# Three model calls; does not change your saved shopping profile:
jac run scripts/verify_chat.jac
# Optional broader acceptance: ten extraction cases plus one explanation call:
python scripts/verify_llm.py --limit 10 --explanation
```

Plan explanations use the model to select relevant fact IDs, then render their computed values. Invalid/fabricated IDs or a selection outage fall back to computed details. The model cannot replace prices or perform basket arithmetic. Purchase feedback and plan acceptance still require explicit confirmation; routine profile/need updates now save directly from chat. The recorded run covers two bilingual extraction cases and the three-call graph flow; the optional ten-case suite is available but has not been claimed as executed.

`.github/workflows/ci.yml` runs Python contracts, Jac graph/workflow tests and the client build on PRs and pushes to `main`, without API secrets or Codex login. The current local suite contains 105 Jac tests and 54 Python tests (159 total), including current/future dates, expired real offers, price dimensions, eligible member prices, plan snapshots, user feedback, model validation and confirmation. The earlier PR passed GitHub CI; new local changes require a fresh CI run after pushing.

## Jac business-rule modules

Conversation follow-up rules, profile/need validation and unit pricing now live in `ai/conversation.jac`, `integrations/validation.jac` and `pricing.jac`. Their imports from Jac are unchanged. Standalone Python tools that import these modules must first `import jaclang` to register the Jac import hook; the affected application entrypoint and tests already do this. Use the pinned project virtual environment for both Jac and Python commands. There is no duplicate Python fallback for these rules.
