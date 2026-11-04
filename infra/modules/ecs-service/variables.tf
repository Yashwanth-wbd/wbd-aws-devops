# ------------------------------------------------------------------ Identity and placement
variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "service_name" {
  description = "Service name without prefix, e.g. api. Service and task family become <name_prefix>-<service_name>."
  type        = string
}

variable "task_role_suffix" {
  description = "Task role name suffix: role is <name_prefix>-task-<suffix> (e.g. api, whatif, optimizer, migrate)."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "execution_role_arn" {
  description = "Shared task execution role (ecs-cluster module)."
  type        = string
}

variable "subnet_ids" {
  description = "Private-app subnets."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups of the task (network module)."
  type        = list(string)
}

variable "permissions_boundary_arn" {
  description = "Permission boundary for the task role."
  type        = string
}

variable "task_role_policy_json" {
  description = "Least-privilege inline policy of the task role (what the app itself may call)."
  type        = string
}

# ------------------------------------------------------------------ Container (seed revision; the pipeline registers later revisions)
variable "image" {
  description = "Image of the seed task definition. deploy.yml replaces it with the ECR image on every deploy."
  type        = string
}

variable "command" {
  description = "Container command override (null = image default)."
  type        = list(string)
  default     = null
}

variable "entry_point" {
  description = "Container entry point override (null = image default)."
  type        = list(string)
  default     = null
}

variable "user" {
  description = "UID[:GID] the container runs as. null = image default (use only for the platform-check task)."
  type        = string
  default     = "1000:1000"
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 1024
}

variable "container_port" {
  description = "Port the app listens on (null for workers)."
  type        = number
  default     = null
}

variable "environment" {
  description = "Non-secret environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Env var name -> Secrets Manager / SSM parameter ARN injected at start (the execution role must be allowed to read it)."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Retention of /ecs/<name_prefix>/<service_name>."
  type        = number
  default     = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key for the log group."
  type        = string
}

# ------------------------------------------------------------------ Service
variable "create_service" {
  description = "false = task definition only (one-off tasks such as migrate)."
  type        = bool
  default     = true
}

variable "desired_count" {
  description = "Initial task count (afterwards owned by autoscaling and the pipeline)."
  type        = number
  default     = 1
}

variable "use_fargate_spot" {
  description = "Run on FARGATE_SPOT (cheaper, can be interrupted; dev only)."
  type        = bool
  default     = false
}

variable "target_group_arn" {
  description = "ALB target group (API only)."
  type        = string
  default     = null
}

variable "service_connect_namespace_arn" {
  description = "Service Connect namespace; null = off."
  type        = string
  default     = null
}

variable "service_connect_server" {
  description = "Publish the container port \"http\" in the Service Connect namespace so other services call http://<discovery_name>:<port>. null = client only."
  type = object({
    discovery_name = string
    port           = number
  })
  default = null
}

variable "enable_execute_command" {
  description = "Allow ECS Exec (break-glass shell, audited)."
  type        = bool
  default     = true
}

variable "exec_audit_log_group_arn" {
  description = "ECS Exec audit log group (ecs-cluster module)."
  type        = string
  default     = null
}

variable "exec_kms_key_arn" {
  description = "KMS key of ECS Exec sessions (ecs-cluster module exec_kms_key_arn)."
  type        = string
  default     = null
}

# ------------------------------------------------------------------ Autoscaling
variable "autoscaling" {
  description = <<-EOT
    null = no autoscaling.
    { type = "cpu", min, max, cpu_target = 60 }
    { type = "sqs", min, max, queue_name, scale_out_threshold = 1 }  - step scaling on queue backlog;
      scale-in to min only when the queue is empty and nothing is in flight.
  EOT
  type = object({
    type                = string
    min                 = number
    max                 = number
    cpu_target          = optional(number, 60)
    queue_name          = optional(string)
    scale_out_threshold = optional(number, 1)
  })
  default = null

  validation {
    condition     = var.autoscaling == null || try(contains(["cpu", "sqs"], var.autoscaling.type) && var.autoscaling.min <= var.autoscaling.max, false)
    error_message = "autoscaling.type must be cpu or sqs, and min <= max."
  }
}

# ------------------------------------------------------------------ Application Signals (optional)
variable "enable_application_signals" {
  description = "Add the CloudWatch agent sidecar and ADOT Python auto-instrumentation (Application Signals)."
  type        = bool
  default     = false
}

variable "cloudwatch_agent_image" {
  description = "CloudWatch agent image for the sidecar."
  type        = string
  default     = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:latest"
}

variable "adot_python_image" {
  description = "ADOT Python auto-instrumentation image (init container)."
  type        = string
  default     = "public.ecr.aws/aws-observability/adot-autoinstrumentation-python:v0.10.0"
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
