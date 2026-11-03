# ecs-service

One Fargate service, or one run-on-demand task definition: task role, log group, task
definition, optional ECS service, and optional autoscaling.

**Status:** implemented in Step 7. Used for `api`, `whatif-worker`, `optimizer-worker`,
`migrate` (task only) and `platform-check` (task only).

## What it creates

| Resource | Name | Notes |
|---|---|---|
| Log group | `/ecs/<prefix>/<service>` | KMS-encrypted with the `logs` key. |
| Task role | `<prefix>-task-<suffix>` | Policy comes from `task_role_policy_json`; permission boundary attached. ECS Exec permissions are added when exec is on. |
| Task definition | family `<prefix>-<service>` | Fargate, `awsvpc`, Linux/X86_64. Read-only root filesystem with a writable `/tmp` volume; runs as `user` (default `1000:1000`, not root). |
| ECS service | `<prefix>-<service>` | Only if `create_service = true`. |
| Autoscaling | – | Only if `autoscaling` is set (see below). |

## Deployments

- Terraform creates the service once with a **seed** task definition. After that, CI/CD (Step 11)
  registers new task definition revisions and updates the service. Terraform therefore ignores
  `task_definition` and `desired_count`, so `terraform apply` never rolls back a deployment.
- Rolling update: `minimum healthy 100 %`, `maximum 200 %`, so new tasks start before old ones stop.
- **Deployment circuit breaker with rollback**: if new tasks keep failing, ECS goes back to the
  last working revision by itself.
- Private subnets only, no public IP.

## Autoscaling

| `type` | How it scales |
|---|---|
| `cpu` | Target tracking on average CPU (`cpu_target`, default 60 %), between `min` and `max`. |
| `sqs` | Step scaling on the `queue_name` depth. Scale **out** when visible messages ≥ `scale_out_threshold` (+1 task; +3 at 10 or more messages above the threshold; +5 at 50 or more). Scale **in** to `min` when visible + in-flight messages = 0 for 5 minutes. |

Workers call `UpdateTaskProtection` while they process a job, so scale-in never stops a task in
the middle of a job.

## ECS Exec

Default on (`enable_execute_command = true`). This requires `exec_audit_log_group_arn` and
`exec_kms_key_arn` (a precondition fails the plan if either is missing). Every session is logged to
`/ecs/<prefix>/exec-audit`.

```powershell
aws ecs execute-command --cluster mmm-dev-ecs --task <task-id> --container app --interactive --command "/bin/sh"
```

## Application Signals (optional)

`enable_application_signals = true` adds the CloudWatch agent and the ADOT Python
auto-instrumentation init container. It is off by default: check the image tags before you turn it
on (the CloudWatch agent default is `latest`; pin a version).

## Inputs (main ones)

| Name | Default | Description |
|---|---|---|
| `name_prefix`, `service_name`, `task_role_suffix` | – | Naming |
| `cluster_name`, `execution_role_arn` | – | From `ecs-cluster` |
| `subnet_ids`, `security_group_ids` | – | App subnets; `api` or `workers` security group |
| `permissions_boundary_arn` | – | |
| `task_role_policy_json` | – | Least-privilege policy for this service |
| `image`, `command`, `entry_point`, `user` | –, `null`, `null`, `1000:1000` | Container |
| `cpu`, `memory` | `512`, `1024` | Fargate size |
| `container_port` | `null` | Set for the API (8080) |
| `environment` | `{}` | Plain environment variables |
| `secrets` | `{}` | Name → Secrets Manager or SSM ARN (injected by the execution role) |
| `log_retention_days`, `logs_kms_key_arn` | `30`, – | |
| `create_service`, `desired_count`, `use_fargate_spot` | `true`, `1`, `false` | |
| `target_group_arn` | `null` | API only |
| `service_connect_namespace_arn` | `null` | |
| `enable_execute_command`, `exec_audit_log_group_arn`, `exec_kms_key_arn` | `true`, `null`, `null` | |
| `autoscaling` | `null` | `{ type, min, max, cpu_target, queue_name, scale_out_threshold }` |
| `enable_application_signals` | `false` | |

## Outputs

`service_name`, `task_definition_family`, `task_definition_arn`, `task_role_arn`,
`task_role_name`, `log_group_name`.
