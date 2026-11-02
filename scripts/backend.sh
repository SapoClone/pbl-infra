#!/usr/bin/env bash
# Stops the backend's ECS services (desired count 0) to save cost, starts them again, or shows them. Nothing else is
# touched: the ALB, DNS, secrets, queues and images stay. See PAUSE-AND-RESUME.md.
# Uses the aws CLI's credentials (AWS_PROFILE=pbl-prod). Subcommands: stop | start | status.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-ap-southeast-1}"
CLUSTER="${CLUSTER:-pbl}"
read -ra SERVICES <<<"${SERVICES:-platform catalog customer inventory sales finance integration insight gateway}"
REST=()
for s in "${SERVICES[@]}"; do [[ $s == platform || $s == gateway ]] || REST+=("$s"); done
has() { [[ " ${SERVICES[*]} " == *" $1 "* ]]; }

scale() { # scale <count> <service...>
  local count=$1 s
  shift
  for s in "$@"; do
    aws ecs update-service --cluster "$CLUSTER" --service "$s" --desired-count "$count" >/dev/null
    echo "$s -> $count"
  done
}
wait_stable() {
  echo "waiting for $* to settle (up to 10 minutes)"
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$@"
}
status() {
  aws ecs describe-services --cluster "$CLUSTER" --services "${SERVICES[@]}" \
    --query 'services[].{service:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount}' \
    --output table
}

case "${1:-}" in
  stop)
    # The gateway first, so no request reaches a service on its way down.
    if has gateway; then scale 0 gateway; fi
    scale 0 "${REST[@]}"
    if has platform; then scale 0 platform; fi
    wait_stable "${SERVICES[@]}"
    status
    ;;
  start)
    # Platform first: every other service verifies tokens against its JWKS. The gateway last, so it opens to traffic
    # once the services behind it run.
    if has platform; then scale 1 platform && wait_stable platform; fi
    scale 1 "${REST[@]}"
    wait_stable "${REST[@]}"
    if has gateway; then scale 1 gateway && wait_stable gateway; fi
    status
    ;;
  status) status ;;
  *) echo "usage: $0 stop|start|status" >&2; exit 2 ;;
esac
