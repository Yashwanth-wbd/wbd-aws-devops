# Runbook: secret and certificate rotation

Where each value lives: [docs/05](../05-secrets-and-config.md). Secret values never go into Git
or tfvars. Tasks read secrets **at start**, so every rotation ends with a new deployment of the
services that use the value.

## Schedule

| Value | Rotation | How |
|---|---|---|
| RDS admin password | automatic, 7 days (RDS-managed secret) | nothing to do; check `aws rds describe-db-instances --query 'DBInstances[0].MasterUserSecret'` |
| App / migration DB users (`mmm/<env>/rds/proxy`, `rds/migrate`) | every 90 days | below |
| Redis auth token, CloudFront origin-verify header | every 180 days, or on suspicion | below (`generated_secret_rotation_id`) |
| Databricks service-principal token, Splunk HEC token, third-party keys | when the issuer rotates them (at least yearly) | below |
| ACM certificates (ALB, CloudFront) | automatic (DNS validation) | alarm `cert-expiry-*` 30 days before expiry means renewal is failing |
| GitHub OIDC | no secret to rotate | – |
| Okta SPA client | public client (PKCE), no secret | – |

## Generated secrets (Redis token, origin-verify)

1. PR: change `generated_secret_rotation_id` in `infra/environments/<env>/terraform.tfvars`
   (e.g. `"initial"` → `"2026-11"`). Apply.
2. Terraform writes new random values; ElastiCache rotates the auth token (strategy `ROTATE`
   keeps the old one valid during the switch); CloudFront and the ALB rule get the new header.
3. Force new deployments so tasks read the new token:
   ```bash
   for s in api whatif-worker optimizer-worker; do aws ecs update-service --cluster $P-ecs --service $P-$s --force-new-deployment; done
   ```
4. Verify: no `NOAUTH` errors, smoke test passes through CloudFront, direct ALB access still 403.

## DB users

1. Generate a password in the DB (DBA / migrate task): `ALTER ROLE mmm_app PASSWORD '<new>'`.
2. `aws secretsmanager put-secret-value --secret-id mmm/<env>/rds/proxy --secret-string '{"username":"mmm_app","password":"<new>"}'`
   (RDS Proxy reads the secret; apps use IAM auth to the proxy and are not affected).
3. Test a connection through the proxy; repeat for `rds/migrate` / `mmm_migrator`.

## External tokens (Databricks, Splunk, third-party)

1. The issuer creates the new token (keep the old one valid until step 3).
2. `aws secretsmanager put-secret-value --secret-id mmm/<env>/<name> --secret-string '<new>'` –
   type it in a terminal without history, never in a file or ticket.
3. Force new deployments of the users (workers for Databricks; Firehose reads Splunk on its own;
   MWAA reads `airflow/connections/*` on the next task). Then the issuer revokes the old token.

## Certificates

`cert-expiry-alb` / `cert-expiry-cloudfront` alarm: ACM could not renew. Check the DNS
validation CNAME still exists in the WBD zone (`aws acm describe-certificate --certificate-arn <arn>
--query 'Certificate.DomainValidationOptions'`) and ask WBD DNS to restore it. For an imported
certificate, import the new one into the same ARN (`aws acm import-certificate --certificate-arn <arn> ...`).
