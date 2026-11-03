# monitoring module - CloudWatch alarms, dashboards, SNS alerts and EventBridge security/deploy alerts.
# Implemented in Step 9. Planned resources:
#   - aws_sns_topic mmm-<env>-alerts (KMS) + subscriptions
#   - CloudWatch alarms (API 5xx, SQS age, DLQ, RDS, what-if latency, certificates, ECS rollback)
#   - CloudWatch dashboards (platform, API, queue, DB, pipelines, cost)
#   - EventBridge rules -> SNS (GuardDuty High, ECS deployment failure, break-glass login)
#   - CloudWatch Logs data protection policy
