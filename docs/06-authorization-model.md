# 06 – Authorization model: who can do what

There are four kinds of identity. Each one is authenticated differently and limited
differently.

| Identity | Authenticated by | Authorized by | Details |
|---|---|---|---|
| Engineers | Okta + MFA → IAM Identity Center | Permission sets per account | [02-aws-access-sso-cli.md](02-aws-access-sso-cli.md) |
| Pipelines | GitHub OIDC token | IAM roles whose trust is bound to repo + GitHub Environment | [03-github-oidc.md](03-github-oidc.md) |
| Running services | ECS task role, Lambda role, or Step Functions role (temporary credentials) | One IAM role per component, least privilege | Section 2 below |
| Planners | Okta (MFA at Okta) → Cognito SAML → ALB session | App roles + business-unit groups + PostgreSQL RLS | [04-okta-mfa-app-login.md](04-okta-mfa-app-login.md) and section 3 |

## 1. Guard rails on every IAM role Terraform creates

A **permission boundary** (Step 3) is attached to every role. Even if a role's own policy is
too broad, the boundary blocks:

- creating IAM users, access keys or login profiles
- changing or removing the permission boundary
- disabling CloudTrail, GuardDuty, Security Hub or Config
- using regions WBD has not approved
- leaving the boundary off any new role it creates

## 2. Service identities (ECS, Lambda, Step Functions, SageMaker)

### ECS task roles

| Role | May | May not |
|---|---|---|
| `mmm-<env>-ecs-task-exec` (shared execution role) | Pull from ECR, write its log groups, read **only the listed** secrets/parameters, KMS decrypt for those | Anything at runtime inside the app |
| `mmm-<env>-task-api` | Connect to RDS Proxy as `mmm_app` (IAM auth), start/watch/stop the optimization state machine, read approved curves under `models/curves/`, read/write the results bucket (run inputs under `runs/*/input/`), read/write exports, **write once** to approved-WORM (on approval), read SSM `/mmm/<env_short>/*`, invoke the private LLM gateway (`execute-api:Invoke`) when GenAI is enabled | Delete or tamper with approved-WORM objects (explicit deny); direct cluster login without the proxy |
| `mmm-<env>-task-ui` | Read SSM `genai_enabled` (UI banner only) | Any other AWS API |
| `mmm-<env>-task-migrate` | Connect to RDS Proxy as `mmm_migrator`. Only while `enable_db_bootstrap = true`: also as `mmm_admin`, plus writing the `rds/migrate` and `rds/proxy` secrets | S3, Step Functions |
| `mmm-<env>-task-platform-check` | S3 round trip under `results/platform-check/`, `DescribeStateMachine` on the optimization state machine, read SageMaker image SSM parameters (dev/staging when enabled) | DB login, other S3 paths |

What-if optimization runs **inside the API** on the approved curves. Full optimization is
asynchronous: the API only starts the Step Functions execution; it does not run SageMaker jobs
itself.

Network limits match the roles: the API accepts traffic only from the ALB security group; the UI
only from the ALB; tasks and Lambda reach the database only through the RDS Proxy security group.

Task roles are defined in `infra/environments/<env>/ecs.tf`.

### Optimization pipeline (Step Functions + SageMaker + Lambda)

| Role | May | May not |
|---|---|---|
| `mmm-<env>-optimization` (Step Functions) | Read the optimizer image from SSM, create/describe/stop SageMaker Processing jobs `<prefix>-opt-*`, invoke the results-publisher Lambda alias `live`, pass the SageMaker optimization role, use KMS grants for job volumes and S3 | Start executions (API only); change image pointers |
| SageMaker role `mmm-<env>-sagemaker-optimization` | Read models and results buckets, write run output under results, pull `mmm/sagemaker-optimizer` from ECR | Other buckets, other repos |
| `mmm-<env>-results-publisher` (Lambda) | Connect to RDS Proxy as `mmm_app`, read finished run output under `results/runs/*` | Write S3, start jobs |

### Model refresh (only when `enable_data_platform = true`)

| Role | May | May not |
|---|---|---|
| `mmm-<env>-model-refresh` (Step Functions) | Call Databricks job APIs through the EventBridge connection, run SageMaker training/evaluation jobs, register model packages `PendingManualApproval` | Approve models (governance pipeline only) |
| SageMaker role `mmm-<env>-sagemaker-training` | Read training-data and models, write artifacts and evaluation reports, register into model package groups `<prefix>-<bu>` | Publish curves to `curves/` (approver role only) |
| `mmm-<env>-model-refresh-trigger` | `states:StartExecution` on the model-refresh state machine (Scheduler and on-demand EventBridge rule) | Anything else |

### GitHub Actions roles (OIDC)

Defined in `infra/modules/iam-oidc/main.tf` per environment:

| Role | Trust (summary) | Purpose |
|---|---|---|
| `mmm-<env>-gha-plan` | GitHub Environment `<env>`, optional PR and `main` | Read-only plan, state lock, refresh secret metadata |
| `mmm-<env>-gha-apply` | GitHub Environment `<env>` | Terraform apply (AdministratorAccess capped by boundary) |
| `mmm-<env>-gha-deploy` | GitHub Environment `<env>` | ECS deploy, migrate task, Aurora **cluster** snapshot, SSM image pointers, Lambda release |
| `mmm-<env>-gha-ecr-push` | `<env>` and optionally `main` | Push images to dev ECR; promotion target in staging/prod |
| `mmm-<env>-gha-ecr-read` | Trusted **previous** environment | Pull images for promotion |
| `mmm-<env>-gha-model-eval` | `main` branch only | Read model registry + evaluation JSON; may set **Rejected** only |
| `mmm-<env>-gha-model-approve` | GitHub Environment `<env>-model-promotion` | Approve/reject packages; copy curves to `s3://<models>/curves/<bu>/` |

### GenAI (Release 2, `enable_genai = true`)

There is no separate GenAI ECS task. The **API task role** invokes a private API Gateway (IAM
SigV4) that proxies to approved external LLM providers; Bedrock guardrails run inside that path.
Provider API keys live in Secrets Manager and are not on the task role. Details:
[12-genai-bedrock.md](12-genai-bedrock.md).

### Database users (RDS Proxy, IAM auth required)

| DB user | Used by | How |
|---|---|---|
| `mmm_app` | API task, results-publisher Lambda | `rds-db:connect` on `arn:…:dbuser:<proxy_resource_id>/mmm_app` |
| `mmm_migrator` | migrate task | Same pattern for `mmm_migrator` |
| `mmm_admin` | migrate task during bootstrap only | Same pattern for `mmm_admin` |

Passwords for these users are in Secrets Manager (`rds/proxy`, `rds/migrate`); the proxy reads
them. Clients never use passwords at runtime—they present an IAM auth token to the proxy with TLS.

## 3. Planner authorization (application layer)

### Sign-in and request identity

Planners open the app URL on the public ALB. Unauthenticated browser traffic is redirected to
Cognito hosted UI → WBD Okta (MFA at Okta). After sign-in, the ALB sets session cookie
`mmm-session`.

- Default ALB route → **ui** target group (static web app).
- `/api/health` → **api** target group without authentication (smoke tests and monitoring).
- `/api/*` → authenticate with Cognito; unauthenticated API calls get **401** (not a redirect).

The API reads the ALB-injected header `x-amzn-oidc-data` (JWT). The signer must match the
environment variable `ALB_ARN`. Okta passes group membership in SAML attribute `groups`, mapped
to Cognito **`custom:groups`**. The API maps those group names to business unit and app role
(same naming convention as in [04](04-okta-mfa-app-login.md)—WBD to confirm group names).

### Roles (from Okta groups via `custom:groups`)

| Action | viewer | analyst | planner | approver | admin |
|---|---|---|---|---|---|
| View scenarios and results in own BU | ✔ | ✔ | ✔ | ✔ | ✔ |
| View cross-BU enterprise view | – | ✔ | ✔ | ✔ | ✔ |
| Create / edit / run scenarios | – | – | ✔ | ✔ | ✔ |
| Override a recommendation (reason required, step-up MFA) | – | – | ✔ | ✔ | – |
| Approve a scenario (step-up MFA, cannot approve own) | – | – | – | ✔ | – |
| Data-quality dashboard | – | ✔ | – | – | ✔ |
| Manage reference data (equivalization factors, pools) | – | – | – | – | ✔ (four-eyes) |

"Four-eyes" means a second admin must approve the change.

The API enforces these rules in code. OPA is optional (alternative F in the design document).

### Business-unit isolation (PostgreSQL row-level security)

The API connects as an app user that does **not** own the tables, so RLS always applies.
Each request sets the user's BU inside its transaction.

```sql
ALTER TABLE scenario ENABLE ROW LEVEL SECURITY;
ALTER TABLE scenario FORCE ROW LEVEL SECURITY;

CREATE POLICY scenario_bu_isolation ON scenario
  USING (
    business_unit = ANY (string_to_array(current_setting('app.current_bu', true), ','))
    OR current_setting('app.cross_bu', true) = 'on'
  );
```

```python
# inside the request's transaction (backend team)
await conn.execute("SELECT set_config('app.current_bu', $1, true)", ",".join(user.bu))
```

`set_config(..., true)` scopes the value to the transaction, so a pooled connection never
leaks one user's BU to the next request. Watch the RDS Proxy "pinned connections" metric in
Step 9; if pinning is high, the backend team may need to adjust how settings are applied.

### Audit

- Every scenario run, override (with reason and value impact), approval and export is
  written to append-only tables (`override_log`, `approval_log`). The app user can insert
  but not update or delete.
- `pgaudit` logs DDL and role changes to CloudWatch → Splunk.
- Approved scenarios are also written to the S3 Object Lock (WORM) bucket.

## 4. Data-layer authorization

| Store | Control |
|---|---|
| S3 buckets | Bucket policy: HTTPS only, deny non-KMS uploads, allow only named roles; per-BU KMS keys on data-platform buckets (Step 13) |
| Aurora | Reached only through RDS Proxy; IAM auth at the proxy; TLS forced; cluster in private data subnets |
| Step Functions | API may start optimization executions; refresh machine started only by Scheduler/EventBridge trigger role |
| SageMaker | Job roles scoped to named buckets and ECR repos; job names prefixed by environment |
| SageMaker Model Registry | Package groups per BU; governance roles may read evaluation JSON and (on approve) write `curves/` |
| Databricks | Unity Catalog role on landing, lakehouse, training-data; no ECS task holds Databricks tokens—the refresh state machine uses an EventBridge connection (OAuth secret set out of band) |
