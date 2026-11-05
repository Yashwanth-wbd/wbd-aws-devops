#!/usr/bin/env bash
# Runs inside the mmm-<env>-platform-check ECS task (aws-cli image) and proves, from the
# private-app subnets, that the task reaches every platform dependency:
#   STS, Step Functions and SSM through VPC endpoints, S3 through the gateway endpoint (TLS),
#   the Aurora RDS Proxy (5432) through the security groups, and the public front door.
# Start it with the command printed by: terraform output platform_check_run_command
set -euo pipefail

echo "== Identity (STS interface endpoint)"
aws sts get-caller-identity --query Arn --output text

echo "== S3 round trip (s3://$RESULTS_BUCKET/platform-check/)"
echo "platform-check $(date -u +%FT%TZ)" > /tmp/check.txt
aws s3 cp /tmp/check.txt "s3://$RESULTS_BUCKET/platform-check/check.txt" --only-show-errors
aws s3api head-object --bucket "$RESULTS_BUCKET" --key platform-check/check.txt --query ServerSideEncryption --output text
aws s3 rm "s3://$RESULTS_BUCKET/platform-check/check.txt" --only-show-errors
echo "put / head / delete OK (encryption shown above must be aws:kms)"

echo "== Optimization state machine (states endpoint)"
aws stepfunctions describe-state-machine --state-machine-arn "$OPTIMIZATION_STATE_MACHINE_ARN" --query status --output text

echo "== SageMaker image pointers (ssm endpoint)"
IFS=, read -ra params <<< "$IMAGE_PARAMETER_NAMES"
for p in "${params[@]}"; do
  v=$(aws ssm get-parameter --name "$p" --query Parameter.Value --output text)
  case "$v" in
    *:unset) echo "$p = $v (no image deployed yet)" ;;
    *) echo "$p = $v" ;;
  esac
done

echo "== Aurora RDS Proxy ($DB_HOST:5432)"
timeout 5 bash -c "</dev/tcp/$DB_HOST/5432" && echo "reachable"

echo "== Front door ($APP_URL)"
# Warning only: the ALB may allow only WBD network ranges (alb_ingress_cidrs), not the NAT address.
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$APP_URL/api/health" || echo 000)
if [ "$code" = 200 ]; then echo "GET /api/health -> 200"; else echo "WARNING: GET $APP_URL/api/health -> $code"; fi

echo "PLATFORM CHECK PASSED"
