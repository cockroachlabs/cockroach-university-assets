---
name: monitor-resource-usage-per-node
description: Can monitor CPU, memory, and disk usage per node in a unified view using crdb_internal tables. Shows sys.cpu.combined.percent-normalized for CPU, sys.rss for memory, and capacity.used/capacity.available for disk. Essential for identifying resource bottlenecks and load imbalances. Use when user says "resource usage per node", "node resources", "check all nodes", "cluster resource health".
metadata:
  domain: Monitoring and Alerting
  tags: monitoring, performance, cluster-operations
  blooms_level: Apply
  version: 1.0.0
---

# Monitor Resource Usage Per Node

Provides unified view of CPU, memory, and disk resources across all cluster nodes. Essential for identifying resource bottlenecks, load imbalances, and capacity planning.

## Why Monitor Per-Node Resources

Per-node monitoring helps:
- **Identify bottlenecks**: Find nodes at capacity
- **Balance load**: Detect uneven resource distribution
- **Capacity planning**: Know when to add nodes
- **Troubleshooting**: Correlate performance with resources
- **Cost optimization**: Right-size node resources

## Instructions

### Method 1: Quick Resource Overview (All Nodes)

```sql
-- Combined CPU, Memory, Disk per node
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  ROUND((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT, 2) as cpu_percent,
  ROUND((metrics->>'sys.rss')::FLOAT / 1073741824.0, 2) as memory_gb,
  ROUND((metrics->>'capacity.used')::FLOAT / 1073741824.0, 2) as disk_used_gb,
  ROUND((metrics->>'capacity.available')::FLOAT / 1073741824.0, 2) as disk_available_gb,
  ROUND(
    (metrics->>'capacity.used')::FLOAT /
    ((metrics->>'capacity.used')::FLOAT + (metrics->>'capacity.available')::FLOAT) * 100,
    1
  ) as disk_usage_percent
FROM crdb_internal.kv_store_status
ORDER BY node_id;
```

**Output**: One row per node with CPU%, memory GB, disk used/available

### Method 2: Detailed Resource Breakdown

```sql
-- Comprehensive resource metrics per node
SET allow_unsafe_internals = true;

SELECT
  kv.node_id,
  kv.store_id,

  -- CPU Metrics
  ROUND((kv.metrics->>'sys.cpu.combined.percent-normalized')::FLOAT, 2) as cpu_percent,
  ROUND((kv.metrics->>'sys.cpu.sys.percent')::FLOAT, 2) as cpu_sys_percent,
  ROUND((kv.metrics->>'sys.cpu.user.percent')::FLOAT, 2) as cpu_user_percent,

  -- Memory Metrics (GB)
  ROUND((kv.metrics->>'sys.rss')::FLOAT / 1073741824.0, 2) as rss_gb,
  ROUND((kv.metrics->>'sys.go.allocbytes')::FLOAT / 1073741824.0, 2) as go_alloc_gb,

  -- Disk Metrics (GB)
  ROUND((kv.metrics->>'capacity.used')::FLOAT / 1073741824.0, 2) as disk_used_gb,
  ROUND((kv.metrics->>'capacity.available')::FLOAT / 1073741824.0, 2) as disk_avail_gb,
  ROUND((kv.metrics->>'capacity')::FLOAT / 1073741824.0, 2) as disk_total_gb,

  -- Disk Usage %
  ROUND(
    (kv.metrics->>'capacity.used')::FLOAT /
    (kv.metrics->>'capacity')::FLOAT * 100,
    1
  ) as disk_usage_pct,

  -- Node Info
  kv.started_at,
  now() - kv.started_at as uptime

FROM crdb_internal.kv_store_status kv
ORDER BY node_id;
```

### Method 3: Resource Health Summary

```sql
-- Summary of resource health across cluster
SET allow_unsafe_internals = true;

SELECT
  'CPU' as resource,
  ROUND(AVG((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT), 2) as avg_usage,
  ROUND(MAX((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT), 2) as max_usage,
  ROUND(MIN((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT), 2) as min_usage
FROM crdb_internal.kv_store_status

UNION ALL

SELECT
  'Memory (GB)',
  ROUND(AVG((metrics->>'sys.rss')::FLOAT / 1073741824.0), 2),
  ROUND(MAX((metrics->>'sys.rss')::FLOAT / 1073741824.0), 2),
  ROUND(MIN((metrics->>'sys.rss')::FLOAT / 1073741824.0), 2)
FROM crdb_internal.kv_store_status

UNION ALL

SELECT
  'Disk Usage %',
  ROUND(AVG(
    (metrics->>'capacity.used')::FLOAT /
    (metrics->>'capacity')::FLOAT * 100
  ), 2),
  ROUND(MAX(
    (metrics->>'capacity.used')::FLOAT /
    (metrics->>'capacity')::FLOAT * 100
  ), 2),
  ROUND(MIN(
    (metrics->>'capacity.used')::FLOAT /
    (metrics->>'capacity')::FLOAT * 100
  ), 2)
FROM crdb_internal.kv_store_status;
```

### Method 4: DB Console (Visual)

**Steps**:
1. Navigate to DB Console: `https://<node-address>:8080`
2. Click **Metrics** → **Hardware**
3. View per-node graphs:
   - CPU Percent
   - Memory Usage
   - Disk Capacity

**Benefits**: Real-time graphs, historical trends, easy comparison

## Resource Thresholds

### Healthy Ranges

| Resource | Healthy | Warning | Critical |
|----------|---------|---------|----------|
| **CPU** | < 60% | 60-80% | > 80% |
| **Memory** | < 75% | 75-85% | > 85% |
| **Disk** | < 70% | 70-85% | > 85% |

### Alert Queries

**Warning - Any node at capacity:**
```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  CASE
    WHEN (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 60 THEN 'CPU Warning'
    WHEN (metrics->>'sys.rss')::FLOAT / (metrics->>'sys.go.totalbytes')::FLOAT > 0.75 THEN 'Memory Warning'
    WHEN (metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT > 0.70 THEN 'Disk Warning'
  END as alert_type,
  ROUND((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT, 2) as cpu_pct,
  ROUND((metrics->>'sys.rss')::FLOAT / 1073741824.0, 2) as memory_gb,
  ROUND((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT * 100, 1) as disk_pct
FROM crdb_internal.kv_store_status
WHERE (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 60
   OR (metrics->>'sys.rss')::FLOAT / (metrics->>'sys.go.totalbytes')::FLOAT > 0.75
   OR (metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT > 0.70;
```

## Understanding Resource Metrics

### CPU Metrics

**sys.cpu.combined.percent-normalized**:
- Normalized to 100% (even on multi-core)
- 50% = using half of one CPU core
- 100% = using one full CPU core
- >100% = using multiple cores

**sys.cpu.sys.percent**: System/kernel CPU time
**sys.cpu.user.percent**: User-space CPU time

### Memory Metrics

**sys.rss**: Resident Set Size - actual physical RAM used
**sys.go.allocbytes**: Go heap allocations
**sys.cgo.allocbytes**: C allocations (RocksDB)

### Disk Metrics

**capacity**: Total disk capacity
**capacity.used**: Disk space used by CockroachDB
**capacity.available**: Free disk space
**capacity.reserved**: Reserved for ballast file

## Example: Complete Node Health Check

```sql
-- Run this query to get full node health picture
SET allow_unsafe_internals = true;

WITH resource_metrics AS (
  SELECT
    node_id,
    (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT as cpu_pct,
    (metrics->>'sys.rss')::FLOAT / 1073741824.0 as memory_gb,
    (metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT * 100 as disk_pct,
    (metrics->>'capacity.available')::FLOAT / 1073741824.0 as disk_avail_gb
  FROM crdb_internal.kv_store_status
)
SELECT
  node_id,
  ROUND(cpu_pct, 2) as cpu_percent,
  CASE
    WHEN cpu_pct > 80 THEN '🔴 Critical'
    WHEN cpu_pct > 60 THEN '🟡 Warning'
    ELSE '🟢 Healthy'
  END as cpu_status,

  ROUND(memory_gb, 2) as memory_gb,
  CASE
    WHEN memory_gb > 12 THEN '🔴 Critical'  -- Assuming 16GB nodes
    WHEN memory_gb > 10 THEN '🟡 Warning'
    ELSE '🟢 Healthy'
  END as memory_status,

  ROUND(disk_pct, 1) as disk_usage_pct,
  ROUND(disk_avail_gb, 1) as disk_avail_gb,
  CASE
    WHEN disk_pct > 85 THEN '🔴 Critical'
    WHEN disk_pct > 70 THEN '🟡 Warning'
    ELSE '🟢 Healthy'
  END as disk_status

FROM resource_metrics
ORDER BY node_id;
```

## Detecting Resource Imbalances

### Unbalanced CPU Load

```sql
-- Find nodes with CPU significantly higher than average
SET allow_unsafe_internals = true;

WITH avg_cpu AS (
  SELECT AVG((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT) as avg_cpu
  FROM crdb_internal.kv_store_status
)
SELECT
  kv.node_id,
  ROUND((kv.metrics->>'sys.cpu.combined.percent-normalized')::FLOAT, 2) as cpu_pct,
  ROUND(ac.avg_cpu, 2) as cluster_avg_cpu,
  ROUND(
    (kv.metrics->>'sys.cpu.combined.percent-normalized')::FLOAT / ac.avg_cpu,
    2
  ) as cpu_ratio
FROM crdb_internal.kv_store_status kv, avg_cpu ac
WHERE (kv.metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > ac.avg_cpu * 1.5
ORDER BY cpu_ratio DESC;
```

**Interpretation**:
- `cpu_ratio > 1.5`: Node has 50% more CPU load than average
- May indicate hot ranges on that node
- Consider rebalancing ranges

### Unbalanced Disk Usage

```sql
-- Find nodes with uneven disk usage
SET allow_unsafe_internals = true;

SELECT
  node_id,
  ROUND((metrics->>'capacity.used')::FLOAT / 1073741824.0, 2) as used_gb,
  ROUND((metrics->>'capacity.available')::FLOAT / 1073741824.0, 2) as avail_gb,
  ROUND(
    (metrics->>'capacity.used')::FLOAT /
    (metrics->>'capacity')::FLOAT * 100,
    1
  ) as usage_pct
FROM crdb_internal.kv_store_status
ORDER BY usage_pct DESC;
```

**Expected**: Similar disk usage across nodes (±20%)
**Problem**: One node 50%+ higher indicates replica imbalance

## Capacity Planning

### Predict When to Add Nodes

**CPU-based**:
```sql
-- If average CPU > 60%, consider adding nodes
SELECT
  'CPU' as metric,
  ROUND(AVG((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT), 2) as avg_usage,
  CASE
    WHEN AVG((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT) > 60
    THEN 'Consider adding nodes'
    ELSE 'Capacity OK'
  END as recommendation
FROM crdb_internal.kv_store_status;
```

**Disk-based**:
```sql
-- Estimate time until disk full (requires historical data)
SELECT
  node_id,
  ROUND((metrics->>'capacity.used')::FLOAT / 1073741824.0, 2) as used_gb,
  ROUND((metrics->>'capacity.available')::FLOAT / 1073741824.0, 2) as avail_gb,
  -- If growing 10GB/month, months until full:
  ROUND((metrics->>'capacity.available')::FLOAT / 1073741824.0 / 10, 1) as months_until_full
FROM crdb_internal.kv_store_status
ORDER BY months_until_full;
```

## Troubleshooting Resource Issues

### High CPU on Specific Node

**Diagnosis**:
```sql
-- Find what's using CPU on high-CPU node
SET allow_unsafe_internals = true;

-- Check for hot ranges on that node
SELECT
  range_id,
  table_name,
  lease_holder,
  writes_per_second,
  reads_per_second
FROM crdb_internal.ranges_no_leases
WHERE lease_holder = <high_cpu_node_id>
ORDER BY writes_per_second DESC
LIMIT 10;
```

**Solutions**:
- Rebalance ranges (automatic, wait for rebalancing)
- Identify hot ranges and apply hash sharding
- Add more nodes to distribute load

### High Memory on Specific Node

**Diagnosis**:
```sql
-- Check for expensive queries
SELECT
  node_id,
  query,
  ROUND(max_mem_usage / 1073741824.0, 2) as max_mem_gb
FROM crdb_internal.statement_statistics
ORDER BY max_mem_usage DESC
LIMIT 10;
```

**Solutions**:
- Optimize expensive queries
- Increase node RAM
- Add LIMIT clauses to queries
- Review connection pool size

### Disk Space Running Low

**Diagnosis**:
```sql
-- Check what's using disk
SELECT
  database_name,
  table_name,
  count(*) as range_count,
  SUM(range_size) / 1073741824.0 as total_gb
FROM [SHOW CLUSTER RANGES WITH TABLES, DETAILS]
WHERE database_name IS NOT NULL
GROUP BY database_name, table_name
ORDER BY total_gb DESC;
```

**Solutions**:
- Drop unused tables/databases
- Reduce GC TTL (allows earlier cleanup)
- Add nodes with more disk capacity
- Archive old data

## Monitoring Script

```bash
#!/bin/bash
# monitor-cluster-resources.sh
# Run every 5 minutes via cron

CERTS_DIR="/path/to/certs"
HOST="localhost:26258"

cockroach sql --certs-dir=$CERTS_DIR --host=$HOST --execute="
SET allow_unsafe_internals = true;

SELECT
  now() as timestamp,
  node_id,
  ROUND((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT, 2) as cpu_pct,
  ROUND((metrics->>'sys.rss')::FLOAT / 1073741824.0, 2) as memory_gb,
  ROUND((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT * 100, 1) as disk_pct
FROM crdb_internal.kv_store_status
ORDER BY node_id;
" | tee -a /var/log/cockroach-resources.log
```

## Verification Checklist

Healthy resource usage when:
- ✅ CPU < 60% on all nodes (with headroom for spikes)
- ✅ Memory < 75% on all nodes
- ✅ Disk < 70% on all nodes
- ✅ Resources balanced across nodes (within 30%)
- ✅ No sustained high usage (indicates capacity issue)
- ✅ Growth rate is predictable and sustainable

## Related Skills

- `monitor-cpu-usage-per-node` - Detailed CPU monitoring
- `monitor-memory-usage-and-pressure` - Detailed memory monitoring
- `monitor-storage-capacity-and-growth` - Detailed disk monitoring
- `identify-hot-ranges` - Find performance bottlenecks
- `monitor-leaseholder-distribution` - Load distribution

## Documentation

- Hardware Dashboard: https://www.cockroachlabs.com/docs/stable/ui-hardware-dashboard.html
- Performance Tuning: https://www.cockroachlabs.com/docs/stable/performance-best-practices-overview.html
- Capacity Planning: https://www.cockroachlabs.com/docs/stable/recommended-production-settings.html
