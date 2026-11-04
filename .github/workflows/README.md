# .github/workflows

GitHub Actions pipelines. The full guide (flow, GitHub setup, app contract, rollback) is
[docs/09-cicd-pipelines.md](../../docs/09-cicd-pipelines.md).

**Status:** implemented in Step 11; `data.yml` and `model-governance.yml` in Step 13
([docs/10](../../docs/10-data-platform-and-model-governance.md)); `genai-ci.yml` in Step 14.

| File | Trigger | Environment(s) | AWS roles |
|---|---|---|---|
| `api-ci.yml` | `apps/api/**` PR / main | `dev` (push job only) | `mmm-dev-gha-ecr-push` |
| `optimizer-ci.yml` | `apps/optimizer-worker/**` PR / main | `dev` (push job only) | `mmm-dev-gha-ecr-push` |
| `genai-ci.yml` (Release 2) | `apps/genai-gateway/**` PR / main | `dev` (push job only) | `mmm-dev-gha-ecr-push` |
| `_python-service-ci.yml` | called by the three above | | |
| `frontend-ci.yml` | `apps/frontend/**` PR / main; called by `deploy.yml` for releases | `dev` (main) | `mmm-dev-gha-deploy` |
| `deploy.yml` | CI finished on main → dev; `vX.Y.Z-rcN` → staging; `vX.Y.Z` → prod; manual | the target | previous env `gha-ecr-read`, own `gha-ecr-push`, own `gha-deploy` |
| `terraform.yml` | `infra/**` PR / main; nightly; manual | `dev` → `staging` → `prod` (apply) | `gha-plan` (PR, drift), `gha-apply` |
| `_terraform-apply.yml` | called by `terraform.yml` | the target | `gha-apply` |
| `repo-checks.yml` | every PR / main | none | none |
| `data.yml` | `data/**` PR / main → dev; `data-vX.Y.Z-rcN` → staging; `data-vX.Y.Z` → prod; manual | the target (publish job only) | own `gha-deploy` |
| `model-governance.yml` | hourly; manual evaluate / promote / rollback | none (evaluate); `<env>-model-promotion` (promote, rollback) | none: Databricks GitHub OIDC federation (eval / promote service principals) |

Rules for changes here:

- Every job that touches AWS declares `permissions: id-token: write` and gets its role ARN from
  `vars.*`. Never add AWS keys as secrets.
- Jobs that change an environment must declare `environment:`. That is what applies the approval
  rules and makes the OIDC `sub` match the role's trust policy.
- Values from events (branch names, inputs) go through `env:` into scripts, never straight into
  `run:` with `${{ }}`, which prevents script injection.
- `repo-checks.yml` runs actionlint on this folder.

Release 2 (Step 14): `genai-ci.yml` builds the GenAI gateway; `deploy.yml` has a `genai` component
that is skipped wherever the Environment variable `GENAI_ENABLED` is not `true`
([docs/12](../../docs/12-genai-bedrock.md)).
