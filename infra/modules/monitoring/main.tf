# monitoring module - CloudWatch alarms, dashboards, SNS alerts and EventBridge security/deploy alerts.
#   - aws_sns_topic mmm-<env>-alerts (KMS) + subscriptions
#   - CloudWatch alarms (UI/API health, API 5xx, Aurora CPU/ACU, what-if latency, certificates)
#   - CloudWatch dashboard (ALB, ECS, Aurora, Step Functions, Lambda, regional WAF)
#   - EventBridge rules -> SNS (GuardDuty High, ECS deployment failure, break-glass login)
#   - CloudWatch Logs data protection policy
# State machine and Lambda alarms are created by the step-functions and lambda-function modules.
