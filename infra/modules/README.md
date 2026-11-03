# infra/modules – reusable Terraform modules

The environment stacks in `infra/environments/<env>/` contain no resources of their own. They
call these modules with different settings, so dev, staging and prod stay identical apart
from size and approvals.

Every module has the same files:

| File | Contents |
|---|---|
| `versions.tf` | Terraform `>= 1.6`, AWS provider `~> 5.60` (+ `random` / `archive` where needed, + provider aliases) |
| `main.tf` | Resources |
| `variables.tf` | Inputs, with descriptions, types and validation |
| `outputs.tf` | Values other modules or pipelines need (IDs, ARNs, names) |
| `README.md` | What it creates, inputs, outputs, notes |

Shared conventions for all modules:

- Every module takes `name_prefix` (e.g. `mmm-dev`) and `tags`. The mandatory tags are set
  once in the environment's provider `default_tags`; `tags` only adds extra ones such as
  `Component`.
- No secret is ever an input variable. Secrets are generated (`random_password`) or filled in
  Secrets Manager out of band.
- Every IAM role takes `permissions_boundary_arn` and attaches it.
- Placeholders are set in the environment `terraform.tfvars`, never as module defaults.

## Module list

| Module | Step | Release | What it builds |
|---|---|---|---|
| [kms](kms/) | 3 | 1 | KMS keys per purpose with rotation |
| [permission-boundary](permission-boundary/) | 3 | 1 | Boundary policy attached to every Terraform-created role |
| [iam-oidc](iam-oidc/) | 3 | 1 | GitHub OIDC provider + gha-plan / apply / deploy / ecr-push / ecr-read roles |
| [budgets](budgets/) | 3 | 1 | Monthly budget alerts + Cost Anomaly Detection |
| [network](network/) | 4 | 1 | VPC, subnets, NAT, endpoints, security groups, flow logs, optional TGW / Resolver |
| [secrets](secrets/) | 5 | 1 | Secrets Manager containers, generated secrets, SSM parameters |
| [ecr](ecr/) | 6 | 1 | Per-environment ECR repositories, scanning, lifecycle |
| [s3-bucket](s3-bucket/) | 6 | 1 | Hardened data bucket (optional Object Lock and replication) |
| [log-bucket](log-bucket/) | 6 | 1 | Log-delivery bucket for ALB / CloudFront / S3 access logs |
| [rds](rds/) | 6 | 1 | RDS PostgreSQL + RDS Proxy |
| [elasticache](elasticache/) | 6 | 1 | Valkey/Redis replication group |
| [sqs](sqs/) | 6 | 1 | FIFO job queue + DLQ |
| [ecs-cluster](ecs-cluster/) | 7 | 1 | ECS cluster, capacity providers, Service Connect namespace, execution role |
| [alb](alb/) | 7 | 1 | ALB, target group, HTTPS listener, origin-verify rule |
| [ecs-service](ecs-service/) | 7 | 1 | One ECS service with task definition, task role, logs, autoscaling |
| [edge](edge/) | 8 | 1 | WAF, CloudFront, security headers (Route 53 deferred) |
| [monitoring](monitoring/) | 9 | 1 | SNS, alarms, dashboards, EventBridge alerts |
| [log-shipping](log-shipping/) | 9 | 1 | CloudWatch Logs → Firehose → Splunk |
| [backup](backup/) | 10 | 1 | AWS Backup vault, plan, selection, vault lock, cross-region copy |
| [mwaa](mwaa/) | 13 | 1 | MWAA Airflow environment |
| [data-trigger](data-trigger/) | 13 | 1 | S3 / on-demand → EventBridge → Lambda → MWAA DAG run |
| [databricks-access](databricks-access/) | 13 | 1 | Unity Catalog role, Databricks PrivateLink, private DNS |
| [bedrock](bedrock/) | 14 | 2 | Bedrock endpoint, guardrails, invocation logging, alarms |

## Adding a module

```powershell
.\scripts\new-module.ps1 -Name <name> -Step <n> -Purpose "<one line>" -Resources "<resource 1>","<resource 2>"
```

## Validating modules

```powershell
.\scripts\validate-modules.ps1               # all modules
.\scripts\validate-modules.ps1 -Name sqs     # one module
```

Runs `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` and
`tflint` per module. No AWS credentials are needed.
