#!/usr/bin/env bash
# ECS deploy helpers used by .github/workflows/deploy.yml.
#
#   ecs-deploy.sh render  <template.json> <image-ref> <version>   -> prints the new task definition ARN
#   ecs-deploy.sh current <cluster> <service>                     -> prints the running task definition ARN
#   ecs-deploy.sh update  <cluster> <service> <task-def-arn>      -> deploys and waits; fails on rollback
#   ecs-deploy.sh digest  <repository> <tag>                      -> prints the image digest
#
# render takes the latest revision of the family (Terraform owns roles, env, secrets, cpu, memory),
# overlays the app-owned fields from ecs/<env>/<service>.json, sets the image and APP_VERSION,
# and registers a new revision.
set -euo pipefail

DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-1500}"

die() { echo "::error::$*" >&2; exit 1; }

render() {
  local template="$1" image="$2" version="$3" family base out
  family=$(jq -r '.family' "$template")
  [ -n "$family" ] && [ "$family" != "null" ] || die "$template has no family"

  base=$(mktemp)
  out=$(mktemp)
  aws ecs describe-task-definition --task-definition "$family" --include TAGS --output json > "$base"

  jq --slurpfile t "$template" --arg image "$image" --arg version "$version" '
    ($t[0].container | with_entries(select(.key | startswith("//") | not))) as $c
    | .tags as $tags
    | .taskDefinition
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
          .registeredAt, .registeredBy, .deregisteredAt)
    | .containerDefinitions |= map(
        if .name == "app" then
          (. + $c + { image: $image })
          | .environment = ([(.environment // [])[] | select(.name != "APP_VERSION")] + [{ name: "APP_VERSION", value: $version }])
          | with_entries(select(.value != null))
        else . end)
    | if ($tags | length) > 0 then .tags = $tags else . end
  ' "$base" > "$out"

  jq -e '.containerDefinitions[] | select(.name == "app")' "$out" > /dev/null || die "$family has no 'app' container"

  aws ecs register-task-definition --cli-input-json "file://$out" \
    --query 'taskDefinition.taskDefinitionArn' --output text
  rm -f "$base" "$out"
}

current() {
  aws ecs describe-services --cluster "$1" --services "$2" \
    --query 'services[0].taskDefinition' --output text
}

update() {
  local cluster="$1" service="$2" task_def="$3" start state primary reason
  aws ecs update-service --cluster "$cluster" --service "$service" --task-definition "$task_def" \
    --query 'service.deployments[0].id' --output text > /dev/null
  echo "Deploying $task_def to $service ..."

  start=$(date +%s)
  while :; do
    sleep 15
    read -r state primary reason < <(aws ecs describe-services --cluster "$cluster" --services "$service" --output json |
      jq -r --arg td "$task_def" '
        .services[0].deployments as $d
        | [ ($d[] | select(.taskDefinition == $td) | .rolloutState) // "GONE",
            ($d[] | select(.status == "PRIMARY") | .taskDefinition),
            (($d[] | select(.taskDefinition == $td) | .rolloutStateReason) // "-" | gsub("\\s"; "_")) ]
        | @tsv')

    case "$state" in
      COMPLETED)
        echo "$service is stable on $task_def"
        return 0 ;;
      FAILED)
        die "$service: deployment failed (${reason//_/ }). The circuit breaker rolls back to the previous revision." ;;
    esac
    [ "$primary" = "$task_def" ] || die "$service: $task_def is no longer the primary deployment (rolled back)."
    [ $(( $(date +%s) - start )) -lt "$DEPLOY_TIMEOUT" ] || die "$service: not stable after ${DEPLOY_TIMEOUT}s"
    echo "  $service: $state"
  done
}

digest() {
  aws ecr describe-images --repository-name "$1" --image-ids "imageTag=$2" \
    --query 'imageDetails[0].imageDigest' --output text
}

cmd="${1:-}"; shift || true
case "$cmd" in
  render)  [ $# -eq 3 ] || die "usage: render <template> <image> <version>"; render "$@" ;;
  current) [ $# -eq 2 ] || die "usage: current <cluster> <service>"; current "$@" ;;
  update)  [ $# -eq 3 ] || die "usage: update <cluster> <service> <task-def-arn>"; update "$@" ;;
  digest)  [ $# -eq 2 ] || die "usage: digest <repository> <tag>"; digest "$@" ;;
  *) die "usage: ecs-deploy.sh render|current|update|digest ..." ;;
esac
