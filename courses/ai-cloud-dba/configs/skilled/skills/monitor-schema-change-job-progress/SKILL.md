---
name: monitor-schema-change-job-progress
description: Monitor long-running schema change jobs (CREATE INDEX, ADD COLUMN, ALTER PRIMARY KEY) using SHOW JOBS and fraction_completed to estimate completion time. Detect stalled operations requiring intervention. Use when user says "check schema changes", "index progress".
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - schema-design
    - indexing
    - monitoring
    - jobs
    - schema-changes
---

# Monitor Schema Change Job Progress

## Overview

Monitor long-running schema change operations in CockroachDB. Schema changes like CREATE INDEX and ALTER PRIMARY KEY can take hours on large tables, so tracking progress, estimating completion time, and detecting stuck operations is critical for production operations.

## Use Cases

- Monitor CREATE INDEX progress on large tables
- Track ALTER TABLE operations (ADD COLUMN, DROP COLUMN, etc.)
- Estimate completion time for schema changes
- Detect stuck or stalled schema changes
- Determine if schema change can be safely canceled
- Monitor multiple concurrent schema changes
- Plan maintenance windows for schema modifications
- Troubleshoot slow schema change operations

## Core Concepts

### Schema Change Job Types

| Job Type | Example | Duration | Requires Backfill |
|----------|---------|----------|-------------------|
| **CREATE INDEX** | `CREATE INDEX ON t(col)` | Minutes-hours | Yes |
| **ALTER PRIMARY KEY** | `ALTER TABLE t ALTER PRIMARY KEY` | Hours | Yes (rewrites table) |
| **ADD COLUMN** (with default) | `ALTER TABLE t ADD COLUMN c INT DEFAULT 0` | Minutes-hours | Yes |
| **ADD COLUMN** (nullable) | `ALTER TABLE t ADD COLUMN c INT` | Seconds | No (metadata only) |
| **DROP INDEX** | `DROP INDEX idx` | Seconds | No |

### Schema Change Phases

1. **Starting** - Job initialization, validating schema
2. **Backfilling** - Reading existing rows, building index/column values (90%+ of time)
3. **Validation** - Verifying backfill correctness
4. **Finalizing** - Making schema change visible
5. **Completed** - Schema change active

### Progress Metrics

**fraction_completed**: 0.0 to 1.0 (0% to 100%)
**running_status**: Current operation phase (text description)

## Instructions

### 1. View Running Schema Changes

```sql
-- Show all running schema change jobs
SELECT
  job_id,
  description,
  status,
  fraction_completed,
  running_status,
  started,
  now() - started AS duration
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE'
  AND status = 'running'
ORDER BY started;
```

**Example output**:
```
  job_id |        description        | fraction_completed |  running_status  | duration
---------+---------------------------+--------------------+------------------+----------
  789    | CREATE INDEX idx_email... | 0.45               | backfill         | 00:12:34
```

### 2. Estimate Completion Time

```sql
-- Calculate estimated time remaining
SELECT
  job_id,
  description,
  fraction_completed,
  now() - started AS elapsed,
  CASE
    WHEN fraction_completed > 0 THEN
      ((now() - started) / fraction_completed) * (1 - fraction_completed)
    ELSE
      interval '0'
  END AS estimated_remaining,
  CASE
    WHEN fraction_completed > 0 THEN
      started + ((now() - started) / fraction_completed)
    ELSE
      NULL
  END AS estimated_completion
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE'
  AND status = 'running'
  AND fraction_completed > 0;
```

**Important**: Estimates assume constant progress rate. Actual time may vary.

### 3. Monitor with Watch Command

```bash
# Update every 30 seconds
watch -n 30 "cockroach sql --insecure -e \"
  SELECT job_id, fraction_completed, running_status, now() - started AS duration
  FROM [SHOW JOBS]
  WHERE job_type = 'SCHEMA CHANGE' AND status = 'running';\""
```

### 4. Detect Stuck Schema Changes

```sql
-- Find jobs with no progress (< 5% in 10+ minutes)
SELECT
  job_id,
  description,
  fraction_completed,
  running_status,
  now() - started AS total_duration
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE'
  AND status = 'running'
  AND now() - started > interval '10 minutes'
  AND fraction_completed < 0.05;
```

### 5. View Recent Schema Change History

```sql
-- Completed and failed schema changes (last 7 days)
SELECT
  job_id,
  description,
  status,
  started,
  finished,
  finished - started AS duration,
  error
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE'
  AND started > now() - interval '7 days'
ORDER BY started DESC;
```

## Monitoring Script

```bash
#!/bin/bash
# monitor-schema-change.sh <job_id>

JOB_ID=$1
HOST="localhost:26257"

if [ -z "$JOB_ID" ]; then
  echo "Usage: $0 <job_id>"
  exit 1
fi

echo "=== Monitoring Schema Change Job $JOB_ID ==="
PREV_PROGRESS=0

while true; do
  STATUS=$(cockroach sql --insecure --host=$HOST --format=tsv -e \
    "SELECT status, fraction_completed, running_status FROM [SHOW JOBS] WHERE job_id = $JOB_ID;" | tail -1)

  JOB_STATUS=$(echo "$STATUS" | cut -f1)
  PROGRESS=$(echo "$STATUS" | cut -f2)
  PHASE=$(echo "$STATUS" | cut -f3)
  PERCENT=$(echo "$PROGRESS * 100" | bc -l | xargs printf "%.1f")

  echo "[$(date +%H:%M:%S)] $PERCENT% complete | Phase: $PHASE | Status: $JOB_STATUS"

  if [ "$JOB_STATUS" = "succeeded" ]; then
    echo "✓ Schema change completed successfully!"
    break
  fi

  if [ "$JOB_STATUS" = "failed" ] || [ "$JOB_STATUS" = "canceled" ]; then
    echo "✗ Schema change $JOB_STATUS"
    break
  fi

  if [ "$PROGRESS" = "$PREV_PROGRESS" ]; then
    echo "  ⚠ Warning: No progress since last check"
  fi

  PREV_PROGRESS=$PROGRESS
  sleep 60
done
```

## Common Patterns

### Pattern 1: Create Index and Monitor

```sql
-- Start index creation
CREATE INDEX idx_users_email ON users(email);

-- Get job ID
SELECT job_id, description, fraction_completed
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE'
  AND status = 'running'
  AND description LIKE '%idx_users_email%';

-- Then run monitoring script
```

### Pattern 2: Multi-Job Dashboard

```sql
-- Dashboard for all active schema changes
SELECT
  job_id,
  substring(description, 1, 40) AS operation,
  round(fraction_completed * 100, 1) AS pct,
  running_status AS phase,
  extract(epoch from (now() - started)) / 60 AS elapsed_min,
  CASE
    WHEN fraction_completed > 0.05 THEN
      round(extract(epoch from (now() - started)) / fraction_completed / 60 * (1 - fraction_completed), 0)
    ELSE
      NULL
  END AS est_remaining_min
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE'
  AND status = 'running'
ORDER BY started;
```

### Pattern 3: Safe Cancellation

```sql
-- Check if safe to cancel (only if < 10% complete)
SELECT
  job_id,
  description,
  fraction_completed,
  running_status
FROM [SHOW JOBS]
WHERE job_id = 789;

-- Cancel job (if appropriate - work is lost)
CANCEL JOB 789;

-- Verify cancellation
SELECT status, error FROM [SHOW JOBS] WHERE job_id = 789;
```

## Troubleshooting

### Schema Change Taking Too Long

**Diagnosis**:
```sql
-- Check table size
SELECT
  table_name,
  total_bytes / 1024 / 1024 / 1024 AS size_gb,
  range_count
FROM [SHOW RANGES FROM TABLE users WITH DETAILS];

-- Check cluster load (requires unsafe internals access in v26.1+)
SET allow_unsafe_internals = true;
SELECT avg(value) AS avg_cpu_pct
FROM crdb_internal.node_metrics
WHERE name = 'sys.cpu.combined.percent-normalized';
```

**Common causes**:
- Very large table (100GB+)
- High concurrent write load
- Limited cluster resources
- Many existing indexes

**Solution**:
```sql
-- Increase concurrent requests (use cautiously)
SET CLUSTER SETTING kv.bulk_io_write.concurrent_addsstable_requests = 10;
-- Default: 5 per store
```

### Schema Change Appears Stuck

**Diagnosis**:
```sql
-- Check if job is actually running
SELECT
  job_id,
  status,
  running_status,
  num_runs,
  last_run
FROM [SHOW JOBS]
WHERE job_id = 789;

-- Check for node failures
SELECT node_id, is_live
FROM crdb_internal.gossip_liveness
WHERE is_live = false;
```

**Common causes**:
- Node failure (coordinator went down)
- Out of memory
- Disk space exhausted
- Network partition

**Fix**: Check cluster health with `cockroach node status` and review logs.

### Schema Change Failed

**Common errors**:

1. **"duplicate key value violates unique constraint"**
   - Creating unique index on column with duplicates
   - Fix: Remove duplicates before creating index

2. **"memory budget exceeded"**
   - Schema change requires more memory than available
   - Fix: Increase node memory or reduce concurrent load

3. **"context canceled"**
   - Job was manually canceled
   - Fix: Restart schema change if needed

```sql
-- Get failure details
SELECT job_id, description, error, finished - started AS duration_before_failure
FROM [SHOW JOBS]
WHERE job_id = 789;
```

## Best Practices

### 1. Monitor Before Starting

```sql
-- Check cluster health (no under-replicated ranges)
-- Note: Requires unsafe internals access in v26.1+
SET allow_unsafe_internals = true;
SELECT count(*)
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
-- Should be 0

-- Check cluster load (should be < 70%)
SELECT avg(value) AS avg_cpu
FROM crdb_internal.node_metrics
WHERE name = 'sys.cpu.combined.percent-normalized';
```

### 2. Run During Low-Traffic Periods

Schema changes run faster with less concurrent write load. Schedule for off-peak hours when possible.

### 3. Test on Staging First

Restore production backup to staging, run schema change, measure timing, then extrapolate for production.

### 4. Set Up Alerts

```sql
-- Alert if schema change running > 1 hour
SELECT job_id, description, now() - started AS duration
FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE'
  AND status = 'running'
  AND now() - started > interval '1 hour';
```

### 5. Document Maintenance Windows

```bash
# Create change log
cat >> schema-changes.log <<EOF
Date: $(date)
Job: CREATE INDEX idx_users_email ON users(email)
Job ID: 789
Estimated duration: 15 minutes
Started by: ops-team
EOF
```

### 6. Verify Before Shutdown

Only shut down if job is fully complete (status = succeeded).

## Performance Factors

| Factor | Impact | Solution |
|--------|--------|----------|
| **Table size** | Larger = slower | Consider partitioning |
| **Concurrent writes** | More writes = slower | Run during low traffic |
| **Cluster resources** | Limited CPU/disk = slower | Scale cluster |
| **Number of indexes** | More indexes = slower validation | Only create necessary indexes |
| **Network latency** | High latency = slower | Optimize network |

## Related Skills

- **create-secondary-indexes-on-single-columns**: Create indexes requiring monitoring
- **alter-table-add-column**: Modify tables with schema changes
- **cancel-long-running-queries-and-sessions**: Cancel problematic schema changes
- **monitor-all-job-types-with-show-jobs**: Monitor all background jobs
- **identify-slow-queries-with-db-console-statements-page**: Identify queries needing indexes

## Examples

### Complete CREATE INDEX Workflow

```sql
-- 1. Check table size
SELECT table_name, total_bytes / 1024 / 1024 / 1024 AS size_gb
FROM [SHOW RANGES FROM TABLE users WITH DETAILS] LIMIT 1;

-- 2. Start index creation
CREATE INDEX idx_users_email ON users(email);

-- 3. Get job ID
SELECT job_id FROM [SHOW JOBS]
WHERE job_type = 'SCHEMA CHANGE' AND status = 'running'
  AND description LIKE '%idx_users_email%';

-- 4. Monitor progress (loop or watch)
SELECT
  round(fraction_completed * 100, 1) AS pct,
  running_status,
  now() - started AS elapsed,
  ((now() - started) / NULLIF(fraction_completed, 0)) * (1 - fraction_completed) AS est_remaining
FROM [SHOW JOBS] WHERE job_id = 789;

-- 5. Verify completion
SELECT status, finished - started AS total_duration
FROM [SHOW JOBS] WHERE job_id = 789;

-- 6. Verify index is active
SHOW INDEXES FROM users;
```

## Testing

```bash
# Test against local cluster

# 1. Create test table with data
cockroach sql --insecure -e "
  CREATE TABLE test_monitoring (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), data TEXT);
  INSERT INTO test_monitoring (data) SELECT repeat('x', 1000) FROM generate_series(1, 100000);
"

# 2. Start schema change
cockroach sql --insecure -e "CREATE INDEX idx_test_data ON test_monitoring(data);" &

# 3. Test monitoring query
cockroach sql --insecure -e "
  SELECT job_id, fraction_completed, running_status
  FROM [SHOW JOBS] WHERE job_type = 'SCHEMA CHANGE' AND status = 'running';
"

# 4. Cleanup
cockroach sql --insecure -e "DROP TABLE test_monitoring CASCADE;"
```

---

**Version**: 1.0.0
**Last Updated**: March 6, 2026
**Tested Against**: CockroachDB v26.1.0
