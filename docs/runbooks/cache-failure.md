# Runbook: cache (ElastiCache Valkey/Redis) failure

Replication group `mmm-<env>-redis` (dev 1 node, staging/prod 2 nodes, Multi-AZ, TLS + auth token).
The cache holds derived data (e.g. cached what-if results); the system of record is PostgreSQL.
Losing the cache should make the app slower, not wrong – confirm this with the app team during
handover, because it decides whether step 6 below is safe.

## Symptoms

`mmm-<env>-redis-cpu-00N`, `redis-memory-00N` alarms; API errors with `ConnectionError` /
`TimeoutError` / `NOAUTH` in `/ecs/mmm-<env>/api`; slow what-ifs.

## Steps

1. **State:**
   ```bash
   aws elasticache describe-replication-groups --replication-group-id $P-redis \
     --query 'ReplicationGroups[0].{status:Status,failover:AutomaticFailover,nodes:NodeGroups[0].NodeGroupMembers[].[CacheClusterId,CurrentRole,PreferredAvailabilityZone]}'
   aws elasticache describe-events --source-type replication-group --source-identifier $P-redis --duration 120
   ```
2. **Primary failed:** automatic failover promotes the replica (about 1 min). Nothing to do but
   confirm the API reconnected (errors stop). If it did not fail over (dev: single node), wait for
   the node replacement or reboot it: `aws elasticache reboot-cache-cluster --cache-cluster-id $P-redis-001 --cache-node-ids-to-reboot 0001`.
3. **Memory full / evictions:** check `Evictions`, `DatabaseMemoryUsagePercentage`. Short term:
   ask the app team to flush the what-if cache keys; long term: larger `redis_node_type` (PR, online).
4. **CPU high:** look for hot keys / expensive commands (`SLOWLOG` via the app team). Scale up the node type.
5. **`NOAUTH` / `WRONGPASS` after a token rotation:** the tasks still have the old token. Force a
   new deployment of api and workers (they read `mmm/<env>/redis/token` at start) – see [rotation.md](rotation.md).
6. **Cache lost completely:** the app keeps working without it (slower). Terraform recreates it
   on apply if it was deleted; data is rebuilt on use (daily snapshots exist in prod for 7 days).

## Verify

Alarms OK, API p95 back to normal, no cache errors in the logs for 15 minutes.
