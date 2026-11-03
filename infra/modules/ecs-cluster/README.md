# ecs-cluster

The ECS Fargate cluster shared by all MMM services, and the one task **execution** role.

**Status:** implemented in Step 7.

## What it creates

| Resource | Name | Notes |
|---|---|---|
| ECS cluster | `<prefix>-ecs` | Container Insights **enhanced** (per-task CPU, memory and network metrics in CloudWatch). |
| Capacity providers | `FARGATE`, `FARGATE_SPOT` | Default strategy is `FARGATE`. A service can opt into Spot (`use_fargate_spot`). |
| ECS Exec configuration | – | Session traffic is encrypted with the `logs` KMS key, and every session is logged (`OVERRIDE`) to the audit log group. |
| Log group | `/ecs/<prefix>/exec-audit` | Commands typed in ECS Exec sessions. KMS-encrypted, kept `log_retention_days`. |
| Service Connect namespace | `<prefix>.internal` | HTTP namespace. Services find each other by name, e.g. `http://api.<prefix>.internal`. |
| IAM role | `<prefix>-ecs-task-exec` | Used by the ECS **agent**, not by the application (see below). Has the permission boundary. |

## Execution role vs. task role

- The **execution role** (this module) is what ECS uses *before* the container starts: it pulls
  the image, writes logs, and reads the secrets and SSM parameters that are injected as
  environment variables. It is allowed to:
  - pull from `repository/mmm/*` only, and decrypt with the ECR KMS key only through ECR;
  - write logs to `/ecs/<prefix>/*` only;
  - read **only the secrets listed in `secret_arns`** and parameters under `parameter_path_arn`;
  - decrypt with the secrets KMS key only through Secrets Manager or SSM.
- The **task role** (one per service, in `ecs-service`) is what the application code uses at
  run time to call AWS (SQS, S3, RDS IAM auth).

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | `mmm-<env>` |
| `logs_kms_key_arn` | – | `module.kms.key_arns["logs"]`. Encrypts the audit log group and ECS Exec sessions. |
| `log_retention_days` | `365` | Audit log retention |
| `permissions_boundary_arn` | – | Boundary attached to the execution role |
| `secret_arns` | – | Secrets the execution role may read |
| `parameter_path_arn` | – | e.g. `arn:aws:ssm:<region>:<acct>:parameter/mmm/<env>/*` |
| `secrets_kms_key_arn` | – | `module.kms.key_arns["secrets"]` |
| `ecr_kms_key_arn` | – | `module.kms.key_arns["ecr"]` |
| `tags` | `{}` | |

## Outputs

`cluster_name` (GitHub variable `ECS_CLUSTER`), `cluster_arn`, `execution_role_arn`,
`service_connect_namespace_arn`, `exec_kms_key_arn`, `exec_audit_log_group_arn`.
