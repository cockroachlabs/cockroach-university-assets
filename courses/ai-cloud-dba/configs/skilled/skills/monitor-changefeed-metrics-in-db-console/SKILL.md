---
name: monitor-changefeed-metrics-in-db-console
description: Access and interpret changefeed metrics in DB Console dashboard. Monitor emitted messages, bytes, backfill progress, lag (max behind nanos), and per-changefeed performance to identify throughput issues and correlate with SQL queries.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: active
  related_skills:
    - access-and-navigate-db-console
    - monitor-changefeed-performance-and-health
    - monitor-changefeed-job-status
    - create-changefeeds-for-change-data-capture
    - configure-changefeed-sinks-and-options
  prerequisites:
    - Running CockroachDB cluster with active changefeeds
    - Access to DB Console (http://localhost:8080 or cluster URL)
    - Basic understanding of changefeed concepts
  estimated_time_minutes: 20
  last_updated: "2026-03-06"
---

# Monitor Changefeed Metrics in DB Console

## Overview

The **DB Console Changefeed Dashboard** provides visual monitoring of changefeed performance, throughput, and health. It displays real-time metrics including emitted messages/bytes, backfill progress, lag (max behind nanos), and per-changefeed breakdowns without requiring SQL queries.

**Key capabilities:**
- Real-time changefeed throughput graphs (messages/sec, bytes/sec)
- Lag visualization (max behind nanos across all ranges)
- Backfill progress tracking (pending rows)
- Per-changefeed performance breakdown
- Historical trend analysis

**Monitoring workflow:** DB Console provides visual dashboards → SQL queries (`crdb_internal.jobs`) provide detailed diagnostics.

## Accessing the Changefeed Dashboard

### Navigate to Changefeeds page

```bash
# Open DB Console
http://localhost:8080

# Or cluster load balancer
http://cockroach-lb.example.com:8080
```

**Navigation:**
1. Open DB Console homepage
2. Click "Changefeeds" in left sidebar (Observability section)
3. Dashboard loads with metrics graphs

**Direct URL:** `http://localhost:8080/#/changefeeds`

**Dashboard sections:**
- Overview metrics (top cards)
- Time-series graphs (throughput, lag, backfill)
- Per-changefeed table (job details)

## Key Changefeed Metrics

### Metric 1: Emitted Messages

**Measures:** Number of change messages emitted per second by all changefeeds.

**Location:** Changefeeds dashboard → "Changefeed Messages" graph

**Interpretation:**
- Steady rate: Healthy changefeed
- Spikes: Burst writes or backfill
- Zero: No changes or paused/stuck
- Declining: Workload decreasing or lag increasing

**Expected:** 0-100 (low), 100-10K (medium), 10K+ (high throughput) messages/sec

### Metric 2: Emitted Bytes

**Measures:** Data volume emitted per second (bytes/sec) across all changefeeds.

**Location:** Changefeeds dashboard → "Changefeed Bytes" graph

**Interpretation:**
- High bytes/message: Large rows or JSON overhead
- Low bytes/message: Small updates or key-only envelope

**Expected:** Small rows 10-100 KB/sec, medium 100KB-1MB/sec, large 1MB+/sec (per 100 msg/sec)

**Reduce bytes:**
```sql
CREATE CHANGEFEED FOR TABLE orders INTO 'kafka://broker:9092'
WITH envelope = 'key_only';  -- Emit only primary key
```

### Metric 3: Max Behind Nanos

**Measures:** Maximum lag (nanoseconds) across all ranges. How far behind real-time.

**Location:** Changefeeds dashboard → "Max Behind Nanos" graph

**Interpretation:**
- < 1s (< 1e9): Real-time
- 1-60s: Acceptable for most use cases
- \> 60s: Investigate sink/cluster issues
- Increasing: Falling behind (throughput < write rate)

**Convert:** 1s = 1e9, 1min = 6e10, 5min = 3e11 nanoseconds

**SQL correlation:**
```sql
-- Note: Use readable_high_water_timestamptz for lag calculations
SELECT job_id, status, readable_high_water_timestamptz,
  now() - readable_high_water_timestamptz AS lag,
  EXTRACT(EPOCH FROM (now() - readable_high_water_timestamptz)) AS lag_seconds
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running' ORDER BY lag_seconds DESC;
```

### Metric 4: Backfill Pending

**Measures:** Rows waiting for backfill during creation or schema changes.

**Location:** Changefeeds dashboard → "Backfill Pending" graph

**Interpretation:**
- Zero: No backfill (caught up)
- High decreasing: Backfill in progress (normal)
- High constant: Stalled (investigate)
- Spikes: Schema changes

**Monitor:**
```sql
SELECT job_id, status, running_status, fraction_completed
FROM [SHOW CHANGEFEED JOBS] WHERE status = 'running';
-- running_status = "running: backfilling 25 ranges"
-- fraction_completed = 0.45 (45% complete)
```

**Optimize:**
```sql
-- Skip schema change backfill
CREATE CHANGEFEED FOR TABLE orders INTO 'kafka://broker:9092'
WITH schema_change_policy = 'nobackfill';

-- Skip initial backfill
WITH initial_scan = 'no';
```

## Per-Changefeed Performance

### Changefeed breakdown table

**Location:** Changefeeds dashboard → Bottom section

**Columns:** Job ID, Description, Status, High Water Mark, Lag

**Usage:**
1. Sort by "Lag" to find slow changefeeds
2. Click job ID for detailed single-changefeed view
3. Compare throughput across changefeeds

**Detail view (click job ID):** Shows per-changefeed message/byte rates, lag graph, sink URI, tracked tables

## Identifying Changefeed Issues

### Issue 1: Lag increasing

**Causes:** Sink slow, cluster contention, large backfill, network issues

**Diagnose:**
```sql
SELECT job_id, readable_high_water_timestamptz,
  now() - readable_high_water_timestamptz AS lag
FROM [SHOW CHANGEFEED JOBS] WHERE status = 'running' ORDER BY lag DESC;

SELECT job_id, status, error FROM [SHOW CHANGEFEED JOBS] WHERE error IS NOT NULL;
```

**DB Console:** Check Metrics → SQL (QPS up?), Resources (CPU/disk maxed?), Network (latency?)

**Fix:** Scale sink, filter changefeed (WHERE clause), use envelope='key_only', add nodes

### Issue 2: Messages dropped to zero

**Causes:** Paused/failed, no writes, rangefeed closed

**Diagnose:**
```sql
SELECT job_id, status, running_status, error FROM [SHOW CHANGEFEED JOBS];
```

**Fix:** Paused → fix sink + `RESUME JOB <id>`, Failed → recreate, No writes → normal

### Issue 3: Backfill stuck

**Causes:** Sink backpressure, large table, resource exhaustion

**Diagnose:**
```sql
SELECT job_id, fraction_completed, running_status FROM [SHOW CHANGEFEED JOBS]
WHERE running_status LIKE '%backfill%';
```

**Fix:**
```sql
SET CLUSTER SETTING changefeed.backfill.concurrent_scans = 5;  -- Increase scans
-- Or skip: CREATE CHANGEFEED ... WITH initial_scan = 'no';
```

### Issue 4: High bytes/low messages

**Cause:** Large rows or verbose envelope

**Fix:** `CREATE CHANGEFEED ... WITH envelope = 'key_only';`

## Correlating DB Console with SQL

### Workflow: Visual → SQL diagnostics

**Step 1:** DB Console shows issue

**Step 2:** SQL investigation
```sql
SELECT * FROM crdb_internal.jobs WHERE job_id = 789123456789;  -- Detailed status
SELECT job_id, description FROM crdb_internal.jobs WHERE job_type = 'CHANGEFEED';  -- Config
```

**Step 3:** Cluster correlation
```sql
SELECT * FROM crdb_internal.node_statement_statistics
WHERE application_name != '$ internal-changefeed' ORDER BY count DESC LIMIT 10;
```

### SQL for metrics not in DB Console

**Resolved timestamps:**
```sql
SELECT job_id, description FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND description LIKE '%resolved%';
```

**Per-table activity:**
```sql
-- Use full_table_names column for table information
SELECT job_id, full_table_names, status,
  now() - readable_high_water_timestamptz AS lag
FROM [SHOW CHANGEFEED JOBS] WHERE status = 'running';
```

## Common Patterns

### Pattern 1: Multi-changefeed monitoring

1. Changefeeds page → Sort "Lag" descending → Focus top 3 → Click job ID

**Alert SQL:**
```sql
SELECT job_id, description, readable_high_water_timestamptz,
  now() - readable_high_water_timestamptz AS lag
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running'
  AND now() - readable_high_water_timestamptz > INTERVAL '5 minutes';
```

### Pattern 2: Backfill monitoring

Watch "Backfill Pending" graph for downward trend to zero.

**Progress SQL:**
```sql
SELECT job_id, fraction_completed,
  CASE WHEN fraction_completed = 0 THEN 'Not started'
       WHEN fraction_completed < 1 THEN 'In progress (' || ROUND(fraction_completed * 100, 2) || '%)'
       ELSE 'Complete' END AS backfill_status
FROM [SHOW CHANGEFEED JOBS] WHERE status = 'running';
```

### Pattern 3: Throughput baseline

1. Set time range "Last 7 days"
2. Note avg messages/sec and max behind nanos
3. Alert at 2x baseline

### Pattern 4: Sink health correlation

**Indicators:**
- Nanos up, messages steady → Sink backpressure
- Nanos up, messages dropping → Cluster overload

**External checks:**
```bash
kafka-consumer-groups --bootstrap-server broker:9092 --group cdc-consumer-group --describe
curl -w "@curl-format.txt" -o /dev/null -s https://webhook-endpoint.com
```

## Best Practices

### 1. Monitor max behind nanos continuously

Set external alerting (Prometheus, Grafana) for lag thresholds:
- Real-time CDC: Alert if > 5 seconds (5e9 nanos)
- Near-real-time: Alert if > 60 seconds (6e10 nanos)
- Batch-like: Alert if > 5 minutes (3e11 nanos)

### 2. Use time range selector for investigations

Narrow time range to incident window:
1. Changefeeds → Time range: "Custom"
2. Set start: 30 min before issue
3. Set end: current or resolution time
4. Examine correlations

### 3. Combine DB Console with SQL

**DB Console strengths:** Visual trends, quick health checks, multi-changefeed overview
**SQL strengths:** Exact values, programmatic alerts, detailed metadata

### 4. Track changefeed restarts

Frequent restarts indicate issues (schema changes, node failures, sink errors).

```sql
-- Recently restarted changefeeds
-- Note: Requires unsafe internals access in v26.1+
SET allow_unsafe_internals = true;
SELECT job_id, status, created, modified
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
  AND modified - created < INTERVAL '1 hour'
ORDER BY modified DESC;
```

### 5. Set realistic lag thresholds

**By use case:**
- Cache invalidation: < 1 second
- Real-time analytics: < 10 seconds
- Data warehouse sync: < 1 hour
- Audit log replication: < 5 minutes

### 6. Monitor during schema changes

Schema changes trigger backfills. Expect temporary:
- Backfill pending spike
- Max behind nanos increase
- Emitted messages spike

Alert only if backfill doesn't complete in expected time.

### 7. Correlate with Jobs page

DB Console Jobs page shows all job types. Filter to changefeeds:
- Navigate: Jobs → Filter by "Changefeed"
- View failed changefeeds (not in Changefeeds dashboard)
- See historical jobs (completed/canceled)

## Troubleshooting

### Problem: Dashboard empty (no metrics)

**Diagnosis:**
```sql
SHOW CHANGEFEED JOBS;  -- Any changefeeds exist?
```

**Solutions:**
- Create test changefeed: `CREATE CHANGEFEED FOR TABLE test INTO 'null://';`
- Adjust time range to include activity
- Check if paused: `SELECT * FROM [SHOW CHANGEFEED JOBS] WHERE status = 'paused';`

### Problem: Max behind nanos huge (hours)

**Diagnosis:**
```sql
SELECT job_id, status, high_water_timestamp, now()
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';
```

**Causes:** Changefeed resumed after pause, sink unavailable, massive backlog

**Solutions:**
- Wait for catch-up (monitor message rate)
- Fix sink, wait for recovery
- If unacceptable: Drop and recreate (loses backlog)

### Problem: Backfill stuck at high value

**Diagnosis:**
```sql
SELECT job_id, fraction_completed, running_status
FROM [SHOW CHANGEFEED JOBS]
WHERE running_status LIKE '%backfill%';
```

**Solutions:**
```sql
-- Increase concurrent scans
SET CLUSTER SETTING changefeed.backfill.concurrent_scans = 5;

-- Or skip backfill
DROP JOB <job_id>;
CREATE CHANGEFEED FOR TABLE large_table
INTO 'kafka://broker:9092'
WITH initial_scan = 'no';
```

### Problem: Emitted messages don't match write rate

**Explanation:** Emitted messages include:
1. INSERT/UPDATE/DELETE changes
2. Resolved timestamp messages (progress markers)
3. Backfill messages

**Verify:**
```sql
SELECT job_id, description FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED' AND description LIKE '%resolved%';
-- If WITH resolved='10s', expect resolved messages every 10s per range
```

**Solution:** Expected behavior. Resolved messages are progress markers.

## Key Takeaways

- **Changefeed Dashboard:** Visual monitoring at `http://localhost:8080/#/changefeeds`
- **Key metrics:** Emitted messages/bytes (throughput), max behind nanos (lag), backfill pending (progress)
- **Per-changefeed view:** Click job ID for individual performance
- **Max behind nanos:** Most critical lag metric (1e9 nanos = 1 second)
- **Lag thresholds:** Set based on use case (< 1s real-time, < 5min analytics)
- **Correlation:** DB Console for trends, SQL for diagnostics
- **Troubleshooting:** Increasing lag → check sink; zero messages → check status
- **Best practice:** Monitor max behind nanos continuously with alerts
