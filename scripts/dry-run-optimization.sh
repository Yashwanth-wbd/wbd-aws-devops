#!/usr/bin/env bash
# Post-release dry run of the optimization state machine (dev/staging). Non-zero exit makes
# deploy.yml roll back.
#
#   dry-run-optimization.sh <state-machine-arn> <results-bucket> <models-bucket> <business-unit> <image-parameter>
#
# Starts one execution with dry_run = true (execution name and run_id dryrun-<github run>-<attempt>).
# App contract: with DRY_RUN=true the optimizer image only loads its input and the approved curves
# and writes a small output; with dry_run the results publisher checks its database connection
# and writes no run to Aurora.
# Skipped (exit 0) while no optimizer image was released or no curves are approved for the business unit.
set -euo pipefail

DRY_RUN_TIMEOUT="${DRY_RUN_TIMEOUT:-1200}"

die() { echo "::error::$*" >&2; exit 1; }

[ $# -eq 5 ] || die "usage: dry-run-optimization.sh <state-machine-arn> <results-bucket> <models-bucket> <business-unit> <image-parameter>"
state_machine="$1" results="$2" models="$3" bu="$4" param="$5"

image=$(aws ssm get-parameter --name "$param" --query Parameter.Value --output text)
if [[ "$image" == *:unset ]]; then
  echo "::notice::Dry run skipped: no optimizer image released yet ($param)"; exit 0
fi
curve=$(aws s3api list-objects-v2 --bucket "$models" --prefix "curves/$bu/" --max-items 1 --query 'Contents[0].Key' --output text)
if [ -z "$curve" ] || [ "$curve" = None ]; then
  echo "::notice::Dry run skipped: no approved curves in s3://$models/curves/$bu/ yet"; exit 0
fi

run_id="dryrun-${GITHUB_RUN_ID:-$(date +%s)}-${GITHUB_RUN_ATTEMPT:-1}"
input_uri="s3://$results/runs/$run_id/input/"
jq -cn --arg bu "$bu" '{dry_run: true, business_unit: $bu}' | aws s3 cp - "${input_uri}request.json" --only-show-errors

input=$(jq -cn --arg run_id "$run_id" --arg bu "$bu" --arg uri "$input_uri" \
  '{run_id: $run_id, business_unit: $bu, input_s3_uri: $uri, dry_run: true}')
execution=$(aws stepfunctions start-execution --state-machine-arn "$state_machine" --name "$run_id" \
  --input "$input" --query executionArn --output text)
echo "Dry run: $execution (image $image)"

start=$(date +%s)
while :; do
  status=$(aws stepfunctions describe-execution --execution-arn "$execution" --query status --output text)
  [ "$status" != RUNNING ] && break
  [ $(( $(date +%s) - start )) -lt "$DRY_RUN_TIMEOUT" ] || die "dry run still RUNNING after ${DRY_RUN_TIMEOUT}s: $execution"
  echo "  $status"
  sleep 20
done

if [ "$status" != SUCCEEDED ]; then
  details=$(aws stepfunctions describe-execution --execution-arn "$execution" --query '[error, cause]' --output text)
  die "dry run $status: $details (see /aws/sagemaker/ProcessingJobs and the execution history)"
fi
echo "Dry run succeeded in $(( $(date +%s) - start ))s."
