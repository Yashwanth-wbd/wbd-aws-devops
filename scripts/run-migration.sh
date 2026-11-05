#!/usr/bin/env bash
# Runs the database migration as a one-off ECS task and fails if it does not exit 0.
#
#   run-migration.sh <cluster> <task-def-arn> <subnet-ids-csv> <security-group-id>
#
# The task definition is rendered by ecs-deploy.sh with the new API image, so the migration
# always matches the code that is about to be deployed. Its log is printed into the job log.
set -euo pipefail

MIGRATION_TIMEOUT="${MIGRATION_TIMEOUT:-1800}"

die() { echo "::error::$*" >&2; exit 1; }

[ $# -eq 4 ] || die "usage: run-migration.sh <cluster> <task-def-arn> <subnet-ids-csv> <security-group-id>"
cluster="$1" task_def="$2" subnets="$3" sg="$4"

run=$(aws ecs run-task --cluster "$cluster" --task-definition "$task_def" --launch-type FARGATE \
  --count 1 --started-by "gha-${GITHUB_RUN_ID:-manual}" --propagate-tags TASK_DEFINITION \
  --network-configuration "awsvpcConfiguration={subnets=[${subnets}],securityGroups=[${sg}],assignPublicIp=DISABLED}" \
  --output json)

task_arn=$(jq -r '.tasks[0].taskArn // empty' <<< "$run")
[ -n "$task_arn" ] || die "run-task failed: $(jq -c '.failures' <<< "$run")"
echo "Migration task: $task_arn"

start=$(date +%s)
while :; do
  status=$(aws ecs describe-tasks --cluster "$cluster" --tasks "$task_arn" --query 'tasks[0].lastStatus' --output text)
  [ "$status" = "STOPPED" ] && break
  [ $(( $(date +%s) - start )) -lt "$MIGRATION_TIMEOUT" ] || die "migration still $status after ${MIGRATION_TIMEOUT}s"
  echo "  $status"
  sleep 10
done

result=$(aws ecs describe-tasks --cluster "$cluster" --tasks "$task_arn" --output json)
exit_code=$(jq -r '.tasks[0].containers[] | select(.name == "app") | .exitCode // "none"' <<< "$result")
reason=$(jq -r '.tasks[0].stoppedReason // ""' <<< "$result")

# awslogs stream: <prefix>/<container>/<task-id>
log_options=$(aws ecs describe-task-definition --task-definition "$task_def" --output json |
  jq -c '.taskDefinition.containerDefinitions[] | select(.name == "app") | .logConfiguration.options')
log_group=$(jq -r '."awslogs-group"' <<< "$log_options")
stream="$(jq -r '."awslogs-stream-prefix"' <<< "$log_options")/app/${task_arn##*/}"

echo "::group::Migration log ($log_group / $stream)"
aws logs get-log-events --log-group-name "$log_group" --log-stream-name "$stream" --start-from-head \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' || echo "(no log events)"
echo "::endgroup::"

[ "$exit_code" = "0" ] || die "migration failed: exit code $exit_code. $reason"
echo "Migration succeeded."
