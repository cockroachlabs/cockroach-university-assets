---
name: monitor-memory-usage-and-pressure
description: Monitor Go heap allocations, SQL memory pools, and system memory using DB Console Hardware metrics or crdb_internal.node_metrics. Track sys.go.allocbytes for memory allocations and sys.rss for resident set size per node. Alert on memory pressure to prevent OOM conditions.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - monitoring
    - performance
    - memory
    - operations
    - troubleshooting
---

# Monitor Memory Usage and Pressure

## Overview

Monitor Go heap allocations, SQL memory pools, and system memory (RSS) to prevent OOM conditions and maintain cluster health. Track memory usage across nodes and identify pressure before it causes failures.

## Why Monitor Memory

Prevent OOM kills, performance degradation, query failures, and cluster instability caused by memory pressure.

## Instructions

### Method 1: Cluster-Wide Memory (Quick Check)

```sql
-- Total memory usage across cluster
SET allow_unsafe_internals = true;

SELECT
  name,
  value as memory_bytes,
  ROUND(value::FLOAT / 1073741824.0, 2) as memory_gb
FROM crdb_internal.node_metrics
WHERE name IN ('sys.go.allocbytes', 'sys.rss')
ORDER BY name;
```

**Output**: Aggregate memory metrics for entire cluster

### Method 2: Per-Node Memory

Use DB Console Hardware dashboard to view per-node memory distribution. Look for imbalanced memory usage (>10% variance between nodes).

### Method 3: DB Console (Visual)

**Steps**:
1. Navigate to DB Console: `https://<node-address>:8080`
2. Click **Metrics** in left sidebar
3. Select **Hardware** dashboard
4. View **Memory Usage** graph

**What to monitor**:
- Memory usage per node (should be balanced)
- Memory growth over time (indicates leak if unbounded)
- Spikes during query execution

### Method 4: Detailed Memory Breakdown

```sql
-- Comprehensive memory metrics
SET allow_unsafe_internals = true;

SELECT
  name,
  ROUND(value::FLOAT / 1073741824.0, 3) as value_gb,
  CASE
    WHEN name LIKE '%sys.go%' THEN 'Go Runtime'
    WHEN name LIKE '%sys.rss%' THEN 'System Memory'
    WHEN name LIKE '%sql.mem%' THEN 'SQL Memory'
    ELSE 'Other'
  END as category
FROM crdb_internal.node_metrics
WHERE name IN (
  'sys.go.allocbytes',
  'sys.rss',
  'sys.cgo.allocbytes',
  'sys.go.totalbytes'
)
ORDER BY value DESC;
```

## Core Concepts

### Memory Components

**1. Go Heap (`sys.go.allocbytes`)**: SQL execution, transactions, metadata. Managed by Go GC.

**2. CGo/RocksDB (`sys.cgo.allocbytes`)**: RocksDB block cache, memtables, bloom filters. Controlled by RocksDB settings.

**3. Resident Set Size (`sys.rss`)**: Total physical RAM used. Best indicator of OOM risk.

**4. SQL Memory**: Query operations, controlled by `sql.distsql.temp_storage.workmem`.

### Go Heap vs RSS

RSS can remain high after Go GC because the runtime caches freed memory for reuse. Normal unless approaching OOM.

## Key Memory Metrics

| Metric | Description | Healthy Range | Warning | Critical |
|--------|-------------|---------------|---------|----------|
| **sys.rss** | Resident set size (actual RAM used) | < 70% of node RAM | 70-85% | > 85% |
| **sys.go.allocbytes** | Go heap allocations | < 50% of node RAM | 50-70% | > 70% |
| **sys.cgo.allocbytes** | C allocations (RocksDB) | Stable, < 30% RAM | Growing continuously | Unbounded growth |
| **sys.go.totalbytes** | Total memory from OS | < 75% of node RAM | 75-90% | > 90% |
| **sql.mem.root.current** | SQL memory pool usage | < workmem setting | Near workmem | Exceeding workmem |

## Alert Thresholds

### Warning Alerts

**Trigger when**:
```sql
-- Memory > 75% of available RAM
SET allow_unsafe_internals = true;

SELECT
  'Warning: High memory usage' as alert,
  ROUND(value::FLOAT / 1073741824.0, 2) as rss_gb
FROM crdb_internal.node_metrics
WHERE name = 'sys.rss'
  AND value::FLOAT / 1073741824.0 > (
    -- Assuming 16GB total RAM per node, 75% threshold
    16 * 0.75
  );
```

### Critical Alerts

**Trigger when**:
```sql
-- Memory > 90% of available RAM
SET allow_unsafe_internals = true;

SELECT
  'CRITICAL: Memory pressure' as alert,
  ROUND(value::FLOAT / 1073741824.0, 2) as rss_gb
FROM crdb_internal.node_metrics
WHERE name = 'sys.rss'
  AND value::FLOAT / 1073741824.0 > (
    -- 90% threshold
    16 * 0.90
  );
```

## Memory Pressure Indicators

**Early Warning**: Memory >70%, continuous heap growth, RSS not decreasing idle, increased GC frequency, rising latency.

**Critical**: Memory >85%, frequent query errors, admission control queuing, node unresponsive, OOM logs.

**Query-Level Check**:
```sql
-- Queries using excessive memory (>1GB)
SET allow_unsafe_internals = true;

SELECT
  app_name,
  metadata->>'querySummary' as query,
  ROUND((statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT::DECIMAL / 1073741824.0, 2) as max_memory_gb,
  (statistics->'statistics'->>'cnt')::INT as execution_count
FROM crdb_internal.cluster_statement_statistics
WHERE (statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT > 1073741824
ORDER BY (statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT DESC
LIMIT 10;
```

## Understanding Memory Metrics

### sys.rss (Resident Set Size)
Actual physical RAM used. **Normal**: Grows during queries, may not decrease immediately (Go runtime caches). **Warning**: >85% RAM, continuous growth, no workload correlation.

### sys.go.allocbytes (Go Heap)
Memory for SQL execution, transactions, metadata. **Normal**: Spikes during queries, decreases after GC (30-60s cycles). **Warning**: >70% RAM, steady growth, frequent GC (<1s).

### sys.cgo.allocbytes (C Allocations)
RocksDB cache, memtables, bloom filters. **Normal**: Plateaus at configured `--cache` value. **Warning**: Unbounded growth, memory leak.

## Example: Memory Health Check

```sql
SET allow_unsafe_internals = true;

-- Current memory usage
SELECT name, ROUND(value::FLOAT / 1073741824.0, 2) as memory_gb
FROM crdb_internal.node_metrics
WHERE name IN ('sys.go.allocbytes', 'sys.rss')
ORDER BY value DESC;

-- Top memory queries
SELECT
  app_name,
  metadata->>'querySummary' as query,
  ROUND((statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT::DECIMAL / 1073741824.0, 2) as max_memory_gb,
  (statistics->'statistics'->>'cnt')::INT as execution_count
FROM crdb_internal.cluster_statement_statistics
ORDER BY (statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT DESC
LIMIT 5;

-- Long-running sessions (potential leak)
SELECT session_id, user_name, application_name, session_start, now() - session_start as duration
FROM crdb_internal.cluster_sessions
WHERE now() - session_start > interval '24 hours'
ORDER BY session_start;
```

## Troubleshooting High Memory Usage

### Problem 1: Sudden Memory Spike

**Symptoms**: Memory jumps 40%→80%+, queries timeout, admission queueing.

**Diagnosis**:
```sql
SHOW CLUSTER QUERIES;  -- Find running queries

SET allow_unsafe_internals = true;

SELECT
  app_name,
  metadata->>'querySummary' as query,
  ROUND((statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT::DECIMAL / 1073741824.0, 2) as gb,
  (statistics->'statistics'->>'cnt')::INT as execution_count
FROM crdb_internal.cluster_statement_statistics
WHERE (statistics->'statistics'->>'lastExecAt')::TIMESTAMPTZ > now() - interval '1 hour'
ORDER BY (statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT DESC
LIMIT 10;
```

**Causes**: Large scans, hash joins, high-cardinality GROUP BY, bulk imports.

**Solutions**: Cancel queries, add indexes (`SHOW INDEX RECOMMENDATIONS`), add LIMITs, enable admission control.

### Problem 2: Gradual Memory Growth (Leak)

**Symptoms**: 5-10% daily growth, no workload correlation, no idle decrease.

**Diagnosis**:
```sql
-- Check connections
SELECT count(*) as total, count(DISTINCT application_name) as apps
FROM crdb_internal.cluster_sessions;

-- Long sessions
SELECT session_id, user_name, application_name, now() - session_start as age
FROM crdb_internal.cluster_sessions
WHERE now() - session_start > interval '24 hours';
```

**Causes**: Unclosed connections, prepared statement leaks, orphaned sessions.

**Solutions**: Cancel old sessions, configure pool max lifetime (30min), set `idle_in_session_timeout`.

### Problem 3: Memory Not Released After Load

**Symptoms**: Memory stays high after load ends, no queries running.

**Cause**: Go runtime caches freed memory (normal behavior).

**Action**: None if <85% RAM; restart node if >90%; increase RAM if workload requires it.

### Problem 4: RocksDB Cache Exceeding Limit

**Diagnosis**:
```sql
SET allow_unsafe_internals = true;

-- Check C/RocksDB allocations
SELECT name, ROUND(value::FLOAT / 1073741824.0, 2) as memory_gb
FROM crdb_internal.node_metrics
WHERE name = 'sys.cgo.allocbytes';
```

**Note**: RocksDB cache size is configured via `--cache` startup flag (not a cluster setting in v23.1+). Cache size cannot be changed without restarting nodes.

**Solution**: If RocksDB cache is too large, adjust `--cache` flag and perform rolling restart.

### Problem 5: Many Concurrent Queries

**Symptoms**: 100+ small queries, total memory high.

**Solutions**: Enable admission control, reduce `sql.distsql.temp_storage.workmem`, set statement timeout, limit app connections.

## SQL Memory and Disk Spilling

Per-query memory controlled by `sql.distsql.temp_storage.workmem` (default 64MB). When exceeded, queries spill to disk.

```sql
SHOW CLUSTER SETTING sql.distsql.temp_storage.workmem;

-- Check queries spilling to disk
SET allow_unsafe_internals = true;

SELECT
  app_name,
  metadata->>'querySummary' as query,
  (statistics->'execution_statistics'->'maxDiskUsage'->>'mean')::FLOAT::BIGINT as max_disk_usage,
  ROUND((statistics->'execution_statistics'->'maxMemUsage'->>'mean')::FLOAT::DECIMAL / 1048576.0, 2) as mb
FROM crdb_internal.cluster_statement_statistics
WHERE (statistics->'execution_statistics'->'maxDiskUsage'->>'mean')::FLOAT > 0
ORDER BY (statistics->'execution_statistics'->'maxDiskUsage'->>'mean')::FLOAT DESC
LIMIT 10;
```

**Impact**: Slower (disk I/O) but prevents OOM.

## Memory Configuration

### RocksDB Cache (25-30% of RAM)

**Note**: In CockroachDB v23.1+, RocksDB cache is configured via startup flag only.

```bash
# RocksDB cache size set at node startup (requires restart to change)
cockroach start --cache=4GB ...   # Fixed size
cockroach start --cache=25% ...   # Percentage of total RAM
```

**Sizing**: <16GB=25%, 16-64GB=25-30%, >64GB=30-35%. Leave 60-70% for Go heap/SQL.

### SQL Memory
```sql
-- Per-query workmem
SHOW CLUSTER SETTING sql.distsql.temp_storage.workmem;
SET CLUSTER SETTING sql.distsql.temp_storage.workmem = '256MB';  -- Analytical
SET CLUSTER SETTING sql.distsql.temp_storage.workmem = '32MB';   -- Concurrent
```

### Node Startup (requires restart)
```bash
cockroach start --cache=25% --max-sql-memory=25% ...
```

## Best Practices

### Monitoring
- **Real-time**: DB Console during deployments, load tests, troubleshooting
- **Automated**: Prometheus metrics every 15-30s with alerts
- **Manual**: Weekly trends, monthly capacity reviews, post-incident analysis

### Alerting
- **Warning (70-85%)**: Investigate within 1 hour
- **Critical (>85%)**: Act within 15 minutes
- **Emergency (>95%)**: Immediate response (cancel queries, restart, add capacity)

### Capacity Planning
**64GB node example**: RocksDB 16GB (25%), SQL 16GB (25%), Go heap 24GB (37.5%), OS 8GB (12.5%)

**Add capacity when**: Sustained >70%, frequent spilling, admission queueing, query timeouts.

**Scale up** (more RAM): Memory-intensive queries. **Scale out** (more nodes): Query concurrency.

### Optimization
```sql
-- Limit rows
SELECT * FROM large_table LIMIT 1000;

-- Add indexes
CREATE INDEX idx_filter ON table (filter_column);

-- Batch queries
SELECT * FROM table WHERE id >= 1 AND id < 1000;
```

**Connection pooling**: Max connections=4x CPUs, lifetime=30-60min, cache prepared statements.

**Schema**: Appropriate types (INT vs BIGINT), normalize large TEXT/JSONB, column families, partitioning.

## Verification Checklist

Memory is healthy when:
- ✅ RSS < 70% of node RAM (warning at 70%)
- ✅ Go allocations < 50% of node RAM
- ✅ Memory usage balanced across nodes (< 10% variance)
- ✅ No continuous unbounded growth over days
- ✅ Memory releases during idle periods
- ✅ No OOM errors in logs
- ✅ No queries exceeding memory limits
- ✅ Admission control not queueing due to memory
- ✅ GC pause times < 100ms
- ✅ SQL queries not spilling to disk frequently

## Related Skills

- `monitor-cpu-usage-per-node` - CPU monitoring
- `monitor-storage-capacity-and-growth` - Disk usage
- `monitor-statement-statistics` - Query performance
- `monitor-resource-usage-per-node` - Combined resource view

## Documentation

- Memory Monitoring: https://www.cockroachlabs.com/docs/stable/ui-hardware-dashboard.html
- Performance Tuning: https://www.cockroachlabs.com/docs/stable/performance-best-practices-overview.html
- Cluster Settings: https://www.cockroachlabs.com/docs/stable/cluster-settings.html
