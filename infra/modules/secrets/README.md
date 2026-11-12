# secrets

Secrets Manager secrets (empty containers or Terraform-generated values) and SSM parameters
for one environment. All of it is encrypted with the `secrets` KMS key.

**Status:** implemented in Step 5.

## What it creates

| Resource | Notes |
|---|---|
| `aws_secretsmanager_secret` per entry in `secrets` | Name `<path_prefix>/<key>`, e.g. `mmm/dev/splunk/hec`; KMS key `alias/mmm-<env>-secrets` |
| `random_password` + `aws_secretsmanager_secret_version` | Only for entries with `generate = true` |
| `aws_ssm_parameter` per entry in `parameters` | Name `/<path_prefix>/<key>`, e.g. `/mmm/dev/okta/issuer`; `String`, or `SecureString` with `secure = true` |

The secret and parameter names are listed in the environment stack (`infra/environments/<env>/main.tf`),
not in this module.

## How secret values are handled

| Kind | Example | Where the value comes from |
|---|---|---|
| Generated (`generate = true`) | none in v2 (supported for future use) | `random_password`, alphanumeric. The value exists only in Secrets Manager and the KMS-encrypted Terraform state. |
| Container (`generate = false`) | `api/db`, `rds/proxy`, `rds/migrate`, `okta/alb-client`, `splunk/hec`, `thirdparty/<vendor>`, `llm/<provider>` (GenAI), `databricks/export-sp` and `rds/etl` (data platform) | Created empty. A DevOps engineer fills it later with `aws secretsmanager put-secret-value` (see `docs/05-secrets-and-config.md`). Terraform never overwrites it. Only `okta/alb-client` is read by the stack (`okta_sign_in_enabled = true`), because the ALB listener needs the client secret; it is then also in the KMS-encrypted state. |
| RDS admin password | – | **Not here.** RDS creates and rotates it itself (`manage_master_user_password`). |
| Databricks export service principal | `databricks/export-sp` | A normal container (`{"client_id","client_secret"}`), read only by the Databricks export Lambda; DevOps fills it out of band (docs/05). |

- **No secret value is ever a Terraform variable**, and nothing has a `change-me` default.
- An ECS task that references an empty container fails to start. That is intentional, so a
  missing credential is noticed straight away.
- To regenerate every generated secret, change `generated_secret_rotation_id` (for example to
  `2026-12-01`) and apply. Then force a new ECS deployment of the consumers.
- `generated_values` is a **sensitive** output. Only other modules in the same stack may use it.
  It is never printed.

## Encryption and TLS

- Secrets and SecureString parameters use the customer-managed `secrets` KMS key. Reading them
  needs both `secretsmanager:GetSecretValue` (or `ssm:GetParameters`) **and** `kms:Decrypt` on
  that key.
- The Secrets Manager and SSM APIs accept TLS 1.2 or higher only. Inside the VPC, tasks reach
  them through the interface endpoints from Step 4.
- Deleted secrets can be restored for `recovery_window_in_days`: 7 in dev and staging, 30 in prod.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `path_prefix` | string | – | e.g. `mmm/dev` |
| `kms_key_arn` | string | – | `module.kms.key_arns["secrets"]` |
| `secrets` | map(object) | – | key → `{ description, generate = false, length = 64 }` |
| `generated_secret_rotation_id` | string | `"initial"` | Change to regenerate generated secrets |
| `recovery_window_in_days` | number | `30` | 7–30 |
| `parameters` | map(object) | `{}` | key → `{ value, description, secure = false }`; never put secrets in `value` |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `secret_arns` | ARN per key, for task definitions and execution-role policies |
| `secret_names` | Full name per key |
| `generated_values` | **Sensitive.** Generated values per key |
| `parameter_arns` | ARN per key |
| `parameter_names` | Full name per key |
