# Runbook: break-glass access (prod)

Break-glass is the `BreakGlass` IAM Identity Center permission set on the prod account, assigned
to a small named Okta group (docs/02 §6). Using it raises the `mmm-prd-breakglass-used` alert
(EventBridge rule, Step 15) to `mmm-prd-alerts`.

## Allowed only when

- SEV1 in prod, **and**
- the normal path does not work in time: the pipeline (GitHub Actions / OIDC) is down or too slow,
  or `mmm-prd-devops` lacks the permission needed, **and**
- an incident ticket exists and the EY lead or WBD app owner agreed (note who, in the ticket).

## Steps

1. Note the ticket number and the planned change before logging in.
2. Log in through the Okta tile (console), or the CLI with a profile like `mmm-prd-devops` but
   `sso_role_name = BreakGlass` (members of `aws-mmm-prd-breakglass` add it once:
   `[profile mmm-prd-breakglass]`). The alert fires – reply to it with the ticket number.
3. Make the smallest change that mitigates (e.g. [rollback.md](rollback.md) manual app rollback,
   scale a service, revoke sessions). Keep a command log:
   ```bash
   export AWS_PROFILE=mmm-prd-breakglass
   aws sts get-caller-identity | tee -a breakglass-<ticket>.log
   ```
4. Log out (`aws sso logout`) as soon as the system is stable. Do not keep the session open.

## Within one business day

- Reproduce the change in code (PR) so Terraform / the pipeline match prod; the nightly drift
  check must be green again.
- Attach the command log and the CloudTrail events
  (`aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=<session name>`) to the ticket.
- Security reviews the use; repeated use for the same reason → fix the normal path (permissions,
  pipeline).

## Test (quarterly, with the access review)

Log in with break-glass in a planned window, make no change, confirm the alert reached on-call
and security, record it in the access-review evidence.
