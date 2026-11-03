# 04 – Planner login: Okta, MFA and step-up MFA

Planners log in to the web app with their WBD Okta account. The app keeps **no local
accounts**. Okta proves who the user is and which business unit and role they have; the API
checks every request; PostgreSQL row-level security stops one business unit from reading
another's data.

## 1. Flow (Authorization Code + PKCE)

```mermaid
sequenceDiagram
  participant B as Browser (React SPA)
  participant O as Okta authorization server
  participant CF as CloudFront + WAF
  participant API as mmm-api (ECS)
  participant DB as PostgreSQL (RLS)
  B->>O: /authorize (client_id, PKCE challenge, scope openid profile mmm.api)
  O->>B: login page: password + MFA
  O-->>B: authorization code
  B->>O: /token (code + PKCE verifier)
  O-->>B: ID token + access token (JWT with bu + role claims)
  B->>CF: GET /api/scenarios  Authorization: Bearer <access token>
  CF->>API: forwarded (+ X-Origin-Verify header)
  API->>O: fetch JWKS (cached) and verify signature, iss, aud, exp
  API->>API: authorize: role allows action? BU allowed?
  API->>DB: SET LOCAL app.current_bu = 'streaming'; SELECT ...
  DB-->>API: only rows for that BU
```

**PKCE** (Proof Key for Code Exchange) lets a browser app use the secure code flow without a
client secret. The SPA has **no client secret**, so nothing about Okta login needs to be
stored as a secret.

## 2. What WBD's Okta team creates (one app per environment)

| Setting | dev | staging | prod |
|---|---|---|---|
| App type | OIDC – Single-Page Application | same | same |
| Grant type | Authorization Code + PKCE (+ refresh token, rotating) | same | same |
| Sign-in redirect URI | `https://<dev-domain>/login/callback` | `https://<stg-domain>/login/callback` | `https://<prod-domain>/login/callback` |
| Sign-out redirect URI | `https://<dev-domain>/` | `https://<stg-domain>/` | `https://<prod-domain>/` |
| Trusted origin (CORS) | `https://<dev-domain>` | `https://<stg-domain>` | `https://<prod-domain>` |
| Authorization server | custom, e.g. `mmm` | same | same |
| Audience | `api://mmm-dev` | `api://mmm-stg` | `api://mmm-prd` |
| Access token lifetime | 60 min | 60 min | 60 min |
| Authentication policy | password + MFA always | same | same |

The audience must differ per environment. If all three apps share one authorization server and
one audience, a dev token is also valid in prod.

The exact values for an environment come from Terraform after Step 8:

```powershell
terraform output okta_app_settings     # redirect URIs and trusted origin, built from cloudfront_aliases
```

The domains are WBD DNS names (`cloudfront_aliases`). Route 53 stays out of scope for now: WBD
DNS creates the CNAMEs listed in `terraform output dns_records_for_wbd`.

### Groups and claims

Okta groups carry the business unit and the app role. The authorization server adds two
custom claims to the access token.

```text
# add actual value
mmm-bu-usnetworks   mmm-bu-streaming   mmm-bu-theatrical   mmm-bu-all
# add actual value
mmm-role-viewer     mmm-role-planner   mmm-role-approver   mmm-role-analyst   mmm-role-admin
```

| Claim | Okta expression (example) | Example value |
|---|---|---|
| `bu` | groups starting with `mmm-bu-`, prefix removed | `["streaming"]` |
| `mmm_roles` | groups starting with `mmm-role-`, prefix removed | `["planner"]` |
| `amr` | standard | `["pwd","mfa"]` |
| `auth_time` | standard | `1793712000` |

**Giving a planner access:** WBD adds the user to one `mmm-bu-*` group and one
`mmm-role-*` group in Okta. Nothing changes in AWS or in this repository.

## 3. MFA and step-up MFA

- **Normal login:** the Okta authentication policy for the app always requires MFA.
- **Step-up for sensitive actions** (approve a scenario, override a recommendation, change
  constraints in a shared scenario): the API checks that the token is recent.
  1. The API requires `auth_time` within the last 15 minutes and `mfa` in `amr`.
  2. If not, it returns `401` with
     `WWW-Authenticate: Bearer error="insufficient_user_authentication", max_age=900`.
  3. The SPA re-authenticates with `max_age=900` (and `acr_values` if WBD's Okta tier
     supports it), and Okta prompts for MFA again.
  4. The API retries with the new token, and the action is written to the audit log with
     the user, time and MFA evidence.

WBD's Okta team must confirm which `acr_values` their Okta tier supports.

## 4. Where the Okta settings are stored

None of these values are secrets. They live in **SSM Parameter Store** (Step 5) and are
read by the API at startup and by the frontend at build time:

| Parameter | Example | Read by |
|---|---|---|
| `/mmm/<env>/okta/issuer` | `https://wbd.okta.com/oauth2/aus0000000000000000` | API (token validation), frontend build |
| `/mmm/<env>/okta/client_id` | `0oa00000000000000000` | Frontend build |
| `/mmm/<env>/okta/audience` | `api://mmm-dev` | API |

If the backend ever calls the Okta management API (for example to list group members), that
API token is a real secret and goes in **Secrets Manager** as `mmm/<env>/okta/api-token`.

## 5. What the API must check on every request (for the backend team)

1. Signature against Okta JWKS (`<issuer>/v1/keys`, cached, refreshed on unknown `kid`).
2. `iss` = issuer parameter, `aud` = audience parameter, `exp` / `nbf` valid,
   algorithm `RS256` only.
3. Role allows the action (see [06-authorization-model.md](06-authorization-model.md)).
4. Requested business unit is in the `bu` claim (or `all`).
5. Open the database transaction with `SET LOCAL app.current_bu` so row-level security
   applies.
6. Step-up check for sensitive actions.

## 6. Infrastructure pieces that protect login (Step 8)

| Control | Where |
|---|---|
| Only CloudFront can reach the ALB | ALB security group allows only the CloudFront origin-facing prefix list, and the listener requires the `X-Origin-Verify` header |
| Rate limiting, OWASP rules, bad inputs, SQL injection, IP reputation | WAF on CloudFront (`mmm-<env>-cdn`) |
| HTTPS only, TLS 1.2+ | CloudFront viewer policy and ALB listener policy |
| Security headers (HSTS, CSP allowing the Okta domain, X-Frame-Options) | CloudFront response headers policy |
| Tokens never logged | WAF logs redact the `Authorization` and `Cookie` headers; CloudFront logs exclude cookies |

The default Content-Security-Policy allows the Okta origin (taken from `okta_issuer`) in
`connect-src`, `frame-src` (silent token renewal) and `form-action`. If the SPA uses another
Okta host, for example a custom Okta domain, set `content_security_policy` in the edge module.

## 7. Validation (Step 8)

Infrastructure (DevOps): see "Validate Step 8" in `infra/environments/dev/README.md`.

Application (once the app is deployed, Step 11), with the app and Okta teams:

- Login with Okta + MFA works in each environment.
- A request without a token, or with a token for another environment's audience, gets `401`.
- A `streaming` user cannot read `theatrical` scenarios (API returns nothing, RLS proves it).
- An override without recent MFA gets `401 insufficient_user_authentication`.
