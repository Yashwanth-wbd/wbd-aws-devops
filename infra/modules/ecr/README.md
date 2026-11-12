# ecr

The container image repositories of **one account**. Every environment has its own registry.

**Status:** implemented in Step 6.

## What it creates

| Resource | Notes |
|---|---|
| `aws_ecr_repository` × 4 | `mmm/api`, `mmm/ui` (ECS services), `mmm/optimizer` (one-off ECS optimizer task), `mmm/sagemaker-training` (SageMaker training / evaluation image, used with the data platform). |
| `aws_ecr_registry_scanning_configuration` | Amazon Inspector **enhanced, continuous** scanning for `mmm/*`. Images are re-checked whenever a new CVE is published, not only on push. |
| `aws_ecr_lifecycle_policy` per repository | Untagged images are deleted after 7 days. The newest 50 `v*` release images and the newest 30 `sha-*` build images (dev) are kept. |

Every repository has:

- **Immutable tags.** A tag such as `sha-1a2b3c4` or `v1.4.0` can never point to a different
  image, so the digest that was tested is the digest that runs.
- **KMS encryption** with `alias/mmm-<env>-ecr`.
- `force_delete = false`, so a repository that still holds images cannot be deleted by accident.

## How images move between accounts

```text
CI build (dev) --push sha-<7>--> dev ECR --copy, same digest, tag vX.Y.Z-rcN--> staging ECR --copy, tag vX.Y.Z--> prod ECR
```

The promotion job (Step 11) pulls with `mmm-<source>-gha-ecr-read` and pushes with
`mmm-<target>-gha-ecr-push`. No repository policy grants cross-account access.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `repositories` | list(string) | the 4 above | Must be `mmm/<name>` (the pipeline roles are scoped to `repository/mmm/*`) |
| `kms_key_arn` | string | – | `module.kms.key_arns["ecr"]` |
| `enhanced_scanning` | bool | `true` | false = basic scan on push |
| `untagged_expiry_days` | number | `7` | |
| `keep_sha_images` | number | `30` | 30 in dev; 1 in staging/prod, which hold release tags only |
| `keep_release_images` | number | `50` | |
| `tags` | map(string) | `{}` | |

## Outputs

`registry` (the `ECR_REGISTRY` GitHub variable), `repository_urls`, `repository_arns`.
