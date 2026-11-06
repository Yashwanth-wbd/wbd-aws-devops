# Runbook: secret and certificate rotation

Where each value lives: [docs/05](../05-secrets-and-config.md). Secret values never go into Git
or tfvars. Tasks read secrets **at start**, so every rotation ends with a new deployment of the
services that use the value.

## Schedule

| Value | Rotation | How |
|---|---|---|
| RDS admin password | automatic (RDS-managed secret) | nothing to do; `terraform output rds.master_user_secret_arn` |
| Okta ALB client secret (`mmm/<env>/okta/alb-client`) | when WBD Identity rotates it (at least yearly) | below – needs a `terraform apply` |
| App / migration DB users (`mmm/<env>/rds/proxy`, `rds/migrate`) | every 90 days | below |
| LLM provider keys (`mmm/<env>/llm/<provider>`) | when the issuer rotates (at least yearly) | below |
| Databricks OAuth client secret (model refresh) | when WBD rotates the service principal | EventBridge connection (below), not Secrets Manager |
| Splunk HEC token, third-party keys | when the issuer rotates them | below |
| ACM certificate (ALB) | automatic (DNS validation) | alarm `cert-expiry-alb` 30 days before expiry means renewal is failing |
| GitHub OIDC | no secret to rotate | – |
| Okta signing keys | rotated by Okta automatically | nothing to do (the ALB reads Okta's keys; the API checks the ALB's signature, not Okta's) |

Terraform does **not** generate Redis, CloudFront or other platform secrets – every container
is filled out of band once.

## Okta ALB client secret

The ALB listener holds the secret, so it changes only when Terraform applies.

1. WBD Identity adds a second client secret in the Okta app (Okta allows two active secrets), or
   agrees a short window.
2. Write it from a file, then delete the file:
   `aws secretsmanager put-secret-value --secret-id mmm/<env>/okta/alb-client --secret-string file://okta-client.json`
   (`{"client_secret":"<new>"}`).
3. Run the `terraform` workflow for that environment (dispatch, or any merge to `main` for dev);
   the plan shows an in-place update of the HTTPS listener and the `/api/*` rule.
4. Test sign-in in a private window, then WBD Identity deactivates the old secret.

## DB users

1. Generate a password in the DB (DBA / migrate task): `ALTER ROLE mmm_app PASSWORD '<new>'`.
2. `aws secretsmanager put-secret-value --secret-id mmm/<env>/rds/proxy --secret-string '{"username":"mmm_app","password":"<new>"}'`
   (RDS Proxy reads the secret; apps use IAM auth to the proxy and are not affected).
3. Test a connection through the proxy; repeat for `rds/migrate` / `mmm_migrator`.

## External tokens (Splunk, third-party, LLM)

1. The issuer creates the new token (keep the old one valid until step 3).
2. `aws secretsmanager put-secret-value --secret-id mmm/<env>/<name> --secret-string '<new>'` –
   type it in a terminal without history, never in a file or ticket. LLM keys use
   `{"api_key":"..."}`.
3. Force new deployment of `api` (and any other reader). Firehose reads Splunk on its own.
   Then the issuer revokes the old token.

## Databricks connection (model refresh)

The OAuth client secret is **not** in Secrets Manager. Update the EventBridge connection WBD owns:

```bash
# name from: terraform output -json data_platform | jq -r .databricks_connection
aws events update-connection --name mmm-dev-databricks --authorization-type OAUTH_CLIENT_CREDENTIALS \
  --auth-parameters 'OAuthParameters={ClientParameters={ClientID=<databricks_sp_client_id>,ClientSecret=<new>},AuthorizationEndpoint=<token-url>,HttpMethod=POST}'
```

No Terraform apply is required if only the secret changed (Terraform ignores the connection secret).

## Certificates

`cert-expiry-alb` alarm: ACM could not renew. Check the DNS validation CNAME still exists in the WBD
zone (`aws acm describe-certificate --certificate-arn <alb_certificate_arn>
--query 'Certificate.DomainValidationOptions'`) and ask WBD DNS to restore it. For an imported
certificate, import the new one into the same ARN (`aws acm import-certificate --certificate-arn <arn> ...`).
