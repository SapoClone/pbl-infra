# pbl-infra — AWS deployment for pbl-api + pbl-mail-service

Terraform-managed AWS infrastructure, run through Terragrunt, backed by AWS
Activate/education/promo credits.

## Layout

```
pbl-infra/
├── root.hcl                 # root: S3 backend (auto-bootstrapping) + provider, shared by every env
├── terraform/               # the actual Terraform module — never applied directly, only via Terragrunt
│   ├── modules/              # ecr_repository, ecs_cluster, ecs_app, events, lambda_sqs_consumer, sqs_queue, github_oidc_deployer
│   └── *.tf
└── live/
    └── prod/
        ├── terragrunt.hcl              # includes root, points source at ../../terraform, sets non-secret inputs
        └── secrets.tfvars.example      # copy to secrets.tfvars (gitignored) and fill in
```

Adding another environment later (e.g. `live/staging/`) means copying
`live/prod/` and adjusting inputs — the backend and provider config stay
defined exactly once, in the root `root.hcl`.

## Architecture

- **pbl-api** — public HTTP API, deployed as an **ECS Fargate** service
  behind an **Application Load Balancer** (public subnets, no NAT Gateway —
  tasks get a public IP directly to keep cost down). When it needs to send
  a verification email, it publishes a message to an **SQS** queue.
- **pbl-mail-service** — owns templates, renders them, sends via
  **Resend**. Deployed as a container-image **AWS Lambda** function,
  triggered directly by the SQS queue (an event source mapping — no HTTP
  call, no shared secret to verify, IAM does the trust boundary instead of
  an app-level signature check).
- **Database**: Neon (serverless Postgres, not AWS-hosted — kept as-is
  rather than migrating to RDS, see the earlier design discussion).
- **Cache**: Upstash Redis (same reasoning — kept as-is).
- **Email**: Resend.
- **Monitoring**: observe.nestjs.com, one project, two `serviceId`s
  (`pbl-api` / `pbl-mail-service`).
- **CI/CD**: GitHub Actions in each repo, authenticated to AWS via OIDC (no
  long-lived AWS access keys in either repo). Deploys are gated on
  lint/build/test passing.
- **Secrets**: AWS SSM Parameter Store (`SecureString`), for pbl-api's ECS
  task definition. Terraform is the source of truth for which secrets
  exist; values come from `live/prod/secrets.tfvars` (gitignored, never
  committed).

```
GitHub Actions (OIDC) ──push──▶ ECR (pbl-api)         GitHub Actions (OIDC) ──push──▶ ECR (pbl-mail-service)
                                    │                                                      │
                                    ▼                                                      ▼
                          ECS Fargate service                                     Lambda (container image)
                    behind an ALB (HTTPS, :80 redirects)                              triggered by SQS
                                    │                                                      ▲
                         publishes on send-mail ──────────▶ SQS queue "email-verification" ┘
```

## Target service topology (eight services)

The API is not one service. pbl-api is a monorepo of eight services behind a
KrakenD gateway ([ADR-0010](https://github.com/SapoClone/pbl-api/blob/main/docs/decisions/0010-eight-services.md)):
open `docs/architecture.html` (published to GitHub Pages) for the diagram and
`docs/erd_viewer.html` for the tables each service owns. `docs/status.html` shows what is built
across the repositories and what is still missing; edit it and merge to `main` to refresh the published copy.

| Service | Gateway path | Postgres schema (role) |
|---|---|---|
| `platform` | `/platform/*` | `public` (`pbl_platform`): its hand-written migrations create tables in `public` |
| `catalog` | `/catalog/*` | `catalog` (`pbl_catalog`) |
| `inventory` | `/inventory/*` | `inventory` (`pbl_inventory`) |
| `sales` | `/sales/*` | `sales` (`pbl_sales`) |
| `customer` | `/customer/*` | `customer` (`pbl_customer`) |
| `finance` | `/finance/*` | `finance` (`pbl_finance`) |
| `integration` | `/integration/*` | `integration` (`pbl_integration`) |
| `insight` | `/insight/*` | `insight` (`pbl_insight`) |

This Terraform provisions all of it ([deployment runbook](DEPLOY-BACKEND.md)):

- one ECS cluster with one Fargate service per backend service plus the gateway, and one ALB that
  forwards only to the gateway (KrakenD, built from `krakend/Dockerfile` with the production config
  `scripts/render-krakend-prod.mjs` renders in pbl-api). Services reach each other by name through
  ECS Service Connect (`http://sales:3000`), so the gateway keeps the hosts of its local config;
- one ECR repository for every service (tags `<service>-<sha>`) and one for the gateway;
- the event bus, generated from pbl-api's topology (`terraform/events-topology.json`): an SNS topic
  per producer, a queue and DLQ per consumer, raw delivery, a filter on the event type, and an alarm
  on every DLQ;
- one Postgres role and schema per service (`scripts/neon-bootstrap.sql`, run once against Neon);
- the secrets every service needs as SSM parameters (`/pbl/shared`, `/pbl/<service>`, `/pbl/platform`),
  including `INTERNAL_S2S_TOKEN`, without which the services refuse service-to-service calls.

The AWS resources are currently destroyed to save credits; the Terraform is kept
and re-applied when a deployment is needed. `rehearsal/` runs the same images, roles and event bus
on one machine, which is how a change here is checked without AWS.

## Domain & HTTPS

- `pbl-api` is reachable at `https://api.sapo.makeasy.id.vn` (HTTP on
  port 80 redirects to HTTPS). The cert is an ACM DNS-validated
  certificate, auto-renewed by AWS as long as the validation CNAME
  records stay in place (they're manual CNAMEs at iNet — never delete them, or the cert can't auto-renew).
- The root domain `makeasy.id.vn` stays managed at iNet — its DNS panel
  has no NS record type, so no Route53 zone hosts any part of
  `sapo.makeasy.id.vn`. Every hostname under it (API, CDN, ACM
  validation) is a plain CNAME you add by hand at iNet — see "3b. Add the
  ACM validation CNAMEs" and the end of "4. Apply everything else" below
  for exactly what to paste in. Auto-renewal still works: ACM only
  re-validates against the same CNAME, which stays in place permanently
  once added.

## Image storage (S3 + CloudFront)

- Images live in a private S3 bucket (`image_bucket_name` output),
  never public directly — `pbl-api`'s ECS task role has
  `PutObject`/`GetObject`/`DeleteObject` on it, and end users only ever
  see `https://static.sapo.makeasy.id.vn/<key>` (CloudFront, via Origin
  Access Control).
- `pbl-api` gets `AWS_S3_BUCKET`, `AWS_S3_REGION`, and `CDN_URL` as
  container env vars — wiring an actual upload endpoint (multer,
  `@aws-sdk/client-s3`, etc.) is a `pbl-api`-side feature, not part of
  this infra.

## Prerequisites

- An AWS account with the Activate/education/promo credit balance applied.
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.55.
- The [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
  configured with credentials that can create IAM roles, ECS/ALB/Lambda/SQS
  resources (an account-root or admin-equivalent principal, for this
  one-time setup only — the ongoing GitHub Actions deployer roles this
  Terraform creates are scoped far narrower).
- [Docker](https://www.docker.com/) (to push the bootstrap images — see below).

## 1. Provision the external services (not AWS, not Terraform-managed)

These have no Terraform provider worth using for a free/low-volume tier —
provision them by hand once:

1. **Neon** — create a project at neon.tech (free tier, autosuspends when
   idle). Note host/database/username/password.
2. **Upstash Redis** — create a Redis database at upstash.com (free tier,
   TLS). Use the TCP connection details, not the REST API.
3. **Resend** — create an account at resend.com, verify a sending domain
   (or use their onboarding test domain, `onboarding@resend.dev`, for
   now). Note the API key.
4. **observe.nestjs.com** — the project you already set up. Note the app
   key/app secret (shared by both services, distinguished by `serviceId`).

## 2. Configure variables

```bash
cd live/prod
cp secrets.tfvars.example secrets.tfvars
```

Fill in every value in `secrets.tfvars` — it's gitignored, so it never
leaves your machine. Then open `live/prod/terragrunt.hcl` and set
`github_owner` to your real GitHub username/org (not a secret, so it's a
plain `inputs` value there rather than in `secrets.tfvars`) — the deployer
IAM roles trust `repo:<github_owner>/pbl-api:ref:refs/heads/main` and the
equivalent for pbl-mail-service, so this has to be exact.

For the four `auth_*_secret` values: `openssl rand -base64 32`, run four
separate times.

All commands from here on run from `live/prod/`, using `terragrunt`
instead of `terraform` directly (it wraps every `terraform` subcommand —
`terragrunt plan`, `terragrunt apply`, etc. — injecting the backend,
provider, and `secrets.tfvars` automatically).

## 3. First-time bootstrap: push a placeholder image to each ECR repo

Terraform creates the ECR repositories, but AWS validates that an image
actually exists at the given tag when it creates the ECS task definition
and the Lambda function — so an empty repo makes the very first `apply`
fail. Two-step bootstrap:

```bash
cd live/prod

# The very first run in a new AWS account needs the S3 state bucket +
# DynamoDB lock table to exist (see root.hcl's remote_state block) —
# --backend-bootstrap creates them automatically instead of you doing it
# by hand. Only needed once; every later `terragrunt` command finds them
# already there.
terragrunt init --backend-bootstrap
terragrunt apply -target=module.pbl_api_ecr -target=module.pbl_mail_service_ecr

# Log in, then push each repo's own Dockerfile once, tagged "bootstrap"
# (the default the variables below expect — see pbl_api_bootstrap_image_tag
# / pbl_mail_service_bootstrap_image_tag in terraform/variables.tf)
aws ecr get-login-password --region <your-region> | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com

cd ../../../pbl-api
docker build --target production -t <account-id>.dkr.ecr.<region>.amazonaws.com/pbl-api:bootstrap .
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/pbl-api:bootstrap

cd ../pbl-mail-service
docker build --target production -t <account-id>.dkr.ecr.<region>.amazonaws.com/pbl-mail-service:bootstrap .
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/pbl-mail-service:bootstrap
```

## 3b. Add the ACM validation CNAMEs

iNet's DNS panel for `makeasy.id.vn` has no NS record type, so there's no
way to delegate `sapo.makeasy.id.vn` to Route53 — every hostname under it
is a plain CNAME added by hand instead. Start with the two ACM
certificates, since the ALB and CloudFront (created in the next step)
both need an already-validated cert:

```bash
cd live/prod
terragrunt apply -target=aws_acm_certificate.regional -target=aws_acm_certificate.us_east_1
```

Print the two CNAMEs to add and paste each into iNet's Add Record form
(Type/Host/Value map directly onto iNet's fields):

```bash
terragrunt output -raw acm_regional_validation_cname
terragrunt output -raw acm_us_east_1_validation_cname
```

Note: ACM's validation record values come with a trailing dot from AWS
(e.g. `_xyz.acm-validations.aws.`) — most DNS panels accept that fine,
but if iNet's form rejects it or double-appends one, just remove it by
hand.

Wait for propagation, then validate both certs:

```bash
terragrunt apply -target=aws_acm_certificate_validation.regional -target=aws_acm_certificate_validation.us_east_1
```

This polls AWS until it sees both CNAMEs resolve publicly and marks the
certs ISSUED — safe to re-run if it times out before propagation
finishes.

## 4. Apply everything else

Still in `live/prod` from the previous step:

```bash
terragrunt apply
```

Review the plan before confirming — it creates ~50 resources (ECS cluster
+ ALB + service + task def + IAM roles, the Lambda function + event
source mapping, the SQS queue + DLQ, both ECR repos, 8 SSM parameters, the
GitHub OIDC provider + two deployer roles, plus the 2 ACM certs + their
validations from step 3b (already in state by this point), the private S3 image bucket + its 4 config
resources, and the CloudFront distribution + OAC + bucket policy).

Note the outputs — `pbl_api_deployer_role_arn` and
`pbl_mail_service_deployer_role_arn` are needed in the next step.

Then print the last two CNAMEs and add them at iNet the same way as
step 3b:

```bash
terragrunt output -raw pbl_api_cname
terragrunt output -raw image_cdn_cname
```

Wait for propagation, then verify:

```bash
curl -I https://api.sapo.makeasy.id.vn/health   # expect 200
```

## 5. Push both application repos to GitHub

If you haven't already: create a GitHub repo for each of `pbl-api` and
`pbl-mail-service`, push.

## 6. Wire up each repo's GitHub Actions

In **each** repo, go to **Settings → Secrets and variables → Actions →
Variables** (not Secrets — none of this is sensitive; it's a role ARN and
resource names, and the workflow's OIDC exchange proves who's calling, not
a shared secret) and add:

### pbl-api repo variables

Print them all with `terragrunt output -raw github_actions_variables`. Setting `AWS_DEPLOYER_ROLE_ARN`
switches the deploy jobs on (they are skipped while it is unset).

| Variable | Value |
|---|---|
| `AWS_DEPLOYER_ROLE_ARN` | `pbl_api_deployer_role_arn` output |
| `AWS_REGION` | your region, e.g. `ap-southeast-1` |
| `AWS_ECR_REPOSITORY` | `pbl-api` (the shared service repository) |
| `AWS_GATEWAY_ECR_REPOSITORY` | `pbl-gateway` |
| `AWS_ECS_CLUSTER` | `ecs_cluster` output |
| `GATEWAY_JWKS_URL` | `http://platform:3000/.well-known/jwks.json` |
| `GATEWAY_CORS_ORIGINS` | comma-separated exact web origins |

### pbl-mail-service repo variables

| Variable | Value |
|---|---|
| `AWS_DEPLOYER_ROLE_ARN` | `pbl_mail_service_deployer_role_arn` output |
| `AWS_REGION` | your region |
| `AWS_ECR_REPOSITORY` | `pbl_mail_service_ecr_name` output |
| `AWS_LAMBDA_FUNCTION_NAME` | `pbl_mail_service_lambda_function_name` output |

Also create a GitHub **environment** named `production` in both repos
(each `deploy.yml` targets it — lets you require manual approval there if
you want).

Push to `main` (or run the workflow manually) — each repo's
`.github/workflows/deploy.yml` builds, pushes to ECR, and deploys (ECS:
register a new task definition revision + force a new deployment; Lambda:
`update-function-code`).

## 7. Provision Neon, then migrate

Run `scripts/neon-bootstrap.sql` once as the database owner (it creates the eight roles and schemas; the
command is in its header), before the first deploy. After that nothing is run by hand: every service
except platform migrates itself at start, and `deploy.yml` runs platform's migrations as a one-off ECS
task of the new image before it rolls any service out.

## Secrets reference (single source of truth)

| Secret | Consumed by | Where the value comes from | Delivery mechanism |
|---|---|---|---|
| `database_passwords` (× 8) | each service, its own `pbl_<service>` role | Generated; the same values go to `scripts/neon-bootstrap.sql` | SSM `/pbl/<service>/DATABASE_PASSWORD` → ECS task `secrets` |
| `REDIS_PASSWORD` | every service | Upstash Redis dashboard | SSM `/pbl/shared/REDIS_PASSWORD` → ECS task `secrets` |
| `INTERNAL_S2S_TOKEN` | every service (header `x-internal-token`) | Generated: `openssl rand -hex 32` | SSM `/pbl/shared/INTERNAL_S2S_TOKEN` → ECS task `secrets` |
| `INTEGRATION_CREDENTIAL_MASTER_KEY` | integration | Generated: `openssl rand -base64 32` | SSM `/pbl/integration/...` → ECS task `secrets` |
| `AUTH_JWT_PRIVATE_KEY` | platform | Generated: `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \| base64 -w0` (base64 PEM RSA key; the key id `AUTH_JWT_KEY_ID` is a plain ECS env var, not a secret) | SSM `SecureString` → ECS task `secrets` |
| `AUTH_FORGOT_SECRET` / `AUTH_CONFIRM_EMAIL_SECRET` | platform | Generated (`openssl rand -base64 32`) | SSM `SecureString` → ECS task `secrets` |
| `OBSERVE_APP_KEY` / `OBSERVE_APP_SECRET` | pbl-api (SSM), pbl-mail-service (plain Lambda env — no SSM-backed `secrets` block exists for Lambda) | observe.nestjs.com project | pbl-api: SSM; pbl-mail-service: Lambda environment variable |
| `RESEND_API_KEY` | pbl-mail-service | Resend dashboard | Lambda environment variable |
| `AWS_DEPLOYER_ROLE_ARN` (× 2) | GitHub Actions (per repo) | Terraform output, no secret value — a role ARN, not a credential | Repo *variable*, not secret |

If a secret isn't in this table, something's undocumented — fix that
rather than adding a new one silently.

## Verifying monitoring survived the split

Both `pbl-api` and `pbl-mail-service` call `createObserveModule()` in
their own `app.module.ts`, using the *same* `OBSERVE_APP_KEY`/
`OBSERVE_APP_SECRET` but a distinct `serviceId` (`'pbl-api'` vs
`'pbl-mail-service'`). pbl-mail-service runs under
`NestFactory.createApplicationContext()` (no HTTP server, since it's a
bare SQS-triggered Lambda) — confirmed compatible with Observe: it only
injects `HttpAdapterHost` (a provider available in both bootstrap modes)
and never calls anything on it during module init.

After deploying both:

1. Open the observe.nestjs.com dashboard.
2. Hit `pbl_api_url`, confirm requests show up under `pbl-api`.
3. Register a user through pbl-api's `/api/v1/auth/email/register` —
   confirm the resulting SQS→Lambda invocation shows up under
   `pbl-mail-service`, and confirm the email actually arrives (check
   Resend's own delivery log too).
4. There's no automatic trace-id propagation from the request that
   published the SQS message to the Lambda invocation it triggers —
   Observe traces each service's own work, but correlating "this request →
   this message → this email" across services isn't wired up here. Treat
   as a follow-up if you need it.

## Notes / things to revisit later

- **No autoscaling** — `desired_count = 1` (see `ecs.tf`), a fixed single
  task. Fine for low traffic; revisit with an `aws_appautoscaling_target`
  if that changes.
- **State is already remote** — the root `root.hcl` puts it in S3
  with a DynamoDB lock table, auto-created on first run. Safe for more
  than one person to `terragrunt apply` against (locking prevents
  concurrent runs from corrupting state), though nothing here restricts
  *who* can — that's an IAM-policy concern on the bucket/table if this
  ever needs it.
- **DLQ has no alerting** — failed SQS messages land in
  `email-verification-dlq` after 3 delivery attempts, but nothing pages
  you when that happens. A CloudWatch alarm on
  `ApproximateNumberOfMessagesVisible` for the DLQ is worth adding once
  this is running for real users.
