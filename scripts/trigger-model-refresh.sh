#!/usr/bin/env bash
# Start an on-demand model refresh: sends an mmm.refresh event to the default EventBridge bus of
# the account your AWS credentials point to; the rule mmm-<env>-model-refresh-on-demand starts one
# mmm-<env>-model-refresh execution per business unit (Databricks features -> train -> evaluate -> register).
#
#   scripts/trigger-model-refresh.sh <dev|staging|prod> <business_unit|all> [reason]
#
# Needs: aws CLI v2, jq, credentials for that environment's account (e.g. AWS_PROFILE=mmm-dev-devops)
# with events:PutEvents. The same event can be sent by any approved caller (e.g. the API).
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
[ $# -ge 2 ] || die "usage: trigger-model-refresh.sh <dev|staging|prod> <business_unit|all> [reason]"

environment=$1 business_unit=$2 reason=${3:-"on-demand refresh"}
case "$environment" in dev | staging | prod) ;; *) die "environment must be dev, staging or prod" ;; esac
[[ "$business_unit" =~ ^[a-z][a-z0-9-]*$ ]] || die "business_unit must be lowercase (e.g. streaming) or all"

short=$(jq -rn --arg e "$environment" '{dev: "dev", staging: "stg", prod: "prd"}[$e]')
caller=$(aws sts get-caller-identity --output json)
account=$(jq -r .Account <<< "$caller")
requested_by=$(jq -r .Arn <<< "$caller")

if [ "$business_unit" = all ]; then
  # One schedule per business unit, named mmm-<env_short>-refresh-<bu>.
  mapfile -t units < <(aws scheduler list-schedules --group-name "mmm-$short-model-refresh" \
    --query 'Schedules[].Name' --output text | tr '\t' '\n' | sed "s/^mmm-$short-refresh-//")
  [ "${#units[@]}" -gt 0 ] && [ -n "${units[0]}" ] || die "no schedules in group mmm-$short-model-refresh"
else
  units=("$business_unit")
fi

entries=$(for bu in "${units[@]}"; do
  jq -cn --arg bu "$bu" --arg by "$requested_by" --arg r "$reason" \
    '{Source: "mmm.refresh", DetailType: "Model Refresh Requested",
      Detail: ({business_unit: $bu, requested_by: $by, reason: $r} | tojson)}'
done | jq -cs .)

echo "account $account ($environment): requesting model refresh of ${units[*]}"
result=$(aws events put-events --entries "$entries" --output json)
[ "$(jq -r .FailedEntryCount <<< "$result")" = 0 ] || die "EventBridge rejected the event: $(jq -c .Entries <<< "$result")"

echo "accepted: $(jq -r '[.Entries[].EventId] | join(", ")' <<< "$result")"
echo "An unknown business_unit matches no rule and starts nothing. Executions:"
echo "  aws stepfunctions list-executions --max-results 5 --state-machine-arn \\"
echo "    arn:aws:states:\$AWS_REGION:$account:stateMachine:mmm-$short-model-refresh"
