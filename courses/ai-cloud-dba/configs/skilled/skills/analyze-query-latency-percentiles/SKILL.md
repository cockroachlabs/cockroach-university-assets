---
name: analyze-query-latency-percentiles
description: Analyze query latency using mean, max, and min metrics from statement statistics; percentile data (p50/p90/p99) only available in DB Console UI
metadata:
  domain: Monitoring and Alerting
  bloom_level: Analyze
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: stable
  author: CockroachDB University
  tags:
    - monitoring
    - performance
    - latency
    - statement-statistics
    - sla
    - db-console
---

# Analyze Query Latency Metrics

**Domain**: Monitoring and Alerting
**Bloom's Level**: Analyze
**CockroachDB Version**: v26.1.0+

## IMPORTANT: Percentile Data Availability in v26.1.0

**CRITICAL LIMITATION**: CockroachDB v26.1.0 does NOT expose percentile fields (p50/p90/p99/p99.9) via SQL queries in the `crdb_internal.statement_statistics` table.

**Available SQL metrics:**
- `runLat.mean` - Mean latency (average)
- `runLat.sqDiff` - Sum of squared differences (for variance calculation)
- `latencyInfo.max` - Maximum observed latency
- `latencyInfo.min` - Minimum observed latency

**To view percentiles:**
- Navigate to DB Console at `http://localhost:8080/#/sql-activity`
- Click on individual SQL statements to see p50/p90/p99 percentile graphs
- Percentiles are computed and displayed graphically but cannot be queried programmatically via SQL

This skill focuses on analyzing latency using available SQL metrics (mean/max/min) and understanding latency variance patterns.

## What This Skill Teaches

This skill teaches you to extract and analyze latency metrics from CockroachDB's statement statistics using mean, maximum, and minimum values to identify slow queries, establish SLA compliance, and diagnose performance issues. You'll learn to detect latency variance and outliers using available metrics, and when to use DB Console for percentile visualization.

## Understanding Latency Metrics and Variance

Mean (average) latency can obscure critical problems. Example: 95 requests at 10ms and 5 at 2000ms yields mean=109.5ms (looks acceptable), but 5% of users suffer 2-second delays.

**Available metrics in v26.1.0:**
- **Mean latency**: Average latency across all executions (can mask outliers)
- **Max latency**: Worst-case latency observed (reveals extreme outliers)
- **Min latency**: Best-case latency (baseline performance)
- **Latency range** (max - min): Indicates variance and consistency

**Detecting variance patterns:**
- **High max/mean ratio** (>5): Indicates tail latency issues (some queries extremely slow)
- **Large latency range**: Suggests inconsistent performance
- **Mean approaching max**: Consistent but uniformly slow queries

**SLA best practices:** While percentiles are ideal (`p99 < 200ms`), you can approximate using `mean < 50ms AND max < 500ms` thresholds. For precise percentile tracking, use DB Console graphs.

## Extracting Latency Data from Statement Statistics

CockroachDB stores latency data in the `statistics` JSONB column. All latency values are in **microseconds** (μs)—divide by 1,000,000 for seconds or 1,000 for milliseconds.

```sql
-- Extract mean, max, min latency with application context
SELECT
  metadata->>'query' AS query,
  metadata->>'db' AS database,
  metadata->>'applicationName' AS app_name,
  (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 AS mean_latency_ms,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000 AS max_latency_ms,
  (statistics->'statistics'->'latencyInfo'->>'min')::FLOAT / 1000 AS min_latency_ms,
  (statistics->'statistics'->>'cnt')::INT AS executions,
  -- Calculate variance indicator
  ROUND(
    (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT /
    NULLIF((statistics->'statistics'->'runLat'->>'mean')::FLOAT, 0),
    2
  ) AS max_to_mean_ratio
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->>'cnt')::INT > 50
  AND (statistics->'statistics'->'runLat'->>'mean')::FLOAT > 0
ORDER BY mean_latency_ms DESC
LIMIT 20;
```

**Note:** High `max_to_mean_ratio` (>5) indicates significant tail latency variance.

## Identifying Queries with High Latency Variance

A high max/mean ratio indicates significant tail latency variance (some executions much slower than average):

```sql
-- Queries with concerning latency variance
WITH latency_data AS (
  SELECT
    metadata->>'query' AS query,
    (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 AS mean_ms,
    (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000 AS max_ms,
    (statistics->'statistics'->'latencyInfo'->>'min')::FLOAT / 1000 AS min_ms,
    (statistics->'statistics'->>'cnt')::INT AS executions
  FROM crdb_internal.statement_statistics
  WHERE (statistics->'statistics'->>'cnt')::INT > 100
    AND (statistics->'statistics'->'runLat'->>'mean')::FLOAT > 0
)
SELECT
  query,
  mean_ms,
  max_ms,
  min_ms,
  max_ms - min_ms AS latency_range_ms,
  ROUND(max_ms / NULLIF(mean_ms, 0), 2) AS max_to_mean_ratio,
  executions,
  CASE
    WHEN max_ms / NULLIF(mean_ms, 0) > 10 THEN 'CRITICAL - Extreme variance'
    WHEN max_ms / NULLIF(mean_ms, 0) > 5 THEN 'WARNING - High variance'
    WHEN max_ms / NULLIF(mean_ms, 0) > 2 THEN 'NOTICE - Moderate variance'
    ELSE 'OK - Consistent performance'
  END AS assessment
FROM latency_data
WHERE mean_ms > 0
ORDER BY max_to_mean_ratio DESC
LIMIT 30;
```

**Interpretation:**
- Ratio < 2 (consistent performance)
- 2-5 (acceptable variance)
- 5-10 (investigate for contention or resource issues)
- >10 (critical - likely lock contention, network timeouts, or GC pauses)

## Comparing Latency Across Applications

```sql
-- Compare latency metrics by application
SELECT
  metadata->>'applicationName' AS application,
  COUNT(*) AS unique_queries,
  SUM((statistics->'statistics'->>'cnt')::INT) AS total_executions,
  ROUND(AVG((statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000), 2) AS avg_mean_latency_ms,
  ROUND(MAX((statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000), 2) AS worst_max_latency_ms,
  ROUND(AVG(
    (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT /
    NULLIF((statistics->'statistics'->'runLat'->>'mean')::FLOAT, 0)
  ), 2) AS avg_variance_ratio
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->>'cnt')::INT > 10
  AND (statistics->'statistics'->'runLat'->>'mean')::FLOAT > 0
GROUP BY application
ORDER BY avg_mean_latency_ms DESC;
```

**Analysis:** Applications with high `avg_variance_ratio` (>5) have inconsistent performance requiring investigation.

## Identifying Outlier Queries and Latency Spikes

### Latency Spike Detection

```sql
-- Identify queries with extreme latency outliers
WITH latency_analysis AS (
  SELECT
    metadata->>'query' AS query,
    (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 AS mean_ms,
    (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000 AS max_ms,
    (statistics->'statistics'->'latencyInfo'->>'min')::FLOAT / 1000 AS min_ms,
    (statistics->'statistics'->>'cnt')::INT AS executions,
    (statistics->'statistics'->'numRows'->>'mean')::FLOAT AS avg_rows
  FROM crdb_internal.statement_statistics
  WHERE (statistics->'statistics'->>'cnt')::INT > 50
    AND (statistics->'statistics'->'runLat'->>'mean')::FLOAT > 0
)
SELECT
  query,
  mean_ms,
  max_ms,
  min_ms,
  executions,
  avg_rows,
  ROUND((max_ms - mean_ms) / NULLIF(mean_ms, 0) * 100, 1) AS max_deviation_pct,
  ROUND((max_ms - min_ms), 1) AS total_range_ms
FROM latency_analysis
WHERE max_ms > mean_ms * 3  -- Max is 3x higher than mean
ORDER BY max_deviation_pct DESC
LIMIT 20;
```

**Common patterns causing high max latency:**
- Lock contention (max >> mean)
- Network timeouts (extreme max values)
- GC pauses (periodic max spikes)
- Resource exhaustion (mean gradually approaching max)
- Cold cache (first execution much slower)

## Setting Latency SLA Thresholds

Define SLA thresholds by workload type using mean and max latency. Example targets:
- **Interactive**: mean < 50ms, max < 500ms
- **API**: mean < 100ms, max < 1000ms
- **Batch**: mean < 5s, max < 30s

```sql
-- Check SLA violations (example: mean > 100ms OR max > 500ms)
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 AS mean_latency_ms,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000 AS max_latency_ms,
  CASE
    WHEN (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000 > 500
      OR (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 > 100
      THEN 'SLA VIOLATION'
    WHEN (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000 > 400
      OR (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 > 80
      THEN 'WARNING'
    ELSE 'COMPLIANT'
  END AS sla_status,
  (statistics->'statistics'->>'cnt')::INT AS executions
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->>'cnt')::INT > 50
  AND (statistics->'statistics'->'runLat'->>'mean')::FLOAT > 0
ORDER BY mean_latency_ms DESC;
```

**Note:** For percentile-based SLAs (e.g., "p99 < 200ms"), monitor the DB Console graphs since percentiles are not queryable via SQL.

## Time-Series Analysis of Latency Trends

```sql
-- Detect latency degradation (compare recent vs baseline)
WITH recent AS (
  SELECT
    metadata->>'query' AS query,
    AVG((statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000) AS mean_ms,
    MAX((statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000) AS max_ms
  FROM crdb_internal.statement_statistics
  WHERE aggregated_ts > NOW() - INTERVAL '1 hour'
  GROUP BY query
),
baseline AS (
  SELECT
    metadata->>'query' AS query,
    AVG((statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000) AS mean_ms,
    MAX((statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000) AS max_ms
  FROM crdb_internal.statement_statistics
  WHERE aggregated_ts BETWEEN NOW() - INTERVAL '48h' AND NOW() - INTERVAL '24h'
  GROUP BY query
)
SELECT
  r.query,
  r.mean_ms AS current_mean,
  b.mean_ms AS baseline_mean,
  r.max_ms AS current_max,
  b.max_ms AS baseline_max,
  ROUND((r.mean_ms - b.mean_ms) / NULLIF(b.mean_ms, 0) * 100, 1) AS mean_change_pct,
  ROUND((r.max_ms - b.max_ms) / NULLIF(b.max_ms, 0) * 100, 1) AS max_change_pct
FROM recent r JOIN baseline b ON r.query = b.query
WHERE r.mean_ms > b.mean_ms * 1.5  -- 50% degradation in mean latency
ORDER BY mean_change_pct DESC
LIMIT 20;
```

**Use cases:**
- Detect gradual performance degradation (mean increasing)
- Identify new latency spikes (max increasing)
- Compare current vs historical performance baselines

## Viewing Percentiles in DB Console

**IMPORTANT:** Since percentiles (p50/p90/p99) are NOT available via SQL queries in v26.1.0, you must use the DB Console for percentile visualization:

1. Navigate to `http://localhost:8080/#/sql-activity` (or your cluster's DB Console URL)
2. Click the "Statements" tab to view all SQL statements
3. Click on any individual statement to see detailed metrics
4. View percentile graphs showing:
   - **p50 (median)** latency over time
   - **p90** latency (90th percentile)
   - **p99** latency (99th percentile)
5. Graphs display latency distribution and trends visually

The DB Console computes percentiles from the underlying histogram data but does not expose these values in the SQL-queryable `statement_statistics` table.

## Best Practices for Latency Monitoring

1. **Monitor mean AND max latency**: Mean shows typical performance, max reveals worst-case outliers
2. **Track variance ratios**: max/mean ratio >5 indicates inconsistent performance requiring investigation
3. **Weight by execution volume**: High-frequency queries with moderate mean latency can have greater impact than low-frequency queries with extreme max latency
4. **Set dual-threshold alerts**:
   - Absolute thresholds (mean > 100ms OR max > 500ms)
   - Regression detection (mean > baseline * 1.5)
   - Variance ratios (max/mean > 10)
5. **Use DB Console for percentiles**: For precise p50/p90/p99 tracking, monitor DB Console graphs at `http://localhost:8080/#/sql-activity`
6. **Correlate with system metrics**: Investigate spikes alongside CPU, disk IOPS, network latency, GC pauses, rebalancing
7. **Use appropriate time windows**: 1h (acute issues), 24h (daily patterns), 7d (baseline)
8. **Filter low-volume queries**: Require 50-100+ executions for statistical significance

## Troubleshooting High Latency and Variance

**Diagnostic steps:**

1. **Identify slow queries** by mean latency and high max/mean ratios (queries above)
2. **Check execution plans**: Use `EXPLAIN (ANALYZE)` to find full table scans, high row counts, index joins
3. **Analyze retry statistics**: High `maxRetries` in statement statistics suggests lock contention
4. **Review latency range**: Large latency range (max - min) indicates inconsistent performance
5. **Check DB Console percentiles**: View p50/p90/p99 graphs for tail latency patterns
6. **Identify hot ranges**: Query `crdb_internal.ranges_no_leases` for high QPS ranges
7. **Monitor system metrics**: Correlate latency spikes with CPU, disk I/O, network latency

**Common remediation:**

**For high mean latency (slow on average):**
- Add indexes for full table scans
- Optimize query predicates for index usage
- Review execution plans for inefficient joins
- Consider query rewriting or denormalization

**For high max latency (extreme outliers):**
- Reduce transaction scope to minimize lock duration
- Use `AS OF SYSTEM TIME` for historical reads to reduce contention
- Split hot ranges to distribute load
- Adjust `sql.defaults.statement_timeout` to limit outliers
- Review schema for hotspot patterns (sequential keys, single-range writes)
- Investigate GC pauses or resource exhaustion

**For high variance (max/mean > 5):**
- Analyze lock contention patterns
- Check for network timeouts or transient failures
- Review application retry logic
- Monitor cluster rebalancing activity

## Instructions

When the user invokes this skill, guide them through latency analysis:

1. **Extract current latency metrics** from statement statistics (mean, max, min)
2. **Calculate variance indicators** (max/mean ratio, latency range)
3. **Identify queries violating SLA thresholds** or showing high variance
4. **Compare current metrics to historical baselines** to detect regressions
5. **Direct users to DB Console** for percentile visualization when needed
6. **Provide actionable recommendations** based on latency patterns

**Important reminders:**
- Always clarify that percentiles (p50/p90/p99) are NOT queryable via SQL in v26.1.0
- Direct users to DB Console at `http://localhost:8080/#/sql-activity` for percentile graphs
- Focus analysis on mean/max/min metrics and variance ratios
- Explain findings in terms of user impact (e.g., "worst-case latency is 10x higher than average")

## Related Skills

- **monitor-statement-statistics**: Understanding the statement_statistics table structure
- **optimize-slow-queries**: Using percentile data to prioritize query optimization
- **analyze-transaction-contention**: Investigating high p99/p50 ratios from lock contention
- **troubleshoot-hot-ranges**: Resolving hot spots causing tail latency
- **query-performance-tuning**: Applying indexes and query rewrites to reduce percentiles
- **monitor-cluster-metrics**: Correlating percentile spikes with system-level metrics

## Summary

Latency analysis in CockroachDB v26.1.0 requires understanding both SQL-queryable metrics and DB Console visualization. While percentiles (p50/p90/p99) are NOT available via SQL queries, you can effectively analyze performance using mean, max, and min latency metrics. Key insights:

**Available SQL metrics:**
- Mean latency shows typical performance but can mask outliers
- Max latency reveals worst-case experiences
- Variance ratios (max/mean > 5) indicate inconsistent performance from contention or resource issues

**For percentile analysis:**
- Use DB Console at `http://localhost:8080/#/sql-activity` to view p50/p90/p99 graphs
- Percentiles are computed and displayed visually but not queryable via SQL

**Best practices:**
- Monitor both mean (typical) and max (worst-case) latency
- Set dual SLA thresholds: mean < Xms AND max < Yms
- Use variance ratios to detect tail latency problems
- Combine SQL analysis with DB Console percentile graphs for complete visibility
- Correlate latency spikes with system metrics (CPU, disk, network)

This hybrid approach provides comprehensive latency monitoring despite schema limitations.
