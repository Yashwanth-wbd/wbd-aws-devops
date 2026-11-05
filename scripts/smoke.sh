#!/usr/bin/env bash
# Post-deploy smoke test through the public ALB. Non-zero exit makes deploy.yml roll back.
#
#   smoke.sh <base-url> [expected-version]
#
# Passes when
#   1. GET <base-url>/api/health returns 200 (and, if given, the body contains the expected
#      version - the API reports APP_VERSION, which ecs-deploy.sh sets), and
#   2. GET <base-url>/ without a session is redirected to the Cognito sign-in (the front door,
#      WAF and Cognito wiring work). SMOKE_CHECK_LOGIN=false skips this.
set -euo pipefail

SMOKE_ATTEMPTS="${SMOKE_ATTEMPTS:-12}"
SMOKE_INTERVAL="${SMOKE_INTERVAL:-10}"
SMOKE_CHECK_LOGIN="${SMOKE_CHECK_LOGIN:-true}"

[ $# -ge 1 ] || { echo "usage: smoke.sh <base-url> [expected-version]" >&2; exit 2; }
base="${1%/}"
url="$base/api/health"
expected="${2:-}"
body=$(mktemp)

ok=false
for i in $(seq 1 "$SMOKE_ATTEMPTS"); do
  code=$(curl -sS -o "$body" -w '%{http_code}' --max-time 10 "$url" || echo "000")
  if [ "$code" = "200" ]; then
    if [ -z "$expected" ] || grep -q -- "$expected" "$body"; then
      echo "Smoke test passed: $url -> 200 $(head -c 200 "$body")"
      ok=true; break
    fi
    echo "  attempt $i: 200 but version '$expected' not reported yet"
  else
    echo "  attempt $i: HTTP $code"
  fi
  sleep "$SMOKE_INTERVAL"
done
$ok || { echo "::error::Smoke test failed: $url (last HTTP $code): $(head -c 500 "$body")"; exit 1; }

if [ "$SMOKE_CHECK_LOGIN" = true ]; then
  read -r code location < <(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' --max-time 10 "$base/" || echo "000 -")
  if [ "$code" = "302" ] && [[ "$location" == *".amazoncognito.com/"* ]]; then
    echo "Sign-in redirect OK: / -> ${location%%\?*}"
  else
    echo "::error::GET $base/ should redirect to the Cognito sign-in, got HTTP $code ${location}"
    exit 1
  fi
fi
