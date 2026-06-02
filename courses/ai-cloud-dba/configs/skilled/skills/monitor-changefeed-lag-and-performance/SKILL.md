---
name: monitor-changefeed-lag-and-performance
description: Monitor changefeed backlog and lag using max_behind_nanos metric, query crdb_internal.jobs for details, track emitted messages/bytes, and correlate lag with cluster load
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: active
  related_skills:
    - monitor-changefeed-performance-and-health
    - monitor-changefeed-metrics-in-db-console
    - create-changefeeds-for-change-data-capture
    - query-changefeed-job-metrics
    - monitor-cluster-performance-metrics
  prerequisites:
    - Running CockroachDB cluster with active changefeeds
    - SQL access to cluster
    - Basic understanding of changefeed concepts
    - Execute SET allow_unsafe_internals = true before querying crdb_internal tables
  estimated_time_minutes: 25
  last_updated: "2026-03-06"
  tested_version: v26.1.0
---

# Monitor Changefeed Lag and Performance

## Overview

Changefeed lag monitoring measures how far behind real-time a changefeed is processing table changes. Primary metric is **max_behind_nanos** (maximum lag across all ranges in nanoseconds), complemented by high_water_timestamp tracking and throughput metrics (emitted messages/bytes). This skill covers SQL-based lag monitoring, correlation with cluster load, and alert thresholds.

**Key capabilities:** Query lag via crdb_internal.jobs, calculate lag from high_water_timestamp (NUMERIC nanoseconds), track emitted messages/bytes, correlate with cluster CPU/IO and table write rate, set alert thresholds (e.g., lag > 1 minute).

**Monitoring hierarchy:** DB Console (dashboards) → SQL queries (detailed metrics) → Prometheus/Grafana (alerting).

## Key Lag Metrics

### high_water_timestamp

**Definition:** Latest timestamp for which all table changes have been emitted to sink.

**Lag calculation:** `now() - high_water_timestamp`

**Interpretation:**
- Advancing steadily: Changefeed healthy
- Stalled: Changefeed paused, sink unavailable, or rangefeed closed
- Lagging behind: Falling behind write rate

### max_behind_nanos

**Definition:** Maximum lag (nanoseconds) across all ranges tracked by changefeed.

**Location:** Prometheus metric `changefeed.max_behind_nanos` or DB Console.

**Conversion:**
- 1 second = 1e9 nanos
- 1 minute = 6e10 nanos
- 5 minutes = 3e11 nanos

**Alert thresholds:**
- Real-time CDC: Alert if > 1-5 seconds
- Near-real-time: Alert if > 1 minute
- Batch-like: Alert if > 5 minutes

### Emitted messages and bytes

**Definition:** Rate of change messages and data volume emitted per second.

**Purpose:** Measure changefeed throughput and correlate with table write rate.

**Location:** DB Console Changefeed dashboard or Prometheus metrics.

## Instructions

### Step 1: Query changefeed lag

```sql
-- Enable access to internal tables
SET allow_unsafe_internals = true;

-- View all running changefeeds with lag
-- Note: high_water_timestamp is NUMERIC (nanoseconds since epoch)
SELECT
  job_id,
  status,
  to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS high_water_timestamp,
  now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS lag_duration,
  EXTRACT(EPOCH FROM (now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9))) AS lag_seconds
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND status = 'running'
ORDER BY lag_seconds DESC;

-- Example output:
-- job_id  | status  | high_water_timestamp    | lag_duration | lag_seconds
-- 789...  | running | 2026-03-06 10:29:45 UTC | 00:00:15     | 15.0
```

### Step 2: Query detailed metrics from crdb_internal.jobs

```sql
-- Get detailed job metrics
SELECT
  job_id,
  status,
  to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS high_water_timestamp,
  error,
  coordinator_id,
  modified,
  created
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND status IN ('running', 'paused')
ORDER BY modified DESC;

-- Check for recent errors or status changes
SELECT
  job_id,
  status,
  to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS high_water_timestamp,
  now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS lag,
  error,
  modified
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND (error IS NOT NULL OR status != 'running')
ORDER BY modified DESC;
```

**Diagnostic fields:** `error` (failure message), `modified` (last status change), `coordinator_id` (node running changefeed).

### Step 3: Set up lag alert queries

```sql
-- Alert: Changefeeds lagging > 1 minute
SELECT
  job_id,
  now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS lag,
  EXTRACT(EPOCH FROM (now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9))) AS lag_seconds
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
  AND status = 'running'
  AND now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '1 minute';

-- Combined health check with status classification
SELECT
  job_id,
  status,
  now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS lag,
  CASE
    WHEN status != 'running' THEN 'CRITICAL: Not running'
    WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '5 minutes' THEN 'CRITICAL: Lag > 5 min'
    WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '1 minute' THEN 'WARNING: Lag > 1 min'
    ELSE 'OK'
  END AS health_status,
  error
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
ORDER BY lag DESC NULLS LAST;
```

### Step 4: Track changefeed throughput

```sql
-- Sample high water mark at intervals to calculate processing rate
SELECT
  job_id,
  high_water_timestamp AS hwm_nanos,
  to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS hwm,
  now() AS sample_time
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND job_id = 789123456789;

-- Wait 60 seconds, re-run query
-- Processing rate = (hwm_t2 - hwm_t1) / (sample_t2 - sample_t1)
-- Ratio = 1.0: Keeping up; < 1.0: Falling behind; > 1.0: Catching up
```

**Note:** Emitted messages/bytes metrics best viewed in DB Console Changefeed dashboard.

### Step 5: Correlate lag with cluster write activity

```sql
-- Check cluster-wide write activity
SELECT store_id, writes_per_second, logical_bytes, range_count
FROM crdb_internal.kv_store_status
ORDER BY writes_per_second DESC;

-- Check table-level estimated row counts (for trending)
SELECT table_name, estimated_row_count
FROM crdb_internal.table_row_statistics
WHERE table_name IN ('orders', 'shipments')
ORDER BY estimated_row_count DESC;
```

**Interpretation:** High write rate + low lag = keeping up; high write rate + high lag = sink capacity issue; low write rate + high lag = changefeed/sink problem.

### Step 6: Correlate lag with cluster load

```sql
-- Check cluster CPU metrics (node_metrics uses name-value pairs)
SELECT
  COALESCE(store_id, 0) AS node_id,
  name,
  ROUND(value, 2) AS value
FROM crdb_internal.node_metrics
WHERE name IN (
  'sys.cpu.combined.percent-normalized',
  'sys.cpu.user.percent',
  'sys.cpu.sys.percent'
)
ORDER BY value DESC;

-- Check storage write throughput
SELECT store_id, writes_per_second, logical_bytes, range_count
FROM crdb_internal.kv_store_status
ORDER BY writes_per_second DESC;
```

**DB Console correlation:** Compare CPU/Memory/Disk graphs (Metrics → Overview) with changefeed lag timeline.

### Step 7: Monitor changefeed error rates

```sql
-- View changefeeds with errors
SELECT job_id, status, error, modified, now() - modified AS time_since_error
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND error IS NOT NULL
ORDER BY modified DESC;

-- Track status changes and recent modifications
SELECT
  job_id,
  status,
  error,
  modified,
  created,
  modified - created AS job_age
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND status != 'running'
ORDER BY modified DESC;
```

**Error patterns:** Paused with error (sink rejection/auth failure), failed status (permanent error), high lag + no error (sink backpressure), frequent status changes via modified timestamp.

## Common Patterns

### Pattern 1: Continuous lag monitoring dashboard

```sql
-- Comprehensive health check query (run periodically via cron)
SELECT
  job_id,
  status,
  to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS high_water_timestamp,
  now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS lag_duration,
  EXTRACT(EPOCH FROM (now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9))) AS lag_seconds,
  CASE
    WHEN status != 'running' THEN 'CRITICAL'
    WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '5 minutes' THEN 'CRITICAL'
    WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '1 minute' THEN 'WARNING'
    ELSE 'OK'
  END AS health_status,
  error
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
ORDER BY lag_seconds DESC NULLS LAST;

-- Filter for alerts only
SELECT * FROM (
  SELECT
    job_id,
    status,
    to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS hwt,
    EXTRACT(EPOCH FROM (now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9))) AS lag_seconds,
    CASE
      WHEN status != 'running' THEN 'CRITICAL'
      WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '5 minutes' THEN 'CRITICAL'
      WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '1 minute' THEN 'WARNING'
      ELSE 'OK'
    END AS health_status,
    error
  FROM crdb_internal.jobs
  WHERE job_type = 'CHANGEFEED'
) WHERE health_status IN ('CRITICAL', 'WARNING');
```

### Pattern 2: Multi-changefeed health check

```sql
SELECT
  job_id,
  status,
  now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) AS lag,
  CASE
    WHEN status = 'failed' THEN 'CRITICAL: Failed'
    WHEN status = 'paused' AND error IS NOT NULL THEN 'CRITICAL: Paused with error'
    WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '5 minutes' THEN 'CRITICAL: Lag > 5min'
    WHEN now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9) > INTERVAL '1 minute' THEN 'WARNING: Lag > 1min'
    ELSE 'OK'
  END AS health_status,
  error,
  modified
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND status IN ('running', 'paused', 'failed')
ORDER BY lag DESC NULLS LAST;
```

### Pattern 3: Automated alerting integration

```sql
-- Query for Prometheus exporter or monitoring script (run every 30-60 seconds)
SELECT
  job_id,
  EXTRACT(EPOCH FROM (now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9))) AS lag_seconds,
  CASE WHEN status = 'running' THEN 1 ELSE 0 END AS is_running,
  CASE WHEN error IS NOT NULL THEN 1 ELSE 0 END AS has_error
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND status IN ('running', 'paused');
```

**Alerting rules:** Alert lag_seconds > 60, Critical lag_seconds > 300, Warning is_running = 0, Critical has_error = 1.

## Troubleshooting

### Issue: High water mark not advancing

**Symptoms:** `high_water_timestamp` stalled, lag increasing.

**Causes:** Sink unavailable (Kafka down, webhook unreachable, storage auth failed), rangefeed closed (schema change, node failure), backfill in progress.

**Solutions:** Fix sink connectivity then `RESUME JOB <job_id>`, wait for backfill completion, check cluster stability.

### Issue: Lag consistently > 1 minute despite healthy cluster

**Cause:** Sink throughput < table write rate (backpressure).

**Solutions:** Scale sink (add Kafka partitions, webhook replicas), filter changefeed with `WITH filter = 'status = "completed"'`, use `envelope = 'key_only'`.

### Issue: Changefeed status frequently changing

**Symptoms:** modified timestamp changing frequently, status alternating between running/paused.

**Causes:** Schema changes (ALTER TABLE triggers rangefeed closure), node failures (coordinator crashes), sink transient errors.

**Solutions:** Use `WITH schema_change_policy = 'nobackfill'`, configure `WITH on_error = 'pause'`, check error field for patterns.

### Issue: Lag spikes during cluster maintenance

**Cause:** Changefeed coordinator relocation, rangefeed restarts during node restarts/upgrades.

**Solution:** Allow 5-10 minutes catch-up post-maintenance, or pause changefeeds with `PAUSE JOB <id>` before maintenance, then `RESUME JOB <id>`.

## Best Practices

### 1. Set lag thresholds based on use case

| Use Case | Max Acceptable Lag | Alert Threshold |
|----------|-------------------|-----------------|
| Real-time cache invalidation | 1-5 seconds | 10 seconds |
| Event-driven microservices | 10-30 seconds | 1 minute |
| Analytics data warehouse sync | 5-15 minutes | 30 minutes |
| Audit log replication | 1-5 minutes | 10 minutes |

### 2. Monitor lag continuously with automated polling

Set up periodic monitoring (every 30-60 seconds) via cron job or monitoring script that queries lag and alerts on threshold violations.

### 3. Track both lag and throughput

- Lag increasing + low throughput: Changefeed stuck
- Lag increasing + high throughput: Sink can't keep up
- Lag stable + high throughput: Processing backlog
- Lag decreasing + high throughput: Catching up

### 4. Correlate lag with cluster health

```sql
SELECT
  (SELECT count(*) FROM crdb_internal.gossip_liveness WHERE expiration < now()) AS dead_nodes,
  (SELECT max(EXTRACT(EPOCH FROM (now() - to_timestamp(high_water_timestamp::DECIMAL / 1e9))))
   FROM crdb_internal.jobs WHERE job_type = 'CHANGEFEED' AND status = 'running') AS max_lag_seconds;
```

### 5. Use resolved timestamps for progress tracking

Use `WITH resolved = '10s'` to emit progress markers every 10 seconds. If resolved timestamps stop advancing, rangefeed is closed.

### 6. Document baseline performance

Sample lag over time to establish baseline average/max. Alert when lag exceeds 2x baseline average.

### 7. Implement multi-tier alerting

- Warning: Lag > 1 minute OR error IS NOT NULL
- Critical: Lag > 5 minutes OR status != running

### 8. Monitor job status changes

Track `modified` timestamp from crdb_internal.jobs. Frequent updates indicate instability from schema changes, node failures, or sink errors.

### 9. Test lag during peak load

Insert test load bursts and monitor lag impact to verify changefeed can handle peak write rates.

### 10. Integrate with cluster monitoring

Export changefeed metrics to Prometheus/Grafana: `changefeed.max_behind_nanos`, lag, throughput, restart count. Set up alerts for critical thresholds.

## Key Takeaways

- **Primary lag metric:** `high_water_timestamp` lag = `now() - high_water_timestamp`
- **max_behind_nanos:** Prometheus metric showing max lag across ranges (1e9 nanos = 1 second)
- **Alert threshold:** Lag > 1 minute (warning), > 5 minutes (critical)
- **Query tools:** Query `crdb_internal.jobs` with `job_type = 'CHANGEFEED'` for all monitoring
- **Throughput tracking:** Sample `high_water_timestamp` at intervals to measure processing rate
- **Lag causes:** Sink backpressure, cluster overload, rangefeed closures, schema changes
- **Correlation:** Always correlate changefeed lag with cluster CPU/IO and write throughput
- **Capacity planning:** Processing rate < 1.0 indicates insufficient sink capacity
- **Status monitoring:** Track `modified` timestamp for frequent status changes indicating instability
- **Best practice:** Set use-case-specific lag thresholds and automate continuous monitoring
- **Important:** high_water_timestamp is NUMERIC (nanoseconds), convert with `to_timestamp(value::DECIMAL / 1e9)`
