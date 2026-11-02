#!/usr/bin/env bash
# pbl-web's hosting on Floci: applies main.tf (the real static_site module), builds pbl-web, deploys it by running the
# AWS steps of pbl-web's .github/workflows/deploy.yml as written, then checks what a browser gets through CloudFront.
# Needs docker, node, the aws CLI and python3 with PyYAML; pbl-web checked out next to pbl-infra (or PBL_WEB_DIR).
# Subcommands: up | test | down.
set -euo pipefail
cd "$(dirname "$0")"
export PBL_WEB_DIR="${PBL_WEB_DIR:-$(cd ../../../pbl-web && pwd)}"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=ap-southeast-1 AWS_ENDPOINT_URL=http://localhost:24566
API_URL=https://api.pbl.test/platform/api/v1
tf() { docker run --rm --user "$(id -u):$(id -g)" --network pbl-web-rehearsal -v "$PWD/.tf:/w" -w /w --entrypoint terraform hashicorp/terraform:1.9 "$@"; }
output() { tf output -raw "$1"; }

workflow_steps() { # prints the run scripts of deploy.yml's AWS steps, with ${{ vars.X }} filled in
  python3 -I - "$PBL_WEB_DIR/.github/workflows/deploy.yml" "$(output bucket)" "$(output distribution_id)" <<'PY'
import re, sys, yaml
workflow, bucket, distribution = sys.argv[1:]
values = {"WEB_BUCKET": bucket, "WEB_DISTRIBUTION_ID": distribution}
steps = yaml.safe_load(open(workflow))["jobs"]["deploy"]["steps"]
for step in steps:
    if step.get("name", "").startswith(("Upload", "Invalidate")):
        print(f'echo "== {step["name"]}"')
        print(re.sub(r"\$\{\{ vars\.(\w+) \}\}", lambda m: values[m.group(1)], step["run"]))
PY
}

failed=0
check() { # check <what> <command...>: PASS when the command succeeds
  local what=$1 out
  shift
  if out=$("$@" 2>&1); then echo "PASS  $what"; else echo "FAIL  $what"; echo "$out" | tail -3 | sed 's/^/      /'; failed=1; fi
}
site() { curl -s --max-time 10 "$@"; }
is_app() { site "$base$1" | grep -q '<div id="root">'; }
status() { [[ "$(site -o /dev/null -w '%{http_code}' "$base$1")" == "$2" ]]; }
header() { site -o /dev/null -D - "$base$1" | tr -d '\r' | grep -qi "^$2"; }

case "${1:-}" in
  up)
    docker compose up -d --wait
    mkdir -p .tf && rm -rf .tf/modules && cp -r ../../terraform/modules main.tf .tf/ # keeps the state: up twice is fine
    tf init -input=false >/dev/null
    tf apply -auto-approve -input=false -no-color | tail -1
    echo "== build pbl-web (VITE_API_URL=$API_URL)"
    (cd "$PBL_WEB_DIR" && { [ -d node_modules ] || npx --yes yarn@1.22.22 install --frozen-lockfile >/dev/null; } &&
      VITE_API_URL=$API_URL npx --yes yarn@1.22.22 -s build >/dev/null)
    steps=$(workflow_steps) # here, where the Terraform state is
    (cd "$PBL_WEB_DIR" && bash -euo pipefail -c "$steps")
    ;;
  test)
    base="http://$(output distribution_id).cloudfront.localhost:24566"
    asset=$(cd "$PBL_WEB_DIR/dist" && ls assets/*.js | head -1)
    check "/ serves the app" is_app /
    check "a client-side route (/orders) serves the app" is_app /orders
    check "a nested client-side route (/customers/42) serves the app" is_app /customers/42
    check "a client-side route answers 200, not 403/404" status /orders 200
    check "a public file (/robots.txt) is served as itself" bash -c "! curl -s '$base/robots.txt' | grep -q 'id=\"root\"'"
    check "the bundle ($asset) is served" status "/$asset" 200
    check "the bundle is cached for a year" header "/$asset" "cache-control: public, max-age=31536000, immutable"
    check "index.html is revalidated on every load" header /index.html "cache-control: no-cache"
    check "the bundle calls the API at VITE_API_URL" bash -c "curl -s '$base/$asset' | grep -q '$API_URL'"
    check "the bucket refuses anonymous reads" bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code}' $AWS_ENDPOINT_URL/$(output bucket)/index.html) == 403 ]]"
    exit $failed
    ;;
  down)
    docker compose down -v --remove-orphans
    rm -rf .tf
    ;;
  *) echo "usage: $0 up|test|down" >&2; exit 2 ;;
esac
