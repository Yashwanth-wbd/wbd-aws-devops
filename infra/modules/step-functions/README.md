# step-functions

One Standard Step Functions state machine with its role, logs and a failure alarm. The stack
passes the definition; the module adds the plumbing. Used for `optimization` and `model-refresh`.

**Status:** implemented (v2 architecture).

## What it creates

| Resource | Notes |
|---|---|
| `aws_sfn_state_machine` `<prefix>-<name>` | Type `STANDARD`, X-Ray tracing, logging level `ALL` without execution data by default (`include_execution_data = false`, so business data stays out of logs) |
| `aws_iam_role` + inline policy | `role_policy_json` from the stack (SageMaker, Lambda, SSM, ...) plus log delivery and X-Ray. Permission boundary attached |
| `aws_cloudwatch_log_group` `/aws/states/<prefix>-<name>` | KMS (`logs`), `log_retention_days` |
| `aws_cloudwatch_metric_alarm` `<prefix>-<name>-failed` | `ExecutionsFailed + ExecutionsTimedOut + ExecutionsAborted > 0` → `alarm_topic_arn` |

## Inputs

`name_prefix`, `name`, `definition` (JSON), `role_policy_json`, `include_execution_data` (false),
`logs_kms_key_arn`, `log_retention_days` (30), `alarm_topic_arn`, `permissions_boundary_arn`,
`component`, `tags`.

## Outputs

`state_machine_arn`, `state_machine_name`, `role_arn`, `log_group_name`, `alarm_name`.
