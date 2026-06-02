---
name: monitor-statement-statistics-using-crdbinternal-tables
description: Query crdb_internal.node_statement_statistics and crdb_internal.cluster_statement_statistics to view query fingerprints, execution counts, mean/max latencies, and resource consumption to identify slow queries and optimization candidates.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - performance
    - monitoring
    - sql-optimization
    - query-analysis
---

# Monitor Statement Statistics Using crdb_internal Tables

## Overview

Query CockroachDB's internal statement statistics tables to monitor query performance, identify slow queries, and find optimization candidates. Statement statistics provide detailed metrics on latency, execution counts, and resource consumption.

**Use when you need to**: Identify slow queries, find high-frequency queries consuming resources, analyze workload patterns, track performance degradation, or correlate DB Console findings with raw data.

## Core Concepts

### Statement Statistics Tables

CockroachDB maintains three primary statement statistics tables:

**1. `crdb_internal.statement_statistics`** (Cluster-wide aggregated)
- Aggregates stats across all nodes
- Most commonly used for cluster-wide analysis
- Automatically combines data from all nodes
- **Use this by default** for most monitoring tasks

**2. `crdb_internal.node_statement_statistics`** (Per-node)
- Shows statistics per individual node
- Useful for identifying node-specific issues
- Includes `node_id` column
- Use when diagnosing uneven query distribution

**3. `crdb_internal.cluster_statement_statistics`** (Cluster-wide)
- Similar to `statement_statistics`
- Legacy table, prefer `statement_statistics`

### Key Concepts

**Query Fingerprint**: Normalized query text with literals replaced by placeholders
```sql
-- Original queries:
SELECT * FROM users WHERE id = 1;
SELECT * FROM users WHERE id = 42;

-- Both become same fingerprint:
SELECT * FROM users WHERE id = _;
```

**Statistics Window**: Stats accumulate since last reset or cluster restart. Not time-bucketed by default.

**JSON Structure**: Most statistics stored in JSONB `statistics` column requiring JSON extraction.

## Instructions

### Step 1: Enable Access to Internal Tables

Statement statistics tables require elevated permissions:

```sql
-- Required for querying crdb_internal tables
SET allow_unsafe_internals = true;
```

**Note**: This setting is session-scoped and must be set each session.

### Step 2: Identify Slow Queries by Mean Latency

Find queries with the highest average latency:

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 AS mean_latency_ms,
  (statistics->'statistics'->'runLat'->'max')::FLOAT / 1000000 AS max_latency_ms,
  (statistics->'statistics'->'cnt')::FLOAT AS execution_count
FROM crdb_internal.statement_statistics
ORDER BY (statistics->'statistics'->'runLat'->'mean')::FLOAT DESC
LIMIT 10;
```

**Output**:
```
                          query                          | mean_latency_ms | max_latency_ms | execution_count
---------------------------------------------------------+-----------------+----------------+-----------------
 SELECT * FROM large_table WHERE status = _              |          8234.5 |        15023.2 |             142
 SELECT COUNT(*) FROM orders WHERE date > _              |          3421.1 |         6234.8 |              89
 UPDATE inventory SET quantity = _ WHERE product_id = _  |          1234.6 |         2341.9 |            1523
```

**Key fields**:
- `runLat.mean`: Average execution time (microseconds)
- `runLat.max`: Maximum execution time (microseconds)
- `cnt`: Number of executions

### Step 3: Find High-Execution Count Queries

Identify queries executed most frequently:

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'cnt')::FLOAT AS execution_count,
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 AS mean_latency_ms,
  ((statistics->'statistics'->'cnt')::FLOAT *
   (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000) AS total_time_ms
FROM crdb_internal.statement_statistics
ORDER BY (statistics->'statistics'->'cnt')::FLOAT DESC
LIMIT 10;
```

**Why this matters**: High-frequency queries multiply small latency issues. A query with 5ms latency executed 100,000 times consumes 500 seconds of cumulative execution time.

### Step 4: Analyze Resource Consumption and Retries

Find memory-intensive queries or queries with high retry rates:

```sql
SET allow_unsafe_internals = true;

-- Memory-intensive queries
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'maxMemUsage')::BIGINT / (1024*1024) AS max_mem_mb,
  (statistics->'statistics'->'cnt')::FLOAT AS execution_count,
  (statistics->'statistics'->'maxRetries')::FLOAT AS max_retries
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'maxMemUsage')::BIGINT > 100*1024*1024  -- > 100MB
   OR (statistics->'statistics'->'maxRetries')::FLOAT > 0
ORDER BY (statistics->'statistics'->'maxMemUsage')::BIGINT DESC
LIMIT 10;
```

**High retries indicate**: Transaction contention, write conflicts, need for optimization.

### Step 5: Filter by Application, Database, or User

Filter statistics using metadata fields:

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  metadata->>'app' AS application,
  metadata->>'db' AS database,
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 AS mean_ms,
  (statistics->'statistics'->'cnt')::FLOAT AS executions
FROM crdb_internal.statement_statistics
WHERE metadata->>'app' = 'myapp'  -- or metadata->>'db' = 'production_db'
ORDER BY (statistics->'statistics'->'runLat'->'mean')::FLOAT DESC
LIMIT 10;
```

### Step 6: Calculate Total Impact (Frequency × Latency)

Identify queries consuming most total CPU time (reveals high-frequency queries):

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'cnt')::FLOAT AS executions,
  round((statistics->'statistics'->'runLat'->'mean')::NUMERIC / 1000000, 2) AS mean_ms,
  round(((statistics->'statistics'->'cnt')::FLOAT *
   (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000)::NUMERIC, 2) AS total_time_ms
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'cnt')::FLOAT > 100  -- Filter low-frequency queries
ORDER BY total_time_ms DESC
LIMIT 10;
```

**Total CPU time** = execution_count × mean_latency. Reveals queries that, while individually fast, consume significant resources due to high frequency.

## Common Patterns

### Pattern 1: Monitoring Specific Query with Mean Latency

Track specific query pattern with latency metrics:

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'cnt')::FLOAT AS executions,
  round((statistics->'statistics'->'runLat'->'mean')::NUMERIC / 1000000, 2) AS mean_ms,
  round((statistics->'statistics'->'runLat'->'max')::NUMERIC / 1000000, 2) AS max_ms
FROM crdb_internal.statement_statistics
WHERE metadata->>'query' LIKE '%SELECT % FROM orders%'
ORDER BY executions DESC;
```

**Latency Metrics**:
- `mean`: Average execution time across all runs
- `max`: Maximum observed execution time

**Note on Percentiles (p50, p99)**: CockroachDB v26.1.0 stores only `mean` and `sqDiff` in the statistics JSONB. Percentile values (p50, p99) are NOT available via `crdb_internal.statement_statistics` queries. For percentile visualization, use the **DB Console UI** at `http://<node>:8080/#/sql-activity` which computes percentiles from the underlying distribution data.

### Pattern 2: Reset Statistics for Fresh Baseline

```sql
SET allow_unsafe_internals = true;

SELECT crdb_internal.reset_sql_stats();
```

**Use after**: Performance fixes, schema changes, or to establish new baseline. Note: Clears all historical data.

### Pattern 3: Export Statistics for Historical Tracking

```sql
-- Create history table (one time)
CREATE TABLE statement_stats_history (
  captured_at TIMESTAMPTZ DEFAULT now(),
  query TEXT,
  execution_count INT,
  mean_latency_ms FLOAT,
  total_time_ms FLOAT,
  PRIMARY KEY (captured_at, query)
);

-- Capture current statistics
INSERT INTO statement_stats_history (query, execution_count, mean_latency_ms, total_time_ms)
SELECT
  metadata->>'query',
  (statistics->'statistics'->'cnt')::FLOAT,
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000,
  ((statistics->'statistics'->'cnt')::FLOAT *
   (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000)
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'cnt')::FLOAT > 10;
```

## Integration with DB Console

The DB Console SQL Activity page (`http://<node-address>:8080/#/sql-activity`) displays the same data from `crdb_internal.statement_statistics` visually.

**When to use each**:
- **DB Console**: Visual exploration, quick diagnostics
- **crdb_internal queries**: Automation, custom reports, scripting, alerting

## Best Practices

### 1. Always Set allow_unsafe_internals

```sql
SET allow_unsafe_internals = true;  -- Required at session start
```

### 2. Focus on Total Impact (Latency × Frequency)

A 1ms query executed 1,000,000 times has more impact than a 100ms query executed 100 times. Sort by `(execution_count * mean_latency_ms)`.

### 3. Filter Low-Frequency Queries

```sql
WHERE (statistics->'statistics'->'cnt')::FLOAT > 100  -- Skip one-off queries
```

### 4. Set Application Names

Enables filtering by application:
```
postgresql://user@host:26257/db?application_name=myapp
```

### 5. Combine with EXPLAIN ANALYZE

Statistics tell you **what** is slow; `EXPLAIN ANALYZE` tells you **why**.

## Troubleshooting

### Error: "allow_unsafe_internals must be true"

Set session variable: `SET allow_unsafe_internals = true;`

### Error: "invalid input syntax for type double precision"

Add NULL check: `WHERE statistics->'statistics'->'runLat'->'mean' IS NOT NULL;`

### No Statistics Appearing

Check if stats exist: `SELECT COUNT(*) FROM crdb_internal.statement_statistics;`

If zero, run some queries or check if stats were recently reset.

### High Memory Usage

Add LIMIT and filter:
```sql
WHERE (statistics->'statistics'->'cnt')::INT > 10 LIMIT 100;
```

## Related Skills

**Monitoring and Alerting**:
- `monitor-statement-statistics` - Basic statement monitoring
- `reset-statement-statistics-for-baseline-analysis` - Clearing statistics for fresh baselines
- `monitor-transaction-contention-metrics` - Analyzing transaction conflicts
- `monitor-memory-usage-and-pressure` - Memory consumption monitoring

**Performance Optimization**:
- `use-explain-to-understand-query-execution-plans` - Analyze query plans
- `use-explain-analyze-to-profile-query-performance` - Profile actual execution
- `identify-slow-queries-using-db-console` - Visual query analysis
- `optimize-queries-based-on-execution-statistics` - Apply optimization techniques

**SQL**:
- `query-system-tables-in-crdb_internal` - Understanding internal tables
- `extract-json-fields-from-crdb_internal-tables` - Advanced JSON querying

## Examples

### Example 1: Daily Performance Report

```sql
SET allow_unsafe_internals = true;

SELECT
  LEFT(metadata->>'query', 80) AS query_preview,
  (statistics->'statistics'->'cnt')::FLOAT AS executions,
  round((statistics->'statistics'->'runLat'->'mean')::NUMERIC / 1000000, 2) AS mean_ms,
  round((statistics->'statistics'->'runLat'->'max')::NUMERIC / 1000000, 2) AS max_ms
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'cnt')::FLOAT > 100
ORDER BY ((statistics->'statistics'->'cnt')::FLOAT *
  (statistics->'statistics'->'runLat'->'mean')::FLOAT) DESC
LIMIT 10;
```

### Example 2: Application-Specific Summary

```sql
SET allow_unsafe_internals = true;

SELECT
  COUNT(*) AS total_queries,
  SUM((statistics->'statistics'->'cnt')::FLOAT) AS total_executions,
  round(AVG((statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000)::NUMERIC, 2) AS avg_latency_ms
FROM crdb_internal.statement_statistics
WHERE metadata->>'app' = 'web-frontend';
```

---

**Version**: 1.1.0
**Last Updated**: March 6, 2026
**Tested Against**: CockroachDB v26.1.0
