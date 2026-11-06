# Runbook: sign-in not working (Okta OIDC at the ALB)

Sign-in path: browser → ALB `authenticate-oidc` → WBD Okta `/v1/authorize` (password + MFA) →
back to `https://<app>/oauth2/idpresponse` → the ALB calls Okta `/v1/token` and `/v1/userinfo`
with the client secret from `mmm/<env>/okta/alb-client` → session cookie `mmm-session`. Use this
runbook when users cannot sign in, loop between the app and the login page, or the smoke test
login check fails.

## 1. Narrow it down

| Check | How | Means |
|---|---|---|
| App reachable | `curl -s -o /dev/null -w '%{http_code}' https://<app>/api/health` → 200 | ALB, WAF and API are fine; the problem is sign-in |
| Sign-in switched on | `curl -sI https://<app>/` → **503** "MMM sign-in is not configured yet." | `okta_sign_in_enabled = false` in that environment ([docs/04 §2](../04-okta-mfa-app-login.md#2-what-wbd-enters-in-okta-one-oidc-app-per-environment)) |
| Redirect to Okta | `curl -sI https://<app>/` → 302 to `https://<okta>/oauth2/<server>/v1/authorize?client_id=<okta_client_id>&redirect_uri=https://<app>/oauth2/idpresponse...` | ALB auth action works; compare `client_id` with `terraform output front_door` |
| Okta login page | Open the redirect in a browser | Okta app exists and accepts the client and redirect URI |
| AWS / Okta status | AWS Health Dashboard (Elastic Load Balancing, region); WBD Okta status / Identity team | Provider outage |

## 2. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| Okta error page "The 'redirect_uri' parameter must be a Login redirect URI" | App host name changed, or the Okta app lacks `https://<app>/oauth2/idpresponse` | WBD Identity adds the URI from `terraform output okta_app_settings`; or fix `app_domain_name` and apply |
| Okta error "Invalid client" / `invalid_client` | Wrong `okta_client_id`, or the app was re-created in Okta | Correct `okta_client_id` in tfvars → PR → apply |
| ALB **401** / 5xx on `/oauth2/idpresponse` after the Okta login | Client secret in `okta/alb-client` wrong or rotated in Okta; the ALB fails the token call | Put the new secret (`put-secret-value`, [rotation.md](rotation.md)) and **apply** the stack—the listener only picks up the secret on apply |
| ALB 5xx on `/oauth2/idpresponse`, secret correct | ALB cannot reach Okta (egress 443 from the `alb` security group, or Okta outage) | Check the `alb_https_out` rule and AWS / Okta status |
| Users sign in but get 403 in the app | Missing or renamed Okta groups, or the `groups` claim is not in user info | WBD Identity checks group assignment and the claim filter "Starts with `mmm-`" ([docs/06](../06-authorization-model.md)) |
| Login loop | Browser blocks the `mmm-session` cookie, or the client clock is far off | Clear cookies; test in a private window |
| Sign-out does not end the Okta session | Okta rejects `client_id` on `/v1/logout` | WBD Identity confirms the logout settings (docs/01 open point) |
| Everyone blocked by WAF | New WAF rule or rate limit | WAF sampled requests; adjust in `waf-regional` via PR |

## 3. During a provider outage

- There is no local user fallback (all users come from Okta). Communicate the outage to planners
  through the WBD app owner; nothing in the platform needs to change.
- Running optimizations, queued runs and model refreshes continue; only new sign-ins fail.
- Existing sessions stay valid until the `mmm-session` cookie expires (`session_hours`).

## 4. After

Record the time window and the cause in the ticket. If the issuer, client ID or app host changed,
make sure the change is in Git (`terraform.tfvars`) so the drift check stays clean.
