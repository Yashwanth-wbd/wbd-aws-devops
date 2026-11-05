#!/usr/bin/env bash
# One place for what a deploy component is (used by .github/workflows/deploy.yml).
#
#   deploy-components.sh <component>   -> prints: kind <TAB> ECR repository <TAB> app folder <TAB> target
#
#   kind ecs        target = ECS service name without prefix (task definition template ecs/<env>/<target>.json)
#   kind sagemaker  target = SSM parameter name under /mmm/<env>/images/
#   kind lambda     target = Lambda function name without prefix (code zip, alias "live")
set -euo pipefail

case "${1:-}" in
  api)       printf 'ecs\tmmm/api\tapps/api\tapi\n' ;;
  ui)        printf 'ecs\tmmm/ui\tapps/ui\tui\n' ;;
  optimizer) printf 'sagemaker\tmmm/sagemaker-optimizer\tapps/sagemaker-optimizer\tsagemaker-optimizer\n' ;;
  training)  printf 'sagemaker\tmmm/sagemaker-training\tapps/sagemaker-training\tsagemaker-training\n' ;;
  publisher) printf 'lambda\t-\tapps/results-publisher\tresults-publisher\n' ;;
  *) echo "::error::unknown component '${1:-}' (api, ui, optimizer, training, publisher)" >&2; exit 1 ;;
esac
