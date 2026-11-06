# Runbook: security incident

WBD security leads every security incident; EY DevOps executes containment on request and
preserves evidence. **Call WBD security first** (contact in docs/01 – add actual value) for:
GuardDuty HIGH, suspected data exposure, leaked credentials, unknown IAM activity, defacement.

## 1. First 15 minutes

1. Open a SEV1 ticket; note the time (UTC) and what you saw. Do not discuss details in open channels.
2. Preserve evidence – do **not** delete resources, logs or images; do not reboot or stop a
   suspicious task until security agrees (stopping it loses memory and network state):
   ```bash
   aws ecs describe-tasks --cluster $P-ecs --tasks <arn> > task-<id>.json
   aws guardduty list-findings --detector-id "$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)" \
     --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}'
   ```
3. Contain (with security's go-ahead), smallest step first:

| Situation | Containment |
|---|---|
| Compromised ECS task | Isolate: replace its SGs with an empty SG or stop the task after capturing evidence; redeploy from a known-good image digest |
| Leaked app secret (Git, logs, ticket) | Rotate it now ([rotation.md](rotation.md)), then remove it from Git history. Okta ALB client secret: WBD Identity revokes it in Okta, new secret + apply ([rotation.md](rotation.md#okta-alb-client-secret)) |
| Compromised planner account | WBD Identity suspends the Okta user and clears its sessions; the `mmm-session` cookie ends at `session_hours` at the latest |
| Leaked / misused IAM role session | Revoke sessions on the role; check CloudTrail |
| Suspicious engineer access | WBD Identity disables the Okta user / removes the permission-set assignment |
| Data exposure via the app | GenAI: [genai.md](genai.md); WAF: block IP / pattern on the regional web ACL (`mmm-<env>-alb`, then PR) |
| Public bucket / object | Re-apply Block Public Access; CloudTrail for who changed it |

## 2. Investigate (with security)

- CloudTrail for the principal and time window; VPC flow logs; ALB and WAF logs (log bucket / Splunk);
  ECS Exec audit; RDS PostgreSQL logs (`/aws/rds/instance/mmm-<env_short>-postgres/postgresql` or
  `terraform output monitoring.splunk_log_groups`).
- Image provenance: release record (digest) and Trivy / Inspector for that digest.

## 3. Recover

Redeploy known-good versions through the pipeline; rotate every secret the attacker could reach;
restore data if it was changed ([db-restore.md](db-restore.md)); re-run security checks
(Checkov, Trivy, Security Hub).

## 4. After

Post-incident review within 5 business days. Notify WBD privacy / legal through WBD security if
personal data was involved.
