# ================================================================== Step 7c - Optimization run queue
# API -> SQS run queue -> dispatcher Lambda -> optimization state machine, at most
# max_concurrent_runs at the same time (SSM optimization/max_concurrent_runs). Requests that wait
# longer than max_queue_wait_minutes are dropped and alarmed; failures end in the DLQ.
module "run_queue" {
  source = "../../modules/run-queue"

  name_prefix             = local.name_prefix
  state_machine_arn       = module.optimization_sfn.state_machine_arn
  state_machine_name      = module.optimization_sfn.state_machine_name
  max_runs_parameter_name = "/mmm/${local.env_short}/optimization/max_concurrent_runs"
  max_runs_parameter_arn  = module.secrets.parameter_arns["optimization/max_concurrent_runs"]
  max_queue_wait_minutes  = var.max_queue_wait_minutes

  sqs_kms_key_arn  = module.kms.key_arns["sqs"]
  env_kms_key_arn  = module.kms.key_arns["secrets"]
  logs_kms_key_arn = module.kms.key_arns["logs"]

  log_retention_days       = var.log_retention_days
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_id        = module.network.security_group_ids["lambda"]
  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}
