variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "environment" {
  description = "GitHub Environment name this account belongs to (dev, staging or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "env_short" {
  description = "Short environment code used in names (dev, stg, prd)."
  type        = string
}

variable "github_org" {
  description = "GitHub organisation that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name (without the organisation)."
  type        = string
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one and pass existing_oidc_provider_arn."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN, used when create_oidc_provider = false."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Permission boundary attached to every role."
  type        = string
}

variable "max_session_duration" {
  description = "Maximum session length in seconds for the pipeline roles."
  type        = number
  default     = 3600
}

variable "plan_allow_pull_requests" {
  description = "Allow pull-request workflows to assume gha-plan. Disable in prod so PR code can never read prod."
  type        = bool
  default     = true
}

variable "plan_allow_main_branch" {
  description = "Allow workflows on main without a GitHub Environment (nightly drift check) to assume gha-plan, so it never waits for an approval."
  type        = bool
  default     = true
}

variable "ecr_push_allow_main_branch" {
  description = "Allow CI builds on main (no GitHub Environment) to push images. True in dev only."
  type        = bool
  default     = false
}

variable "ecr_read_trusted_environments" {
  description = "GitHub Environments that may pull from this account's ECR to promote images (dev: [\"staging\"], staging: [\"prod\"], prod: [])."
  type        = list(string)
  default     = []
}

variable "ecr_repository_prefix" {
  description = "ECR repository namespace the pipeline roles may use."
  type        = string
  default     = "mmm"
}

variable "state_bucket_name" {
  description = "Terraform state bucket created by infra/bootstrap."
  type        = string
}

variable "state_kms_key_arn" {
  description = "KMS key that encrypts the state bucket (bootstrap output)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key for Secrets Manager (kms module output)."
  type        = string
}

variable "s3_kms_key_arn" {
  description = "KMS key for the S3 buckets (models bucket evaluation reports; kms module output)."
  type        = string
}

variable "ecr_kms_key_arn" {
  description = "KMS key for ECR (kms module output)."
  type        = string
}

variable "deploy_lambda_functions" {
  description = "Lambda functions (name without the <name_prefix>- prefix) the deploy role may release: new version + alias live."
  type        = list(string)
  default     = ["results-publisher"]
}

variable "enable_model_governance" {
  description = "Create gha-model-eval (main branch) and gha-model-approve (environment <env>-model-promotion) for the SageMaker Model Registry (data platform)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
