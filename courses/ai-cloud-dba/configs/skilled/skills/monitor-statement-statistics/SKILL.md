---
name: monitor-statement-statistics
description: Can query crdb_internal.node_statement_statistics and crdb_internal.cluster_statement_statistics to view query fingerprints, execution counts, mean/max latencies, and resource consumption. Use to identify slow queries and optimization candidates. Use when user says "check query performance", "slow queries".
metadata:
  domain: Monitoring and Alerting
  tags: performance
  blooms_level: Apply
  version: 1.0.0
---

# Monitor Statement Statistics

Monitors query performance to identify slow queries and optimization opportunities.

## Instructions

### Top Slow Queries

```sql
SET allow_unsafe_internals = true;
SELECT
  metadata->>'query' as query,
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 as mean_latency_ms,
  (statistics->'statistics'->'cnt')::INT as execution_count
FROM crdb_internal.statement_statistics
ORDER BY (statistics->'statistics'->'runLat'->'mean')::FLOAT DESC
LIMIT 10;
```

### Memory-Intensive Queries

```sql
SET allow_unsafe_internals = true;
SELECT
  metadata->>'query' as query,
  (statistics->'statistics'->'maxMemUsage')::BIGINT / (1024*1024) as max_mem_mb
FROM crdb_internal.statement_statistics
ORDER BY (statistics->'statistics'->'maxMemUsage')::BIGINT DESC
LIMIT 10;
```

## Alert Thresholds

- **Warning**: Query latency > 1 second
- **Critical**: Query latency > 5 seconds

## Key Metrics

- `runLat.mean`: Average query latency
- `runLat.max`: Maximum query latency
- `maxMemUsage`: Peak memory usage
- `cnt`: Execution count
