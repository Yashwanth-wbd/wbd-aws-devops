#!/usr/bin/env bash
# Post-release dry run of the optimization path (dev/staging). Non-zero exit makes deploy.yml roll back.
#
#   dry-run-optimization.sh <queue-url> <state-machine-arn> <uploads-bucket> <models-bucket> <business-unit> <task-parameter>
#
# Uploads a small input to s3://<uploads>/<bu>/runs/<run_id>/input/ (where the browser's presigned
# PUT puts user files) and sends one request with dry_run = true to the run queue (run_id
# dryrun-<github run>-<attempt>), the same way the API does, so it also proves the run dispatcher.
# The dispatcher starts the execution named run_id when a run slot is free; the execution runs the
# optimizer task revision named by <task-parameter> (/mmm/<env>/ecs/optimizer_task_definition).
# App contract: with DRY_RUN=true the optimizer task only loads its input and the approved curves
# and writes a small output; with dry_run the results publisher checks its database connection
# and writes no run to RDS.
# Skipped (exit 0) while no optimizer task was released or no curves are approved for the business unit.
set -euo pipefail

DRY_RUN_TIMEOUT="${DRY_RUN_TIMEOUT:-1200}"
DISPATCH_TIMEOUT="${DISPATCH_TIMEOUT:-600}"

die() { echo "::error::$*" >&2; exit 1; }

[ $# -eq 6 ] || die "usage: dry-run-optimization.sh <queue-url> <state-machine-arn> <uploads-bucket> <models-bucket> <business-unit> <task-parameter>"
queue="$1" state_machine="$2" uploads="$3" models="$4" bu="$5" param="$6"

task=$(aws ssm get-parameter --name "$param" --query Parameter.Value --output text)
if [[ "$task" == *:unset ]]; then
  echo "::notice::Dry run skipped: no optimizer task released yet ($param)"; exit 0
fi
curve=$(aws s3api list-objects-v2 --bucket "$models" --prefix "curves/$bu/" --max-items 1 --query 'Contents[0].Key' --output text)
if [ -z "$curve" ] || [ "$curve" = None ]; then
  echo "::notice::Dry run skipped: no approved curves in s3://$models/curves/$bu/ yet"; exit 0
fi

run_id="dryrun-${GITHUB_RUN_ID:-$(date +%s)}-${GITHUB_RUN_ATTEMPT:-1}"
input_uri="s3://$uploads/$bu/runs/$run_id/input/"
jq -cn --arg bu "$bu" '{dry_run: true, business_unit: $bu, run_type: "optimize"}' | aws s3 cp - "${input_uri}request.json" --only-show-errors

body=$(jq -cn --arg run_id "$run_id" --arg bu "$bu" --arg uri "$input_uri" --arg by "github:${GITHUB_ACTOR:-local}" \
  '{run_id: $run_id, business_unit: $bu, input_s3_uri: $uri, requested_by: $by, dry_run: true, run_type: "optimize"}')
aws sqs send-message --queue-url "$queue" --message-body "$body" > /dev/null
execution="${state_machine/:stateMachine:/:execution:}:$run_id"
echo "Dry run queued: $run_id (task $task)"

start=$(date +%s)
until status=$(aws stepfunctions describe-execution --execution-arn "$execution" --query status --output text 2> /dev/null); do
  [ $(( $(date +%s) - start )) -lt "$DISPATCH_TIMEOUT" ] || die "dry run not started after ${DISPATCH_TIMEOUT}s - all run slots busy or the dispatcher fails (runbooks/optimization-run-failed.md)"
  echo "  queued"
  sleep 15
done
echo "Dry run started: $execution"

while [ "$status" = RUNNING ]; do
  [ $(( $(date +%s) - start )) -lt "$DRY_RUN_TIMEOUT" ] || die "dry run still RUNNING after ${DRY_RUN_TIMEOUT}s: $execution"
  echo "  $status"
  sleep 20
  status=$(aws stepfunctions describe-execution --execution-arn "$execution" --query status --output text)
done

if [ "$status" != SUCCEEDED ]; then
  details=$(aws stepfunctions describe-execution --execution-arn "$execution" --query '[error, cause]' --output text)
  die "dry run $status: $details (see the optimizer task log /ecs/<prefix>/optimizer and the execution history)"
fi
echo "Dry run succeeded in $(( $(date +%s) - start ))s."
