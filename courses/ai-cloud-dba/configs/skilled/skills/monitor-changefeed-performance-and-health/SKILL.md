---
name: monitor-changefeed-performance-and-health
description: Monitor changefeed health using SHOW CHANGEFEED JOBS, DB Console metrics, high water mark lag, and sink-specific indicators
metadata:
  domain: Data Management
  bloom_level: Evaluate
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: active
---

# Monitor changefeed performance and health

**Domain**: Data Management
**Bloom's Level**: Evaluate

## What This Skill Teaches

You will learn to monitor changefeed health and performance using SQL commands (SHOW CHANGEFEED JOBS), DB Console dashboards (throughput, latency), high water mark tracking (lag between database and changefeed), and sink-specific metrics (Kafka broker lag, webhook response times). You'll understand common issues like sink unavailability, high latency, and schema change impacts, and how to use PAUSE/RESUME JOB for maintenance.

**Key Concepts**:
- SHOW CHANGEFEED JOBS for status and high water mark
- DB Console changefeed dashboard for throughput and latency
- Resolved timestamps as progress indicators
- Lag calculation: current time vs. high water mark
- Sink-specific metrics (Kafka, webhook, cloud storage)

## Prerequisites

Before starting, ensure:
- Active changefeeds running in cluster
- Access to DB Console (http://localhost:8080 or cluster URL)
- SQL access to CockroachDB cluster

**Related Skills**:
- `create-changefeeds-for-change-data-capture` - Create changefeeds to monitor
- `configure-changefeed-sinks-and-options` - Configure changefeed options
- `understand-changefeed-message-formats-and-envelopes` - Understand resolved timestamps

## Instructions

### Step 1: View changefeed jobs

```sql
-- List all changefeed jobs
SHOW CHANGEFEED JOBS;

-- Output columns:
-- job_id: Unique job identifier
-- description: Changefeed configuration
-- user_name: User who created changefeed
-- status: running, paused, failed, canceled
-- running_status: Detailed status (e.g., "running: 3 ranges")
-- created: Creation timestamp
-- started: Start timestamp
-- finished: Completion timestamp (for completed jobs)
-- modified: Last modified timestamp
-- fraction_completed: Progress (0.0 to 1.0)
-- high_water_timestamp: Latest emitted change timestamp
-- error: Error message (if failed)
-- sink_uri: Destination sink
```

### Step 2: Monitor high water mark and lag

```sql
-- Calculate lag between current time and high water mark
SELECT
  job_id,
  status,
  high_water_timestamp,
  now() - high_water_timestamp AS lag,
  running_status
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';

-- Example output:
-- job_id  | status  | high_water_timestamp    | lag      | running_status
-- --------+---------+-------------------------+----------+-----------------
-- 789...  | running | 2024-01-15 10:30:00 UTC | 00:00:05 | running: 25 ranges

-- Alert if lag > 1 minute
SELECT job_id, now() - high_water_timestamp AS lag
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running'
  AND now() - high_water_timestamp > INTERVAL '1 minute';
```

High water mark = latest timestamp for which all changes have been emitted.

### Step 3: Check changefeed status and errors

```sql
-- View detailed changefeed status
SELECT
  job_id,
  status,
  running_status,
  error
FROM [SHOW CHANGEFEED JOBS]
WHERE job_id = 789123456789;

-- Common statuses:
-- running: Actively emitting changes
-- paused: Manually paused or paused due to error (on_error='pause')
-- failed: Job failed (on_error='fail')
-- canceled: Manually canceled

-- View recent job errors
SELECT job_id, status, error, modified
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'paused'
  AND error IS NOT NULL
ORDER BY modified DESC
LIMIT 10;
```

### Step 4: Monitor changefeed progress with resolved timestamps

```sql
-- Check if resolved timestamps are being emitted
-- (requires changefeed created WITH resolved option)

-- Create changefeed with resolved timestamps
CREATE CHANGEFEED FOR TABLE orders
INTO 'kafka://broker:9092'
WITH resolved = '10s';

-- Monitor resolved timestamp progress
-- Resolved timestamps appear as special messages in sink
-- If resolved timestamps stop advancing, changefeed may be stuck
```

Resolved timestamp = watermark indicating all changes before timestamp have been emitted.

### Step 5: View changefeed metrics in DB Console

Navigate to DB Console > Changefeeds dashboard:

**Key metrics**:
- **Commit Latency**: Time from transaction commit to message emission
- **Emitted Bytes**: Throughput in bytes per second
- **Emitted Messages**: Message rate per second
- **Restart Count**: Number of changefeed restarts
- **Max Behind Nanos**: Maximum lag across all ranges (changefeed.max_behind_nanos)

**Access DB Console**:
```bash
# Open DB Console in browser
# Default: http://localhost:8080
# Or cluster load balancer URL
```

### Step 6: Query changefeed metrics from system tables

```sql
-- View changefeed job details
SELECT * FROM crdb_internal.jobs WHERE job_type = 'CHANGEFEED';

-- Track changefeed progress over time
SELECT
  job_id,
  status,
  high_water_timestamp,
  modified
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
ORDER BY modified DESC;

-- Calculate message emission rate (requires time-series data)
-- Track high_water_timestamp progress over time intervals
```

### Step 7: Pause and resume changefeeds for maintenance

```sql
-- Pause changefeed
PAUSE JOB 789123456789;

-- Verify paused
SELECT job_id, status FROM [SHOW CHANGEFEED JOBS] WHERE job_id = 789123456789;

-- Perform maintenance (e.g., schema changes, sink updates)

-- Resume changefeed
RESUME JOB 789123456789;

-- Verify resumed and catching up
SELECT job_id, status, now() - high_water_timestamp AS lag
FROM [SHOW CHANGEFEED JOBS]
WHERE job_id = 789123456789;
```

### Step 8: Monitor sink-specific metrics

**Kafka sinks**:
- Monitor Kafka broker lag (consumer group lag)
- Check topic partition distribution
- Track Kafka broker CPU/memory/disk

```bash
# Check Kafka consumer group lag (external tool)
kafka-consumer-groups --bootstrap-server broker:9092 \
  --group cdc-consumer-group --describe
```

**Webhook sinks**:
- Monitor webhook endpoint response times
- Track HTTP error rates (4xx, 5xx)
- Check webhook endpoint availability

**Cloud storage sinks**:
- Monitor file creation rate
- Track bucket write throughput
- Check for write errors (permissions, quotas)

## Common Patterns

### Pattern 1: Continuous lag monitoring

Track changefeed lag over time:

```sql
-- Create view for lag monitoring
CREATE VIEW changefeed_lag AS
SELECT
  job_id,
  status,
  high_water_timestamp,
  now() - high_water_timestamp AS lag_duration,
  EXTRACT(EPOCH FROM (now() - high_water_timestamp)) AS lag_seconds
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';

-- Query lag
SELECT * FROM changefeed_lag ORDER BY lag_seconds DESC;
```

### Pattern 2: Automated alerting

Alert on changefeed issues:

```sql
-- Alert query (run periodically via monitoring tool)
SELECT
  job_id,
  'High lag' AS alert_type,
  now() - high_water_timestamp AS lag
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running'
  AND now() - high_water_timestamp > INTERVAL '5 minutes'

UNION ALL

SELECT
  job_id,
  'Paused/Failed' AS alert_type,
  NULL AS lag
FROM [SHOW CHANGEFEED JOBS]
WHERE status IN ('paused', 'failed');
```

### Pattern 3: Restart detection

Track changefeed restarts:

```bash
# Monitor DB Console changefeed restart count metric
# Frequent restarts indicate issues:
# - Schema changes
# - Node failures
# - Sink connectivity problems
```

### Pattern 4: Throughput monitoring

Track message emission rate:

```sql
-- Sample high water mark at intervals
-- Time T1:
SELECT job_id, high_water_timestamp AS hwm_t1
FROM [SHOW CHANGEFEED JOBS] WHERE job_id = 789123456789;

-- Time T2 (e.g., 1 minute later):
SELECT job_id, high_water_timestamp AS hwm_t2
FROM [SHOW CHANGEFEED JOBS] WHERE job_id = 789123456789;

-- Calculate throughput:
-- Rows emitted = count of changes between hwm_t1 and hwm_t2
-- Throughput = rows / (T2 - T1)
```

### Pattern 5: Multi-changefeed dashboard

Monitor all changefeeds:

```sql
-- Summary dashboard query
SELECT
  job_id,
  status,
  running_status,
  now() - high_water_timestamp AS lag,
  CASE
    WHEN now() - high_water_timestamp < INTERVAL '1 minute' THEN 'healthy'
    WHEN now() - high_water_timestamp < INTERVAL '5 minutes' THEN 'warning'
    ELSE 'critical'
  END AS health_status,
  error
FROM [SHOW CHANGEFEED JOBS]
WHERE status IN ('running', 'paused')
ORDER BY lag DESC;
```

## Troubleshooting

### Issue: High water mark not advancing

**Symptoms**: `high_water_timestamp` stuck, lag increasing.
**Causes**: Sink unavailable, sink backpressure, rangefeed closed (schema change/node failure).
**Solution**: Check job status/error, fix sink issue, resume changefeed. Wait for backfill completion after schema changes.

### Issue: Changefeed paused with error

**Symptoms**: `status='paused'`, error message present.
**Cause**: Sink error with `on_error='pause'`.
**Solution**: View error (`SELECT job_id, error FROM [SHOW CHANGEFEED JOBS]`), fix issue (connection refused, auth failed, timeout), resume job.

### Issue: High lag despite healthy cluster

**Cause**: Sink cannot keep up with write rate.
**Solution**: Scale sink (add Kafka partitions/webhook replicas), filter changefeed (`WITH WHERE`), use `envelope='key_only'`.

### Issue: Frequent changefeed restarts

**Cause**: Schema changes or node failures.
**Solution**: Monitor restart count metric, batch schema changes, use `schema_change_policy='nobackfill'`, investigate cluster stability.

### Issue: Resolved timestamps not advancing

**Cause**: Write-heavy workload or rangefeed closed.
**Solution**: Check if writes ongoing, verify rangefeed enabled, check logs for rangefeed closures.

### Issue: Kafka consumer group lag increasing

**Cause**: Downstream consumers too slow.
**Solution**: Scale Kafka consumers (not changefeed), check consumer group lag, add consumer instances.

## Best Practices

### 1. Monitor high water mark lag continuously
Set up automated monitoring to alert if lag exceeds threshold (e.g., 5 minutes).

### 2. Use resolved timestamps for progress tracking
Enable `resolved='10s'` to emit progress markers every 10 seconds.

### 3. Track changefeed restart count
High restart count indicates schema changes, node failures, or sink errors. Monitor in DB Console.

### 4. Configure on_error='pause' for production
Prevent silent failures by pausing on error for manual investigation.

### 5. Set lag thresholds per use case
Real-time analytics: < 1 minute; cache invalidation: < 5 seconds; data warehouse: < 1 hour.

### 6. Monitor sink-specific metrics
Track Kafka broker lag, webhook response times, and cloud storage throughput alongside changefeed metrics.

### 7. Use DB Console for visual monitoring
View real-time throughput graphs, commit latency histograms, restart trends, and per-changefeed details.

### 8. Implement health check queries
Create periodic health check query that returns rows only when changefeeds are paused or lag exceeds threshold.

### 9. Document changefeed baseline performance
Establish baseline metrics (normal lag, throughput, restart frequency) and alert on deviations.

### 10. Coordinate monitoring with sink monitoring
Correlate changefeed lag with sink metrics to identify whether issue is changefeed or sink capacity.

## Key Takeaways

- Use SHOW CHANGEFEED JOBS to view status, high water mark, and errors
- High water mark = latest timestamp for which all changes emitted
- Lag = current time - high water mark (alert if > threshold)
- Resolved timestamps provide progress markers (require `WITH resolved` option)
- DB Console provides throughput, latency, and restart count metrics
- Common issues: sink unavailable (pause), high latency (backpressure), schema changes (restart)
- Use PAUSE JOB/RESUME JOB for maintenance
- Monitor sink-specific metrics (Kafka lag, webhook response times, cloud storage throughput)
- Set on_error='pause' to investigate errors before data loss
- Track changefeed restart count to detect instability
