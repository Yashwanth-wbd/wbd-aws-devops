#!/usr/bin/env bash
# Post-deploy smoke test through CloudFront. Non-zero exit makes deploy.yml roll back.
#
#   smoke.sh <base-url> [expected-version]
#
# Passes when GET <base-url>/api/health returns 200 (and, if given, the body contains the
# expected version - the API reports APP_VERSION, which ecs-deploy.sh sets).
set -euo pipefail

SMOKE_ATTEMPTS="${SMOKE_ATTEMPTS:-12}"
SMOKE_INTERVAL="${SMOKE_INTERVAL:-10}"

[ $# -ge 1 ] || { echo "usage: smoke.sh <base-url> [expected-version]" >&2; exit 2; }
url="${1%/}/api/health"
expected="${2:-}"
body=$(mktemp)

for i in $(seq 1 "$SMOKE_ATTEMPTS"); do
  code=$(curl -sS -o "$body" -w '%{http_code}' --max-time 10 "$url" || echo "000")
  if [ "$code" = "200" ]; then
    if [ -z "$expected" ] || grep -q -- "$expected" "$body"; then
      echo "Smoke test passed: $url -> 200 $(head -c 200 "$body")"
      exit 0
    fi
    echo "  attempt $i: 200 but version '$expected' not reported yet"
  else
    echo "  attempt $i: HTTP $code"
  fi
  sleep "$SMOKE_INTERVAL"
done

echo "::error::Smoke test failed: $url (last HTTP $code): $(head -c 500 "$body")"
exit 1
