# Runbook: sign-in not working (Cognito / Okta)

Sign-in path: browser → ALB `authenticate-cognito` → Cognito hosted domain → WBD Okta (SAML) →
back to `https://<app>/oauth2/idpresponse` → session cookie `mmm-session`. Use this runbook when
users cannot sign in, loop between the app and the login page, or the smoke test login check fails.

## 1. Narrow it down

| Check | How | Means |
|---|---|---|
| App reachable | `curl -s -o /dev/null -w '%{http_code}' https://<app>/api/health` → 200 | ALB, WAF and API are fine; the problem is sign-in |
| Redirect to Cognito | `curl -sI https://<app>/` → 302 to `<prefix>.auth.<region>.amazoncognito.com` | ALB auth action works |
| Okta login page | Open the redirect in a browser | Cognito → Okta federation works |
| AWS / Okta status | AWS Health Dashboard (Cognito, region); WBD Okta status / IAM team | Provider outage |

## 2. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| Error page from Cognito after Okta login ("Invalid SAML response", "Invalid relayState") | Okta signing certificate rotated; Cognito still has the old metadata | Cognito reloads the metadata URL on update: re-run `terraform apply` for the environment, or WBD IAM checks the Okta app |
| `redirect_mismatch` | App host name changed; callback URL in the client is stale | Fix `app_domain_name` and apply |
| Users sign in but get 403 in the app | Missing or renamed Okta groups (`custom:groups`) | WBD IAM checks group assignment and the `groups` SAML attribute ([docs/06](../06-authorization.md)) |
| Login loop | Browser blocks the `mmm-session` cookie, or the clock on the client is far off | Clear cookies; test in a private window |
| 5xx from the ALB on `/oauth2/idpresponse` | ALB cannot reach the Cognito token endpoint (outbound from the ALB) | Check AWS Health; the ALB needs no SG egress change for Cognito |
| Everyone blocked by WAF | New WAF rule or rate limit | WAF sampled requests; adjust in `waf-regional` via PR |

## 3. During a provider outage

- There is no local user fallback (all users come from Okta). Communicate the outage to planners
  through the WBD app owner; nothing in the platform needs to change.
- Running optimizations and model refreshes continue; only new sign-ins fail.
- Existing sessions stay valid until the `mmm-session` cookie expires.

## 4. After

Record the time window and the cause in the ticket. If the Okta metadata or the app host changed,
make sure the change is in Git (`terraform.tfvars`) so the drift check stays clean.
