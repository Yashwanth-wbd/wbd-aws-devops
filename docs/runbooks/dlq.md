# Runbook: dead-letter queues

| Alarm | Queue | Who puts messages there |
|---|---|---|
| `mmm-<env>-dlq-not-empty` | `mmm-<env>-jobs-dlq.fifo` | SQS, after a job was received 3 times without being deleted (worker crashed or failed) |
| `mmm-<env>-data-trigger-dlq-not-empty` | data-trigger DLQ (`terraform output data_platform` → `trigger_dlq_url`) | EventBridge, when the data-trigger Lambda failed for an hour |

## Jobs DLQ

1. **Look at the messages (do not delete them):**
   ```bash
   DLQ=$(aws sqs get-queue-url --queue-name $P-jobs-dlq.fifo --query QueueUrl --output text)
   aws sqs get-queue-attributes --queue-url $DLQ --attribute-names ApproximateNumberOfMessages
   aws sqs receive-message --queue-url $DLQ --max-number-of-messages 10 --visibility-timeout 30 \
     --attribute-names All --query 'Messages[].{id:MessageId,group:Attributes.MessageGroupId,count:Attributes.ApproximateReceiveCount,body:Body}'
   ```
   (`--visibility-timeout 30` puts them back after 30 s.)
2. **Find the cause** in the worker logs for those job IDs:
   ```bash
   aws logs filter-log-events --log-group-name /ecs/$P/optimizer-worker --filter-pattern '"<job id>"' --max-items 50
   ```
   Typical causes: bug for a specific input (fix and release first), out of memory (task stopped
   with `OutOfMemoryError` – raise memory in `ecs.tf`), database or Databricks unavailable (wait
   until healthy), job longer than the visibility timeout (raise `visibility_timeout_seconds`).
3. **Redrive** once the cause is fixed (the jobs are idempotent by job ID):
   ```bash
   SRC=$(aws sqs get-queue-attributes --queue-url $DLQ --attribute-names QueueArn --query Attributes.QueueArn --output text)
   aws sqs start-message-move-task --source-arn $SRC        # back to mmm-<env>-jobs.fifo
   aws sqs list-message-move-tasks --source-arn $SRC        # wait for COMPLETED
   ```
4. **Jobs that should not run again** (user cancelled, input invalid): tell the app team which
   job IDs to mark failed, then purge only after agreement: `aws sqs purge-queue --queue-url $DLQ`.
5. The alarm returns to OK when the DLQ is empty. Note the job IDs and cause in the ticket.

## Data-trigger DLQ

The Lambda failed for every retry (code error, MWAA unavailable, permission). Check
`/aws/lambda/mmm-<env>-data-trigger`, fix, then re-send: each DLQ message is the original
EventBridge event – replay it with `aws events put-events` (same `detail`, so duplicates are
ignored by `request_id`), or start a fresh run with `scripts/trigger-ondemand.sh <env> <bu>`.
Then purge the DLQ. Details: [docs/10 §9](../10-data-platform-and-model-governance.md#9-troubleshooting).
