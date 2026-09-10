# Deploying pbl-api + pbl-mail-service to Render

This is a **runbook, not Terraform** — Render's Free plan for web services
cannot be provisioned through any API or IaC tool (Terraform, `render.yaml`
Blueprints, none of it — it's dashboard-only by design, presumably an
anti-abuse measure). Everything below is a one-time manual setup; ongoing
deploys are automated via GitHub Actions + a Render deploy hook (see
step 8).

## Architecture

Two Render web services, both Free plan (spins down after 15 min idle,
~1 min cold start on the next request — this is Render's own scale-to-zero
equivalent, not something this repo configures).

- **pbl-api** — public HTTP API. When it needs to send a verification
  email, it publishes a message to **Upstash QStash**, which pushes it to
  pbl-mail-service over HTTP.
- **pbl-mail-service** — owns templates, renders them, sends via
  **Resend**. Its `/tasks/email-verification` endpoint verifies every
  request actually came from QStash (via QStash's signed
  `Upstash-Signature` header) before doing anything — there's no
  Cloud-Run-style network-level IAM to lean on here, so the app verifies
  the signature itself.

Database: **Neon** (serverless Postgres). Cache: **Upstash Redis** (used by
pbl-api's `CacheModule` only). Email: **Resend**. Queue: **Upstash QStash**.
Monitoring: **observe.nestjs.com**, same project, two `serviceId`s.
CI/CD: **GitHub Actions**, gated on tests passing, triggering a Render
deploy hook.

## 1. Provision Neon

Create a project at neon.tech (free tier: 500MB, autosuspends when idle).
Note host/database/username/password.

## 2. Provision Upstash Redis

Create a Redis database at upstash.com (free tier: 256MB, TLS). Use the
TCP connection details, not the REST API.

## 3. Provision Upstash QStash

Same Upstash account as step 2 — go to the **QStash** tab. No separate
signup, no credit card. Note:

- The QStash **token** (pbl-api uses this to publish messages).
- The **current signing key** and **next signing key** (pbl-mail-service
  uses these to verify incoming requests actually came from QStash).

## 4. Provision Resend

Create an account at resend.com (free tier: 100/day, 3000/mo), verify a
sending domain (or use their onboarding test domain — `onboarding@resend.dev`
— for now). Note the API key.

## 5. observe.nestjs.com

Same project you already set up earlier — note the app key/app secret
(shared by both services, distinguished by `serviceId`).

## 6. Push both repos to GitHub

Render deploys by connecting directly to a GitHub repo (it builds the
Docker image itself from your `Dockerfile` on every push) — this is
different from the old Cloud Run design, which pushed a pre-built image to
a registry. Create a GitHub repo for each of `pbl-api` and
`pbl-mail-service` and push.

## 7. Create the Render web services

Create **pbl-mail-service first** — pbl-api needs its URL, but
pbl-mail-service only needs its own URL (known immediately after
creation), so this ordering avoids a circular wait.

For each service, in the Render dashboard: **New → Web Service** → connect
the GitHub repo → **Runtime: Docker** → **Plan: Free** → pick a region →
under **Advanced**, turn **Auto-Deploy OFF** (deploys are gated by GitHub
Actions instead — see step 8) → set the environment variables below → Create.

### pbl-mail-service environment variables

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `APP_NAME` | `pbl-mail-service` |
| `APP_LOG_LEVEL` | `warn` |
| `APP_LOG_SERVICE` | `console` |
| `API_PUBLIC_URL` | *(pbl-api's URL — you don't have this yet; use a placeholder like `https://example.com` for now, come back after step 7's pbl-api creation and fix it)* |
| `RESEND_API_KEY` | from step 4 |
| `RESEND_FROM_EMAIL` | your verified sender (or `onboarding@resend.dev`) |
| `RESEND_FROM_NAME` | `pbl-api` |
| `QSTASH_CURRENT_SIGNING_KEY` | from step 3 |
| `QSTASH_NEXT_SIGNING_KEY` | from step 3 |
| `QSTASH_DESTINATION_URL` | this service's own URL + `/tasks/email-verification` — Render shows the URL once the service is created; edit this variable right after |
| `OBSERVE_APP_KEY` | from step 5 |
| `OBSERVE_APP_SECRET` | from step 5 |

Render sets `PORT` automatically — the app already reads it (no manual wiring needed).

### pbl-api environment variables

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `APP_NAME` | `pbl-api` |
| `APP_DEBUG` | `false` |
| `API_PREFIX` | `api` |
| `APP_FALLBACK_LANGUAGE` | `en` |
| `APP_LOG_LEVEL` | `warn` |
| `APP_LOG_SERVICE` | `console` |
| `APP_CORS_ORIGIN` | `false` (or your real frontend origin once you have one) |
| `DATABASE_TYPE` | `postgres` |
| `DATABASE_HOST` / `DATABASE_USERNAME` / `DATABASE_NAME` | from step 1 |
| `DATABASE_PASSWORD` | from step 1 |
| `DATABASE_PORT` | `5432` |
| `DATABASE_LOGGING` | `false` |
| `DATABASE_SYNCHRONIZE` | `false` |
| `DATABASE_MAX_CONNECTIONS` | `10` |
| `DATABASE_SSL_ENABLED` | `true` |
| `DATABASE_REJECT_UNAUTHORIZED` | `true` |
| `REDIS_HOST` | from step 2 |
| `REDIS_PORT` | from step 2 |
| `REDIS_PASSWORD` | from step 2 |
| `REDIS_TLS_ENABLED` | `true` |
| `QSTASH_TOKEN` | from step 3 |
| `MAIL_SERVICE_URL` | pbl-mail-service's URL (from step 7 above — this one you already have) |
| `OBSERVE_APP_KEY` | from step 5 |
| `OBSERVE_APP_SECRET` | from step 5 |
| `AUTH_JWT_SECRET` / `AUTH_REFRESH_SECRET` / `AUTH_FORGOT_SECRET` / `AUTH_CONFIRM_EMAIL_SECRET` | `openssl rand -base64 32` each, four separate values |
| `AUTH_JWT_TOKEN_EXPIRES_IN` | `1d` |
| `AUTH_REFRESH_TOKEN_EXPIRES_IN` | `365d` |
| `AUTH_FORGOT_TOKEN_EXPIRES_IN` | `7d` |
| `AUTH_CONFIRM_EMAIL_TOKEN_EXPIRES_IN` | `1d` |

### Go back and fix pbl-mail-service's `API_PUBLIC_URL`

Now that pbl-api has a real URL, edit pbl-mail-service's `API_PUBLIC_URL`
env var to point at it (Render redeploys automatically when you change an
env var, even with Auto-Deploy off for git pushes).

## 8. Wire up GitHub Actions (CI-gated deploys)

Each service has a **Deploy Hook URL** under its Render dashboard →
Settings. It's a bearer-token-like secret — a plain `POST` to it triggers a
deploy of the latest commit on the connected branch.

In **each** repo (pbl-api, pbl-mail-service), go to **Settings → Secrets
and variables → Actions → Secrets** (not Variables — this one's sensitive)
and add:

| Secret | Value |
|---|---|
| `RENDER_DEPLOY_HOOK_URL` | that service's Deploy Hook URL |

Also create a GitHub **environment** named `production` in both repos (the
`deploy.yml` workflow targets it — lets you require manual approval there
if you want).

Push to `main` and `.github/workflows/deploy.yml` runs lint/build/test,
then calls the deploy hook only if everything passed — Render's own
auto-deploy-on-push is intentionally left off so untested code can't reach
production.

## 9. Run the initial migration against Neon

```bash
pnpm migration:up
```

(from the pbl-api repo, with Neon credentials in a local `.env`.)

## Secrets reference (single source of truth)

| Secret | Consumed by | Where the value comes from |
|---|---|---|
| `DATABASE_PASSWORD` | pbl-api | Neon dashboard (step 1) |
| `REDIS_PASSWORD` | pbl-api | Upstash Redis dashboard (step 2) |
| `QSTASH_TOKEN` | pbl-api | Upstash QStash tab (step 3) |
| `QSTASH_CURRENT_SIGNING_KEY` / `QSTASH_NEXT_SIGNING_KEY` | pbl-mail-service | Upstash QStash tab (step 3) |
| `RESEND_API_KEY` | pbl-mail-service | Resend dashboard (step 4) |
| `OBSERVE_APP_KEY` / `OBSERVE_APP_SECRET` | pbl-api, pbl-mail-service (same value, both services) | observe.nestjs.com project |
| `AUTH_JWT_SECRET` / `AUTH_REFRESH_SECRET` / `AUTH_FORGOT_SECRET` / `AUTH_CONFIRM_EMAIL_SECRET` | pbl-api | Generated (`openssl rand -base64 32`) |
| `RENDER_DEPLOY_HOOK_URL` | GitHub Actions (per repo) | That service's Render dashboard → Settings → Deploy Hook |

If a secret isn't in this table, something's undocumented — fix that
rather than adding a new one silently.

## Verifying monitoring survived the split

Both `pbl-api` and `pbl-mail-service` call `createObserveModule()` in
their own `app.module.ts`, using the *same* `OBSERVE_APP_KEY`/
`OBSERVE_APP_SECRET` secret but a distinct `serviceId` (`'pbl-api'` vs
`'pbl-mail-service'`). After deploying both:

1. Open the observe.nestjs.com dashboard.
2. Hit pbl-api's public URL (it may take ~1 min to cold-start first),
   confirm requests show up under `pbl-api`.
3. Register a user through pbl-api's `/api/v1/auth/email/register` —
   confirm the `/tasks/email-verification` call shows up under
   `pbl-mail-service`, and confirm the email actually arrives (check
   Resend's own delivery log too, and QStash's own dashboard for delivery
   status/retries).
4. There is no automatic trace-id propagation from the request that
   published the QStash message to the HTTP call QStash makes to
   pbl-mail-service — Observe traces each service's own HTTP handling, but
   correlating "this request → this message → this email" across services
   isn't wired up here. Treat as a follow-up if you need it.

## Notes / things to revisit later

- **Cold starts apply to both services** on Render's Free plan (spin-down
  after 15 min idle, ~1 min to wake). If pbl-api and pbl-mail-service are
  both asleep, a registration request pays both cold-start costs (pbl-api
  waking to handle the request, then QStash retrying its push to
  pbl-mail-service until it wakes too — QStash retries on failure, so this
  should still eventually succeed, just slower than a warm request).
- **Free Postgres on some providers expires after a fixed period** — this
  doesn't apply here since the database is on Neon, not Render, but if you
  ever add a Render-hosted database, check its own free-tier expiry terms
  separately.
- If you outgrow Render's Free plan, the official Render Terraform
  provider (`render-oss/render`) exists and is early-access — but paid
  plans, unlike Free, likely *can* be provisioned through it. Revisit
  Terraform then if it's worth it.
