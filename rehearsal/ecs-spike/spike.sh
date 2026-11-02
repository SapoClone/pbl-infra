#!/usr/bin/env bash
# Can the ECS part of the deployment run on Floci? Applies main.tf (the real ecs_cluster, ecs_app and ecr_repository
# modules) to Floci with the echo image as inventory, sales and the gateway, then checks what production relies on.
# Needs docker and the aws CLI. Subcommands: up | test | down.
set -euo pipefail
cd "$(dirname "$0")"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=ap-southeast-1 AWS_ENDPOINT_URL=http://localhost:4566
ECR=localhost:4566/000000000000/ap-southeast-1 # FLOCI_SERVICES_ECR_URI_STYLE=path
SERVICES=(inventory sales gateway)
tf() { docker run --rm --user "$(id -u):$(id -g)" --network pbl-ecs-spike -v "$PWD/.tf:/w" -w /w --entrypoint terraform hashicorp/terraform:1.9 "$@"; }
alb() { curl -sk --max-time 10 "https://localhost:18443$1"; }

failed=0
check() { # check <what> <command...>: PASS when the command succeeds
  local what=$1 out
  shift
  if out=$("$@" 2>&1); then echo "PASS  $what"; else echo "FAIL  $what"; echo "$out" | tail -3 | sed 's/^/      /'; failed=1; fi
}
running() { [[ "$(aws ecs describe-services --cluster pbl --services "$1" --query 'services[0].runningCount' --output text)" == 1 ]]; }
healthy() { [[ "$(aws ecs describe-tasks --cluster pbl --tasks "$(aws ecs list-tasks --cluster pbl --service-name "$1" --query 'taskArns[0]' --output text)" --query 'tasks[0].healthStatus' --output text)" == HEALTHY ]]; }
contains() { local out; out=$("${@:2}"); [[ "$out" == *"$1"* ]] || { echo "$out"; return 1; }; }
logged() { [[ "$(aws logs filter-log-events --log-group-name "/ecs/$1" --query 'length(events)' --output text)" -gt 0 ]]; }

case "${1:-}" in
  up)
    docker compose up -d --wait
    rm -rf .tf && mkdir -p .tf && cp -r ../../terraform/modules main.tf .tf/
    tf init -input=false >/dev/null
    echo "== the ECR repositories first, so the images exist before the services start (as the first deploy does)"
    tf apply -auto-approve -input=false -no-color -target=module.pbl_api_ecr -target=module.gateway_ecr | tail -1
    docker build -q -t pbl-ecs-spike/echo echo >/dev/null
    for image in pbl-api:inventory-spike pbl-api:sales-spike pbl-gateway:spike; do
      docker tag pbl-ecs-spike/echo "$ECR/$image" && docker push -q "$ECR/$image" >/dev/null
    done
    echo "== everything else"
    tf apply -auto-approve -input=false -no-color | tail -1
    ;;
  test)
    for _ in $(seq 1 40); do running inventory && running sales && running gateway && break; sleep 3; done
    for s in "${SERVICES[@]}"; do check "$s: one task running (image pulled from ECR)" running "$s"; done
    for _ in $(seq 1 20); do healthy inventory && break; sleep 3; done
    check "inventory: container health check reported HEALTHY" healthy inventory
    check "ALB: HTTP listener redirects to HTTPS" contains "301" curl -s -o /dev/null -w '%{http_code}' http://localhost:18081/
    check "ALB: HTTPS listener (ACM certificate) forwards to the gateway" contains "service=gateway" alb /cgi-bin/env
    check "ECS: the SSM secret reaches the container" contains "secret=from-ssm" alb /cgi-bin/env
    check "Service Connect: gateway reaches http://inventory:3000" contains "reached" alb "/cgi-bin/peer?inventory"
    check "Service Connect: gateway reaches http://sales:3000" contains "reached" alb "/cgi-bin/peer?sales"
    check "Cloud Map: gateway reaches inventory.pbl.internal" contains "reached" alb "/cgi-bin/peer?inventory.pbl.internal"
    check "CloudWatch Logs: the gateway's awslogs output arrives" logged gateway
    exit $failed
    ;;
  down)
    [ -d .tf ] && tf destroy -auto-approve -input=false -no-color >/dev/null || true
    docker compose down -v --remove-orphans
    rm -rf .tf
    ;;
  *) echo "usage: $0 up|test|down" >&2; exit 2 ;;
esac
