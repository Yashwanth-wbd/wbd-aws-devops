# elasticache

The ElastiCache replication group `mmm-<env>-redis`: the what-if cache and job status store.

**Status:** implemented in Step 6.

## Settings

| Setting | Value |
|---|---|
| Engine | **Valkey 8.0** by default (Redis-compatible, about 20 % cheaper). Set `engine = "redis"` and `engine_version = "7.1"` if WBD requires Redis OSS. |
| Topology | dev: 1 node. staging/prod: primary + replica in different AZs with automatic failover and Multi-AZ. |
| In transit | TLS **required** (`transit_encryption_mode = "required"`) |
| Auth | Auth token = the Terraform-generated `mmm/<env>/redis/token` secret. Rotation uses `ROTATE`, so the old and new tokens both work during the switch. |
| At rest | KMS encrypted (the `rds` key, shared by the data stores), including snapshots |
| Snapshots | Daily 03:00–04:00 UTC; kept 1 day in dev and staging, 7 days in prod |
| Logs | Slow log and engine log as JSON to `/aws/elasticache/mmm-<env>-redis/*` (KMS) |
| Network | Private-data subnets, `redis` security group (only the API and worker SGs can connect) |

Clients connect with `rediss://:<token>@<primary_endpoint>:6379`. They get the token from the
`REDIS_AUTH_TOKEN` secret that ECS injects (Step 7).

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | |
| `subnet_ids` / `security_group_id` | – | From the network module |
| `engine` / `engine_version` | `valkey` / `8.0` | |
| `node_type` | `cache.t4g.small` | |
| `num_cache_clusters` | `2` | 1 in dev |
| `auth_token` | – | Sensitive; `module.secrets.generated_values["redis/token"]` |
| `kms_key_arn` / `logs_kms_key_arn` | – | |
| `log_retention_days` | `30` | |
| `snapshot_retention_days` | `7` | |
| `apply_immediately` | `false` | |

Requires AWS provider 5.80 or newer (Valkey support).

## Outputs

`replication_group_id`, `primary_endpoint` (`REDIS_HOST`), `reader_endpoint`, `port`.
