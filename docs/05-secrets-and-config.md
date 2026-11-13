# 05 – Secrets and configuration: where everything lives

## 1. Decision table

| Kind of value | Store | Examples | Why |
|---|---|---|---|
| Passwords, tokens, keys | **AWS Secrets Manager** (KMS key `alias/mmm-<env>-secrets`) | DB app user, Okta OIDC client secret (ALB), Splunk HEC token, third-party API keys, LLM provider keys | Encrypted, audited, rotatable, injected into ECS at start |
| Non-secret runtime settings | **SSM Parameter Store** (`String`, or `SecureString` if sensitive) | `genai_enabled`, Okta issuer, run concurrency limit, Databricks host, GenAI quotas | Change via Terraform tfvars + apply |
| Non-secret pipeline settings | **GitHub Environment variables** | role ARNs, region, cluster name, subnet IDs, `APP_URL` | Not secret; scoped per environment |
| Pipeline secrets | **GitHub Environment secrets** (rare) | `SONAR_TOKEN` if SonarQube is used | Only for third-party tools that cannot use OIDC |
| AWS credentials for pipelines | **none stored** | – | GitHub OIDC gives temporary credentials |
| Databricks export service principal (model refresh) | **AWS Secrets Manager** `mmm/<env>/databricks/export-sp` | `{"client_id","client_secret"}` (OAuth M2M) | Read only by the export Lambda; DevOps fills it once (§4) |
| RDS admin password | **RDS-managed secret** (Secrets Manager, auto-rotated) | `rds!db-…` | Nobody ever sees it |

**Never:** in Git, in Docker images, in plain task-definition `environment`, in Terraform
variables or tfvars (for secret **values**), in GitHub variables, in logs.

## 2. Secret names (Step 5 creates empty containers)

All paths use prefix **`mmm/<env_short>/`** (for example `mmm/dev/api/db` in the dev account).

| Secret | Contents | Created / filled by | Read by |
|---|---|---|---|
| `mmm/<env>/api/db` | `{host, port, dbname, username, password}` | DevOps after first migration / bootstrap | API (`migrate` uses `rds/migrate`) |
| `mmm/<env>/rds/proxy` | app DB user `{username, password}` (never the admin) | DevOps after first migration | RDS Proxy (app user) |
| `mmm/<env>/rds/migrate` | migration DB user `{username, password}` (schema owner) | DevOps at first-time DB setup | Migrate task (via RDS Proxy + IAM auth) |
| `mmm/<env>/okta/alb-client` | `{"client_secret":"..."}` of the Okta OIDC Web app (`okta_client_id`) | DevOps from WBD Identity, before `okta_sign_in_enabled = true` | Terraform (data source, only with `okta_sign_in_enabled`) → ALB listener `authenticate-oidc` |
| `mmm/<env>/splunk/hec` | `{"hec_token":"..."}` (Firehose requires this key name) | DevOps from WBD Splunk team | Firehose (when `enable_splunk_shipping`) |
| `mmm/<env>/thirdparty/<vendor>` | Vendor-specific JSON (e.g. API keys) | DevOps from WBD data owners | API / batch jobs as wired by the app |
| `mmm/<env>/llm/<provider>` | `{"api_key":"..."}` (only when `enable_genai`) | DevOps from WBD / vendor | LLM gateway proxy Lambda |
| `mmm/<env>/databricks/export-sp` | `{"client_id","client_secret"}` of the WBD export service principal (only with `enable_data_platform`) | DevOps from WBD Databricks admins | Databricks export Lambda |
There is **no** `redis/token`, **no** `edge/origin-verify`, **no** EventBridge connection secret,
and **no** MWAA connection secrets.

## 3. SSM parameters (Terraform-owned values)

| Parameter | Example | Set from | Read by |
|---|---|---|---|
| `/mmm/<env>/genai_enabled` | `false` | tfvars `genai_enabled` | API |
| `/mmm/<env>/okta/issuer` | `https://wbd.okta.com/oauth2/default` | tfvars `okta_issuer` | API (also env `OKTA_ISSUER`) |
| `/mmm/<env>/optimization/max_concurrent_runs` | `5` | tfvars `max_concurrent_runs` (change it there, not in the console) | Run dispatcher Lambda (each batch) |
| `/mmm/<env>/databricks/host` | `https://dbc-….cloud.databricks.com` | tfvars `databricks_host` | Operators / diagnostics (the export Lambda gets the same value as env `DATABRICKS_HOST`) |
| `/mmm/<env>/databricks/export_job_ids` | `{"streaming":123,…}` | tfvars `databricks_export_job_ids` (data platform) | Export Lambda |
| `/mmm/<env>/genai/token_quota/<bu>` | `1000000` | tfvars `genai_token_quotas` | LLM gateway (Release 2) |

Release pointers are written by `deploy.yml` (Terraform only creates them): the optimizer task
definition ARN in **`/mmm/<env_short>/ecs/optimizer_task_definition`** and the SageMaker training
image in **`/mmm/<env_short>/images/sagemaker-training`** (data platform).

## 4. Databricks export service principal (model refresh)

When `enable_data_platform = true`, Terraform creates the empty secret
**`mmm/<env>/databricks/export-sp`**. WBD Databricks admins create a workspace service principal
with "Can manage run" on the export jobs and an OAuth secret; DevOps stores both once:

```powershell
$env:AWS_PROFILE = "mmm-dev-devops"
# export-sp.json (add actual value): {"client_id":"<application id>","client_secret":"<oauth secret>"}
aws secretsmanager put-secret-value --secret-id mmm/dev/databricks/export-sp --secret-string file://export-sp.json
Remove-Item export-sp.json
```

The export Lambda reads the secret whenever it needs a new token and exchanges it for a
short-lived token at `{databricks_host}/oidc/v1/token` (cached until shortly before expiry);
nothing else can read it.

## 5. How a value gets into a running container

```mermaid
flowchart LR
  sm[(Secrets Manager)] -->|GetSecretValue + kms:Decrypt| exec[ECS task execution role]
  ssm[(SSM Parameter Store)] -->|GetParameters| exec
  exec -->|injected as env vars at task start| c[Container]
  td[Task definition 'secrets' block lists ARNs only] --> exec
```

Example API task secrets (from Terraform): `GENAI_ENABLED` from SSM; DB credentials from Secrets
Manager when wired after bootstrap. Plain environment: `OKTA_ISSUER`, `OPTIMIZATION_QUEUE_URL`.

- The **execution role** may read only the secrets listed for that service.
- The **task role** (the app's own identity) gets no Secrets Manager access unless the app
  reads secrets itself at runtime.
- After rotating a secret, force a new deployment so tasks pick it up:
  `aws ecs update-service --cluster mmm-dev-ecs --service mmm-dev-api --force-new-deployment`

## 6. Filling a secret (DevOps engineer, through SSO)

Use a file so the value doesn't end up in shell history, then delete the file:

```powershell
$env:AWS_PROFILE = "mmm-dev-devops"
aws secretsmanager put-secret-value --secret-id mmm/dev/splunk/hec --secret-string file://hec.json
Remove-Item hec.json
aws secretsmanager describe-secret --secret-id mmm/dev/splunk/hec --query "LastChangedDate"
```

LLM provider key (Release 2, after `enable_genai = true`):

```powershell
aws secretsmanager put-secret-value --secret-id mmm/dev/llm/openai --secret-string '{"api_key":"..."}'
```

Changing a non-secret flag: update `infra/environments/<env>/terraform.tfvars` (for example
`genai_enabled = true`) through a pull request and apply. Then force a new ECS deployment,
because tasks read parameters at start.

```powershell
terraform plan -out=cfg.tfplan
terraform apply cfg.tfplan
aws ssm get-parameter --name /mmm/dev/genai_enabled --query Parameter.Value
```

## 7. Rotation

| Secret | Rotation |
|---|---|
| RDS admin | Automatic (RDS-managed) |
| Okta ALB client secret | When WBD Identity rotates it: `put-secret-value` on `okta/alb-client`, then `terraform apply` (the listener gets the new value; [runbooks/rotation.md](runbooks/rotation.md)) |
| App / migrate DB users | Manual or rotation Lambda follow-up; update Secrets Manager and redeploy |
| Splunk / third-party / LLM keys | When the issuer rotates; update the secret and force a new deployment |
| Databricks export service principal | WBD rotates the OAuth secret; `put-secret-value` on `databricks/export-sp` (used from the next token request, at most about an hour later; no redeploy) |

## 8. Guard rails

- **Trivy secret scan** (`repo-checks.yml`, the same rules as `scripts/secret-scan.ps1`) on every pull request blocks committed secrets. Turn on GitHub secret scanning push protection too, if licensed.
  Locally, run `.\scripts\secret-scan.ps1` (Trivy).
- **Checkov** fails on hard-coded credentials in Terraform.
- **CloudWatch Logs data-protection policy** masks credentials and personal data in logs.
- **Terraform state** may reference secret metadata, and holds the Okta ALB client secret (the listener needs it); the state bucket is KMS-encrypted,
  versioned, has public access blocked, and only the `gha-plan` / `gha-apply` roles and the
  DevOps permission set can read it.
