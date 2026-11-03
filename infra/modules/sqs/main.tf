locals {
  tags = merge(var.tags, { Component = "sqs" })
}

resource "aws_sqs_queue" "dlq" {
  name                              = "${var.name_prefix}-jobs-dlq.fifo"
  fifo_queue                        = true
  content_based_deduplication       = true
  message_retention_seconds         = var.dlq_retention_seconds
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = merge(local.tags, { Name = "${var.name_prefix}-jobs-dlq.fifo" })
}

# One FIFO queue for optimizer and what-if jobs; the message group is the scenario ID,
# so jobs of one scenario run in order while different scenarios run in parallel.
resource "aws_sqs_queue" "jobs" {
  name                              = "${var.name_prefix}-jobs.fifo"
  fifo_queue                        = true
  content_based_deduplication       = true
  deduplication_scope               = "messageGroup"
  fifo_throughput_limit             = "perMessageGroupId"
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = var.message_retention_seconds
  receive_wait_time_seconds         = 20
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.tags, { Name = "${var.name_prefix}-jobs.fifo" })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.jobs.arn]
  })
}

# Who may send / receive is granted by the task roles (Step 7); the queue policy only enforces TLS.
data "aws_iam_policy_document" "tls_only" {
  for_each = { jobs = aws_sqs_queue.jobs.arn, dlq = aws_sqs_queue.dlq.arn }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [each.value]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  for_each = { jobs = aws_sqs_queue.jobs.id, dlq = aws_sqs_queue.dlq.id }

  queue_url = each.value
  policy    = data.aws_iam_policy_document.tls_only[each.key].json
}
