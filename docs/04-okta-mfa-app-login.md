# 04 – Planner login: Okta OIDC at the ALB, and MFA

Planners open the app in a browser at `https://<app_domain_name>`. There are **no local
accounts**. WBD Okta (with MFA) is the identity source. The **Application Load Balancer** signs
users in directly against Okta with `authenticate-oidc` (OIDC authorization code flow) and passes
identity to the **UI** and the **API**. There is no Cognito user pool in v3. PostgreSQL row-level
security still isolates business units ([06-authorization-model.md](06-authorization-model.md)).

## 1. Flow

```mermaid
sequenceDiagram
  participant B as Browser
  participant W as Regional WAF + ALB
  participant O as WBD Okta (OIDC authorization server)
  participant UI as mmm-ui (ECS)
  participant API as mmm-api (ECS)
  participant DB as RDS PostgreSQL (RLS)
  B->>W: GET / (no session cookie)
  W-->>B: 302 to Okta /v1/authorize (client_id, redirect_uri = /oauth2/idpresponse)
  B->>O: sign in: password + MFA
  O-->>B: 302 to https://<app>/oauth2/idpresponse?code=...
  B->>W: GET /oauth2/idpresponse?code=...
  W->>O: /v1/token (client secret) + /v1/userinfo (groups claim)
  W-->>B: Set-Cookie mmm-session; redirect to original URL
  B->>W: GET / (with mmm-session)
  W->>UI: forward (authenticated)
  B->>W: GET /api/scenarios (with mmm-session)
  W->>API: forward + x-amzn-oidc-data JWT (signed by the ALB)
  API->>API: verify JWT signer = ALB_ARN; map groups → BU + role
  API->>DB: SET LOCAL app.current_bu; SELECT ...
```

| Path | ALB behaviour |
|---|---|
| `/*` (default) | `authenticate-oidc`, redirect to Okta if unauthenticated → **ui** target group |
| `/api/health` | No sign-in (priority 10) → **api** (smoke test, health checks) |
| `/api/*` | `authenticate-oidc` with **deny** if unauthenticated (401, no redirect) → **api** |

Session cookie name: **`mmm-session`**. Lifetime: `session_hours` from tfvars (default 12 h),
converted to seconds on the listener. The ALB calls Okta's token and user info endpoints over
the internet (the `alb` security group allows 443 out).

**Before sign-in is switched on** (`okta_sign_in_enabled = false`, the default for the first
apply): every path except `/api/health` returns **503** "MMM sign-in is not configured yet."
The app is never reachable without sign-in.

## 2. What WBD enters in Okta (one OIDC app per environment)

After Terraform apply for that environment, run:

```powershell
terraform output okta_app_settings
terraform output front_door
```

Use `okta_app_settings` when creating the Okta **OIDC – Web Application**:

| Okta field | Value (from Terraform) |
|---|---|
| Grant type | Authorization Code (`grant_types`) |
| Sign-in redirect URI | `sign_in_redirect_uris` → `https://<app_domain_name>/oauth2/idpresponse` |
| Sign-out redirect URI | `sign_out_redirect_uris` → `https://<app_domain_name>/` |
| Initiate login URI | `initiate_login_uri` → `https://<app_domain_name>/` |
| Scopes | `openid profile email groups` |
| Groups claim | Name **`groups`**, filter "Starts with `mmm-`", in the ID token and user info (`groups_claim`) |
| Client authentication | Client secret |

WBD Identity then gives EY the **client ID** and the **issuer** of the authorization server
(org server `https://<org>.okta.com` or a custom one `https://<org>.okta.com/oauth2/<id>`), and
puts the **client secret** into Secrets Manager (or hands it over through a secure channel):

```hcl
# terraform.tfvars
# add actual value
okta_issuer    = "https://wbd.okta.com/oauth2/default"
# add actual value
okta_client_id = "0oa00000000000000000"
```

```powershell
# okta-client.json = {"client_secret": "..."}   (never in Git)
aws secretsmanager put-secret-value --secret-id mmm/dev/okta/alb-client --secret-string file://okta-client.json
Remove-Item okta-client.json
```

Then set `okta_sign_in_enabled = true` in that environment's tfvars, plan and apply (PR), and
re-run `scripts/setup-github.ps1` so `SMOKE_CHECK_LOGIN` becomes `true`. Terraform reads the
secret only to configure the listener; the value is then in the KMS-encrypted state too.

Recommended group naming (WBD to confirm):

```text
# add actual value
mmm-bu-usnetworks   mmm-bu-streaming   mmm-bu-theatrical   mmm-bu-all
# add actual value
mmm-role-viewer     mmm-role-planner   mmm-role-approver   mmm-role-analyst   mmm-role-admin
```

The API (application team) maps the `groups` claim to business unit and role—same semantics as in
[06-authorization-model.md](06-authorization-model.md). **Giving a planner access:** add them
to one `mmm-bu-*` and one `mmm-role-*` group in Okta and assign the group to the app. Nothing
changes in AWS or in this repository.

## 3. MFA

MFA is **enforced in Okta** (authentication policy on the OIDC app). There is no AWS-side
password or MFA for planners.

For sensitive actions (approve a scenario, override a recommendation), the API may require
evidence of a recent authentication. That logic reads claims inside **`x-amzn-oidc-data`**
(not a browser-held Okta token). The backend team defines the exact rules; Okta must still
require MFA at login.

## 4. Sign-out

Terraform output `front_door.logout_url` (also the UI environment variable `LOGOUT_URL`) is the
URL the UI redirects to after expiring the `mmm-session` cookie:
`<okta base>/v1/logout?client_id=<okta_client_id>&post_logout_redirect_uri=https://<app_domain_name>/`.
The ALB does not give the app the ID token, so the URL uses `client_id` instead of
`id_token_hint`. **WBD Identity to confirm** that their Okta org accepts this (tracked in docs/01).

## 5. How the API reads the signed-in user

For every authenticated request, the ALB adds:

| Header | Purpose |
|---|---|
| `x-amzn-oidc-data` | JWT signed by the ALB with the user info claims (including `groups`) |
| `x-amzn-oidc-identity` | Subject (`sub`) from Okta |
| `x-amzn-oidc-accesstoken` | Okta access token (the API does not need it) |

The API task receives **`ALB_ARN`** and **`OKTA_ISSUER`** in its environment. It must:

1. Fetch the ALB public key for the region (documented by AWS for `x-amzn-oidc-data`).
2. Verify the JWT signature and expiry.
3. Confirm the JWT **`signer`** claim equals **`ALB_ARN`** and **`iss`** equals `OKTA_ISSUER`
   (prevents token replay from another ALB or IdP).
4. Map `groups` to BU and role; enforce authorization and RLS.

Unauthenticated calls to `/api/*` never reach the task: the ALB returns **401**.

## 6. Settings

| Value | Where | Secret? |
|---|---|---|
| Issuer | tfvars `okta_issuer`, SSM `/mmm/<env>/okta/issuer`, API env `OKTA_ISSUER` | no |
| Client ID | tfvars `okta_client_id` (ALB listener) | no |
| Client secret | Secrets Manager `mmm/<env>/okta/alb-client` → ALB listener | **yes** – never in Git or tfvars |
| Logout URL | UI env `LOGOUT_URL` | no |

## 7. Infrastructure controls (Step 8)

| Control | Where |
|---|---|
| TLS 1.2+ on the public listener | ALB HTTPS listener policy |
| Ingress restriction | ALB security group: 443/80 from `alb_ingress_cidrs` |
| WAF (IP reputation, OWASP, rate limit, optional geo allow list) | Regional WAF on the ALB (`waf-regional` module) |
| HTTP → HTTPS | ALB port 80 redirect |
| No access without sign-in | Listener answers 503 until `okta_sign_in_enabled = true` |
| Access logs | ALB → S3 log bucket prefix `alb/` |

## 8. Testing

**Infrastructure (DevOps), after Step 8 apply:**

1. `terraform output dns_records_for_wbd` — if `route53_zone_id` is null, ask WBD DNS to create the CNAME to `front_door.alb_dns_name`.
2. Until DNS exists, use `https://<alb_dns_name>/api/health` — expect **200**.
3. Before sign-in is on: `curl -I https://<app-url>/` — expect **503**.
4. After sign-in is on: `curl -I https://<app-url>/` without cookies — expect **302** to
   `https://<okta>/oauth2/<server>/v1/authorize?...` (same check as `scripts/smoke.sh`).
5. `curl -I https://<app-url>/api/scenarios` without cookies — expect **401** (not a redirect).

**With Okta configured:**

1. Browser login with MFA reaches the UI.
2. Authenticated API calls succeed; `/api/health` stays open without a session.
3. A user in `mmm-bu-streaming` cannot read another BU's data (API + RLS).
4. Sign-out ends the Okta session and returns to the app, which asks to sign in again.

See also "Validate Step 8" in `infra/environments/dev/README.md` and post-deploy
`scripts/smoke.sh` in [09-cicd-pipelines.md](09-cicd-pipelines.md).
