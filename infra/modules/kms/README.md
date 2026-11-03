# kms

Customer-managed KMS keys, one per purpose, with automatic yearly rotation.

**Status:** implemented in Step 3.

## What it creates

| Resource | Name (dev) |
|---|---|
| `aws_kms_key` + `aws_kms_alias` per purpose | `alias/mmm-dev-rds`, `-s3`, `-logs`, `-secrets`, `-sqs`, `-ecr` |

The Terraform state key (`alias/mmm-<env>-tfstate`) is created by `infra/bootstrap`, not here.
With the data platform (Step 13) the stack adds `mwaa` and one key per business unit
(`s3-usnetworks`, `s3-streaming`, `s3-theatrical`), all through `purposes`.

## Key policy

Every key policy has:

1. **EnableIAMPoliciesInThisAccount**: the AWS default statement. It lets IAM policies in this
   account grant use of the key. No role can use a key unless its IAM policy allows it.
2. **Purposes in `logs_service_purposes` only** (`logs`, plus `mwaa` with the data platform):
   CloudWatch Logs in this account and region may use the key, because log groups cannot use
   IAM grants.
3. Anything passed in `additional_policy_documents` for that purpose. Later steps use this,
   for example to let CloudFront read KMS-encrypted frontend files.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | – | e.g. `mmm-dev` |
| `purposes` | list(string) | `["rds","s3","logs","secrets","sqs","ecr"]` | One key per entry |
| `logs_service_purposes` | list(string) | `["logs"]` | Keys CloudWatch Logs may use |
| `deletion_window_in_days` | number | `30` | 7–30 |
| `additional_policy_documents` | map(string) | `{}` | Extra key-policy JSON per purpose |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `key_arns` | `{ rds = "arn:aws:kms:...", ... }` |
| `key_ids` | Key IDs per purpose |
| `alias_names` | Alias names per purpose |
