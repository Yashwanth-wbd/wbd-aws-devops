# monitoring module - CloudWatch alarms, dashboards, SNS alerts and EventBridge security/deploy alerts.
#   - aws_sns_topic mmm-<env>-alerts (KMS) + subscriptions
#   - CloudWatch alarms (UI/API health, API 5xx, availability, Aurora CPU/ACU/connections/storage/lag,
#     what-if latency, optimization runtime, model refresh overdue, certificates)
#   - CloudWatch dashboards (platform, api-ui, aurora, cost, optimization, training, genai)
#   - EventBridge rules -> SNS (GuardDuty High, ECS deployment failure, break-glass login)
#   - CloudWatch Logs data protection policy
# State machine and Lambda alarms are created by the step-functions and lambda-function modules.
