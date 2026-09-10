# Deploying pbl-api + pbl-mail-service to Cloud Run

Architecture: two Cloud Run v2 services, both scale-to-zero
(`min_instance_count = 0` — genuinely free-tier friendly, no always-on
worker cost). `pbl-api` handles public HTTP traffic and, when it needs to
send a verification email, creates a **Google Cloud Task** targeting
`pbl-mail-service`'s `/tasks/email-verification` endpoint. Cloud Tasks
pushes over HTTP with an OIDC identity token — `pbl-mail-service` never
needs to sit and listen on a persistent queue connection, which is why it
can scale to zero too.

Database: **Neon** (serverless Postgres). Cache: **Upstash** (serverless
Redis — used by pbl-api's `CacheModule` only; no longer used for the email
queue). Email: **Resend**. CI/CD: **GitHub Actions** via Workload Identity
Federation (no long-lived JSON key).

## 1. Provision Neon

Create a project at neon.tech (free tier: 500MB, autosuspends when idle).
Note host/database/username/password.

## 2. Provision Upstash

Create a Redis database at upstash.com (free tier: 256MB, TLS). Use the
TCP connection details, not the REST API.

## 3. Provision Resend

Create an account at resend.com (free tier: 100/day, 3000/mo), verify a
sending domain (or use their onboarding test domain for now), grab an API
key.

## 4. Create the GCP project

```bash
gcloud auth login
gcloud projects create pbl-api-<something-unique>
gcloud config set project pbl-api-<something-unique>
gcloud billing projects link pbl-api-<something-unique> --billing-account=<BILLING_ACCOUNT_ID>
```

## 5. First Terraform apply

```bash
cd pbl-infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: project_id, api_github_owner/repo,
# mail_github_owner/repo, and non_secret_env/mail_non_secret_env overrides
# for DATABASE_HOST/USERNAME/NAME, REDIS_HOST from steps 1-2.

terraform init
terraform apply
```

This creates the Artifact Registry repo, both Cloud Run services (with
placeholder images — nothing's been pushed yet, so they'll fail to start;
that's expected at this point), the Cloud Tasks queue, the OIDC invoker
service account, both deployer service accounts, and empty Secret Manager
containers.

## 6. Fill in the real secrets

```bash
echo -n "<neon-password>"                 | gcloud secrets versions add DATABASE_PASSWORD --data-file=-
echo -n "<upstash-password>"              | gcloud secrets versions add REDIS_PASSWORD --data-file=-
echo -n "<resend-api-key>"                | gcloud secrets versions add RESEND_API_KEY --data-file=-
echo -n "<observe.nestjs.com app key>"    | gcloud secrets versions add OBSERVE_APP_KEY --data-file=-
echo -n "<observe.nestjs.com app secret>" | gcloud secrets versions add OBSERVE_APP_SECRET --data-file=-
openssl rand -base64 32 | tr -d '\n'      | gcloud secrets versions add AUTH_JWT_SECRET --data-file=-
openssl rand -base64 32 | tr -d '\n'      | gcloud secrets versions add AUTH_REFRESH_SECRET --data-file=-
openssl rand -base64 32 | tr -d '\n'      | gcloud secrets versions add AUTH_FORGOT_SECRET --data-file=-
openssl rand -base64 32 | tr -d '\n'      | gcloud secrets versions add AUTH_CONFIRM_EMAIL_SECRET --data-file=-
```

### Secrets reference (single source of truth)

Every secret this project uses, where it comes from, and which service(s)
actually read it. If a secret isn't in this table, something's
undocumented — fix that rather than adding a new secret silently.

| Secret (Secret Manager name) | Consumed by | Where the value comes from |
|---|---|---|
| `DATABASE_PASSWORD` | pbl-api | Neon project dashboard (step 1) |
| `REDIS_PASSWORD` | pbl-api | Upstash database dashboard (step 2) |
| `RESEND_API_KEY` | pbl-mail-service | Resend dashboard → API Keys (step 3) |
| `OBSERVE_APP_KEY` | pbl-api, pbl-mail-service (same value, both services) | observe.nestjs.com project → Add API key |
| `OBSERVE_APP_SECRET` | pbl-api, pbl-mail-service (same value, both services) | observe.nestjs.com project → Add API key |
| `AUTH_JWT_SECRET` | pbl-api | Generated (`openssl rand -base64 32`) — not from any external dashboard |
| `AUTH_REFRESH_SECRET` | pbl-api | Generated |
| `AUTH_FORGOT_SECRET` | pbl-api | Generated |
| `AUTH_CONFIRM_EMAIL_SECRET` | pbl-api | Generated |

Non-secret config that still needs a real value (set via `terraform.tfvars`'
`non_secret_env`/`mail_non_secret_env` overrides, not Secret Manager):

| Variable | Consumed by | Where the value comes from |
|---|---|---|
| `DATABASE_HOST`/`DATABASE_USERNAME`/`DATABASE_NAME` | pbl-api | Neon project dashboard |
| `REDIS_HOST` | pbl-api | Upstash database dashboard |
| `RESEND_FROM_EMAIL`/`RESEND_FROM_NAME` | pbl-mail-service | Whatever sending identity you verified in Resend |
| `API_PUBLIC_URL` | pbl-mail-service | `terraform output api_url` after the first apply (step 7 below) — can't be wired automatically (would create a Terraform dependency cycle with pbl-api's `CLOUD_TASKS_MAIL_SERVICE_URL`), so it must be set manually |

`CLOUD_TASKS_MAIL_SERVICE_URL`, `CLOUD_TASKS_QUEUE_NAME`,
`CLOUD_TASKS_INVOKER_SA_EMAIL`, `GCP_PROJECT_ID`, and `CLOUD_TASKS_LOCATION`
are all wired automatically as real Terraform resource references
(`locals.api_env` in `cloud_run.tf`) — nothing to do for those.

## 7. Set pbl-api's real public URL for pbl-mail-service

```bash
terraform output api_url
```

Set this as `API_PUBLIC_URL` in `variables.tf`'s `mail_non_secret_env`
default (replacing the `CHANGE_ME` placeholder), or override it in
`terraform.tfvars`. Then:

```bash
terraform apply
```

## 8. Run the initial migration against Neon

```bash
pnpm migration:up
```

(from the pbl-api repo, with Neon credentials in a local `.env`.)

## 9. Push real images

Push to `main` in both `pbl-api` and `pbl-mail-service` — their own
`deploy.yml` builds and pushes their own image and updates only their own
Cloud Run service.

## 10. Wire up GitHub Actions

`terraform apply` printed `workload_identity_provider`,
`api_deployer_service_account_email`, `mail_deployer_service_account_email`.
In **each** app repo, go to **Settings → Secrets and variables → Actions →
Variables** and add:

| Variable | pbl-api value | pbl-mail-service value |
|---|---|---|
| `GCP_PROJECT_ID` | your project id | your project id |
| `GCP_REGION` | `asia-southeast1` | `asia-southeast1` |
| `GCP_ARTIFACT_REPO` | `pbl-api` | `pbl-api` (same repo, different image name) |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | terraform output `workload_identity_provider` | same value |
| `GCP_DEPLOYER_SA_EMAIL` | terraform output `api_deployer_service_account_email` | terraform output `mail_deployer_service_account_email` |
| `GCP_API_SERVICE_NAME` | `pbl-api` | — |
| `GCP_MAIL_SERVICE_NAME` | — | `pbl-mail-service` |

Also create a GitHub **environment** named `production` in both repos.

## Verifying monitoring survived the split

Both `pbl-api` and `pbl-mail-service` call `createObserveModule()` in their
own `app.module.ts`, using the *same* `OBSERVE_APP_KEY`/`OBSERVE_APP_SECRET`
secret but a distinct `serviceId` (`'pbl-api'` vs `'pbl-mail-service'`).
After deploying both:

1. Open the observe.nestjs.com dashboard.
2. Hit pbl-api's public URL, confirm requests show up under `pbl-api`.
3. Register a user through pbl-api's `/api/auth/email/register` — confirm
   the `/tasks/email-verification` call shows up under `pbl-mail-service`,
   and confirm the email actually arrives (check Resend's own delivery log
   too).
4. There is no automatic trace-id propagation from the request that
   created the Cloud Task to the HTTP call Cloud Tasks makes to
   pbl-mail-service — Observe traces each service's own HTTP handling, but
   correlating "this request → this task → this email" across services
   isn't wired up by anything in this plan. Cloud Tasks does add its own
   `X-CloudTasks-*` headers to the forwarded request if you want to build
   that correlation yourself later.

## Notes / things to revisit later

- **State is local** — no GCP project existed when this was written. Once
  you have one, create a GCS bucket and switch `versions.tf`'s backend,
  then `terraform init -migrate-state`.
- Both services are genuinely scale-to-zero now — no always-on cost from
  the app layer. Neon and Upstash both auto-suspend/are pay-per-request on
  their free tiers too, so the only guaranteed non-zero cost here is
  whatever GCP charges for the Cloud Tasks queue itself at low volume
  (check current Cloud Tasks pricing — it has its own free tier separate
  from Cloud Run's) and the Artifact Registry storage for images.
- Cold starts apply to both services now (previously only pbl-api) — the
  first email after an idle period pays pbl-mail-service's cold-start cost
  in addition to pbl-api's.
