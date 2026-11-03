# infra/bootstrap – Terraform remote state (Step 1)

Creates, **once per AWS account**, the place where every other Terraform stack stores its
state. It must exist before anything else, so this folder uses **local state** and is run
by a DevOps engineer through SSO. Everything after this runs only from GitHub Actions.

## What it creates (per account)

| Resource | Name (dev example) | Settings |
|---|---|---|
| KMS key + alias | `alias/mmm-dev-tfstate` | Rotation on, 30-day deletion window, standard key policy |
| S3 bucket | `wbd-mmm-dev-tfstate-use1` | Versioning, SSE-KMS with bucket key, public access blocked, ACLs disabled, HTTPS + TLS 1.2 only, old versions expire after 90 days (365 in prod), `prevent_destroy` |
| DynamoDB lock table (optional) | `mmm-dev-tfstate-lock` | Off by default. Pay-per-request, PITR, KMS, deletion protection |

Bucket names: `wbd-mmm-<env>-tfstate-<region-code>`, where `<region-code>` is derived from
the region (`us-east-1` → `use1`).

### Why no DynamoDB table by default

Terraform 1.10 and later lock state with a lock file next to the state in S3
(`use_lockfile = true`), and the DynamoDB option is deprecated. That is simpler and costs
nothing. Set `enable_dynamodb_lock = true` only if WBD requires a DynamoDB table.

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Terraform ≥ 1.6, AWS provider `~> 5.60`, no backend (local state) |
| `provider.tf` | Region, default tags, `allowed_account_ids` so the wrong account is refused |
| `variables.tf` | Inputs with validation (environment name, 12-digit account ID) |
| `main.tf` | KMS key, state bucket and its settings, optional lock table |
| `outputs.tf` | Bucket, key ARN and the `backend_config` values used by Step 3 |
| `dev.tfvars`, `staging.tfvars`, `prod.tfvars` | Per-account values (placeholders marked `# add actual value`) |

## Safety checks built in

1. **Wrong account:** `allowed_account_ids` stops Terraform if your credentials are for another
   account than the tfvars says.
2. **Wrong workspace:** a precondition stops the run if the selected workspace does not match
   `environment` in the tfvars. Each account's local state lives in its own workspace folder:
   `terraform.tfstate.d/<env>/terraform.tfstate`.
3. **Accidental delete:** the bucket has `prevent_destroy`.

## How to run (after WBD provides the accounts)

Replace the placeholders in the three tfvars files first (`aws_account_id`, `aws_region`,
`cost_center`).

```powershell
cd infra\bootstrap
aws sso login --sso-session wbd

# ---- dev account
$env:AWS_PROFILE = "mmm-dev-devops"
aws sts get-caller-identity                    # must show the dev account
terraform init
terraform workspace new dev                    # first time only; later: terraform workspace select dev
terraform plan  -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan

# ---- staging account (later, after dev is proven)
$env:AWS_PROFILE = "mmm-stg-devops"
terraform workspace new staging
terraform plan  -var-file=staging.tfvars -out=staging.tfplan
terraform apply staging.tfplan

# ---- prod account
$env:AWS_PROFILE = "mmm-prd-devops"            # needs time-limited DevOps elevation in prod
terraform workspace new prod
terraform plan  -var-file=prod.tfvars -out=prod.tfplan
terraform apply prod.tfplan
```

### Keep the bootstrap state safe

The local state files are not committed to Git (`*.tfstate` is git-ignored). After each
apply, copy them into the bucket they created:

```powershell
$bucket = terraform output -raw state_bucket_name
aws s3 cp terraform.tfstate.d\dev\terraform.tfstate "s3://$bucket/bootstrap/terraform.tfstate"
```

If the local file is ever lost, nothing breaks: the bucket keeps working, and the resources
can be re-imported with `terraform import`.

## Validate Step 1

Without AWS access (can be run now):

```powershell
cd infra\bootstrap
terraform fmt -check
terraform init -backend=false
terraform validate
tflint --config=..\..\.tflint.hcl
..\..\scripts\checkov-scan.ps1 -Path .
```

With AWS access (after `apply`, for each account):

```powershell
$bucket = terraform output -raw state_bucket_name
aws s3api get-bucket-versioning        --bucket $bucket          # Status: Enabled
aws s3api get-bucket-encryption        --bucket $bucket          # aws:kms + key ARN
aws s3api get-public-access-block      --bucket $bucket          # all four true
aws s3api get-bucket-policy            --bucket $bucket          # DenyInsecureTransport, DenyOldTLS
aws kms get-key-rotation-status --key-id (terraform output -raw state_kms_key_arn)   # KeyRotationEnabled: true
terraform output backend_config                                  # values for Step 3
```

Lock test: the state lock is proven in Step 3, when the first environment stack uses this
bucket. Two `terraform plan` runs at the same time must make the second one wait with
`Error acquiring the state lock`.
