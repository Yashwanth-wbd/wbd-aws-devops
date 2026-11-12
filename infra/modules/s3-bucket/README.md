# s3-bucket

One hardened, reusable S3 bucket. The environment stack calls it once per purpose: `landing`,
`results`, `approved-worm`, `exports` and `models`. The data platform adds `training-data` and
`lakehouse`.

**Status:** implemented in Step 6.

## Always on

| Control | How |
|---|---|
| No public access | Public access block (all four settings) and `BucketOwnerEnforced` (ACLs disabled) |
| Versioning | Enabled; overwritten or deleted versions expire after `noncurrent_version_days` |
| Encryption at rest | SSE-KMS with the `s3` KMS key and an S3 bucket key, which cuts KMS request cost |
| Encryption in transit | Bucket policy denies plain HTTP and TLS below 1.2 |
| KMS-only uploads (`deny_non_kms_uploads`) | Denies uploads that ask for SSE-S3, SSE-C or a different KMS key. Uploads **without** an encryption header get the bucket default and are allowed. If a client names the key, it must use the full key ARN of the default key or of one in `additional_kms_key_arns`. |
| Access logs | S3 server access logging to `<log bucket>/s3-access/<bucket>/` |
| Housekeeping | Incomplete multipart uploads are aborted after 7 days |

## Optional

| Feature | Input | Used by |
|---|---|---|
| Object Lock (WORM) | `object_lock = { mode, days }` | `approved-worm`: GOVERNANCE in dev/staging, COMPLIANCE in prod, 2555 days (7 years); `training-data` (training snapshots, `training_data_retention_days`). It can only be turned on when the bucket is **created**. |
| Glacier transition | `glacier_transition_days` | `landing`: 365 days; `training-data`: 180 days; objects are kept, never expired |
| Expiry | `expiration_days` | `exports`: 30 days |
| Prefix expiry | `prefix_expiration_days` | `lakehouse`: `monitoring/` 90 days (drift-check feature exports) |
| CORS | `cors_allowed_origins` | `uploads`: PUT / GET / HEAD from the app URL only, headers `content-type`, `content-md5`, `x-amz-*`, exposes `ETag` |
| EventBridge events | `enable_eventbridge` | `landing`: object events on the default bus (no rule consumes them yet; ready for a data-arrival trigger) |
| Extra policy | `additional_policy_json` | Optional, e.g. a cross-account read |
| Cross-region replication | `replication = { destination_bucket_arn, destination_kms_key_arn, permissions_boundary_arn }` | Not used for now: Step 12 uses the AWS Backup cross-region copy instead (docs/08 section 2). Turn it on for `results` / `approved-worm` only if WBD needs RPO in minutes |

Replication creates the IAM role `<bucket>-replication`. The role has the permission boundary
and can only read this bucket, write the destination, decrypt the source key through S3, and
encrypt with the destination key. The destination bucket must already exist, with versioning
on, in the DR region.

**Object Lock in practice:**

- **GOVERNANCE:** users with `s3:BypassGovernanceRetention` can still delete objects early.
  That is useful in dev.
- **COMPLIANCE:** nobody can delete or overwrite a locked version before its retention date,
  not even the root user. Use it in prod only after WBD Legal confirms the retention period.

## Inputs

| Name | Type | Default |
|---|---|---|
| `bucket_name` | string | – |
| `kms_key_arn` | string | – |
| `access_log_bucket` | string | – |
| `access_log_prefix` | string | `"s3-access/"` |
| `deny_non_kms_uploads` | bool | `true` |
| `additional_kms_key_arns` | list(string) | `[]` (landing: the per-BU keys, Step 13) |
| `object_lock` | object | `null` |
| `expiration_days` / `glacier_transition_days` | number | `null` |
| `prefix_expiration_days` | map(number) | `{}` |
| `noncurrent_version_days` | number | `90` |
| `enable_eventbridge` | bool | `false` |
| `cors_allowed_origins` | list(string) | `[]` (uploads: the app URL, for the browser's presigned PUT; https only, no wildcard) |
| `additional_policy_json` | string | `""` |
| `replication` | object | `null` |
| `component` | string | `"s3"` |
| `tags` | map(string) | `{}` |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_regional_domain_name`, `kms_key_arn`.
