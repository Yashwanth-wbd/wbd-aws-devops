# 06 – Authorization model: who can do what

There are four kinds of identity. Each one is authenticated differently and limited
differently.

| Identity | Authenticated by | Authorized by | Details |
|---|---|---|---|
| Engineers | Okta + MFA → IAM Identity Center | Permission sets per account | [02-aws-access-sso-cli.md](02-aws-access-sso-cli.md) |
| Pipelines | GitHub OIDC token | IAM roles whose trust is bound to repo + GitHub Environment | [03-github-oidc.md](03-github-oidc.md) |
| Running services | ECS task role (automatic temporary credentials) | One IAM role per service, least privilege | Section 2 below |
| Planners | Okta OIDC + MFA (step-up for sensitive actions) | App roles + business-unit claim + PostgreSQL RLS | [04-okta-mfa-app-login.md](04-okta-mfa-app-login.md) and section 3 |

## 1. Guard rails on every IAM role Terraform creates

A **permission boundary** (Step 3) is attached to every role. Even if a role's own policy is
too broad, the boundary blocks:

- creating IAM users, access keys or login profiles
- changing or removing the permission boundary
- disabling CloudTrail, GuardDuty, Security Hub or Config
- using regions WBD has not approved
- leaving the boundary off any new role it creates

## 2. Service identities (ECS task roles)

| Role | May | May not |
|---|---|---|
| `mmm-<env>-ecs-task-exec` (shared execution role) | Pull from ECR, write its log groups, read **only the listed** secrets/parameters, KMS decrypt for those | Anything at runtime inside the app |
| `mmm-<env>-task-api` | Connect to RDS Proxy as `mmm_app` (IAM auth), send to the job queue, read results bucket, read/write exports bucket, **write once** to the approved-WORM bucket (on approval), read SSM `/mmm/<env>/*` | Receive or delete queue messages; delete, change retention or bypass governance on approved-WORM objects (explicit deny) |
| `mmm-<env>-task-whatif` | Connect as `mmm_app`, receive / delete queue messages, read/write results bucket, set its own task scale-in protection, read SSM | Send to queue, touch exports or approved-WORM |
| `mmm-<env>-task-optimizer` | Same as what-if | Anything else |
| `mmm-<env>-task-migrate` | Connect to RDS Proxy as `mmm_migrator`. Only while `enable_db_bootstrap = true`: also as `mmm_admin`, plus writing the `rds/migrate` and `rds/proxy` secrets | Queue, S3 |
| `mmm-<env>-task-platform-check` | SQS round trip, S3 under `results/platform-check/` (test task, dev and staging) | DB login, other S3 paths |

Redis access is by network (security group) and the auth token, not by IAM.
The task roles are defined in `infra/environments/<env>/ecs.tf` (Step 7).
| `mmm-<env>-task-genai` (R2) | `bedrock:InvokeModel*` on the approved model ARNs, `bedrock:ApplyGuardrail` on the platform guardrail, read `/mmm/<env>/genai/*` | Any Bedrock call not through the PrivateLink endpoint; training, customization, provisioned throughput, logging and guardrail changes (explicit deny) – [docs/12](12-genai-bedrock.md) |

Each service also has its own **security group** (Step 4), so network access is limited too:
the API only accepts traffic from the ALB, the workers accept nothing inbound, the database
only accepts the RDS Proxy.

## 3. Planner authorization (application layer)

### Roles (from the Okta `mmm_roles` claim)

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
| S3 buckets | Bucket policy: HTTPS only, deny non-KMS uploads, allow only named roles; per-BU KMS keys on data buckets (Step 13) |
| SQS | Queue policy: API role can send, worker roles can receive/delete |
| Redis | TLS + auth token, security group limited to API/worker SGs |
| RDS | Reached only through RDS Proxy; IAM auth at the proxy; TLS forced |
| Databricks | Unity Catalog grants per BU; ECS workers use a service principal with read on Gold and MLflow |
