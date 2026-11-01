#!/usr/bin/env bash
# Rehearse the production deployment on this machine (see docker-compose.yml). Needs docker; pbl-api checked out
# next to pbl-infra (or PBL_API_DIR). Subcommands: up | test | down.
set -euo pipefail
cd "$(dirname "$0")"
export PBL_API_DIR="${PBL_API_DIR:-$(cd ../../pbl-api && pwd)}"
export GATEWAY_HOST_PORT="${GATEWAY_HOST_PORT:-18080}"
export SQS_URL="http://sqs.ap-southeast-1.localhost.localstack.cloud:14566/000000000000" # LocalStack, for the demo scripts that read queue depths
SERVICES=(platform catalog customer inventory sales finance integration insight)
dc() { docker compose "$@"; }

terraform_events() { # apply the real events module (and the email queue) to LocalStack
  rm -rf .tf && mkdir -p .tf && cp -r ../terraform/modules .tf/ && cp ../terraform/events-topology.json .tf/
  cat > .tf/main.tf <<'TF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" {
  region                      = "ap-southeast-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    sns        = "http://localstack:4566"
    sqs        = "http://localstack:4566"
    cloudwatch = "http://localstack:4566"
  }
}
module "events" {
  source   = "./modules/events"
  topology = jsondecode(file("${path.module}/events-topology.json"))
}
module "email_verification_queue" {
  source = "./modules/sqs_queue"
  name   = "email-verification"
}
TF
  local tf=(docker run --rm --user "$(id -u):$(id -g)" --network rehearsal_pbl -v "$PWD/.tf:/w" -w /w --entrypoint terraform hashicorp/terraform:1.9)
  "${tf[@]}" init -input=false >/dev/null
  "${tf[@]}" apply -auto-approve -input=false | tail -3
}

bootstrap_database() { # the same script that provisions Neon
  local vars=()
  for s in "${SERVICES[@]}"; do vars+=(-v "${s}_pw=pw-${s}"); done
  dc exec -T postgres psql -U postgres -d pbl -v ON_ERROR_STOP=1 "${vars[@]}" -f - < ../scripts/neon-bootstrap.sql >/dev/null
}

case "${1:-}" in
  up)
    [ -f .env ] || echo "AUTH_JWT_PRIVATE_KEY=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null | base64 -w0)" > .env
    (cd "$PBL_API_DIR" && JWKS_URL=http://platform:3000/.well-known/jwks.json CORS_ORIGINS=https://app.example.com \
      node scripts/render-krakend-prod.mjs > krakend/krakend.prod.json)
    dc up -d --wait postgres redis localstack
    terraform_events
    bootstrap_database
    dc build
    echo "== platform migration, as the deploy workflow runs it (one-off task, command override)"
    dc run --rm --no-deps platform node node_modules/typeorm/cli.js migration:run \
      -d dist/apps/platform/apps/platform/src/database/data-source.js 2>&1 | tail -3
    dc up -d --wait
    echo "Gateway on http://localhost:$GATEWAY_HOST_PORT"
    ;;
  test)
    failed=0
    mkdir -p logs
    for demo in demo-first-wave demo-rbac demo-events; do
      if bash "$PBL_API_DIR/scripts/$demo.sh" > "logs/$demo.log" 2>&1; then status=PASS; else status=FAIL; failed=1; fi
      printf '%-18s %s  (%s ok, %s FAIL lines)  logs/%s.log\n' "$demo" "$status" \
        "$(grep -c '^ok:' "logs/$demo.log" || true)" "$(grep -c '^FAIL:' "logs/$demo.log" || true)" "$demo"
      grep '^FAIL:' "logs/$demo.log" | head -3 || true
    done
    exit $failed
    ;;
  down)
    dc down -v --remove-orphans
    rm -rf .tf .env
    ;;
  *) echo "usage: $0 up|test|down" >&2; exit 2 ;;
esac
