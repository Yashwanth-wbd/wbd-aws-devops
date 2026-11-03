#!/usr/bin/env bash
# Start an on-demand data refresh: sends an mmm.ondemand event to the default EventBridge bus of
# the account your AWS credentials point to; the data-trigger Lambda starts one mmm_ingest run.
#
#   scripts/trigger-ondemand.sh <dev|staging|prod> <business_unit|all> [reason]
#
# Needs: aws CLI v2, jq, credentials for that environment's account (e.g. AWS_PROFILE=mmm-dev-devops)
# with events:PutEvents. The same event can be sent by any approved caller (e.g. the API).
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
[ $# -ge 2 ] || die "usage: trigger-ondemand.sh <dev|staging|prod> <business_unit|all> [reason]"

environment=$1 business_unit=$2 reason=${3:-"on-demand refresh"}
case "$environment" in dev | staging | prod) ;; *) die "environment must be dev, staging or prod" ;; esac
[[ "$business_unit" =~ ^[a-z][a-z0-9-]*$ ]] || die "business_unit must be lowercase (e.g. streaming) or all"

caller=$(aws sts get-caller-identity --output json)
account=$(jq -r .Account <<< "$caller")
requested_by=$(jq -r .Arn <<< "$caller")
request_id=$(cat /proc/sys/kernel/random/uuid 2> /dev/null || uuidgen | tr '[:upper:]' '[:lower:]')

detail=$(jq -cn --arg e "$environment" --arg bu "$business_unit" --arg id "$request_id" \
  --arg by "$requested_by" --arg r "$reason" \
  '{environment: $e, business_unit: $bu, request_id: $id, requested_by: $by, reason: $r}')
entries=$(jq -cn --arg d "$detail" '[{Source: "mmm.ondemand", DetailType: "Data refresh requested", Detail: $d}]')

echo "account $account ($environment): requesting refresh of '$business_unit' (request_id $request_id)"
result=$(aws events put-events --entries "$entries" --output json)
[ "$(jq -r .FailedEntryCount <<< "$result")" = 0 ] || die "EventBridge rejected the event: $(jq -c .Entries <<< "$result")"

short=$(jq -rn --arg e "$environment" '{dev: "dev", staging: "stg", prod: "prd"}[$e]')
echo "event $(jq -r '.Entries[0].EventId' <<< "$result") accepted."
echo "The Lambda logs the dag_run_id: aws logs tail /aws/lambda/mmm-$short-data-trigger --since 5m"
