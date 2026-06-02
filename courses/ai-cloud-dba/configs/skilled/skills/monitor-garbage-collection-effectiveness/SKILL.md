---
name: monitor-garbage-collection-effectiveness
description: Monitor garbage collection effectiveness using metrics, DB Console, and SQL queries to track GC activity, identify performance issues, and optimize MVCC version cleanup.
metadata:
  domain: Data Management
  bloom_level: Evaluate
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Monitor Garbage Collection Effectiveness

**Domain**: Data Management
**Bloom's Level**: Evaluate

## What This Skill Teaches

This skill teaches how to **monitor and evaluate** garbage collection effectiveness in CockroachDB, identifying when GC is working well and when it needs attention.

You'll learn to:
- Track GC metrics (gc.num_runs, gc.num_resolved, garbage bytes)
- Calculate garbage accumulation percentage
- Use DB Console for GC visualization
- Monitor protected timestamps that block GC
- Identify range bloat and GC bottlenecks
- Correlate GC activity with storage trends
- Troubleshoot GC performance issues
- Create alerts for GC problems

**Key metrics**:
- **MVCC Garbage**: `(key_bytes + value_bytes) - live_bytes`
- **Garbage Percentage**: `garbage_bytes / total_bytes × 100`
- **GC Run Rate**: Frequency of GC operations
- **Protected Timestamps**: Timestamps blocking GC

---

## Understanding GC Metrics

### Core Metrics

| Metric | Description | Good Value | Red Flag |
|--------|-------------|------------|----------|
| **MVCC Garbage Bytes** | Old versions awaiting GC | < 30% of total | > 50% of total |
| **GC Run Count** | Number of GC operations | Steady, proportional to writes | Declining or zero |
| **GC Resolved Count** | Versions successfully cleaned | Increasing with writes | Stagnant |
| **Protected Timestamps** | Timestamps blocking GC | 0-2 (during backups) | Many, or very old |
| **Range Size** | Including all versions | Stable or slowly growing | Rapid growth |

### Metric Relationships

**Healthy GC**:
```
High write rate → Many GC runs → High resolved count → Low garbage %
```

**Unhealthy GC**:
```
High write rate → Few/no GC runs → Low resolved count → High garbage %
                     OR
High write rate → Many GC runs → Low resolved count → High garbage %
                     (Protected timestamps blocking GC)
```

---

## Method 1: SQL-Based Monitoring

### 1.1 Cluster-Wide Garbage Accumulation

```sql
-- Total MVCC garbage across cluster
SELECT
  round(sum(key_bytes + value_bytes) / (1024*1024*1024.0), 2) AS total_gb,
  round(sum(live_bytes) / (1024*1024*1024.0), 2) AS live_gb,
  round(sum(key_bytes + value_bytes - live_bytes) / (1024*1024*1024.0), 2) AS garbage_gb,
  round(100.0 * sum(key_bytes + value_bytes - live_bytes) / NULLIF(sum(key_bytes + value_bytes), 0), 1) AS garbage_pct
FROM crdb_internal.ranges_no_leases;
```

**Example output**:
```
  total_gb | live_gb | garbage_gb | garbage_pct
-----------+---------+------------+-------------
    250.50 |  200.00 |      50.50 |        20.2
```

**Interpretation**:
- `garbage_pct < 20%`: Excellent - GC keeping up well
- `garbage_pct 20-30%`: Good - Normal operation
- `garbage_pct 30-50%`: Warning - Monitor closely
- `garbage_pct > 50%`: Critical - GC not keeping up

### 1.2 Per-Table Garbage Analysis

```sql
-- Garbage by table (top offenders)
SELECT
  table_name,
  round(approximate_disk_bytes / (1024*1024*1024.0), 2) AS disk_gb,
  round(live_bytes / (1024*1024*1024.0), 2) AS live_gb,
  round((approximate_disk_bytes - live_bytes) / (1024*1024*1024.0), 2) AS garbage_gb,
  round(100.0 * (approximate_disk_bytes - live_bytes) / NULLIF(approximate_disk_bytes, 0), 1) AS garbage_pct
FROM crdb_internal.table_stats
WHERE approximate_disk_bytes > 0
ORDER BY garbage_gb DESC
LIMIT 20;
```

**Example output**:
```
  table_name  | disk_gb | live_gb | garbage_gb | garbage_pct
--------------+---------+---------+------------+-------------
  events      |   50.00 |   30.00 |      20.00 |        40.0
  sessions    |   25.00 |   20.00 |       5.00 |        20.0
  logs        |   15.00 |   14.00 |       1.00 |         6.7
```

**Action items**:
- `events`: 40% garbage → investigate gc.ttlseconds or protected timestamps
- `sessions`: 20% garbage → healthy
- `logs`: 7% garbage → excellent

### 1.3 Per-Range Garbage (Detailed View)

```sql
-- Top 20 ranges by garbage accumulation
SELECT
  range_id,
  start_pretty,
  database_name,
  table_name,
  round((key_bytes + value_bytes) / (1024*1024.0), 2) AS total_mb,
  round(live_bytes / (1024*1024.0), 2) AS live_mb,
  round((key_bytes + value_bytes - live_bytes) / (1024*1024.0), 2) AS garbage_mb,
  round(100.0 * (key_bytes + value_bytes - live_bytes) / NULLIF(key_bytes + value_bytes, 0), 1) AS garbage_pct
FROM crdb_internal.ranges_no_leases
WHERE (key_bytes + value_bytes - live_bytes) > 10485760  -- > 10 MB garbage
ORDER BY garbage_mb DESC
LIMIT 20;
```

**Use case**: Identify specific ranges with GC problems.

### 1.4 Protected Timestamps (GC Blockers)

```sql
-- View protected timestamps that prevent GC
SELECT
  id,
  timestamp,
  (now() - timestamp)::INTERVAL AS age,
  meta_type,
  CASE
    WHEN meta_type = 'jobs' THEN 'Backup/Changefeed Job'
    WHEN meta_type = 'schema_change' THEN 'Schema Change'
    ELSE meta_type
  END AS description
FROM crdb_internal.kv_protected_ts_records
ORDER BY timestamp;
```

**Example output**:
```
   id   |        timestamp         |     age      | meta_type |      description
--------+--------------------------+--------------+-----------+-----------------------
  12345 | 2026-03-06 10:00:00 UTC  | 00:15:00     | jobs      | Backup/Changefeed Job
  12346 | 2026-03-06 09:00:00 UTC  | 01:15:00     | jobs      | Backup/Changefeed Job
```

**Red flags**:
- Age > 6 hours: Stalled backup or changefeed
- Many records: Multiple concurrent jobs
- Very old timestamps: Zombie jobs blocking GC

**Correlation**:
```sql
-- Find jobs associated with protected timestamps
SELECT
  job_id,
  job_type,
  status,
  created,
  (now() - created)::INTERVAL AS job_age
FROM [SHOW JOBS]
WHERE job_type IN ('CHANGEFEED', 'BACKUP')
  AND status IN ('running', 'pause-requested')
ORDER BY created;
```

### 1.5 GC Configuration Audit

```sql
-- All custom gc.ttlseconds configurations
SELECT
  target,
  CAST(regexp_extract(raw_config_sql, 'gc\.ttlseconds = (\d+)') AS INT) AS gc_ttl_seconds,
  CAST(regexp_extract(raw_config_sql, 'gc\.ttlseconds = (\d+)') AS INT) / 3600.0 AS gc_ttl_hours
FROM [SHOW ZONE CONFIGURATIONS]
WHERE raw_config_sql LIKE '%gc.ttlseconds%'
ORDER BY gc_ttl_seconds DESC;
```

**Example output**:
```
         target          | gc_ttl_seconds | gc_ttl_hours
-------------------------+----------------+--------------
 TABLE audit_log         |         604800 |       168.00  -- 7 days
 DATABASE production     |          43200 |        12.00  -- 12 hours
 RANGE default           |          14400 |         4.00  -- 4 hours
 TABLE sessions          |           3600 |         1.00  -- 1 hour
```

---

## Method 2: DB Console Monitoring

### Accessing GC Metrics

**Navigate to**: DB Console (`http://localhost:8080`) → Metrics → Advanced Metrics

### Key Dashboard Views

#### 2.1 Storage Dashboard

**Path**: Metrics → Storage

**Key graphs**:

1. **Live Bytes**
   - Shows current data size without MVCC garbage
   - Should grow steadily with data insertion

2. **Total Bytes (Key + Value)**
   - Shows total storage including all versions
   - Gap between this and Live Bytes = MVCC Garbage

3. **MVCC Garbage** (derived)
   - Visual representation: `(Key Bytes + Value Bytes) - Live Bytes`
   - Should remain < 30% of Total Bytes

**Visualization**:
```
Total Bytes ─────────────────────────────────  (e.g., 500 GB)
                                        ▲
                                        │ MVCC Garbage (e.g., 100 GB = 20%)
                                        │
Live Bytes  ─────────────────────────── (e.g., 400 GB)
```

#### 2.2 Queue Dashboard

**Path**: Metrics → Queues → GC Queue

**Key metrics**:

1. **GC Queue Processing Rate**
   - Ranges processed per second
   - Should increase with write activity

2. **GC Queue Pending Ranges**
   - Ranges waiting for GC
   - High value: GC falling behind

3. **GC Queue Successes/Failures**
   - Track GC operation outcomes
   - Failures: investigate logs

#### 2.3 Advanced GC Metrics

**Path**: Metrics → Advanced Debug → search "gc"

1. **gc.num_runs**
   - Total GC operations executed
   - Should increase steadily

2. **gc.num_resolved**
   - MVCC versions successfully cleaned
   - Should correlate with write volume

3. **gc.num_txns**
   - Transactions cleaned up
   - Tracks txn record cleanup

**Query metrics directly** (requires prometheus/time-series setup):
```promql
# Garbage accumulation rate
rate(gc_num_resolved[5m])

# GC effectiveness ratio
gc_num_resolved / gc_num_runs
```

---

## Method 3: Trend Analysis

### 3.1 Storage Growth Over Time

```sql
-- Track storage growth daily
-- (Requires time-series data or periodic snapshots)

-- Example snapshot query (run daily, store results)
SELECT
  now() AS snapshot_time,
  round(sum(key_bytes + value_bytes) / (1024*1024*1024.0), 2) AS total_gb,
  round(sum(live_bytes) / (1024*1024*1024.0), 2) AS live_gb,
  round(sum(key_bytes + value_bytes - live_bytes) / (1024*1024*1024.0), 2) AS garbage_gb,
  round(100.0 * sum(key_bytes + value_bytes - live_bytes) / NULLIF(sum(key_bytes + value_bytes), 0), 1) AS garbage_pct
FROM crdb_internal.ranges_no_leases;
```

**Store in monitoring table**:
```sql
CREATE TABLE gc_metrics_history (
  snapshot_time TIMESTAMPTZ PRIMARY KEY,
  total_gb DECIMAL,
  live_gb DECIMAL,
  garbage_gb DECIMAL,
  garbage_pct DECIMAL
);

-- Insert daily snapshots
INSERT INTO gc_metrics_history
SELECT now(), total_gb, live_gb, garbage_gb, garbage_pct
FROM (...); -- above query
```

**Analyze trends**:
```sql
-- 7-day garbage percentage trend
SELECT
  DATE(snapshot_time) AS date,
  avg(garbage_pct) AS avg_garbage_pct
FROM gc_metrics_history
WHERE snapshot_time > now() - interval '7 days'
GROUP BY DATE(snapshot_time)
ORDER BY date;
```

### 3.2 GC Effectiveness Score

Calculate a simple effectiveness score:

```sql
WITH metrics AS (
  SELECT
    sum(key_bytes + value_bytes - live_bytes) AS garbage_bytes,
    sum(key_bytes + value_bytes) AS total_bytes,
    count(*) FILTER (WHERE (key_bytes + value_bytes - live_bytes) > live_bytes * 0.5) AS high_garbage_ranges,
    count(*) AS total_ranges
  FROM crdb_internal.ranges_no_leases
)
SELECT
  round(100.0 * garbage_bytes / NULLIF(total_bytes, 0), 1) AS garbage_pct,
  high_garbage_ranges,
  total_ranges,
  CASE
    WHEN garbage_bytes::FLOAT / NULLIF(total_bytes, 0) < 0.20 THEN 'Excellent'
    WHEN garbage_bytes::FLOAT / NULLIF(total_bytes, 0) < 0.30 THEN 'Good'
    WHEN garbage_bytes::FLOAT / NULLIF(total_bytes, 0) < 0.50 THEN 'Fair'
    ELSE 'Poor'
  END AS gc_health
FROM metrics;
```

**Example output**:
```
 garbage_pct | high_garbage_ranges | total_ranges | gc_health
-------------+---------------------+--------------+-----------
        18.5 |                   3 |          450 | Excellent
```

---

## Monitoring Scenarios

### Scenario 1: Normal Operation

**Characteristics**:
- Garbage % steady at 15-25%
- GC run count increasing with writes
- No protected timestamps (except during backups)
- Storage growing linearly with data

**SQL check**:
```sql
SELECT
  round(100.0 * sum(key_bytes + value_bytes - live_bytes) / NULLIF(sum(key_bytes + value_bytes), 0), 1) AS garbage_pct,
  count(*) AS protected_ts_count
FROM crdb_internal.ranges_no_leases
CROSS JOIN crdb_internal.kv_protected_ts_records;
```

**Expected**: `garbage_pct: 15-25, protected_ts_count: 0-2`

### Scenario 2: High Garbage Accumulation

**Characteristics**:
- Garbage % > 50%
- GC runs occurring but not reducing garbage
- Possible protected timestamps blocking GC

**Investigation**:
```sql
-- 1. Identify problem tables
SELECT table_name, garbage_pct
FROM (
  SELECT
    table_name,
    round(100.0 * (approximate_disk_bytes - live_bytes) / NULLIF(approximate_disk_bytes, 0), 1) AS garbage_pct
  FROM crdb_internal.table_stats
)
WHERE garbage_pct > 50
ORDER BY garbage_pct DESC;

-- 2. Check protected timestamps
SELECT * FROM crdb_internal.kv_protected_ts_records;

-- 3. Check gc.ttlseconds settings
SHOW ZONE CONFIGURATIONS;
```

**Action**:
- If protected timestamps: Cancel stalled jobs
- If gc.ttlseconds too long: Reduce it
- If neither: Investigate compaction performance

### Scenario 3: Stalled Garbage Collection

**Characteristics**:
- GC run count not increasing
- Garbage % steadily rising
- No compaction activity

**Diagnosis**:
```sql
-- Check recent compaction (via DB Console: Metrics → Storage → Compactions)
-- Or check range statistics
SELECT
  count(*) AS ranges_needing_gc
FROM crdb_internal.ranges_no_leases
WHERE (key_bytes + value_bytes - live_bytes) > live_bytes * 0.3;
```

**Possible causes**:
- Cluster overloaded (CPU/disk saturation)
- Compaction throttled
- Storage issues

**Action**:
- Check DB Console: Hardware → CPU/Disk metrics
- Review logs for compaction errors
- Consider scaling cluster

### Scenario 4: Protected Timestamp Leak

**Characteristics**:
- Multiple old protected timestamps
- Garbage % increasing despite low gc.ttlseconds
- Stalled backup/changefeed jobs

**Diagnosis**:
```sql
-- Find old protected timestamps
SELECT
  id,
  timestamp,
  (now() - timestamp)::INTERVAL AS age,
  meta_type
FROM crdb_internal.kv_protected_ts_records
WHERE timestamp < (now() - interval '6 hours')
ORDER BY timestamp;

-- Find associated jobs
SELECT job_id, job_type, status, created
FROM [SHOW JOBS]
WHERE job_type IN ('CHANGEFEED', 'BACKUP')
  AND created < (now() - interval '6 hours')
  AND status IN ('running', 'pause-requested');
```

**Action**:
```sql
-- Cancel stalled jobs
CANCEL JOB <job_id>;

-- Verify protected timestamp removed
SELECT * FROM crdb_internal.kv_protected_ts_records;
```

---

## Creating Monitoring Alerts

### Alert 1: High Garbage Percentage

```sql
-- Alert if cluster-wide garbage > 40%
SELECT
  round(100.0 * sum(key_bytes + value_bytes - live_bytes) / NULLIF(sum(key_bytes + value_bytes), 0), 1) AS garbage_pct
FROM crdb_internal.ranges_no_leases
HAVING round(100.0 * sum(key_bytes + value_bytes - live_bytes) / NULLIF(sum(key_bytes + value_bytes), 0), 1) > 40;
```

**Alert threshold**: garbage_pct > 40

**Response**: Investigate gc.ttlseconds and protected timestamps.

### Alert 2: Old Protected Timestamps

```sql
-- Alert if protected timestamps older than 12 hours
SELECT count(*) AS old_protected_ts
FROM crdb_internal.kv_protected_ts_records
WHERE timestamp < (now() - interval '12 hours')
HAVING count(*) > 0;
```

**Alert threshold**: count > 0

**Response**: Cancel stalled backup/changefeed jobs.

### Alert 3: Range Bloat

```sql
-- Alert if any range has > 1 GB garbage
SELECT count(*) AS bloated_ranges
FROM crdb_internal.ranges_no_leases
WHERE (key_bytes + value_bytes - live_bytes) > 1073741824  -- 1 GB
HAVING count(*) > 0;
```

**Alert threshold**: count > 5

**Response**: Investigate specific ranges, check for split issues.

### Alert 4: GC Not Running

**DB Console Alert**: Set up alert on `gc.num_runs` metric
- Alert if rate `< 0.1 runs/minute` for 30+ minutes
- Indicates GC queue stalled

---

## Best Practices

### 1. Establish Baseline Metrics

```sql
-- Record baseline during normal operation
SELECT
  round(100.0 * sum(key_bytes + value_bytes - live_bytes) / NULLIF(sum(key_bytes + value_bytes), 0), 1) AS baseline_garbage_pct
FROM crdb_internal.ranges_no_leases;
```

**Use baseline**: Alert when garbage % exceeds `baseline + 20%`.

### 2. Regular Monitoring Schedule

**Daily**:
- Check cluster-wide garbage %
- Review top 10 tables by garbage

**Weekly**:
- Analyze storage growth trends
- Review gc.ttlseconds configurations

**Monthly**:
- Audit zone configurations
- Review historical GC metrics

### 3. Automated Reporting

```sql
-- Weekly GC health report
SELECT
  'Cluster Summary' AS category,
  concat(
    'Total: ', round(sum(key_bytes + value_bytes) / (1024*1024*1024.0), 2), ' GB, ',
    'Live: ', round(sum(live_bytes) / (1024*1024*1024.0), 2), ' GB, ',
    'Garbage: ', round(100.0 * sum(key_bytes + value_bytes - live_bytes) / NULLIF(sum(key_bytes + value_bytes), 0), 1), '%'
  ) AS details
FROM crdb_internal.ranges_no_leases
UNION ALL
SELECT
  'Protected Timestamps' AS category,
  concat(count(*), ' active') AS details
FROM crdb_internal.kv_protected_ts_records
UNION ALL
SELECT
  'High Garbage Tables' AS category,
  string_agg(table_name, ', ') AS details
FROM (
  SELECT table_name
  FROM crdb_internal.table_stats
  WHERE 100.0 * (approximate_disk_bytes - live_bytes) / NULLIF(approximate_disk_bytes, 0) > 40
  LIMIT 5
);
```

### 4. Correlate with Workload

Monitor GC effectiveness relative to write volume:
- High writes + low garbage = excellent GC
- High writes + high garbage = investigate
- Low writes + high garbage = gc.ttlseconds too long

### 5. Document Expected Ranges

**Document per-environment targets**:
```
Development:   garbage_pct target < 15% (aggressive GC)
Staging:       garbage_pct target < 25% (moderate GC)
Production:    garbage_pct target < 30% (conservative GC)
```

---

## Troubleshooting GC Monitoring Issues

### Issue: Metrics Not Available

**Symptom**: `crdb_internal.ranges_no_leases` returns no data.

**Cause**: Permission issue or cluster not initialized.

**Solution**:
```sql
-- Verify permissions
SHOW GRANTS ON crdb_internal.ranges_no_leases;

-- Use alternative (slower)
SELECT * FROM crdb_internal.ranges;
```

### Issue: Garbage Calculation Seems Wrong

**Symptom**: Negative garbage or > 100%.

**Cause**: Race condition in reading ranges.

**Solution**:
```sql
-- Add safety checks
SELECT
  round(100.0 * GREATEST(0, sum(key_bytes + value_bytes - live_bytes)) / NULLIF(sum(key_bytes + value_bytes), 0), 1) AS garbage_pct
FROM crdb_internal.ranges_no_leases;
```

---

## Related Skills

**Data Management**:
- `configure-garbage-collection-ttl-settings` - Adjust GC based on monitoring findings
- `configure-garbage-collection-settings` - GC configuration methods
- `understand-how-mvcc-and-garbage-collection-affect-storage` - GC concepts
- `understand-mvcc-multi-version-concurrency-control-concepts` - MVCC foundation

**Monitoring**:
- `monitor-storage-capacity-and-growth` - Broader storage monitoring
- `monitor-compaction-activity-and-read-amplification` - Compaction metrics
- `query-cluster-timeseries-metrics` - Advanced metrics querying

**Troubleshooting**:
- `troubleshoot-slow-queries-due-to-storage-issues` - Storage-related performance
- `investigate-storage-hot-spots` - Range-level storage issues

---

## References

- [CockroachDB Docs: Monitor and Debug](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html)
- [CockroachDB Docs: DB Console Overview](https://www.cockroachlabs.com/docs/stable/ui-overview.html)
- [CockroachDB Docs: Storage Layer](https://www.cockroachlabs.com/docs/stable/architecture/storage-layer.html)
- [Blog: Monitoring MVCC Garbage Collection](https://www.cockroachlabs.com/blog/mvcc-garbage-collection/)

---

**Version**: 1.0.0
**Last Updated**: March 6, 2026
**Tested Against**: CockroachDB v26.1.0
