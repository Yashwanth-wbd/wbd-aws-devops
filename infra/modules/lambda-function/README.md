# lambda-function

A VPC Lambda function with a `live` alias, created from a seed handler so Terraform owns the
infrastructure and `deploy.yml` owns the code. Used for `results-publisher`.

**Status:** implemented (v2 architecture).

## What it creates

| Resource | Notes |
|---|---|
| `aws_lambda_function` `<prefix>-<name>` | Python 3.12, zip from `source_dir` or the module `seed/` handler; private-app subnets; X-Ray active; KMS for environment variables; `reserved_concurrency` cap. Terraform ignores later code changes (`filename`, `source_code_hash`) |
| `aws_lambda_alias` `live` | What callers invoke. `scripts/lambda-release.sh publish` moves it to a new version; `switch` moves it back (rollback). Terraform ignores the version it points to |
| `aws_iam_role` + inline policy | `policy_json` plus logs, VPC ENIs, X-Ray and the env-var key; permission boundary |
| `aws_cloudwatch_log_group` `/aws/lambda/<prefix>-<name>` | KMS (`logs`) |
| `aws_cloudwatch_metric_alarm` `<prefix>-<name>-errors` | Errors > 0 in 5 minutes → `alarm_topic_arn` |

## Inputs

`name_prefix`, `name`, `description`, `source_dir` (null = seed), `handler`, `runtime`, `timeout`
(60), `memory_size` (512), `reserved_concurrency` (10), `environment`, `policy_json`, `subnet_ids`,
`security_group_ids`, `kms_key_arn`, `logs_kms_key_arn`, `log_retention_days`, `alarm_topic_arn`,
`permissions_boundary_arn`, `component`, `tags`.

## Outputs

`function_name`, `function_arn`, `alias_arn`, `invoke_arn`, `role_arn`, `log_group_name`, `alarm_name`.
