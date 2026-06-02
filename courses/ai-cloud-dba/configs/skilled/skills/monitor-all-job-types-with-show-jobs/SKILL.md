---
name: monitor-all-job-types-with-show-jobs
description: Monitor background operations using SHOW JOBS to track BACKUP, RESTORE, IMPORT, CHANGEFEED, CREATE STATISTICS, and schema changes. Filter by status, type, and time. Monitor progress and troubleshoot failures.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: active
---

# Monitor All Job Types with SHOW JOBS

Monitor background operations across all job types using SHOW JOBS for operational visibility.

## What This Skill Teaches

You will learn to use SHOW JOBS to monitor all background operations in CockroachDB including backups, restores, imports, changefeeds, statistics collection, and schema changes. You'll understand job status values, track progress with fraction_completed, filter jobs by type and status, and troubleshoot failed operations.

**Key Concepts**: SHOW JOBS syntax, job types (BACKUP, RESTORE, IMPORT, CHANGEFEED, CREATE STATS, SCHEMA CHANGE), job lifecycle (pending -> running -> succeeded/failed), progress tracking, filtering by type/status/time, error interpretation.

## Basic Usage

```sql
-- List all jobs (recent 1000 by default)
SHOW JOBS;

-- Key output columns:
-- job_id: Unique job identifier
-- job_type: BACKUP, RESTORE, IMPORT, CHANGEFEED, CREATE STATS, SCHEMA CHANGE
-- description: Human-readable job description
-- status: pending, running, succeeded, failed, canceled, paused
-- running_status: Detailed progress message
-- created, started, finished, modified: Timestamps
-- fraction_completed: Progress 0.0 to 1.0
-- error: Error message if failed
-- coordinator_id: Node coordinating the job
```

## Job Types

```sql
-- List all job types in cluster
SELECT DISTINCT job_type FROM [SHOW JOBS] ORDER BY job_type;

-- Common types:
-- BACKUP - Full and incremental backups
-- RESTORE - Database/table restoration
-- IMPORT - CSV/AVRO/Parquet import
-- CHANGEFEED - Change data capture
-- CREATE STATS - Statistics collection
-- SCHEMA CHANGE - DDL (CREATE INDEX, ADD COLUMN, etc.)
-- AUTO CREATE STATS - Automatic statistics
```

## Job Status Values

```sql
-- Status lifecycle: pending -> running -> succeeded/failed/canceled
-- pending: Created, waiting to start
-- running: Actively executing
-- succeeded: Completed successfully
-- failed: Failed with error
-- canceled: Manually canceled
-- paused: Paused (changefeeds or manual)

-- View jobs by status
SELECT job_id, job_type, status, modified
FROM [SHOW JOBS]
WHERE status = 'running'
ORDER BY modified DESC;
```

## Filtering Jobs

### By Job Type

```sql
-- BACKUP jobs
SELECT job_id, status, created, fraction_completed, description
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
ORDER BY created DESC LIMIT 20;

-- Schema changes
SELECT job_id, status, fraction_completed, description
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE' AND status = 'running';

-- Changefeeds
SELECT job_id, status, running_status, description
FROM [SHOW JOBS]
WHERE job_type = 'CHANGEFEED' AND status IN ('running', 'paused');

-- IMPORT jobs
SELECT job_id, status, created, finished, description
FROM [SHOW JOBS]
WHERE job_type = 'IMPORT'
ORDER BY created DESC;
```

### By Status

```sql
-- Active jobs
SELECT job_id, job_type, description, started, now() - started AS duration
FROM [SHOW JOBS]
WHERE status = 'running'
ORDER BY started;

-- Failed jobs
SELECT job_id, job_type, description, error, finished
FROM [SHOW JOBS]
WHERE status = 'failed'
ORDER BY finished DESC LIMIT 20;

-- Pending jobs
SELECT job_id, job_type, description, created, now() - created AS waiting
FROM [SHOW JOBS]
WHERE status = 'pending'
ORDER BY created;
```

### By Creation Time

```sql
-- Jobs created today
SELECT job_id, job_type, status, description
FROM [SHOW JOBS]
WHERE created > current_date()
ORDER BY created DESC;

-- Jobs in last hour
SELECT job_id, job_type, status, description
FROM [SHOW JOBS]
WHERE created > now() - INTERVAL '1 hour';

-- Jobs in time range
SELECT job_id, job_type, status, created
FROM [SHOW JOBS]
WHERE created BETWEEN '2026-03-01' AND '2026-03-02'
ORDER BY created DESC;
```

## Tracking Progress

```sql
-- Running jobs with progress
SELECT
  job_id,
  job_type,
  fraction_completed,
  running_status,
  now() - started AS duration,
  description
FROM [SHOW JOBS]
WHERE status = 'running' AND fraction_completed IS NOT NULL
ORDER BY fraction_completed;

-- Estimate completion time
SELECT
  job_id,
  job_type,
  fraction_completed,
  now() - started AS elapsed,
  CASE
    WHEN fraction_completed > 0 AND fraction_completed < 1 THEN
      (now() - started) / fraction_completed * (1 - fraction_completed)
    ELSE NULL
  END AS estimated_remaining
FROM [SHOW JOBS]
WHERE status = 'running' AND fraction_completed > 0
ORDER BY estimated_remaining DESC NULLS LAST;

-- Monitor specific job
SELECT job_id, status, fraction_completed, running_status, modified
FROM [SHOW JOBS]
WHERE job_id = 123456789;
```

## Common Queries

### Active Jobs

```sql
-- All running jobs
SELECT job_id, job_type, description, started, now() - started AS duration
FROM [SHOW JOBS]
WHERE status = 'running'
ORDER BY started;

-- Active jobs by type
SELECT job_type, COUNT(*) AS active_count, MIN(started) AS oldest
FROM [SHOW JOBS]
WHERE status = 'running'
GROUP BY job_type
ORDER BY active_count DESC;
```

### Failed Jobs

```sql
-- Recent failures (24 hours)
SELECT job_id, job_type, description, error, finished
FROM [SHOW JOBS]
WHERE status = 'failed' AND finished > now() - INTERVAL '24 hours'
ORDER BY finished DESC;

-- Failed jobs by type
SELECT job_type, COUNT(*) AS failures, MAX(finished) AS last_failure
FROM [SHOW JOBS]
WHERE status = 'failed'
GROUP BY job_type
ORDER BY failures DESC;

-- Jobs with specific error
SELECT job_id, job_type, description, error
FROM [SHOW JOBS]
WHERE status = 'failed' AND error LIKE '%timeout%'
ORDER BY finished DESC;
```

### Long-Running Jobs

```sql
-- Jobs running > 1 hour
SELECT
  job_id,
  job_type,
  description,
  fraction_completed,
  now() - started AS duration,
  running_status
FROM [SHOW JOBS]
WHERE status = 'running' AND now() - started > INTERVAL '1 hour'
ORDER BY duration DESC;

-- Jobs taking longer than expected
SELECT
  job_id,
  job_type,
  fraction_completed,
  now() - started AS elapsed,
  (now() - started) / NULLIF(fraction_completed, 0) AS estimated_total
FROM [SHOW JOBS]
WHERE status = 'running'
  AND fraction_completed > 0
  AND (now() - started) / fraction_completed > INTERVAL '2 hours'
ORDER BY estimated_total DESC;
```

## Common Patterns

### Daily Job Dashboard

```sql
-- Summary of 24-hour job activity
SELECT
  job_type,
  status,
  COUNT(*) AS count,
  MIN(created) AS first,
  MAX(created) AS last
FROM [SHOW JOBS]
WHERE created > now() - INTERVAL '24 hours'
GROUP BY job_type, status
ORDER BY job_type, status;
```

### Job Success Rate

```sql
-- Success rate by type (7 days)
SELECT
  job_type,
  COUNT(*) AS total,
  COUNT(CASE WHEN status = 'succeeded' THEN 1 END) AS succeeded,
  COUNT(CASE WHEN status = 'failed' THEN 1 END) AS failed,
  ROUND(
    COUNT(CASE WHEN status = 'succeeded' THEN 1 END)::FLOAT /
    NULLIF(COUNT(*), 0) * 100, 2
  ) AS success_pct
FROM [SHOW JOBS]
WHERE created > now() - INTERVAL '7 days'
  AND status IN ('succeeded', 'failed')
GROUP BY job_type
ORDER BY total DESC;
```

### Job Duration Analysis

```sql
-- Average duration by type
SELECT
  job_type,
  COUNT(*) AS count,
  AVG(finished - started) AS avg_duration,
  MIN(finished - started) AS min_duration,
  MAX(finished - started) AS max_duration
FROM [SHOW JOBS]
WHERE status = 'succeeded' AND finished > now() - INTERVAL '7 days'
GROUP BY job_type
ORDER BY avg_duration DESC;
```

### Alert on Stuck Jobs

```sql
-- Jobs possibly stuck (running > 2 hours, low progress)
SELECT
  job_id,
  job_type,
  description,
  fraction_completed,
  now() - started AS duration,
  now() - modified AS time_since_update
FROM [SHOW JOBS]
WHERE status = 'running'
  AND now() - started > INTERVAL '2 hours'
  AND (fraction_completed < 0.1 OR fraction_completed IS NULL)
ORDER BY duration DESC;
```

### Backup Monitoring

```sql
-- Scheduled backup jobs (24 hours)
SELECT job_id, status, fraction_completed, created, description
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND description LIKE '%BACKUP SCHEDULE%'
  AND created > now() - INTERVAL '24 hours'
ORDER BY created DESC;

-- Backup failures
SELECT job_id, description, error, finished
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP' AND status = 'failed'
  AND finished > now() - INTERVAL '7 days'
ORDER BY finished DESC;
```

### Schema Change Tracking

```sql
-- Active schema changes with progress
SELECT
  job_id,
  description,
  fraction_completed,
  now() - started AS duration,
  running_status
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE' AND status = 'running'
ORDER BY started;
```

### Coordinator Node Distribution

```sql
-- Jobs by coordinator node
SELECT
  coordinator_id,
  COUNT(*) AS job_count,
  COUNT(CASE WHEN status = 'running' THEN 1 END) AS running
FROM [SHOW JOBS]
WHERE status IN ('running', 'pending')
GROUP BY coordinator_id
ORDER BY job_count DESC;
```

## Troubleshooting

### Job Stuck in Pending

**Symptoms**: Job status = 'pending' for extended period.

**Causes**: All job slots occupied, cluster overloaded, waiting for resources.

```sql
-- Check running job count
SELECT job_type, COUNT(*) FROM [SHOW JOBS]
WHERE status = 'running' GROUP BY job_type;

-- Check if cluster overloaded
-- Note: Job concurrency managed automatically in v26.1+

-- Cancel if no longer needed
CANCEL JOB <job_id>;
```

### Job Failed

**Symptoms**: Job status = 'failed' with error.

```sql
-- View error
SELECT job_id, job_type, description, error
FROM [SHOW JOBS]
WHERE job_id = <job_id>;

-- Common errors:
-- "context canceled" - Job canceled or cluster restarted
-- "connection refused" - External service unavailable
-- "permission denied" - Insufficient credentials
-- "node liveness" - Node failure during execution

-- Retry by re-running original statement
```

### Long-Running with No Progress

**Symptoms**: fraction_completed not increasing.

**Causes**: Large data volume (normal), resource contention, job stuck (rare).

```sql
-- Check progress over time
SELECT job_id, fraction_completed, running_status, modified
FROM [SHOW JOBS]
WHERE job_id = <job_id>;

-- If truly stuck, cancel and restart
CANCEL JOB <job_id>;
```

### Repeated Failures

**Symptoms**: Same job type failing repeatedly.

```sql
-- Find common failure pattern
SELECT error, COUNT(*) AS occurrences
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP' AND status = 'failed'
GROUP BY error
ORDER BY occurrences DESC;

-- Address root cause (permissions, connectivity, etc.)
```

### Changefeed Paused

**Symptoms**: Changefeed status = 'paused' with error.

```sql
-- View error
SELECT job_id, error FROM [SHOW JOBS]
WHERE job_type = 'CHANGEFEED' AND status = 'paused';

-- Fix issue (sink availability, permissions), then resume
RESUME JOB <job_id>;
```

## Best Practices

1. **Monitor regularly**: Run daily queries to check for failed or stuck jobs
2. **Set up alerts**: Create queries that return rows only when action needed
3. **Track duration trends**: Monitor average durations to detect degradation
4. **Filter by time**: Focus on recent jobs (7-30 days) to manage history size
5. **Use for debugging**: Check SHOW JOBS when operations seem slow
6. **Monitor distribution**: Ensure jobs balanced across coordinator nodes
7. **Combine with schedules**: Use SHOW SCHEDULES for scheduled jobs

## Alerting Queries

```sql
-- Failed jobs in last hour
SELECT job_id, job_type, description, error
FROM [SHOW JOBS]
WHERE status = 'failed' AND finished > now() - INTERVAL '1 hour';

-- Long-running jobs (> 2 hours)
SELECT job_id, job_type, description, now() - started AS duration
FROM [SHOW JOBS]
WHERE status = 'running' AND now() - started > INTERVAL '2 hours';

-- Paused changefeeds
SELECT job_id, description, error
FROM [SHOW JOBS]
WHERE job_type = 'CHANGEFEED' AND status = 'paused';
```

## Key Takeaways

- SHOW JOBS displays all background operations: BACKUP, RESTORE, IMPORT, CHANGEFEED, CREATE STATS, SCHEMA CHANGE
- Job lifecycle: pending -> running -> succeeded/failed/canceled/paused
- Track progress with fraction_completed (0.0 to 1.0) and running_status
- Filter by job_type, status, and created time for targeted monitoring
- error column contains failure reason; long-running jobs normal for large datasets
- Monitor regularly, set up automated alerts, combine with DB Console and SHOW SCHEDULES

## Related Skills

- `monitor-changefeed-job-status` - Changefeed-specific monitoring
- `monitor-schema-change-job-progress` - DDL operation tracking
- `monitor-scheduled-backups-with-show-schedules` - Backup schedule monitoring
- `create-automated-backup-schedules` - Create backup jobs
- `create-changefeeds-for-change-data-capture` - Create changefeed jobs
- `import-data-using-import-into-from-csv` - Create import jobs
