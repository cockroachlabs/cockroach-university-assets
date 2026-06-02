---
name: monitor-changefeed-job-status
description: Monitor and track changefeed job status, health, and progress using SQL commands and DB Console
metadata:
  domain: Change Data Capture (CDC)
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: production
  prerequisites:
    - create-enterprise-changefeeds
    - understand-changefeed-fundamentals
  related_skills:
    - query-changefeed-job-metrics
    - inspect-changefeed-errors-in-logs
    - pause-and-resume-changefeeds
    - troubleshoot-changefeed-performance
    - protect-changefeed-data-from-gc
  estimated_time: 25 minutes
---

# Monitor Changefeed Job Status

**Domain**: Change Data Capture (CDC)
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

You will learn how to monitor changefeed job status, track progress through high water timestamps, detect and diagnose errors, and manage the changefeed job lifecycle. This skill covers both SQL-based monitoring using `SHOW CHANGEFEED JOBS` and visual monitoring through the DB Console Jobs page and Changefeeds Dashboard.

Effective changefeed monitoring is critical for ensuring data consistency, detecting issues early, and maintaining operational visibility into your change data capture pipelines.

## Why This Matters

Changefeeds are long-running jobs that continuously emit data changes to external systems. Without proper monitoring, you risk:

- **Data loss**: Failed changefeeds may miss critical changes if they fall behind the garbage collection window
- **Pipeline delays**: Lagging changefeeds can cause downstream systems to process stale data
- **Resource exhaustion**: Stuck or failing changefeeds can accumulate protected timestamps and prevent garbage collection
- **Operational blind spots**: Lack of visibility into changefeed health prevents proactive intervention

Monitoring changefeed job status enables you to detect issues early, understand changefeed progress, and maintain reliable data pipelines.

## Core Concepts

### Changefeed as a Job

Changefeeds run as jobs in CockroachDB's jobs subsystem. Each changefeed has:

- **Job ID**: Unique identifier for the changefeed job
- **Status**: Current lifecycle state (running, paused, failed, canceled)
- **Running Status**: Additional runtime state information
- **High Water Timestamp**: Progress checkpoint guaranteeing all changes before this time have been emitted
- **Error Messages**: Diagnostic information when failures occur

### High Water Timestamp

The high water timestamp is the most critical metric for monitoring changefeed progress. It represents a point-in-time guarantee:

- **All changes at or before this timestamp have been emitted**
- **Changes after this timestamp may or may not have been emitted**
- **The timestamp advances as the changefeed processes new data**

The lag between the high water timestamp and the current time indicates how far behind the changefeed is in processing changes.

### Job Status Values

Changefeed jobs progress through these status values:

| Status | Meaning | Next Actions |
|--------|---------|--------------|
| `running` | Changefeed is actively processing and emitting changes | Normal operation; monitor for lag |
| `paused` | Changefeed has been manually paused via `PAUSE JOB` | Resume with `RESUME JOB` when ready |
| `pause-requested` | Pause operation is in progress but not yet complete | Wait for status to transition to `paused` |
| `failed` | Changefeed encountered a terminal error and cannot continue | Investigate error, fix root cause, restart from cursor |
| `canceled` | Changefeed was explicitly canceled or auto-canceled after protected timestamp expiry | Create new changefeed if needed |

### Error Types

Changefeeds handle two types of errors differently:

**Retryable Errors** (automatically retried):
- Temporary network failures
- Transient sink unavailability
- Resource contention errors
- Most operational issues

**Terminal Errors** (cause job failure):
- Schema incompatibility (e.g., table dropped, unsupported column family added)
- Data conversion failures (e.g., unsupported Avro types)
- Invalid changefeed configuration
- Target table offline or inaccessible

When a changefeed encounters a retryable error, it pauses briefly and retries. Terminal errors cause the job to fail permanently, requiring manual intervention.

## Instructions

### 1. View All Changefeed Jobs

Use `SHOW CHANGEFEED JOBS` to display all changefeed jobs across the cluster:

```sql
SHOW CHANGEFEED JOBS;
```

**Output columns**:
- `job_id`: Unique job identifier
- `description`: Human-readable description of the changefeed configuration
- `user_name`: User who created the changefeed
- `status`: Current job status (running, paused, failed, canceled)
- `running_status`: Additional runtime state information
- `created`: Timestamp when the job was created
- `started`: Timestamp when the job started running
- `finished`: Timestamp when the job completed (NULL for active jobs)
- `modified`: Timestamp of last modification
- `high_water_timestamp`: Progress checkpoint in nanoseconds since Unix epoch
- `readable_high_water_timestamptz`: Human-readable timestamp with timezone
- `error`: Error message for failed jobs
- `sink_uri`: Destination URI for the changefeed (redacted credentials)
- `full_table_names`: Fully-qualified names of watched tables
- `topics`: Kafka/Pub/Sub topic names for the changefeed
- `format`: Message format (json, avro, csv, parquet)

**Example output**:
```
        job_id       |                    description                     | status  |          running_status           | created              | started              | finished |     modified         | high_water_timestamp |  readable_high_water_timestamptz  | error |           sink_uri            |     full_table_names      |      topics       | format
---------------------+---------------------------------------------------+---------+-----------------------------------+----------------------+----------------------+----------+----------------------+----------------------+-----------------------------------+-------+-------------------------------+---------------------------+-------------------+--------
  912345678901234567 | CREATE CHANGEFEED FOR TABLE mydb.public.orders... | running | running: resolving timestamps     | 2026-03-07 10:15:23  | 2026-03-07 10:15:24  | NULL     | 2026-03-07 14:22:10  | 1709821330000000000  | 2026-03-07 14:22:10+00:00        | NULL  | kafka://broker:9092           | mydb.public.orders        | orders            | json
```

### 2. View Specific Changefeed Job Details

Query specific changefeed jobs by job ID:

```sql
SHOW CHANGEFEED JOB 912345678901234567;
```

This displays the same columns as `SHOW CHANGEFEED JOBS` but filtered to a single job.

### 3. Filter Changefeeds by Status

Use standard SQL `WHERE` clauses to filter by status:

```sql
-- View only running changefeeds
SELECT job_id, status, readable_high_water_timestamptz, error
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';

-- View failed or paused changefeeds
SELECT job_id, status, error, sink_uri
FROM [SHOW CHANGEFEED JOBS]
WHERE status IN ('failed', 'paused');

-- View changefeeds by table name
SELECT job_id, status, full_table_names
FROM [SHOW CHANGEFEED JOBS]
WHERE full_table_names LIKE '%orders%';
```

### 4. Monitor Changefeed Lag (Time Behind Current)

Calculate how far behind a changefeed is by comparing the high water timestamp to the current time:

```sql
SELECT
    job_id,
    status,
    running_status,
    NOW() - readable_high_water_timestamptz AS lag,
    readable_high_water_timestamptz AS high_water_mark,
    full_table_names
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running'
ORDER BY lag DESC;
```

**Interpreting lag**:
- **0-10 seconds**: Healthy changefeed keeping up with writes
- **10-60 seconds**: Acceptable lag for moderate write volumes
- **1-5 minutes**: Concerning; investigate write volume or sink throughput
- **>5 minutes**: Critical; changefeed may be falling behind and risk hitting GC window

### 5. Track High Water Timestamp Progress Over Time

Monitor high water timestamp advancement to verify the changefeed is making progress:

```sql
-- Run this query periodically (e.g., every 30 seconds)
SELECT
    job_id,
    readable_high_water_timestamptz,
    EXTRACT(epoch FROM (NOW() - readable_high_water_timestamptz))::INT AS lag_seconds
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';
```

If the `readable_high_water_timestamptz` value doesn't advance between queries, the changefeed may be stuck or experiencing issues.

### 6. Detect Changefeeds with Errors

Query the jobs table for changefeeds with error messages:

```sql
SELECT
    job_id,
    status,
    error,
    readable_high_water_timestamptz,
    full_table_names
FROM [SHOW CHANGEFEED JOBS]
WHERE error IS NOT NULL OR status = 'failed'
ORDER BY modified DESC;
```

**Common error patterns**:

| Error Message | Cause | Resolution |
|--------------|-------|------------|
| `table offline` | Table was dropped or is unavailable | Remove table from changefeed or restore table |
| `changefeed cannot handle column family` | DDL added column family to watched table | Create new changefeed; some DDL changes are terminal |
| `protected timestamp verification failed` | Changefeed fell behind GC window | Restart changefeed with `cursor` option from safe timestamp |
| `sink unavailable` | Cannot connect to Kafka/Pub/Sub/webhook | Check sink connectivity, credentials, and configuration |
| `schema change occurred` | Incompatible DDL operation | Review schema changes; restart changefeed if needed |

### 7. Use the DB Console Jobs Page

Navigate to the Jobs page in the DB Console:

**Access**: `http://<cluster-host>:8080` → **Jobs** (left navigation)

**Features**:
- **Visual status indicators**: Color-coded status (green=running, yellow=paused, red=failed)
- **High water timestamp tooltip**: Hover over the timestamp to see system time
- **Job filtering**: Filter by type, status, or user
- **Job details**: Click job ID to view full description, error messages, and timeline
- **Search**: Find jobs by table name or job ID

**Best practices**:
- Bookmark the Jobs page for quick access during incidents
- Set up auto-refresh (if available) to monitor active changefeeds
- Use filters to focus on running or failed changefeeds

### 8. Use the Changefeeds Dashboard

Navigate to the Changefeeds Dashboard for metrics and aggregated health:

**Access**: `http://<cluster-host>:8080` → **Metrics** → **Dashboard** → **Changefeeds**

**Key metrics displayed**:
- **Max Changefeed Latency**: Maximum lag across all changefeeds
- **Changefeed Error Retries**: Total retryable errors encountered
- **Sink Byte Traffic**: Data volume emitted to sinks
- **Changefeed Restarts**: Number of times changefeeds restarted due to errors

**When to use**:
- Monitoring overall changefeed health across the cluster
- Correlating changefeed issues with cluster events
- Identifying trends in changefeed performance over time

### 9. Query Internal Jobs Table for Advanced Monitoring

For programmatic monitoring or custom queries, use `crdb_internal.jobs`:

```sql
SELECT
    job_id,
    job_type,
    status,
    created,
    NOW() - to_timestamp((high_water_timestamp/1000000000)::FLOAT) AS changefeed_lag,
    LEFT(description, 100) AS config_summary,
    error
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
  AND status IN ('running', 'paused', 'pause-requested')
ORDER BY created DESC;
```

This query provides similar information to `SHOW CHANGEFEED JOBS` but allows more flexible SQL operations like joins, aggregations, and complex filtering.

### 10. Set Up Continuous Monitoring Queries

For production environments, implement continuous monitoring:

**Polling query for alerting systems** (Prometheus, Datadog, etc.):
```sql
SELECT
    COUNT(*) AS running_count,
    SUM(CASE WHEN EXTRACT(epoch FROM (NOW() - readable_high_water_timestamptz)) > 300 THEN 1 ELSE 0 END) AS lagging_count,
    MAX(EXTRACT(epoch FROM (NOW() - readable_high_water_timestamptz))) AS max_lag_seconds
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';
```

**Alert thresholds**:
- Alert if `lagging_count > 0` (any changefeed >5 minutes behind)
- Critical alert if `max_lag_seconds > 600` (any changefeed >10 minutes behind)
- Warning if running count drops unexpectedly (changefeeds stopped)

## Changefeed Job Lifecycle Management

### Pausing a Changefeed

Pause a running changefeed to temporarily halt processing:

```sql
PAUSE JOB 912345678901234567;
```

**When to pause**:
- Performing maintenance on downstream systems
- Temporarily reducing cluster load
- Modifying changefeed configuration with `ALTER CHANGEFEED`

**Important considerations**:
- Paused changefeeds hold protected timestamps (if `protect_data_from_gc_on_pause` is enabled)
- After `gc_protect_expires_after` duration, protected timestamps expire and the job is auto-canceled
- Default `gc_protect_expires_after` is 24 hours

**Verify pause**:
```sql
SELECT job_id, status FROM [SHOW CHANGEFEED JOBS] WHERE job_id = 912345678901234567;
```

Expected status: `paused`

### Resuming a Changefeed

Resume a paused changefeed:

```sql
RESUME JOB 912345678901234567;
```

The changefeed continues from its high water timestamp, emitting changes that occurred during the pause.

**Verify resume**:
```sql
SELECT job_id, status, running_status FROM [SHOW CHANGEFEED JOBS] WHERE job_id = 912345678901234567;
```

Expected status: `running`

### Canceling a Changefeed

Permanently stop a changefeed:

```sql
CANCEL JOB 912345678901234567;
```

**When to cancel**:
- Changefeed is no longer needed
- Replacing changefeed with new configuration
- Changefeed has failed and cannot be recovered

**Important**: Canceled changefeeds cannot be resumed. To continue capturing changes, create a new changefeed with the `cursor` option.

## Troubleshooting Common Issues

### Issue 1: Changefeed Status is "Failed"

**Symptoms**:
```sql
SELECT job_id, status, error FROM [SHOW CHANGEFEED JOBS] WHERE status = 'failed';
```
Returns failed jobs with error messages.

**Diagnosis**:
1. Review the `error` column for the root cause
2. Check logs for detailed error context: `grep <job_id> /var/log/cockroach/cockroach.log`
3. Verify the target table still exists and is accessible
4. Check for schema changes that may have broken the changefeed

**Resolution**:

**For terminal errors** (schema changes, dropped tables):
```sql
-- Create new changefeed starting from the failed job's high water timestamp
CREATE CHANGEFEED FOR TABLE mydb.public.orders
INTO 'kafka://broker:9092'
WITH cursor = '1709821330000000000';
```

**For transient errors** (sink connectivity):
1. Fix the underlying issue (restore sink connectivity)
2. Resume the job if it auto-paused due to retryable errors:
   ```sql
   RESUME JOB 912345678901234567;
   ```

### Issue 2: High Water Timestamp Not Advancing

**Symptoms**:
High water timestamp remains static across multiple queries over several minutes.

**Diagnosis**:
```sql
-- Check for errors and running status
SELECT job_id, status, running_status, error, readable_high_water_timestamptz
FROM [SHOW CHANGEFEED JOBS]
WHERE job_id = 912345678901234567;
```

**Common causes**:
1. **Sink is slow or unavailable**: Check sink connectivity and throughput
2. **Large transaction in progress**: Changefeed waits for transaction to commit
3. **Resource contention**: CPU, memory, or network saturation
4. **Schema registry issues** (for Avro format): Check schema registry health

**Resolution**:
1. Check sink metrics and logs for errors or backpressure
2. Verify cluster health and resource utilization
3. For Avro changefeeds, verify schema registry is accessible
4. Consider scaling sink capacity or adjusting changefeed configuration

### Issue 3: Changefeed Lag Increasing Over Time

**Symptoms**:
```sql
SELECT
    job_id,
    EXTRACT(epoch FROM (NOW() - readable_high_water_timestamptz))::INT AS lag_seconds
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';
```
Shows lag increasing from seconds to minutes.

**Diagnosis**:
1. **Write volume exceeds changefeed throughput**: Check table write rates
2. **Sink cannot keep up**: Monitor sink performance and backpressure
3. **Expensive transformations**: Review changefeed options like `diff`, `envelope`
4. **Network bandwidth constraints**: Check network utilization

**Resolution**:
- **Scale sink capacity**: Add Kafka partitions, increase Pub/Sub quota
- **Optimize changefeed configuration**:
  - Disable `resolved` if not needed
  - Increase `min_checkpoint_frequency` to reduce overhead
  - Use `full_table_name=false` if possible
- **Partition large tables**: Consider multiple changefeeds per table partition
- **Increase cluster resources**: Scale CockroachDB cluster to handle write load

### Issue 4: Changefeed Auto-Canceled After Pause

**Symptoms**:
```sql
SELECT job_id, status, error FROM [SHOW CHANGEFEED JOBS] WHERE status = 'canceled';
```
Shows canceled status with error mentioning protected timestamp expiry.

**Diagnosis**:
Changefeed was paused longer than `gc_protect_expires_after` duration (default 24 hours), causing protected timestamps to expire and the job to auto-cancel.

**Resolution**:
```sql
-- Get the high water timestamp from the canceled job
SELECT job_id, high_water_timestamp FROM [SHOW CHANGEFEED JOBS] WHERE job_id = 912345678901234567;

-- Create new changefeed from the high water timestamp
CREATE CHANGEFEED FOR TABLE mydb.public.orders
INTO 'kafka://broker:9092'
WITH cursor = '1709821330000000000';
```

**Prevention**:
- Resume paused changefeeds within the `gc_protect_expires_after` window
- Increase `gc_protect_expires_after` for longer maintenance windows:
  ```sql
  ALTER CHANGEFEED 912345678901234567 SET gc_protect_expires_after = '48h';
  ```
- Set `protect_data_from_gc_on_pause=false` if protected timestamps are not needed during pause

### Issue 5: Multiple Retryable Errors

**Symptoms**:
Changefeeds Dashboard shows high `changefeed.error_retries` metric, or logs show repeated retryable errors.

**Diagnosis**:
```sql
-- Check for changefeeds with recent errors (requires monitoring external metrics)
SELECT job_id, status, running_status, readable_high_water_timestamptz
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running';
```

Check Changefeeds Dashboard for error retry trends.

**Common retryable errors**:
- Transient network failures to sink
- Temporary sink unavailability
- Resource contention during peak load

**Resolution**:
1. **Investigate sink health**: Check Kafka broker logs, Pub/Sub quotas, webhook endpoints
2. **Review cluster logs**: Look for error messages associated with the job ID
3. **Monitor cluster resources**: Ensure cluster has sufficient CPU, memory, network
4. **If errors persist**: Consider pausing, investigating, and resuming after fixing root cause

## Monitoring Best Practices

### 1. Establish Baseline Metrics

Before deploying changefeeds to production, establish baseline metrics:

- **Typical lag**: Expected high water timestamp lag under normal load
- **Write volume**: Rows/second written to watched tables
- **Sink throughput**: Messages/second emitted to sink
- **Error rates**: Expected retryable error frequency (should be near zero)

Use these baselines to set meaningful alert thresholds.

### 2. Set Up Alerting on Critical Metrics

Configure alerts for:

| Metric | Threshold | Severity | Action |
|--------|-----------|----------|--------|
| `changefeed.max_behind_nanos` | >5 minutes | Warning | Investigate lag causes |
| `changefeed.max_behind_nanos` | >10 minutes | Critical | Immediate intervention required |
| Changefeed status = `failed` | Any failed job | Critical | Investigate and restart |
| `changefeed.error_retries` | Sudden spike | Warning | Check sink and cluster health |
| High water timestamp not advancing | >2 minutes | Warning | Check for stuck changefeeds |

### 3. Monitor Protected Timestamps

Changefeeds hold protected timestamps to prevent garbage collection of data they haven't yet emitted. Monitor protected timestamp age:

```sql
SELECT
    c.job_id,
    c.status,
    NOW() - c.readable_high_water_timestamptz AS protected_age
FROM [SHOW CHANGEFEED JOBS] c
WHERE c.status IN ('running', 'paused')
ORDER BY protected_age DESC;
```

**Risk**: Old protected timestamps prevent garbage collection, causing data accumulation and storage growth.

**Mitigation**: Cancel or resume long-paused changefeeds promptly.

### 4. Track Changefeed Inventory

Maintain an inventory of all production changefeeds:

```sql
SELECT
    job_id,
    status,
    full_table_names,
    sink_uri,
    created,
    user_name
FROM [SHOW CHANGEFEED JOBS]
ORDER BY created DESC;
```

Document the purpose and owner of each changefeed to avoid orphaned or forgotten changefeeds.

### 5. Regular Health Checks

Implement a periodic health check script (run every 5 minutes):

```sql
-- Changefeed health check query
SELECT
    'total_changefeeds' AS metric,
    COUNT(*)::STRING AS value
FROM [SHOW CHANGEFEED JOBS]

UNION ALL

SELECT
    'running_changefeeds',
    COUNT(*)::STRING
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running'

UNION ALL

SELECT
    'failed_changefeeds',
    COUNT(*)::STRING
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'failed'

UNION ALL

SELECT
    'lagging_changefeeds',
    COUNT(*)::STRING
FROM [SHOW CHANGEFEED JOBS]
WHERE status = 'running'
  AND EXTRACT(epoch FROM (NOW() - readable_high_water_timestamptz)) > 300;
```

Send results to your monitoring system (Prometheus, Datadog, CloudWatch, etc.).

### 6. Use DB Console for Visual Monitoring

The DB Console provides visual, real-time monitoring:

- **Jobs Page**: Quick status overview of all changefeeds
- **Changefeeds Dashboard**: Aggregate metrics and trends
- **Metrics Explorer**: Custom metric queries and visualization

**Recommended workflow**:
1. Start with Changefeeds Dashboard for overall health
2. Drill into Jobs Page to identify specific problematic changefeeds
3. Click job ID for detailed error messages and configuration
4. Use Metrics Explorer to correlate changefeed issues with cluster events

## Related Skills

**Prerequisites**:
- **create-enterprise-changefeeds**: Create the changefeeds you'll monitor
- **understand-changefeed-fundamentals**: Understand how changefeeds work

**Next steps**:
- **query-changefeed-job-metrics**: Query Prometheus metrics for changefeed health
- **inspect-changefeed-errors-in-logs**: Find detailed error messages in cluster logs
- **pause-and-resume-changefeeds**: Manage changefeed lifecycle for maintenance
- **troubleshoot-changefeed-performance**: Diagnose and resolve performance issues
- **protect-changefeed-data-from-gc**: Configure protected timestamps and GC settings

**Advanced topics**:
- **alter-changefeed-configuration**: Modify changefeed settings without recreating
- **restart-changefeeds-from-cursor**: Restart failed changefeeds from specific timestamps
- **monitor-changefeed-sink-performance**: Monitor downstream sink health and throughput

## References

### Official Documentation

- [Monitor and Debug Changefeeds](https://www.cockroachlabs.com/docs/stable/monitor-and-debug-changefeeds)
- [SHOW JOBS](https://www.cockroachlabs.com/docs/stable/show-jobs)
- [CREATE CHANGEFEED](https://www.cockroachlabs.com/docs/stable/create-changefeed)
- [ALTER CHANGEFEED](https://www.cockroachlabs.com/docs/stable/alter-changefeed)
- [PAUSE JOB](https://www.cockroachlabs.com/docs/stable/pause-job)
- [RESUME JOB](https://www.cockroachlabs.com/docs/stable/resume-job.html)
- [CANCEL JOB](https://www.cockroachlabs.com/docs/stable/cancel-job)
- [Jobs Page](https://www.cockroachlabs.com/docs/stable/ui-jobs-page.html)
- [Changefeeds Dashboard](https://www.cockroachlabs.com/docs/stable/ui-cdc-dashboard.html)
- [Changefeed Monitoring Guide](https://www.cockroachlabs.com/docs/stable/changefeed-monitoring-guide)
- [Protect Changefeed Data from Garbage Collection](https://www.cockroachlabs.com/docs/stable/protect-changefeed-data)
- [Create and Configure Changefeeds](https://www.cockroachlabs.com/docs/stable/create-and-configure-changefeeds)
- [Changefeed Examples](https://www.cockroachlabs.com/docs/stable/changefeed-examples)
- [Essential Alerts for Advanced Deployments](https://www.cockroachlabs.com/docs/stable/essential-alerts-advanced)

### Key Metrics

- `changefeed.max_behind_nanos`: Maximum lag across all changefeeds
- `changefeed.error_retries`: Total retryable errors encountered
- `changefeed.checkpoint_progress`: Changefeed checkpoint persistence status

---

**Version**: 1.0.0
**Last Updated**: 2026-03-07
**Skill Author**: CockroachDB University
**License**: CC BY-NC-SA 4.0
