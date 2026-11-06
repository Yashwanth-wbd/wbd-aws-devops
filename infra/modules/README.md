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
| [iam-oidc](iam-oidc/) | 3 | 1 | GitHub OIDC provider + gha-plan / apply / deploy / ecr-push / ecr-read roles; gha-model-eval / gha-model-approve with the data platform |
| [budgets](budgets/) | 3 | 1 | Monthly budget alerts + Cost Anomaly Detection |
| [network](network/) | 4 | 1 | VPC, subnets, NAT, endpoints, security groups, flow logs, optional TGW / Resolver |
| [secrets](secrets/) | 5 | 1 | Secrets Manager containers, generated secrets, SSM parameters |
| [ecr](ecr/) | 6 | 1 | Per-environment ECR repositories, scanning, lifecycle |
| [s3-bucket](s3-bucket/) | 6 | 1 | Hardened data bucket (optional Object Lock and replication) |
| [log-bucket](log-bucket/) | 6 | 1 | Log-delivery bucket for ALB and S3 access logs |
| [rds](rds/) | 6 | 1 | RDS PostgreSQL instance (Multi-AZ in staging / prod) + RDS Proxy (IAM auth) |
| [ecs-cluster](ecs-cluster/) | 7 | 1 | ECS cluster, capacity providers, Service Connect namespace, execution role |
| [alb](alb/) | 7 | 1 | Public ALB, `ui` / `api` target groups, HTTPS listener with Okta OIDC authentication (`authenticate-oidc`) |
| [ecs-service](ecs-service/) | 7 | 1 | One ECS service with task definition, task role, logs, CPU autoscaling |
| [waf-regional](waf-regional/) | 8 | 1 | Regional WAF on the ALB: managed rules, rate limit, optional geo filter |
| [run-queue](run-queue/) | 8 | 1 | SQS optimization request queue + DLQ, dispatcher Lambda that starts runs up to the concurrency limit, alarms |
| [step-functions](step-functions/) | 8 | 1 | Standard state machine with role, logs and failure alarm (optimization, model refresh, model monitor) |
| [sagemaker](sagemaker/) | 8 | 1 | SageMaker job execution role; Model Registry groups per business unit (training) |
| [lambda-function](lambda-function/) | 8 | 1 | VPC Lambda with `live` alias, seeded by Terraform, code shipped by `deploy.yml` (results publisher) |
| [monitoring](monitoring/) | 9 | 1 | SNS, alarms, dashboards, EventBridge alerts |
| [log-shipping](log-shipping/) | 9 | 1 | CloudWatch Logs → Firehose → Splunk |
| [backup](backup/) | 10 | 1 | AWS Backup vault, plan, selection, vault lock, cross-region copy |
| [databricks-access](databricks-access/) | 13 | 1 | Unity Catalog role, Databricks PrivateLink, private DNS |
| [bedrock-guardrails](bedrock-guardrails/) | 14 | 2 | Bedrock guardrail + pinned version, interventions alarm |
| [llm-gateway](llm-gateway/) | 14 | 2 | Private API Gateway + proxy Lambda to the approved LLM providers, guardrail on every call |

## Adding a module

```powershell
.\scripts\new-module.ps1 -Name <name> -Step <n> -Purpose "<one line>" -Resources "<resource 1>","<resource 2>"
```

## Validating modules

```powershell
.\scripts\validate-modules.ps1               # all modules
.\scripts\validate-modules.ps1 -Name rds     # one module
```

Runs `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` and
`tflint` per module. No AWS credentials are needed.
