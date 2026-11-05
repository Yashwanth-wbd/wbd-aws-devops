# ecs/

App-owned task-definition settings, one folder per environment, one file per service.
`deploy.yml` merges them over the Terraform task definition with `scripts/ecs-deploy.sh render`.

**Status:** `dev/` in Step 11. `staging/` and `prod/` (Step 12) are generated from `dev/` by
`scripts/sync-environments.ps1`, which renames `mmm-dev-` to `mmm-stg-` / `mmm-prd-`. Edit
`dev/` only. `repo-checks.yml` fails if the copies differ.

| File | Family / service | Image |
|---|---|---|
| `<env>/api.json` | `mmm-<env>-api` (ALB `/api/*`) | `mmm/api` |
| `<env>/ui.json` | `mmm-<env>-ui` (ALB default route) | `mmm/ui` |
| `<env>/migrate.json` | `mmm-<env>-migrate` (one-off task) | `mmm/api` |

The optimizer and training images (`mmm/sagemaker-optimizer`, `mmm/sagemaker-training`) are SageMaker
jobs, not ECS services; `deploy.yml` points the SSM parameters `/mmm/<env_short>/images/*` at them.
`sync-environments.ps1` deletes `ecs/<env>/*.json` files that no longer exist in `ecs/dev/`.

## Format

```json
{
  "//": "comment - keys starting with // are ignored",
  "family": "mmm-dev-api",
  "repository": "mmm/api",
  "container": {
    "command": ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"],
    "entryPoint": null,
    "stopTimeout": 30
  }
}
```

- `container` is merged into the `app` container. A `null` value **removes** the field, so
  `"entryPoint": null` drops the seed/bootstrap entry point.
- Only settings the app owns go here: `command`, `entryPoint`, `stopTimeout`, and if needed
  `healthCheck` or `workingDirectory`. Roles, CPU and memory, environment variables, secrets, logging
  and sidecars stay in Terraform (`infra/environments/<env>/ecs.tf`). That keeps a single owner
  for each value and keeps secrets out of Git.
- The pipeline sets `image` and the `APP_VERSION` environment variable.
- `repo-checks.yml` checks that `family` matches `mmm-<dev|stg|prd>-<file name>`.

The commands are placeholders (`//command: add actual value`) until the dev teams confirm them.
