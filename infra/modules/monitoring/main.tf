# monitoring module - CloudWatch alarms, dashboards, SNS alerts and EventBridge security/deploy alerts.
#   - aws_sns_topic mmm-<env>-alerts (KMS) + subscriptions
#   - CloudWatch alarms (UI/API health, API 5xx, availability, RDS CPU/storage/connections/latency,
#     what-if latency, optimization runtime, model refresh overdue, certificates)
#   - CloudWatch dashboards (platform, api-ui, rds, cost, optimization incl. run queue and optimizer tasks,
#     training incl. drift, data-pipeline (Glue jobs, Databricks export), genai)
#   - EventBridge rules -> SNS (GuardDuty High, ECS deployment failure, optimizer task not started,
#     Glue job failed, Glue Data Quality failed, break-glass login)
#   - CloudWatch Logs data protection policy
# State machine and Lambda alarms are created by the step-functions and lambda-function modules.
