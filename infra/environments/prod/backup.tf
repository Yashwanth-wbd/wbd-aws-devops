# ================================================================== Step 10 - Backup and DR
locals {
  # RDS is selected through instance_tags in module "rds"; these buckets through their tags.
  backed_up_buckets = ["results", "approved-worm"]

  backup_retention = {
    dev     = { daily = 7, monthly = null }
    staging = { daily = 14, monthly = null }
    prod    = { daily = 35, monthly = 365 }
  }[var.environment]
}

module "backup" {
  source = "../../modules/backup"
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name_prefix = local.name_prefix

  daily_retention_days   = local.backup_retention.daily
  monthly_retention_days = local.backup_retention.monthly

  # dev: recovery points can be deleted so the stack can be torn down
  deny_manual_deletion = var.environment != "dev"

  # COMPLIANCE lock after 3 days - cannot be undone. prod only, and only once WBD approves.
  vault_lock = local.is_prod && var.enable_vault_lock ? {
    min_retention_days  = 7
    max_retention_days  = 400
    changeable_for_days = 3
  } : null

  enable_cross_region_copy = var.enable_cross_region_copy
  dr_retention_days        = local.backup_retention.daily

  permissions_boundary_arn = module.permission_boundary.policy_arn
  alert_topic_arn          = module.monitoring.alert_topic_arn
}
