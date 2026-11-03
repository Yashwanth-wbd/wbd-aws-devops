# sqs

One FIFO job queue for optimizer and what-if jobs, plus its dead-letter queue.

**Status:** implemented in Step 6.

## Queues

| Queue | Settings |
|---|---|
| `mmm-<env>-jobs.fifo` | Visibility timeout **960 s**, longer than the 15-minute longest job, so a job is never handed to a second worker while it is still running. Long polling 20 s; retention 4 days; content-based deduplication; high-throughput FIFO (deduplication and throughput per message group). |
| `mmm-<env>-jobs-dlq.fifo` | Receives a message after **3** failed deliveries (`maxReceiveCount`); kept 14 days. A redrive-allow policy accepts messages only from the job queue. |

- Both queues are KMS-encrypted with `alias/mmm-<env>-sqs` (data key reused for 5 minutes) and
  deny any request that is not over TLS.
- **Message group ID = scenario ID**, so the jobs of one scenario run in order while different
  scenarios run in parallel. The API sets a `MessageDeduplicationId` (the job ID), so a retried
  send is not processed twice.
- **Who may send or receive** is granted by IAM on the task roles (Step 7), not by the queue
  policy: the API role may only send, and the worker roles may only receive and delete. Their
  KMS permission is limited to the `sqs` key.
- **Step 9 alarms:** DLQ depth > 0, and the age of the oldest message.
- **Step 7 autoscaling:** the workers scale on queue depth.

To move messages from the DLQ back to the job queue after a fix:

```powershell
aws sqs start-message-move-task --source-arn <dlq_arn> --destination-arn <queue_arn>
```

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | |
| `kms_key_arn` | – | `module.kms.key_arns["sqs"]` |
| `visibility_timeout_seconds` | `960` | Must be > 900 |
| `max_receive_count` | `3` | |
| `message_retention_seconds` | `345600` (4 days) | |
| `dlq_retention_seconds` | `1209600` (14 days) | |
| `tags` | `{}` | |

## Outputs

`queue_url` (`OPTIMIZE_QUEUE_URL`), `queue_arn`, `queue_name`, `dlq_url`, `dlq_arn`, `dlq_name`.
