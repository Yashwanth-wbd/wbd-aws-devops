# ------------------------------------------------------------------ VPC and subnets
variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR from WBD Network; /19 or larger, must not overlap WBD networks."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 19
    error_message = "vpc_cidr must be a valid IPv4 CIDR of /19 or larger."
  }
}

variable "availability_zone_ids" {
  description = "AZ IDs (e.g. use1-az1) in subnet order: 2 in dev, 3 in staging/prod. IDs are the same physical zone in every account; names are not."
  type        = list(string)

  validation {
    condition     = length(var.availability_zone_ids) >= 2 && length(var.availability_zone_ids) <= 3
    error_message = "availability_zone_ids must contain 2 or 3 AZ IDs."
  }
}

# ------------------------------------------------------------------ Internet egress
variable "enable_nat_gateway" {
  description = "Create NAT gateways for private-app egress. Set false if WBD provides central egress through the Transit Gateway."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (dev) instead of one per AZ (staging/prod)."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ VPC endpoints
variable "interface_endpoints" {
  description = "Interface endpoint service suffixes (com.amazonaws.<region>.<suffix>) placed in the private-endpoint subnets."
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "secretsmanager",
    "ssm",
    "ssmmessages",
    "kms",
    "logs",
    "monitoring",
    "xray",
    "states",
    "sagemaker.api",
    "sqs",
  ]
}

variable "additional_interface_endpoints" {
  description = "Extra interface endpoint suffixes added to interface_endpoints (data platform adds glue; Release 2 adds execute-api and bedrock-runtime for the LLM gateway)."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------ Security groups
variable "app_port" {
  description = "Container port of the API service (ALB -> API)."
  type        = number
  default     = 8080
}

variable "ui_port" {
  description = "Container port of the UI service (ALB -> UI)."
  type        = number
  default     = 8080
}

variable "alb_ingress_cidrs" {
  description = "Source ranges allowed to reach the public ALB (0.0.0.0/0 = internet, filtered by the WAF; or the WBD egress ranges)."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.alb_ingress_cidrs) > 0 && alltrue([for c in var.alb_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "alb_ingress_cidrs must be a non-empty list of IPv4 CIDRs."
  }
}

variable "create_genai_security_group" {
  description = "Create the LLM gateway proxy security group: no inbound, HTTPS out (Release 2)."
  type        = bool
  default     = false
}

variable "create_data_platform_security_groups" {
  description = "Create the glue (self-referencing, for Glue jobs in the VPC) and databricks_export (HTTPS out) security groups (data platform)."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ Flow logs
variable "flow_logs_retention_days" {
  description = "Retention of the VPC flow log group."
  type        = number
  default     = 365
}

variable "logs_kms_key_arn" {
  description = "KMS key ARN for the flow log group (kms module, purpose logs)."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary attached to the flow-logs IAM role."
  type        = string
}

# ------------------------------------------------------------------ WBD hub connectivity (optional)
variable "enable_transit_gateway" {
  description = "Attach the VPC to the WBD Transit Gateway."
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "WBD Transit Gateway ID (shared to this account through AWS RAM)."
  type        = string
  default     = null
}

variable "transit_gateway_routes" {
  description = "Destination CIDRs routed from the private-app subnets to the Transit Gateway (use 0.0.0.0/0 only when enable_nat_gateway = false)."
  type        = list(string)
  default     = []
}

variable "enable_resolver_forwarding" {
  description = "Create a Route 53 Resolver outbound endpoint and FORWARD rules for WBD-internal domains."
  type        = bool
  default     = false
}

variable "resolver_forward_domains" {
  description = "WBD-internal domains forwarded to the WBD DNS servers, e.g. [\"wbd.internal\"]."
  type        = list(string)
  default     = []
}

variable "resolver_target_ips" {
  description = "WBD DNS server IPs that receive the forwarded queries."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.resolver_target_ips : can(cidrhost("${ip}/32", 0))])
    error_message = "resolver_target_ips must be IPv4 addresses."
  }
}

variable "tags" {
  description = "Extra tags for all network resources."
  type        = map(string)
  default     = {}
}
