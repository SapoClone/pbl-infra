# Deploying the full backend

Eight services and the gateway on ECS Fargate, behind one ALB, on Neon, Upstash and SNS/SQS. Read the
[README](README.md) for the architecture. Everything below that can be checked without AWS has been: see
[What was verified](#what-was-verified-without-aws). The rest happens on the first real apply.

## Before you start

- AWS credentials for the account (`aws sts get-caller-identity` works), Terraform >= 1.5 and Terragrunt.
- A Neon database (use the **direct**, non-pooled host) and an Upstash Redis.
- DNS: you add CNAMEs by hand at iNet (no Route53); the `*_cname` outputs say which.
- Cost: about nine small Fargate tasks plus an ALB, roughly 90 to 130 USD a month in ap-southeast-1 (an estimate).
  Destroy it when you are done: `terragrunt destroy` from `live/prod`.

## 1. Secrets

Copy `live/prod/secrets.tfvars.example` to `live/prod/secrets.tfvars` (gitignored) and fill it in:

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 | base64 -w0   # auth_jwt_private_key (2048 bits: SSM size limit)
openssl rand -hex 32                                                       # internal_s2s_token
openssl rand -base64 32                                                    # integration_credential_master_key, auth_*_secret
openssl rand -base64 24 | tr -d '/+='                                      # each of database_passwords (8 values)
```

Never reuse the key committed in pbl-api's `.env.docker.platform`.

## 2. Database

Run once as the database owner. The passwords are the `database_passwords` values; the command is in the header of
the script.

```bash
psql "$ADMIN_DATABASE_URL" -v ON_ERROR_STOP=1 -v platform_pw=... -v catalog_pw=... (all eight) -f scripts/neon-bootstrap.sql
```

Use a fresh Neon database or branch: old tables from before the monorepo would collide with the baseline migrations.

## 3. Apply

```bash
cd live/prod
terragrunt plan      # read it: ~150 resources, nothing destroyed on a first apply
terragrunt apply     # ACM waits for the validation CNAMEs: add them at iNet while it waits
terragrunt output -raw acm_regional_validation_cname
terragrunt output -raw acm_us_east_1_validation_cname
```

The ECS services start pointing at `<service>-bootstrap` images that do not exist yet, so their tasks fail to
pull until step 4. That is expected.

## 4. First deploy

1. In pbl-api: Settings > Secrets and variables > Actions > Variables, add what
   `terragrunt output -raw github_actions_variables` prints (and your real `GATEWAY_CORS_ORIGINS`).
   Create the GitHub environment `production` if it is missing.
2. Run the `Deploy to ECS` workflow (Actions tab, Run workflow). It tests, builds the nine images, runs platform's
   migrations as a one-off task, then rolls every service out.
3. Add the `pbl_api_cname` and `image_cdn_cname` records at iNet.

## 5. Verify

```bash
API=https://api.sapo.makeasy.id.vn
curl -s $API/platform/health                        # 200 (the gateway route of platform's /health)
curl -s $API/platform/.well-known/jwks.json         # {"keys":[{"kty":"RSA","kid":"prod-1",...}]} without a "d" field
```

Then a full pass through the gateway: run pbl-api's `scripts/demo-first-wave.sh`, `demo-rbac.sh` and `demo-events.sh`
against `GATEWAY=<api url>` (they create a throwaway store; they read the database through `docker compose exec`, so
against AWS use the HTTP assertions only or the rehearsal copy).

Event bus smoke test, once: sign in, create a branch, and check `sales.branch_projection` has it within seconds and
that no dead-letter alarm fired. Then `node scripts/redrive-dlq.js sales` against SQS, to prove the redrive works.

## Changing the event topology

`terraform/events-topology.json` is generated from pbl-api's `libs/contracts/src/topology.ts`. After a change there:

```bash
cd ../pbl-api && pnpm exec ts-node -r tsconfig-paths/register --transpile-only scripts/export-topology.ts \
  > ../pbl-infra/terraform/events-topology.json
```

then `terragrunt apply`. A new producer or consumer gets its topic, queue, DLQ, alarm and IAM statement from the
file; nothing else needs editing (a new service still needs an entry in `local.services`).

## Rolling back

`aws ecs update-service --cluster pbl --service <name> --task-definition <name>:<previous revision>`; the previous
revision is the one before the latest in `aws ecs list-task-definitions --family-prefix <name>`. Migrations are not
rolled back by this: they are additive baselines, so an older image keeps working with a newer schema.

## What was verified without AWS

`rehearsal/` runs the production images built by the same Dockerfile, the production gateway config, one Postgres
role per service from `scripts/neon-bootstrap.sql`, the SNS topics and SQS queues that `terraform/modules/events`
creates (a real `terraform apply` against LocalStack), and the container settings of `services.tf`. Then it runs
pbl-api's three demo scripts through the gateway.

`terraform test` plans the whole stack offline against a mocked provider.

Not verifiable without AWS: ECS Service Connect name resolution, the ALB and its health checks, IAM policies,
the `wget` container health checks under Fargate, Neon and Upstash themselves (TLS, pooling), CloudWatch alarms
delivering email. Expect to fix something there on the first apply; the order above keeps the blast radius small.

## Known gaps

- Catalog uploads use local disk, which Fargate loses on every deploy: object storage is deferred.
- Services connect with roles that own their schema, so Postgres row-level security does not apply to them; the
  tenant filter lives in the application.
- Access tokens still live 1 day and the clients have no refresh logic, so keep the Redis logout deny-list.
- No rate limiting, and `APP_SWAGGER_ENABLED` is on for platform behind basic auth only.
- ECS tasks run with public IPs and no NAT: they are reachable only from the gateway and each other (security
  group), but they are not in private subnets.
