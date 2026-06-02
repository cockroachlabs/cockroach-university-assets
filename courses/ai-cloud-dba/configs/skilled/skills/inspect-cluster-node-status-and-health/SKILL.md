---
name: inspect-cluster-node-status-and-health
description: Inspect cluster node status and health using SHOW CLUSTER QUERIES, crdb_internal.kv_node_status, and related commands. Monitor node liveness, uptime, build version, and resource utilization across the cluster.
metadata:
  domain: Cluster Management
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  related_skills:
    - access-and-navigate-db-console
    - inspect-active-sessions-and-connections
    - explore-system-catalog-tables
    - verify-cluster-health-between-restarts
    - verify-cluster-membership
  prerequisites:
    - Running CockroachDB cluster
    - SQL access to cluster
    - Basic understanding of cluster architecture
  estimated_time_minutes: 20
  last_updated: "2026-03-06"
---

# Inspect Cluster Node Status and Health

## Overview

Monitoring node status and health is critical for maintaining cluster reliability. CockroachDB provides SQL commands and system tables to inspect node liveness, resource usage, versions, and overall health.

**Key concepts:**
- **Node liveness**: Whether node is up and participating in cluster
- **Node health**: Resource utilization (CPU, memory, disk, network)
- **Build version**: CockroachDB version running on each node
- **Uptime**: How long node has been running
- **Locality**: Geographic placement (region, zone, datacenter)

**Why inspect node status:**
- Verify all nodes are live and healthy
- Identify resource bottlenecks (CPU, memory, disk)
- Confirm version consistency after upgrades
- Troubleshoot node failures or network issues
- Monitor cluster capacity and growth

## Basic Node Status Commands

### cockroach node status (CLI)

```bash
# Show all nodes from CLI
cockroach node status --host=localhost:26257

# With certificates (secure cluster)
cockroach node status --certs-dir=/path/to/certs --host=node1:26257

# Output format options
cockroach node status --format=table
cockroach node status --format=csv
cockroach node status --format=json
```

**Example output:**
```
  id |     address     |  build  |       started_at        |       updated_at        | is_live
-----+-----------------+---------+-------------------------+-------------------------+---------
   1 | localhost:26257 | v26.1.0 | 2026-03-06 10:00:00.000 | 2026-03-06 14:30:15.123 | true
   2 | localhost:26258 | v26.1.0 | 2026-03-06 10:00:05.000 | 2026-03-06 14:30:16.234 | true
   3 | localhost:26259 | v26.1.0 | 2026-03-06 10:00:10.000 | 2026-03-06 14:30:17.345 | true
```

**Key columns:**
- `id`: Node ID
- `address`: RPC address (node-to-node communication)
- `build`: CockroachDB version
- `started_at`: Node start time
- `updated_at`: Last heartbeat received
- `is_live`: Whether node is alive (true/false)

## SQL-Based Node Inspection

### crdb_internal.kv_node_status

The primary table for node health inspection:

```sql
-- Enable access to internal tables
SET allow_unsafe_internals = true;

-- View all nodes with key health metrics
SELECT
  node_id,
  address,
  tag,
  started_at,
  updated_at,
  is_live,
  metrics
FROM crdb_internal.kv_node_status
ORDER BY node_id;
```

**Key columns:**
- `node_id`: Unique node identifier
- `address`: Node RPC address
- `is_live`: Boolean - node is alive
- `started_at`: Timestamp of node start
- `updated_at`: Last liveness heartbeat
- `tag`: CockroachDB version
- `locality`: JSON object with region/zone/dc tags
- `metrics`: JSONB object with detailed metrics

### Extract Key Health Metrics

```sql
SET allow_unsafe_internals = true;

-- Node uptime and version
SELECT
  node_id,
  tag,
  now() - started_at AS uptime,
  age(now(), updated_at) AS last_heartbeat_ago,
  CASE
    WHEN is_live THEN 'LIVE'
    ELSE 'DOWN'
  END AS status
FROM crdb_internal.kv_node_status
ORDER BY node_id;
```

**Example output:**
```
  node_id | tag |     uptime      | last_heartbeat_ago | status
----------+-----------+-----------------+--------------------+--------
    1     | v26.1.0   | 4 days 04:30:00 | 00:00:02           | LIVE
    2     | v26.1.0   | 4 days 04:25:00 | 00:00:01           | LIVE
    3     | v26.1.0   | 4 days 04:20:00 | 00:00:03           | LIVE
```

### Extract Resource Utilization from Metrics

```sql
SET allow_unsafe_internals = true;

-- CPU and memory usage
SELECT
  node_id,
  (metrics->'sys.cpu.user.percent')::FLOAT AS cpu_user_pct,
  (metrics->'sys.cpu.sys.percent')::FLOAT AS cpu_sys_pct,
  (metrics->'sys.rss')::BIGINT / (1024*1024*1024) AS memory_gb,
  (metrics->'capacity')::BIGINT / (1024*1024*1024) AS total_disk_gb,
  (metrics->'capacity.available')::BIGINT / (1024*1024*1024) AS available_disk_gb,
  ROUND(
    100 - (
      (metrics->'capacity.available')::FLOAT /
      (metrics->'capacity')::FLOAT * 100
    ), 2
  ) AS disk_used_pct
FROM crdb_internal.kv_node_status
WHERE is_live
ORDER BY node_id;
```

**Interpreting results:**
- CPU user/sys: Combined > 80% = high load
- Memory GB: RSS (resident set size) - actual RAM used
- Disk used %: > 85% = warning, > 95% = critical

## Node Liveness Inspection

### crdb_internal.gossip_liveness

Track node liveness heartbeats:

```sql
SET allow_unsafe_internals = true;

-- View liveness status for all nodes
SELECT
  node_id,
  epoch,
  expiration,
  draining,
  decommissioning,
  membership,
  CASE
    WHEN expiration > now() THEN 'LIVE'
    ELSE 'DEAD'
  END AS liveness_status,
  expiration - now() AS expires_in
FROM crdb_internal.gossip_liveness
ORDER BY node_id;
```

**Key columns:**
- `epoch`: Liveness epoch (increments when node restarts)
- `expiration`: Liveness expiration timestamp (heartbeat deadline)
- `draining`: Whether node is draining (preparing to shut down)
- `decommissioning`: Whether node is being removed from cluster
- `membership`: Node membership status (active, decommissioned, etc.)

**Liveness states:**
- `expiration > now()`: Node alive and heartbeating
- `expiration < now()`: Node missed heartbeats (likely down)
- `draining = true`: Node shutting down gracefully
- `decommissioning = true`: Node being removed

## Health Check Workflows

### Workflow 1: Quick Health Check (All Nodes Live?)

```sql
SET allow_unsafe_internals = true;

-- Count live vs total nodes
SELECT
  count(*) AS total_nodes,
  sum(CASE WHEN is_live THEN 1 ELSE 0 END) AS live_nodes,
  sum(CASE WHEN NOT is_live THEN 1 ELSE 0 END) AS dead_nodes
FROM crdb_internal.kv_node_status;
```

**Expected result**: `total_nodes = live_nodes`, `dead_nodes = 0`

**If dead_nodes > 0**:
```sql
-- Identify dead nodes
SELECT
  node_id,
  address,
  started_at,
  updated_at,
  now() - updated_at AS time_since_last_heartbeat
FROM crdb_internal.kv_node_status
WHERE NOT is_live;
```

### Workflow 2: Resource Utilization Check

```sql
SET allow_unsafe_internals = true;

-- High CPU nodes
SELECT
  node_id,
  ROUND((metrics->'sys.cpu.user.percent')::FLOAT, 1) AS cpu_pct,
  ROUND((metrics->'sys.rss')::BIGINT / (1024.0*1024*1024), 2) AS memory_gb
FROM crdb_internal.kv_node_status
WHERE is_live
  AND (metrics->'sys.cpu.user.percent')::FLOAT > 70.0
ORDER BY cpu_pct DESC;
```

**Threshold guidance:**
- CPU > 70%: Moderate load
- CPU > 85%: High load, investigate queries
- CPU > 95%: Critical, add nodes or reduce load

```sql
-- High disk usage nodes
SELECT
  node_id,
  ROUND((metrics->'capacity')::BIGINT / (1024.0*1024*1024), 1) AS total_gb,
  ROUND((metrics->'capacity.available')::BIGINT / (1024.0*1024*1024), 1) AS avail_gb,
  ROUND(
    100 - ((metrics->'capacity.available')::FLOAT / (metrics->'capacity')::FLOAT * 100),
    1
  ) AS used_pct
FROM crdb_internal.kv_node_status
WHERE is_live
  AND (
    100 - ((metrics->'capacity.available')::FLOAT / (metrics->'capacity')::FLOAT * 100)
  ) > 80.0
ORDER BY used_pct DESC;
```

**Threshold guidance:**
- Disk > 80%: Warning, plan capacity expansion
- Disk > 90%: Urgent, add storage or nodes soon
- Disk > 95%: Critical, cluster may reject writes

### Workflow 3: Version Consistency Check

```sql
SET allow_unsafe_internals = true;

-- Verify all nodes on same version
SELECT
  tag,
  count(*) AS node_count,
  array_agg(node_id ORDER BY node_id) AS nodes
FROM crdb_internal.kv_node_status
WHERE is_live
GROUP BY tag
ORDER BY tag;
```

**Expected**: Single row (all nodes on same version)

**Example mixed version (during upgrade):**
```
  tag  | node_count |  nodes
-------------+------------+---------
  v26.0.3    |     2      | {1,2}
  v26.1.0    |     1      | {3}
```

**Action**: Complete rolling upgrade to get all nodes on v26.1.0.

## Common Patterns

### Pattern 1: Health Summary Dashboard Query

```sql
SET allow_unsafe_internals = true;

-- Single query health overview
SELECT
  n.node_id,
  n.tag AS version,
  CASE WHEN n.is_live THEN 'LIVE' ELSE 'DOWN' END AS status,
  ROUND((now() - n.started_at)::numeric / 3600, 1) AS uptime_hours,
  ROUND((n.metrics->'sys.cpu.user.percent')::FLOAT, 1) AS cpu_pct,
  ROUND((n.metrics->'sys.rss')::BIGINT / (1024.0*1024*1024), 2) AS mem_gb,
  ROUND(
    100 - ((n.metrics->'capacity.available')::FLOAT / (n.metrics->'capacity')::FLOAT * 100),
    1
  ) AS disk_used_pct,
  n.locality::STRING AS locality
FROM crdb_internal.kv_node_status n
ORDER BY n.node_id;
```

**Save as a view for regular health checks**:
```sql
CREATE VIEW cluster_health_summary AS
SELECT ... (query above);

-- Then simply:
SELECT * FROM cluster_health_summary;
```

### Pattern 2: Alert on Node Down

```sql
SET allow_unsafe_internals = true;

-- Returns rows only if any node is down
SELECT
  node_id,
  address,
  'NODE DOWN' AS alert,
  now() - updated_at AS time_down
FROM crdb_internal.kv_node_status
WHERE NOT is_live;
```

**Automation**: Run this query periodically (cron, monitoring tool) and alert if returns rows.

## Best Practices

1. **Automate health checks**: Run node status queries every 5 minutes
   ```bash
   # Cron job to check health
   */5 * * * * cockroach sql --host=localhost:26257 -e "SELECT count(*) FROM crdb_internal.kv_node_status WHERE NOT is_live;" | grep -q "^0$" || alert-script.sh
   ```

2. **Monitor key thresholds**:
   - CPU > 80%
   - Memory RSS > 90% of system RAM
   - Disk > 85%
   - Any node down (is_live = false)

3. **Track version consistency**: During upgrades, ensure all nodes eventually converge to same version

4. **Use DB Console for visual monitoring**: Complement SQL checks with DB Console Overview page

5. **Check liveness expiration**: Nodes should heartbeat every 9 seconds (default)
   ```sql
   -- Alert if expiration < 30 seconds away (node struggling)
   SELECT node_id FROM crdb_internal.gossip_liveness
   WHERE expiration - now() < interval '30 seconds';
   ```

## Troubleshooting

### Problem: Node shows is_live = false

**Diagnosis:**
```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  address,
  started_at,
  updated_at,
  now() - updated_at AS time_since_heartbeat
FROM crdb_internal.kv_node_status
WHERE NOT is_live;
```

**Common causes:**
- Node process crashed (check `ps aux | grep cockroach`)
- Network partition (node isolated from cluster)
- Node overloaded (CPU/memory exhaustion)
- Clock skew (NTP not synchronized)

**Solution:**
```bash
# Check if process running
ps aux | grep cockroach

# Check logs
tail -100 /var/log/cockroach/cockroach.log

# Restart node if needed
systemctl restart cockroach
```

### Problem: High CPU on specific node

**Diagnosis:**
```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  (metrics->'sys.cpu.user.percent')::FLOAT AS cpu_pct
FROM crdb_internal.kv_node_status
WHERE (metrics->'sys.cpu.user.percent')::FLOAT > 80
ORDER BY cpu_pct DESC;
```

**Investigate:**
```sql
-- Check if node has more leaseholders than others
SELECT lease_holder, count(*) AS lease_count
FROM crdb_internal.ranges
GROUP BY lease_holder
ORDER BY lease_count DESC;
```

**Solution:**
- Rebalance leaseholders using zone configurations
- Identify hot ranges and split them
- Scale cluster (add nodes)

### Problem: Metrics show NULL values

**Cause**: `allow_unsafe_internals` not set or metrics not collected yet

**Solution:**
```sql
-- Enable access
SET allow_unsafe_internals = true;

-- Wait 10 seconds for metrics collection cycle
-- Metrics refresh every ~10 seconds
```

## Summary

Inspect node status and health using:

✅ **cockroach node status** - CLI command for quick overview
✅ **crdb_internal.kv_node_status** - Comprehensive node health metrics
✅ **crdb_internal.gossip_liveness** - Node liveness and heartbeat status
✅ **SHOW LOCALITY** - Node placement information

**Key health indicators:**
- All nodes show `is_live = true`
- CPU < 80%, Memory < 90%, Disk < 85%
- All nodes on same `tag` version
- Liveness expiration > now() (heartbeating normally)

**Remember**: Regular health checks prevent outages. Automate monitoring and set alerts on critical thresholds to catch issues before they impact users.
