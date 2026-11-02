# Deploy CartCompass to Render

This deployment is a **password-protected, shared course demo**. Everyone using
the demo password sees the same shopping workspace. It does not introduce
separate shopper accounts. Use public/example addresses when sharing the demo.
The local `.env`, databases and Codex login are excluded from the Docker image.

## 1. Accounts and costs

1. Register at https://dashboard.render.com/register with GitHub. Grant Render
   access to `Jinghan-Wang-26/eecs449` (the repository owner may need to approve
   the GitHub integration). Choose a personal workspace if appropriate.
2. The Blueprint requests one Standard web service (1 CPU / 2 GB RAM; current
   plan ID `1c-2g`, legacy name `standard`) and a 1 GB persistent disk in Ohio.
   Review Render's displayed compute, disk and usage estimate before creating
   the service. API usage is billed separately by the model provider.
   The running local app was already using about 630 MB; a 512 MB service is
   not a suitable default. No GPU or custom domain is required.
3. Create a model API account and key. For the configured DeepSeek example,
   use https://platform.deepseek.com/, open API Keys, create a key, and check
   that the account has usable API balance. The regular chatbot login is not
   an API key. Current API documentation uses `deepseek-flash` with the base
   URL `https://api.deepseek.com`. The adapter disables thinking for JSON intent
   extraction. A real authenticated model call must still be verified after
   configuring the key.

## 2. Create the service

1. Push the deployment changes to GitHub. In Render choose **New → Blueprint**,
   select the repository and the branch containing `render.yaml` (initially
   `feat/render-deployment`), and use the root `render.yaml` file.
2. Fill the prompted secret environment variables directly in Render:

   | Variable | Value/source |
   | --- | --- |
   | `LLM_API_KEY` | Model provider's API key |
   | `GEOAPIFY_API_KEY` | Existing local Geoapify project key |
   | `KROGER_CLIENT_ID` | Existing Kroger production application |
   | `KROGER_CLIENT_SECRET` | Matching Kroger production secret |

   Blueprint defaults are `LLM_BACKEND=api`,
   `LLM_BASE_URL=https://api.deepseek.com`, `LLM_MODEL=deepseek-flash`.
   Change the latter two for another compatible Chat Completions provider
   supporting JSON output. Missing retailer credentials leave that source
   unavailable; historical records never become current stock or prices.
3. Review the service and cost details, then create the Blueprint. Render builds
   the Docker image and provides an HTTPS `onrender.com` URL.
4. In the service's **Environment** settings, reveal the generated
   `CARTCOMPASS_DEMO_PASSWORD`. The browser's login username is `cartcompass`;
   the password is this generated value. Do not publish it in repository files
   or screenshots. You may replace it with a unique password of at least
   16 characters and redeploy.
5. Automatic deployments are disabled. After reviewing later changes, use
   **Manual Deploy → Deploy latest commit**. Once the PR is merged, update the
   Blueprint/service branch to `main` if it still points to the feature branch.

`/healthz` reports proxy process liveness and contains no shopping data. The
proxy starts only after Jac serves the homepage; if either service process
exits, the container exits. This endpoint does not validate external API
availability or prove that a planning request is making progress.

Render terminates HTTPS. Caddy checks the demo password before forwarding to
Jac on internal port 8081. Only the proxy's `PORT` is exposed. Do not expose
port 8081 as a second public service. All application/API paths require the
password. The two services run as uid 10001 after the entrypoint prepares the
dedicated data directory. Do not change `LLM_BACKEND` to `codex` on Render.

## 3. Data and validation

The disk mounts at `/var/data`, and `JAC_DATA_PATH=/var/data` makes Jac store
both `main.db` (identities) and `cartcompass.db` (shopping graph) inside
`/var/data/.jac/data`. Cache/build files remain separate under `/app/.jac`.
Do not mount over `/app/.jac`: that would hide the prebuilt frontend. This
starts a fresh cloud workspace; it does not upload the local shopping history.

Keep exactly one instance. The SQLite graph and background reminder scheduler
have not been validated for distributed workers. A disk-backed deployment can
briefly interrupt service during redeploys. Keep a verified backup before
changing database schemas. Render disk snapshots do not replace a tested,
SQLite-aware backup/restore procedure.

Read-only deployment probe (the password is prompted, never echoed):

```bash
python scripts/verify_cloud.py https://YOUR-SERVICE.onrender.com
```

Then verify in the browser:

1. Open a private window: the demo password is required before viewing the app.
2. Start a new trip. Request milk and rice; answer missing-information questions
   and use a public address such as Michigan Union in Ann Arbor.
3. Select transport/time constraints and generate a real-store plan. Check
   observed timestamps, unknown data, and scheduled rather than live bus times.
4. Confirming a plan rechecks retailer evidence; it does not place an order.
5. Restart/redeploy the service. Previously saved needs/preferences/history
   must remain. Retest the page and real API call after deployment.

Model intent requests have a 60-second response timeout; map/retailer requests
retain their shorter timeout and IPv4-first transport. Full planning can take
longer than an individual request. Concurrent planners can still contend on
this prototype's synchronous server; use it as a small shared demo, not a
public multi-user service. Monitor memory and logs during real route testing.
Logs may include application reports, so do not share raw logs containing
addresses or shopping history. Email reminders remain optional; configure the
`SMTP_*` variables separately if needed.

## 4. Local container rehearsal

```bash
docker build -t cartcompass:render-test .
docker volume create cartcompass-demo-data
read -rsp 'Demo password (at least 16 characters): ' CARTCOMPASS_DEMO_PASSWORD
export CARTCOMPASS_DEMO_PASSWORD
# Secrets are optional for an initial UI/persistence rehearsal. Pass separately
# configured API variables with -e NAME when testing actual external calls.
docker run --rm --name cartcompass-render-demo \
  -p 127.0.0.1:18000:10000 \
  -e CARTCOMPASS_DEMO_PASSWORD \
  -v cartcompass-demo-data:/var/data \
  cartcompass:render-test
```

Open `http://localhost:18000` and use username `cartcompass`. HTTP is allowed
only for this loopback rehearsal; always use HTTPS for the cloud URL. Stop the
container with Ctrl+C. Recreating it with the same volume preserves data.
Do not delete the volume if you need that demo data.

Sources: [Render Docker](https://render.com/docs/docker),
[Blueprint fields](https://render.com/docs/blueprint-spec),
[persistent disks](https://render.com/docs/disks),
[compute plans](https://render.com/docs/compute-plans),
[DeepSeek API](https://api-docs.deepseek.com/),
[Caddy basic authentication](https://caddyserver.com/docs/caddyfile/directives/basic_auth).
