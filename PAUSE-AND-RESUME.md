# Pausing and resuming the deployment

The nine Fargate tasks are most of the bill. Stop them when nobody uses the API; stop the load balancer too for longer
breaks. Prices are ap-southeast-1 on-demand from the AWS Pricing API (November 2026), for the sizes in `services.tf`.

| State | AWS cost a month | To get there | Back up in | What you redo |
|---|---|---|---|---|
| Running | about 186 USD | | | |
| [Paused](#pause): services at 0 tasks | about 30 USD (the ALB) | 1 command, ~1 min | ~5 min | nothing |
| [Stopped](#stop-for-a-long-break): cluster, ALB and services destroyed | about 1 to 2 USD | 1 command, ~5 min | ~20 min | the `api.sapo` CNAME, a deploy |
| [Removed](#remove-everything): `terragrunt destroy` | 0 | several steps | a first deploy | everything in DEPLOY-BACKEND.md |

Where the running cost goes: Fargate 2.75 vCPU and 5.5 GB (124 USD), a public IPv4 address per task and three for the
ALB (44 USD), the ALB itself (18 USD plus a little per request). Neon and Upstash are billed outside AWS and are not
affected by any of this.

Every command below runs with the account's credentials:

```bash
export AWS_PROFILE=pbl-prod
cd pbl-infra
```

## Pause

```bash
scripts/backend.sh stop     # gateway first, then the services; waits until every task has stopped
scripts/backend.sh status   # desired 0, running 0 for all nine
```

While paused:

- `https://api.sapo.makeasy.id.vn` answers 503 (the ALB has no target). `https://app.sapo.makeasy.id.vn` still loads,
  but every API call fails.
- Images on `static.sapo`, the event queues, the secrets and the mail Lambda stay as they are. Nothing produces events,
  so nothing waits in the queues.
- A merge to pbl-api's `main` still deploys: the workflow registers the new task definitions and runs platform's
  migration, but the services stay at 0. The next start runs the new version.
- Terraform owns the task count. A `terragrunt apply` sets every service back to 1 task, which is also a way to resume.

## Resume

```bash
scripts/backend.sh start    # platform first (the others verify tokens against it), the gateway last
curl -s https://api.sapo.makeasy.id.vn/platform/health
```

`start` waits for each step to settle, up to 10 minutes. If a service never gets to `running 1`, its log group
(`/ecs/<service>`) says why.

## Stop for a long break

Destroys the cluster, the ALB and the services, and keeps everything that holds data or took setup: the ECR images,
both S3 buckets and their CloudFront distributions, the certificates, the SSM secrets, the event bus, the mail Lambda.

```bash
scripts/backend.sh stop     # optional, makes the destroy quicker
cd live/prod
terragrunt destroy -target=module.cluster -target=module.service -target=module.gateway
```

Read the plan before typing `yes`: 79 to destroy, all of them under `module.cluster`, `module.service` or
`module.gateway`, plus `module.pbl_api_deployer.aws_iam_role_policy.this` (it names the services, and comes back with
them). The services' CloudWatch logs go with their log groups.

## Bring back after a stop

1. Recreate what was destroyed. The ALB takes 2 to 3 minutes; the certificate is reused.

   ```bash
   cd live/prod
   terragrunt apply                       # about 79 to add, nothing to destroy
   terragrunt output -raw pbl_api_cname
   ```

2. At iNet, change the `api.sapo` CNAME to the value printed: a new ALB gets a new address every time.
3. Deploy. The services come back pointing at the `bootstrap` image tag, which does not exist, so their tasks fail to
   start until this runs. The GitHub variables have not changed.

   ```bash
   gh workflow run deploy.yml -R SapoClone/pbl-api --ref main
   ```

4. Check: `curl -s https://api.sapo.makeasy.id.vn/platform/health`.

## Remove everything

For the end of the project. `terragrunt destroy` from `live/prod` stops on two things it will not delete while they
hold data, because the modules do not set `force_delete` or `force_destroy`:

- the ECR repositories `pbl-api`, `pbl-gateway` and `pbl-mail-service` (delete their images first);
- the S3 buckets `pbl-images-<account>` and `pbl-web-<account>` (empty them first; the image bucket holds what users
  uploaded, so copy it out if it matters: `aws s3 sync s3://pbl-images-<account> ./images-backup`).

Leave the ACM validation CNAMEs at iNet: a later apply validates the new certificates against them at once. The state
bucket and lock table that Terragrunt created are not part of the stack; delete them by hand if you want the account
empty. Coming back from here is a first deploy: follow DEPLOY-BACKEND.md from step 3.

## How this was checked

`scripts/backend.sh stop` and `start` ran against the Floci stack in `rehearsal/ecs-spike/`: every task stopped and
its container went away, then the services came back in order and the ALB routed to the gateway again. The scope of
"stop for a long break" is from a `plan -destroy` with the same targets against the real account.
