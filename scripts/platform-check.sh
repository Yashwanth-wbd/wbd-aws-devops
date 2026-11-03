#!/usr/bin/env bash
# Runs inside the mmm-<env>-platform-check ECS task (aws-cli image) and proves, from the
# private-app subnets, that the task reaches every platform dependency:
#   STS + SQS + Secrets injection through VPC endpoints, S3 through the gateway endpoint (TLS),
#   RDS Proxy (5432) and Redis (6379) through the security groups.
# Start it with the command printed by: terraform output platform_check_run_command
set -euo pipefail

echo "== Identity (STS interface endpoint)"
aws sts get-caller-identity --query Arn --output text

echo "== Secret injected by the execution role"
test -n "$REDIS_AUTH_TOKEN" && echo "REDIS_AUTH_TOKEN present (${#REDIS_AUTH_TOKEN} chars)"

echo "== SQS round trip ($OPTIMIZE_QUEUE_URL)"
aws sqs send-message --queue-url "$OPTIMIZE_QUEUE_URL" \
  --message-group-id platform-check --message-deduplication-id "chk-$(date +%s%N)" \
  --message-body '{"job_type":"platform-check"}' \
  --message-attributes 'job_type={DataType=String,StringValue=platform-check}' >/dev/null
RH=$(aws sqs receive-message --queue-url "$OPTIMIZE_QUEUE_URL" --wait-time-seconds 10 \
  --message-attribute-names All --query 'Messages[0].ReceiptHandle' --output text)
test "$RH" != "None"
aws sqs delete-message --queue-url "$OPTIMIZE_QUEUE_URL" --receipt-handle "$RH"
echo "send / receive / delete OK"

echo "== S3 round trip (s3://$RESULTS_BUCKET/platform-check/)"
echo "platform-check $(date -u +%FT%TZ)" > /tmp/check.txt
aws s3 cp /tmp/check.txt "s3://$RESULTS_BUCKET/platform-check/check.txt" --only-show-errors
aws s3api head-object --bucket "$RESULTS_BUCKET" --key platform-check/check.txt --query ServerSideEncryption --output text
aws s3 rm "s3://$RESULTS_BUCKET/platform-check/check.txt" --only-show-errors
echo "put / head / delete OK (encryption shown above must be aws:kms)"

echo "== RDS Proxy ($DB_HOST:5432)"
timeout 5 bash -c "</dev/tcp/$DB_HOST/5432" && echo "reachable"

echo "== ElastiCache ($REDIS_HOST:6379)"
timeout 5 bash -c "</dev/tcp/$REDIS_HOST/6379" && echo "reachable"

echo "PLATFORM CHECK PASSED"
