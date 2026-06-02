---
name: monitor-query-resource-consumption
description: Track CPU time, disk I/O, and row operations per query using statement statistics to identify resource-intensive queries
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Monitor Query Resource Consumption

**Domain**: Monitoring and Alerting
**Bloom's Level**: Apply
**Version**: 1.1.0
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

Monitor and analyze query resource consumption using statement statistics to track CPU time, disk I/O, and row operations per query to identify resource-intensive queries for optimization.

## Prerequisites

- CockroachDB cluster (v26.1.0+) with SQL client access
- Understanding of statement statistics and JSON querying
- Session setting: `SET allow_unsafe_internals = true` required for all queries

## v26.1.0 Resource Metrics Available

**Available Metrics**:
- CPU: `runLat.mean` (runtime), `svcLat.mean` (service latency), `kvCPUTimeNanos.mean`
- Disk I/O: `bytesRead.mean`, `rowsRead.mean`, `rowsWritten.mean`
- Execution: `cnt` (count), `numRows.mean` (returned rows), `maxRetries`

**NOT Available in v26.1.0**:
- Memory metrics (`maxMemUsage`, `meanMemUsage`)
- Network metrics (`networkBytes`)
- Percentile latencies (p50, p90, p99) - use DB Console for visualization

## Instructions

### 1. Understanding Query Resource Metrics

CockroachDB tracks resource consumption metrics in `crdb_internal.statement_statistics` stored as JSON:

**Available in v26.1.0:**
- **Disk I/O:** `rowsRead.mean`, `rowsWritten.mean`, `bytesRead.mean`
- **CPU:** `runLat.mean` (runtime), `svcLat.mean` (service latency), `kvCPUTimeNanos.mean`
- **Execution:** `cnt` (execution count), `numRows.mean` (rows returned), `maxRetries`
- **Timestamp:** `lastExecAt` (last execution time)

All queries require `SET allow_unsafe_internals = true` session setting.

### 2. Analyze Rows Read Versus Rows Returned

The read-to-return ratio indicates query efficiency and index usage.

**Identify queries with poor efficiency ratios:**

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'rowsRead'->'mean')::BIGINT AS avg_rows_read,
  (statistics->'statistics'->'numRows'->'mean')::BIGINT AS avg_rows_returned,
  CASE WHEN (statistics->'statistics'->'numRows'->'mean')::BIGINT > 0
    THEN ROUND((statistics->'statistics'->'rowsRead'->'mean')::FLOAT /
               (statistics->'statistics'->'numRows'->'mean')::FLOAT, 2)
    ELSE 0 END AS read_to_return_ratio,
  (statistics->'statistics'->'cnt')::BIGINT AS executions
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'rowsRead'->'mean')::BIGINT > 0
  AND (statistics->'statistics'->'numRows'->'mean')::BIGINT > 0
ORDER BY read_to_return_ratio DESC
LIMIT 20;
```

**Interpretation:**
- Ratio > 100: Likely missing index or inefficient filtering
- Ratio > 1000: Probable full table scan
- High ratio + high executions = ongoing performance problem

### 3. Monitor CPU Time Per Query

Track CPU consumption and distinguish compute-bound from I/O-bound queries.

**Find highest CPU consumers:**

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 AS avg_cpu_ms,
  (statistics->'statistics'->'svcLat'->'mean')::FLOAT / 1000000 AS avg_service_ms,
  ((statistics->'statistics'->'svcLat'->'mean')::FLOAT -
   (statistics->'statistics'->'runLat'->'mean')::FLOAT) / 1000000 AS avg_wait_ms,
  (statistics->'statistics'->'cnt')::BIGINT AS executions,
  ((statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000) *
    (statistics->'statistics'->'cnt')::FLOAT AS total_cpu_ms,
  (statistics->'statistics'->'kvCPUTimeNanos'->'mean')::FLOAT / 1000000 AS kv_cpu_ms
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'runLat'->'mean')::BIGINT > 0
ORDER BY total_cpu_ms DESC
LIMIT 20;
```

**Patterns:** High CPU% (>80%) = compute-bound, Low CPU% (<20%) = I/O or network-bound.

### 4. Track Disk I/O Operations

Monitor disk reads to identify storage pressure.

**Find queries with highest disk I/O:**

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'bytesRead'->'mean')::FLOAT / (1024*1024) AS avg_mb_read,
  (statistics->'statistics'->'rowsRead'->'mean')::BIGINT AS avg_rows_read,
  (statistics->'statistics'->'cnt')::BIGINT AS executions,
  ((statistics->'statistics'->'bytesRead'->'mean')::FLOAT / (1024*1024)) *
    (statistics->'statistics'->'cnt')::FLOAT AS total_mb_read,
  CASE WHEN (statistics->'statistics'->'rowsRead'->'mean')::BIGINT > 0
    THEN (statistics->'statistics'->'bytesRead'->'mean')::FLOAT /
         (statistics->'statistics'->'rowsRead'->'mean')::FLOAT
    ELSE 0 END AS bytes_per_row_read
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'bytesRead'->'mean')::BIGINT > 0
ORDER BY total_mb_read DESC
LIMIT 20;
```

### 5. Comprehensive Resource Dashboard

Create a complete resource profile for all queries with v26.1.0 available metrics:

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'cnt')::BIGINT AS executions,

  -- CPU
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 AS avg_cpu_ms,
  (statistics->'statistics'->'svcLat'->'mean')::FLOAT / 1000000 AS avg_service_ms,
  (statistics->'statistics'->'kvCPUTimeNanos'->'mean')::FLOAT / 1000000 AS kv_cpu_ms,

  -- I/O
  (statistics->'statistics'->'rowsRead'->'mean')::BIGINT AS avg_rows_read,
  (statistics->'statistics'->'rowsWritten'->'mean')::BIGINT AS avg_rows_written,
  (statistics->'statistics'->'numRows'->'mean')::BIGINT AS avg_rows_returned,
  (statistics->'statistics'->'bytesRead'->'mean')::FLOAT / (1024*1024) AS avg_mb_read,

  -- Retries
  (statistics->'statistics'->'maxRetries')::INT AS max_retries,

  -- Context
  metadata->>'db' AS database,
  metadata->>'appName' AS app_name,
  (statistics->'statistics'->>'lastExecAt')::TIMESTAMPTZ AS last_executed
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'cnt')::BIGINT > 0
ORDER BY (statistics->'statistics'->'svcLat'->'mean')::FLOAT DESC
LIMIT 30;
```

### 6. Identify Multi-Resource Violations

Find queries exceeding multiple thresholds (v26.1.0 compatible):

```sql
SET allow_unsafe_internals = true;

WITH resource_check AS (
  SELECT
    metadata->>'query' AS query,
    (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 AS avg_cpu_ms,
    (statistics->'statistics'->'rowsRead'->'mean')::BIGINT AS avg_rows_read,
    (statistics->'statistics'->'bytesRead'->'mean')::FLOAT / (1024*1024) AS avg_mb_read,
    (statistics->'statistics'->'cnt')::BIGINT AS executions,
    (statistics->'statistics'->'maxRetries')::INT AS max_retries,

    -- Threshold flags (customize these values)
    CASE WHEN (statistics->'statistics'->'runLat'->'mean')::BIGINT > 1000*1000000 THEN 1 ELSE 0 END AS high_cpu,
    CASE WHEN (statistics->'statistics'->'rowsRead'->'mean')::BIGINT > 100000 THEN 1 ELSE 0 END AS high_io,
    CASE WHEN (statistics->'statistics'->'bytesRead'->'mean')::BIGINT > 100*1024*1024 THEN 1 ELSE 0 END AS high_disk,
    CASE WHEN (statistics->'statistics'->'maxRetries')::INT > 5 THEN 1 ELSE 0 END AS high_retries,

    metadata->>'db' AS database
  FROM crdb_internal.statement_statistics
)
SELECT
  query,
  avg_cpu_ms,
  avg_rows_read,
  avg_mb_read,
  max_retries,
  executions,
  (high_cpu + high_io + high_disk + high_retries) AS violations,
  ARRAY_TO_STRING(ARRAY_REMOVE(ARRAY[
    CASE WHEN high_cpu = 1 THEN 'CPU' END,
    CASE WHEN high_io = 1 THEN 'I/O' END,
    CASE WHEN high_disk = 1 THEN 'DISK' END,
    CASE WHEN high_retries = 1 THEN 'RETRIES' END
  ], NULL), ', ') AS violation_types
FROM resource_check
WHERE (high_cpu + high_io + high_disk + high_retries) >= 2
ORDER BY violations DESC, executions DESC;
```

### 7. Set Up Resource Consumption Alerts

Monitor for increases in resource usage over time (v26.1.0 compatible):

```sql
SET allow_unsafe_internals = true;

-- Create baseline snapshot (run periodically)
CREATE TABLE IF NOT EXISTS monitoring.query_resource_baseline AS
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'runLat'->'mean')::BIGINT AS avg_cpu,
  (statistics->'statistics'->'bytesRead'->'mean')::BIGINT AS avg_bytes_read,
  (statistics->'statistics'->'rowsRead'->'mean')::BIGINT AS avg_rows_read,
  (statistics->'statistics'->'cnt')::BIGINT AS executions,
  now() AS captured_at
FROM crdb_internal.statement_statistics;

-- Detect regressions
WITH current AS (
  SELECT
    metadata->>'query' AS query,
    (statistics->'statistics'->'runLat'->'mean')::BIGINT AS avg_cpu,
    (statistics->'statistics'->'bytesRead'->'mean')::BIGINT AS avg_bytes_read,
    (statistics->'statistics'->'rowsRead'->'mean')::BIGINT AS avg_rows_read
  FROM crdb_internal.statement_statistics
),
baseline AS (
  SELECT query,
    AVG(avg_cpu) AS baseline_avg_cpu,
    AVG(avg_bytes_read) AS baseline_avg_bytes_read,
    AVG(avg_rows_read) AS baseline_avg_rows_read
  FROM monitoring.query_resource_baseline
  WHERE captured_at > now() - INTERVAL '7 days'
  GROUP BY query
)
SELECT
  c.query,
  c.avg_cpu / 1000000 AS current_avg_cpu_ms,
  b.baseline_avg_cpu / 1000000 AS baseline_avg_cpu_ms,
  ROUND((c.avg_cpu::FLOAT / NULLIF(b.baseline_avg_cpu, 0) - 1) * 100, 2) AS cpu_increase_pct,
  c.avg_bytes_read / (1024*1024) AS current_avg_mb_read,
  b.baseline_avg_bytes_read / (1024*1024) AS baseline_avg_mb_read,
  ROUND((c.avg_bytes_read::FLOAT / NULLIF(b.baseline_avg_bytes_read, 0) - 1) * 100, 2) AS io_increase_pct
FROM current c
JOIN baseline b ON c.query = b.query
WHERE c.avg_cpu > b.baseline_avg_cpu * 1.5  -- 50% threshold
   OR c.avg_bytes_read > b.baseline_avg_bytes_read * 1.5
ORDER BY cpu_increase_pct DESC NULLS LAST;
```

### 8. Optimization Strategies

Based on v26.1.0 available metrics:

**CPU Optimization:**
- Use prepared statements to reduce parsing overhead
- Optimize WHERE clauses and join conditions
- Run `ANALYZE` to update table statistics
- Consider query rewrite for complex operations

**I/O Optimization:**
- Add indexes on filter columns to reduce `rowsRead`
- Use covering indexes to minimize disk access
- Partition large tables by access patterns
- Monitor `bytesRead` vs `rowsRead` ratio for wide-row issues

**Retry Reduction:**
- Minimize transaction scope and duration
- Avoid cross-region writes when possible
- Use `SELECT FOR UPDATE` to prevent read-write conflicts
- Consider follower reads for stale data tolerance

## Common Patterns

**Daily resource summary:** Aggregate unique queries, executions, total memory, avg CPU
**By application:** Group by `appName` to track resource usage per app
**Hourly trends:** Use `date_trunc('hour')` on `lastExecAt` for time-series analysis

## Troubleshooting

**No statement statistics:** Enable `sql.metrics.statement_details.enabled = true`

**Stale metrics:** Run `SET allow_unsafe_internals = true; SELECT crdb_internal.reset_sql_stats();`

**JSON parsing errors:** Use `COALESCE((statistics->'field')::TEXT::BIGINT, 0)` for safe casting

**Permission denied errors:** All queries require `SET allow_unsafe_internals = true` in v26.1.0

**Type casting errors:** Always cast to FLOAT before arithmetic operations (e.g., `::FLOAT *` not `::BIGINT *`)

**Missing metrics (memory/network):** Not available in v26.1.0 - use DB Console for memory visualization

## Best Practices

1. Capture daily baselines to identify trends and set thresholds
2. Prioritize high-impact queries (resource usage × execution frequency)
3. Configure memory limits and statement timeouts
4. Segment OLTP vs OLAP workloads by application
5. Use EXPLAIN ANALYZE to verify optimization improvements
6. Export metrics to Prometheus/Grafana for real-time monitoring

## Related Skills

- **analyze-slow-queries**: Identify queries with high latency
- **monitor-statement-statistics**: Comprehensive statement statistics guide
- **configure-query-timeouts**: Set timeout and resource limits
- **use-admission-control**: Manage resource allocation
- **monitor-cluster-metrics**: Track cluster-wide resource utilization
- **create-and-manage-indexes**: Optimize I/O with indexes
- **troubleshoot-out-of-memory-errors**: Diagnose OOM conditions
