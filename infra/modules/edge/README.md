# edge

The front door of the app: CloudFront serves the React app from S3 and sends `/api/*` to the
ALB, with a WAF in front of both.

**Status:** implemented in Step 8. Route 53 records come later; for now WBD DNS creates CNAMEs.

## Request flow

```text
browser ──HTTPS (TLS 1.2+)──> CloudFront + WAF
                                ├── /api/*      ──HTTPS + X-Origin-Verify──> ALB ──> api tasks
                                └── everything  ──OAC (SigV4)──────────────> S3 frontend bucket
                                     else          /releases/<current_release>/...
```

## What it creates

| Resource | Name | Notes |
|---|---|---|
| WAF web ACL (us-east-1, CLOUDFRONT scope) | `<prefix>-cdn` | See "WAF rules" below. Default action: allow. |
| Log group (us-east-1) | `aws-waf-logs-<prefix>` | KMS-encrypted, 365 days. The `Authorization` and `Cookie` headers are redacted. Step 9 sends it on to Splunk. |
| KMS key (us-east-1, only if `create_waf_log_kms_key = true`) | `alias/<prefix>-waf-logs` | Needed when the stack is not in us-east-1, because a log group needs a key in its own region. |
| Origin access control | `<prefix>-frontend` | CloudFront signs S3 requests. The bucket stays private. |
| Key value store | `<prefix>-frontend` | Key `current_release` = folder served. Terraform sets it once (`initial_release`) and then ignores it. |
| CloudFront Function | `<prefix>-frontend-router` | Viewer request on the default behaviour. It rewrites `/x` to `/releases/<current_release>/x`, and app routes without a file extension get `index.html`. |
| Response headers policy | `<prefix>-security-headers` | HSTS 2 years with subdomains, CSP, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`. |
| Distribution | `<prefix>-cdn` | Aliases and ACM certificate, TLS 1.2 minimum (`TLSv1.2_2021`), HTTP/2 and HTTP/3, IPv6. Standard logs go to the log bucket under `cloudfront/`. |

## Behaviours

| Path | Origin | Caching | Sent to origin |
|---|---|---|---|
| `/api/*` | ALB (`alb_origin_domain_name`, HTTPS only, TLS 1.2) | **Off** (`Managed-CachingDisabled`) | All viewer headers except `Host` (`Managed-AllViewerExceptHostHeader`), which includes `Authorization`. Also the `X-Origin-Verify` custom header. |
| everything else | S3 frontend bucket | `Managed-CachingOptimized` | Nothing extra |

CloudFront connects to the ALB with `alb_origin_domain_name`. That name must be on the ALB
certificate and must be a CNAME to the ALB DNS name, otherwise CloudFront returns 502.

## Frontend releases without changing the distribution

`frontend-ci.yml` (Step 11) uploads a build to `s3://<frontend-bucket>/releases/<version>/`, then
changes the `current_release` key. Within seconds every edge serves the new folder:

```powershell
$kvs  = "<frontend_kvs_arn>"
$etag = aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $kvs --query ETag --output text
aws cloudfront-keyvaluestore put-key --kvs-arn $kvs --key current_release --value v1.4.0 --if-match $etag
```

**Rollback** is the same command with the previous version. Old releases stay in the bucket.
The cache key is the rewritten path (`/releases/<version>/...`), so a switch never serves files
from the old release. An invalidation is not needed, but it does no harm.

## WAF rules

| Priority | Rule | Action |
|---|---|---|
| 10 | `AWSManagedRulesAmazonIpReputationList` | block |
| 20 | `AWSManagedRulesCommonRuleSet` (OWASP top risks) | block. Rules in `waf_count_only_rules` (default `SizeRestrictions_BODY`, bodies over 8 KB) only count. |
| 30 | `AWSManagedRulesKnownBadInputsRuleSet` (includes Log4j) | block |
| 40 | `AWSManagedRulesSQLiRuleSet` | block |
| 50 | Rate limit per IP (`waf_rate_limit` per 5 min, default 2000) | block |

About 1,130 WCU, under the 1,500 included in the base price. To find a false positive, filter
the WAF log on `action = "BLOCK"` and read `terminatingRuleId`. Then add that rule to
`waf_count_only_rules` instead of turning the whole group off.

## Checkov skips (with reason)

| Check | Reason |
|---|---|
| `CKV_AWS_310` | Origin failover needs a second region; DR is Step 10. |
| `CKV_AWS_374` | Geo restriction is a WBD decision (`geo_allow_countries`). |
| `CKV_AWS_259` | HSTS has no `preload`: preload commits the whole WBD domain to browsers' preload lists, so the WBD domain owners decide. |
| `CKV_AWS_192`, `CKV2_AWS_47` | The Log4j rule group is included, but in a dynamic block Checkov cannot read. |

## Provider aliases

The calling stack passes `aws` (its own region) and `aws.us_east_1`. To validate the module on
its own, `scripts/validate-modules.ps1` uses a temporary copy with a stand-in provider block.

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | |
| `aliases` | – | App domain names (at least one). The first one is `app_url`. |
| `certificate_arn` | – | ACM certificate in **us-east-1** covering all aliases |
| `frontend_bucket_regional_domain_name` | – | `module.buckets["frontend"].bucket_regional_domain_name` |
| `alb_origin_domain_name` | – | Name on the ALB certificate, CNAME to the ALB |
| `origin_verify_value` | – | Sensitive. `module.secrets.generated_values["edge/origin-verify"]` |
| `okta_issuer` | – | Its host is allowed in the default CSP |
| `content_security_policy` | `null` | Override of the default CSP |
| `api_path_pattern` | `/api/*` | |
| `origin_read_timeout` | `60` | |
| `price_class` | `PriceClass_100` | |
| `geo_allow_countries` | `[]` | Empty means no restriction |
| `initial_release` | `seed` | |
| `access_log_bucket_domain_name`, `access_log_prefix` | –, `cloudfront` | |
| `waf_rate_limit` | `2000` | |
| `waf_count_only_rules` | `["SizeRestrictions_BODY"]` | |
| `waf_log_retention_days` | `365` | |
| `create_waf_log_kms_key` | `true` | Create a WAF log key in us-east-1. The calling stack passes `aws_region != "us-east-1"`. It is a plain bool, so `count` is known at plan time; testing the ARN for null would fail the first plan, because the ARN is unknown until apply |
| `waf_log_kms_key_arn` | `null` | Existing key in us-east-1, used when `create_waf_log_kms_key = false` |
| `tags` | `{}` | |

## Outputs

`distribution_id` (`CLOUDFRONT_DISTRIBUTION_ID`), `distribution_arn`, `distribution_domain_name`
(CNAME target), `hosted_zone_id` (for Route 53 later), `app_url` (`APP_URL`), `web_acl_arn`,
`waf_log_group_name`, `frontend_kvs_arn`, `frontend_function_name`.
