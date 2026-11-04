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
| Compromised ECS task | Isolate: replace its SGs with an empty SG (`aws ecs update-service --network-configuration` with a deny-all SG) or stop the task after capturing evidence; redeploy from a known-good image digest |
| Leaked app secret (Git, logs, ticket) | Rotate it now ([rotation.md](rotation.md)), then remove it from Git history (the secret is burned either way) |
| Leaked / misused IAM role session | Revoke sessions: IAM → role → *Revoke active sessions* (adds a deny for tokens issued before now); check CloudTrail for what it did |
| Suspicious engineer access | WBD Identity disables the Okta user / removes the permission-set assignment |
| Data exposure via the app | Flag off the feature (GenAI: [genai.md](genai.md)); WAF: block the IP / pattern (`aws wafv2` rule in `mmm-<env>-cdn`, then the PR) |
| Public bucket / object | Every project bucket has Block Public Access on (Terraform); re-apply it (`aws s3api put-public-access-block`), then find who changed it (CloudTrail) and let the next apply / drift check confirm |

## 2. Investigate (with security)

- CloudTrail (org trail) for the principal and time window; VPC flow logs (`/aws/vpc/...`, shipped
  to Splunk on request); ALB / WAF logs (log bucket, Splunk); ECS Exec audit log; pgaudit logs
  (`/aws/rds/instance/mmm-<env>-pg/postgresql`).
- Image provenance: release record (digest) and Trivy / Inspector findings for that digest.

## 3. Recover

Redeploy known-good versions through the pipeline; rotate every secret the attacker could reach;
restore data if it was changed ([db-restore.md](db-restore.md)); re-run the security checks
(Checkov, Trivy, Security Hub score).

## 4. After

Post-incident review within 5 business days: timeline, root cause, what alerted us, actions
(owner + date). Notify WBD privacy / legal through WBD security if personal data was involved.
