# log-bucket

The bucket that receives AWS service logs: ALB access logs, CloudFront standard logs and S3
server access logs. VPC flow logs and application logs go to CloudWatch, not here.

**Status:** implemented in Step 6.

## Why it differs from the data buckets

| Setting | Log bucket | Data buckets (`s3-bucket` module) | Reason |
|---|---|---|---|
| Encryption | **SSE-S3** (AES-256) | SSE-KMS | ALB access logs can only be written to SSE-S3 buckets |
| Object ownership | **BucketOwnerPreferred** (ACLs on) | BucketOwnerEnforced (ACLs off) | CloudFront standard logging writes with an ACL grant |
| Bucket policy | log-delivery grants + TLS-only | TLS-only + KMS-only uploads | Log delivery services need write access |

Everything else is the same: public access block, versioning, TLS 1.2+ only, and lifecycle expiry.

## Layout

| Prefix | Written by | Granted to |
|---|---|---|
| `alb/AWSLogs/<account>/` | ALB (Step 7) | The regional ELB account (`aws_elb_service_account`) and `logdelivery.elasticloadbalancing.amazonaws.com` |
| `cloudfront/` | CloudFront (Step 8) | ACL grant that CloudFront adds when logging is turned on |
| `s3-access/<bucket>/` | S3 server access logging of every data bucket | `logging.s3.amazonaws.com`, only from this account |

Objects expire after `retention_days` (dev 90). Splunk keeps the long-term copy (Step 9).

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `bucket_name` | string | – | e.g. `wbd-mmm-dev-logs-use1` |
| `retention_days` | number | `365` | |
| `noncurrent_version_days` | number | `30` | |
| `tags` | map(string) | `{}` | |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_domain_name` (CloudFront needs this form), `prefixes`.
