# 04 – Planner login: Okta SAML, Cognito, ALB and MFA

Planners open the app in a browser at `https://<app_domain_name>`. There are **no local
accounts**. WBD Okta (with MFA) is the identity source; **Amazon Cognito** federates to Okta
over SAML; the **Application Load Balancer** signs users in with `authenticate-cognito` and
passes identity to the **API** on `/api/*`. PostgreSQL row-level security still isolates
business units ([06-authorization-model.md](06-authorization-model.md)).

## 1. Flow

```mermaid
sequenceDiagram
  participant B as Browser
  participant W as Regional WAF + ALB
  participant C as Cognito hosted UI
  participant O as WBD Okta (SAML IdP)
  participant UI as mmm-ui (ECS)
  participant API as mmm-api (ECS)
  participant DB as Aurora (RLS)
  B->>W: GET / (no session cookie)
  W->>C: authenticate-cognito redirect
  C->>O: SAML authn request
  O->>B: password + MFA
  O-->>C: SAML assertion (groups attribute)
  C-->>B: Set-Cookie mmm-session; redirect to app
  B->>W: GET / (with mmm-session)
  W->>UI: forward (authenticated)
  B->>W: GET /api/scenarios (with mmm-session)
  W->>API: forward + x-amzn-oidc-data JWT
  API->>API: verify JWT signer = ALB_ARN; map groups → BU + role
  API->>DB: SET LOCAL app.current_bu; SELECT ...
```

| Path | ALB behaviour |
|---|---|
| `/*` (default) | `authenticate-cognito` with redirect to sign-in if unauthenticated → **ui** target group |
| `/api/health` | No sign-in (priority 10) → **api** (smoke test, health checks) |
| `/api/*` | `authenticate-cognito` with **deny** if unauthenticated (401, no redirect) → **api** |

Session cookie name: **`mmm-session`**. Lifetime: `session_hours` from tfvars (default 12 h),
converted to seconds on the listener.

## 2. What WBD enters in Okta (one SAML app per environment)

After Terraform apply for that environment, run:

```powershell
terraform output okta_app_settings
terraform output front_door
```

Use `okta_app_settings` when configuring the Okta **SAML 2.0** application:

| Okta field | Value (from Terraform) |
|---|---|
| Single sign-on URL (ACS) | `single_sign_on_url` → `https://<cognito-domain>.auth.<region>.amazoncognito.com/saml2/idpresponse` |
| Audience URI (SP Entity ID) | `audience_uri` → `urn:amazon:cognito:sp:<user-pool-id>` |
| Name ID format | `Persistent` (`name_id_format`) |
| Attribute statements | Release `email` and `name` (names in `attributes`) |
| Group attribute | SAML attribute **`groups`** (must match `group_attribute` in output; default name `groups`) |

Assign users through Okta groups. On each sign-in, Cognito maps the SAML **`groups`**
attribute to **`custom:groups`** on the user profile (`infra/modules/cognito/main.tf`).

Recommended group naming (WBD to confirm):

```text
# add actual value
mmm-bu-usnetworks   mmm-bu-streaming   mmm-bu-theatrical   mmm-bu-all
# add actual value
mmm-role-viewer     mmm-role-planner   mmm-role-approver   mmm-role-analyst   mmm-role-admin
```

The API (application team) maps `custom:groups` to business unit and role claims—same
semantics as in [06-authorization-model.md](06-authorization-model.md). **Giving a planner
access:** add them to one `mmm-bu-*` and one `mmm-role-*` group in Okta. Nothing changes in
AWS or in this repository.

Also provide the **SAML metadata URL** for that app to EY so it can be set in tfvars:

```hcl
okta_saml_metadata_url = "https://wbd.okta.com/app/exk…/sso/saml/metadata"  # add actual value
```

## 3. MFA

MFA is **enforced in Okta** (authentication policy on the SAML app / federation policy).
Cognito MFA is off (`mfa_configuration = OFF`); users never get a Cognito-local password.

For sensitive actions (approve a scenario, override a recommendation), the API may require
evidence of a recent authentication. That logic reads claims inside **`x-amzn-oidc-data`**
(not a browser-held Okta access token). The backend team defines the exact rules; Okta must
still require MFA at login.

## 4. Sign-out

Terraform output `front_door.logout_url` (same as `module.cognito.logout_url`) is the URL the
UI should redirect to after clearing the ALB session cookie. It targets the Cognito hosted
domain logout endpoint with `client_id` and `logout_uri=https://<app_domain_name>/`.

## 5. How the API reads the signed-in user

For every authenticated request to `/api/*`, the ALB adds:

| Header | Purpose |
|---|---|
| `x-amzn-oidc-data` | JWT with user claims (including `custom:groups`) |
| `x-amzn-oidc-identity` | Opaque subject identifier |

The API task receives **`ALB_ARN`** in its environment (the load balancer ARN). It must:

1. Fetch the ALB public key for the region (documented by AWS for `x-amzn-oidc-data`).
2. Verify the JWT signature and expiry.
3. Confirm the JWT **`signer`** claim equals **`ALB_ARN`** (prevents token replay from another ALB).
4. Map `custom:groups` to BU and role; enforce authorization and RLS.

Unauthenticated calls to `/api/*` never reach the task: the ALB returns **401**.

## 6. Non-secret settings (SSM)

Cognito identifiers are **not secrets**. Terraform writes them to Parameter Store (Step 5):

| Parameter | Example | Read by |
|---|---|---|
| `/mmm/<env>/cognito/user_pool_id` | `us-east-1_abc123` | API (optional diagnostics) |
| `/mmm/<env>/cognito/client_id` | ALB app client ID | API |
| `/mmm/<env>/cognito/domain` | `wbd-mmm-dev` | API / UI (logout URL construction) |

There are **no** `/mmm/<env>/okta/*` parameters in v2.

## 7. Infrastructure controls (Step 8)

| Control | Where |
|---|---|
| TLS 1.2+ on the public listener | ALB HTTPS listener policy |
| Ingress restriction | ALB security group: 443/80 from `alb_ingress_cidrs` |
| WAF (IP reputation, OWASP, rate limit, optional geo allow list) | Regional WAF on the ALB (`waf-regional` module) |
| HTTP → HTTPS | ALB port 80 redirect |
| Access logs | ALB → S3 log bucket prefix `alb/` |

## 8. Testing

**Infrastructure (DevOps), after Step 8 apply:**

1. `terraform output dns_records_for_wbd` — if `route53_zone_id` is null, ask WBD DNS to create the CNAME to `front_door.alb_dns_name`.
2. Until DNS exists, use `https://<alb_dns_name>/api/health` — expect **200**.
3. `curl -I https://<app-url>/` without cookies — expect **302** toward Cognito / Okta (same check as `scripts/smoke.sh`).
4. `curl -I https://<app-url>/api/scenarios` without cookies — expect **401** (not a redirect).

**With Okta configured:**

1. Browser login with MFA reaches the UI.
2. Authenticated API calls succeed; `/api/health` stays open without a session.
3. A user in `mmm-bu-streaming` cannot read another BU's data (API + RLS).

See also "Validate Step 8" in `infra/environments/dev/README.md` and post-deploy
`scripts/smoke.sh` in [09-cicd-pipelines.md](09-cicd-pipelines.md).
