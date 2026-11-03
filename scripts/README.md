# scripts/

Helper scripts. More are added in later steps. The `.sh` files must keep LF line endings
(`.gitattributes` enforces it, and `repo-checks.yml` checks it).

| Script | Step | What it does |
|---|---|---|
| `install-prereqs.ps1` | 0 | Installs Terraform, AWS CLI v2, Git (with Git Bash), GitHub CLI, jq, tflint, Trivy, Python 3.12 + Checkov and Node.js 22 into `%USERPROFILE%\tools` without admin rights, and adds them to the user PATH. Safe to re-run. |
| `checkov-scan.ps1` | 1 | Runs Checkov on a Terraform folder. Copies the files to `%TEMP%` first, because Checkov fails on network (UNC) paths on Windows. Usage: `.\scripts\checkov-scan.ps1 -Path .\infra\bootstrap` |
| `new-module.ps1` | 2 | Creates a new module folder in `infra/modules/` with the standard files (`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `README.md`). Never overwrites an existing module. |
| `validate-modules.ps1` | 2 | Runs `fmt -check`, `init -backend=false`, `validate` and `tflint` on every module (or `-Name a,b`). Providers are cached in `%USERPROFILE%\.terraform.d\plugin-cache`. On the network share each module takes about a minute; a clone on `C:\` is much faster. A module that needs a provider alias (`configuration_aliases`, e.g. `edge`) is checked in a temp copy with a stand-in provider block, because Terraform cannot validate it on its own. |
| `secret-scan.ps1` | 5 | Scans the whole repo for committed secrets with Trivy (105 built-in rules). Copies the repo to `%TEMP%` first because of the UNC path. Exit code 1 means a secret was found. Usage: `.\scripts\secret-scan.ps1` |
| `platform-check.sh` | 7 | Not run locally. It is the command of the `mmm-<env>-platform-check` ECS task (AWS CLI image). It checks the task identity, the injected Redis token, an SQS send/receive/delete, an S3 put/head/delete under `results/platform-check/`, and TCP to RDS Proxy (5432) and Redis (6379). It ends with `PLATFORM CHECK PASSED`. Run it with `terraform output -raw platform_check_run_command`. Must keep LF line endings. |
| `db-bootstrap.py` | 7 | Not run locally. It is the command of the migrate task while `enable_db_bootstrap = true`. It creates the `mmm_migrator` and `mmm_app` DB users through RDS Proxy (IAM token as `mmm_admin`), makes `mmm_migrator` the database owner, enables `pgaudit`, and writes generated passwords only to the `rds/migrate` and `rds/proxy` secrets. Idempotent. Ends with `DB BOOTSTRAP DONE`. |
| `ecs-deploy.sh` | 11 | Used by `deploy.yml`. `render`: latest Terraform revision of a family + `ecs/<env>/<service>.json` + image + `APP_VERSION` → new revision. `update`: deploys it and waits for `rolloutState = COMPLETED`; it fails if the circuit breaker rolls back. Also `current` and `digest` |
| `run-migration.sh` | 11 | Runs the rendered `mmm-<env>-migrate` task once (`data_clients` SG, app subnets), waits, prints its log, and fails on a non-zero exit code |
| `smoke.sh` | 11 | `GET <url>/api/health` must return 200 (optionally containing the version) within 12 × 10 s; non-zero exit triggers rollback |
| `promote-images.sh` | 11 | Copies an image to the next environment's ECR with the same digest (`skopeo`), no rebuild. `find-build` picks the dev image of a commit, `find-rc` the staging rc of a prod tag |
| `deploy-frontend.sh` | 11 | Uploads a frontend build to `releases/<version>/`, writes `config.json` from the `/mmm/<env>/okta/*` parameters, and switches `current_release`. `switch` re-points only (rollback) |
| `setup-github.ps1` | 11, 13 | Creates a GitHub Environment with reviewers and allowed refs (`main`; staging/prod also `v*` and `data-v*` tags), and sets its variables from `terraform output`. With `-ModelApproverTeams/-ModelApproverUsers` it also creates `<env>-model-promotion` (prevent self-review, `main` only). Usage in `docs/09` section 4 |
| `sync-environments.ps1` | 12 | Copies the dev stack code to staging and prod: every `*.tf` except `backend.tf`, `.terraform.lock.hcl`, `tests/*.tftest.hcl`, and `ecs/dev/*.json` → `ecs/<env>/` with `mmm-dev-` renamed to `mmm-stg-` / `mmm-prd-`. It removes `.tf` files that no longer exist in dev. `-Check` changes nothing and exits 1 on any difference (CI runs the same check in `repo-checks.yml`) |
| `mock-plan.ps1` | 12 | Runs `terraform test` (`tests/mock-plan.tftest.hcl`) for each stack against a mocked AWS provider: no credentials, nothing created. It plans the tfvars and plans again with every optional feature on, then prints `Plan: N to add`. Copies to `%TEMP%` first (UNC path). Usage: `.\scripts\mock-plan.ps1 -Environment dev,staging,prod` (`-ShowPlan` for the full output) |
| `trigger-ondemand.sh` | 13 | Starts an on-demand data refresh: `scripts/trigger-ondemand.sh <dev\|staging\|prod> <business_unit\|all> "<reason>"`. Sends an `mmm.ondemand` / `Data refresh requested` event (with a new `request_id` and the caller's ARN) to the default bus of the account your credentials point to, and fails if EventBridge rejects it. Needs AWS CLI v2, jq and `events:PutEvents`. LF line endings |
| `model_governance.py` | 13 | Used by `model-governance.yml` and `data.yml`. `check-thresholds` and `evaluate-file` work offline; `evaluate`, `promote` and `rollback` talk to the Unity Catalog model registry (MLflow) with GitHub OIDC federation. Packages: `requirements-model-governance.txt`. Details in docs/10 §7 |

## install-prereqs.ps1

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-prereqs.ps1
# optional: different install folder
powershell -ExecutionPolicy Bypass -File .\scripts\install-prereqs.ps1 -ToolsDir D:\tools
```

How it works:

- Latest versions come from the HashiCorp checkpoint API, GitHub releases (Git, gh, jq,
  tflint, Trivy) and nodejs.org. Python is pinned to 3.12.10.
- The AWS CLI MSI is extracted with `msiexec /a` (an administrative install), which needs no
  admin rights.
- Python is installed per user; Checkov is installed with pip. A small `checkov.cmd` wrapper
  goes in `tools\bin` because pip's own launcher needs a `.py` file association that a
  per-user install doesn't register.
- Docker Desktop is skipped (needs admin and WSL2). CI builds images on GitHub runners.
