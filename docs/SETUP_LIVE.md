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

**Chat** optionally needs an OpenAI-compatible LLM provider configured with `LLM_API_KEY`, `LLM_BASE_URL` and `LLM_MODEL`. The example uses DeepSeek. The structured profile, interest and plan controls work without this key. The LLM proposes a validated JSON change; the user confirms it in the shopping panel before saved needs/profile/feedback change. Pricing and constraint arithmetic remain deterministic. API credentials are never sent in model context. Text the user types into chat is sent to their configured LLM provider, so only include address details there intentionally.

If a key was shared in chat, replace it in the provider console and update only the local `.env`. Restart the server after a change to ensure old environment values are replaced. `.env` is ignored by Git; do not commit it or paste its contents into an issue.

## Real-address demonstration

1. In **Shopping workspace**, choose **Real stores**.
2. Enter the public demonstration address `150 E McKinley Avenue, Sunnyvale, CA 94086`, click **Look up address**, and confirm the intended result with **Use this address**.
3. Click **Find supermarkets within 5 km**. A store can have historical prices, optional Kroger product access, or location information only.
4. Click **View historical products** on Whole Foods or another Open Prices location. Each record displays observation date, currency, discount conditions, source and supporting evidence. Pagination browses up to 100 pages, 20 records each; the text filter filters the current page only.
5. Click **Estimate walk** for a Geoapify round-trip estimate. This is not a transit timetable. BUS/RIDESHARE are intentionally unsupported by the routing adapter.
6. Historical records do not enter the current-price planner. To exercise the full plan lifecycle now, switch to **Demo data**, save profile/free time and needs, compare plans, accept one, then record individual outcomes.

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
