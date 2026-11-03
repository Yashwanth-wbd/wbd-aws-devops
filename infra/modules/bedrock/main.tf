# bedrock module - Release 2 GenAI: Bedrock private endpoint, guardrails, invocation logging, alarms and budget.
# Implemented in Step 14. Planned resources:
#   - VPC interface endpoint bedrock-runtime (policy allows only approved models + guardrail)
#   - aws_bedrock_guardrail (prompt attack, PII, contextual grounding)
#   - Invocation logging to encrypted S3 + CloudWatch
#   - GenAI alarms, dashboard and AWS Budget
