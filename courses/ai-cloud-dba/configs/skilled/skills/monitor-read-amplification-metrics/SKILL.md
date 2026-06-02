---
name: monitor-read-amplification-metrics
description: Calculate read amplification using rocksdb.read-amplification metric. Track L0-L6 level reads to detect storage inefficiencies. Alert when ratio exceeds 10. Correlate with compaction activity and query performance using SHOW RANGES for per-range diagnostics.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: stable
  author: CockroachDB University
  tags:
    - monitoring
    - storage
    - performance
    - read-amplification
    - pebble
    - lsm-tree
    - compaction
---

# Monitor Read Amplification Metrics

**Domain**: Monitoring and Alerting
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you to monitor and diagnose read amplification in CockroachDB's Pebble storage engine (LSM-tree based). You will learn to:

- Understand what read amplification measures and why it matters for performance
- Calculate read amplification using `storage.read-amplification` metrics
- Track LSM-tree level statistics (L0-L6) to identify storage inefficiencies
- Set alert thresholds when read amplification exceeds 10
- Correlate high read amplification with compaction activity and query latency
- Use `SHOW RANGES` to diagnose per-range read amplification issues
- Apply optimization strategies to reduce read amplification
- Distinguish between healthy LSM-tree operation and performance-impacting problems

Read amplification directly impacts query latency because each point read may require scanning multiple SSTable files across LSM-tree levels. High read amplification (ratio > 10) indicates that reads must consult many files, causing disk I/O multiplication and degraded performance.

## Prerequisites

All queries in this skill require setting the session variable:

```sql
SET allow_unsafe_internals = true;
```

This is required to access `crdb_internal.kv_store_status` and related system tables.

## Understanding Read Amplification

**Read amplification** measures how many SSTable files must be read to satisfy a single logical read operation. In Pebble (CockroachDB's LSM-tree storage engine), data is organized in levels L0-L6, and a read may require scanning multiple files across levels.

**Formula:** `Read Amplification = Total SSTable Files Read / Logical Reads Issued`

**Performance thresholds:**
- < 5: Healthy operation
- 5-10: Elevated, monitor compaction
- > 10: Critical, investigate immediately
- > 20: Severe degradation

**LSM-Tree levels:**
- **L0**: Newly flushed memtables with overlapping key ranges (primary driver of read amplification)
- **L1-L6**: Compacted, non-overlapping ranges (increasingly larger files, more stable)

**Read path:** Memtable → L0 files (multiple overlapping) → L1-L6 files (binary search) → result

**Root cause:** When L0 accumulates too many files (sublevels), compaction falls behind, causing reads to scan excessive files. This multiplies disk I/O, increases query latency, adds CPU overhead, and pressures block cache.

## Monitoring Read Amplification Metrics

### Method 1: Current Read Amplification via DB Console

Navigate to `http://localhost:8080/metrics` → **Storage Dashboard**:

1. **Read Amplification Graph**: Shows cluster-wide read amplification over time
2. **L0 Sublevels Graph**: Displays L0 sublevel count (correlates with read amplification)
3. **Compaction Activity**: Shows compaction throughput

**Interpretation:**
- Sustained read amplification > 10 requires investigation
- Spikes during heavy write load are normal if they resolve quickly
- Correlation between high L0 sublevels and high read amplification indicates compaction backlog

### Method 2: Prometheus Metrics Export

CockroachDB exposes read amplification via `_status/vars` endpoint:

```bash
# Query read amplification metric from a node
curl -s http://localhost:8080/_status/vars | grep read_amplification

# Example output (metric names use underscores in Prometheus format):
# storage_read_amplification 7.2
# storage_l0_sublevels 12
# storage_l0_num_files 8
```

**Key metrics:**
- `storage_read_amplification`: Current read amplification ratio (Prometheus format)
- `rocksdb.read-amplification`: Same metric in JSONB format
- `storage_l0_sublevels`: L0 sublevel count
- `storage_l0_num_files`: Total L0 files
- `rocksdb.estimated-pending-compaction`: Compaction backlog (bytes)

### Method 3: Per-Store Read Amplification

```sql
-- Query per-store read amplification statistics
SELECT
  store_id,
  (metrics->>'rocksdb.read-amplification')::FLOAT AS read_amplification,
  ((metrics->>'rocksdb.num-sstables')::FLOAT)::INT AS total_sstables,
  ((metrics->>'storage.l0-num-files')::FLOAT)::INT AS l0_files,
  (metrics->>'rocksdb.estimated-pending-compaction')::BIGINT / (1024*1024*1024) AS pending_compaction_gb
FROM crdb_internal.kv_store_status
ORDER BY read_amplification DESC;
```

**Expected output:**
```
 store_id | read_amplification | total_sstables | l0_files | pending_compaction_gb
----------+--------------------+----------------+----------+-----------------------
        1 |               12.3 |            127 |       23 |                   4.2
        2 |                8.6 |             98 |       15 |                   2.1
        3 |                6.2 |             82 |        9 |                   0.8
```

**Analysis:**
- Store 1: High read amplification (12.3), elevated L0 files (23), significant compaction debt (4.2 GB) → compaction falling behind
- Store 2: Moderate read amplification (8.6), needs monitoring
- Store 3: Healthy read amplification (6.2)

### Method 4: L0-L6 Level Statistics

```sql
-- Detailed LSM-tree level breakdown per store
SELECT
  store_id,
  ((metrics->>'storage.l0-num-files')::FLOAT)::INT AS l0_files,
  ((metrics->>'storage.l1-level-size')::FLOAT)::BIGINT / (1024*1024*1024) AS l1_size_gb,
  ((metrics->>'storage.l2-level-size')::FLOAT)::BIGINT / (1024*1024*1024) AS l2_size_gb,
  ((metrics->>'storage.l3-level-size')::FLOAT)::BIGINT / (1024*1024*1024) AS l3_size_gb,
  ((metrics->>'storage.l4-level-size')::FLOAT)::BIGINT / (1024*1024*1024) AS l4_size_gb,
  ((metrics->>'storage.l5-level-size')::FLOAT)::BIGINT / (1024*1024*1024) AS l5_size_gb,
  ((metrics->>'storage.l6-level-size')::FLOAT)::BIGINT / (1024*1024*1024) AS l6_size_gb,
  (metrics->>'rocksdb.read-amplification')::FLOAT AS read_amp
FROM crdb_internal.kv_store_status
ORDER BY read_amp DESC;
```

**Note:** L1-L6 metrics show size in GB, not file counts. L0 shows file count because overlapping files at L0 are the primary driver of read amplification.

**Healthy:** L0 = 0-5 files, small level sizes, read_amp < 5
**Unhealthy:** L0 = 20+ files, large L0-L2 sizes, read_amp > 10 → compaction backlog

## Setting Alert Thresholds

### Recommended Alert Rules

Configure alerts based on these thresholds:

**CRITICAL: Read Amplification > 10**
```yaml
# Prometheus AlertManager rule
- alert: HighReadAmplification
  expr: storage_read_amplification > 10
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Read amplification exceeds 10 on {{ $labels.instance }}"
    description: "Current read amplification: {{ $value }}. Investigate compaction backlog."
```

**WARNING: Read Amplification > 7**
```yaml
- alert: ElevatedReadAmplification
  expr: storage_read_amplification > 7
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Read amplification elevated on {{ $labels.instance }}"
    description: "Current read amplification: {{ $value }}. Monitor compaction activity."
```

**WARNING: Excessive L0 Sublevels**
```yaml
- alert: HighL0Sublevels
  expr: storage_l0_sublevels > 20
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "L0 sublevels exceed 20 on {{ $labels.instance }}"
    description: "L0 sublevels: {{ $value }}. Compaction may be falling behind."
```

### SQL-Based Alert Query

```sql
-- Identify stores requiring immediate attention
SELECT
  store_id,
  (metrics->>'rocksdb.read-amplification')::FLOAT AS read_amp,
  ((metrics->>'storage.l0-num-files')::FLOAT)::INT AS l0_files,
  (metrics->>'rocksdb.estimated-pending-compaction')::BIGINT / (1024*1024*1024) AS pending_gb,
  CASE
    WHEN (metrics->>'rocksdb.read-amplification')::FLOAT > 15 THEN 'CRITICAL - Immediate action required'
    WHEN (metrics->>'rocksdb.read-amplification')::FLOAT > 10 THEN 'WARNING - High read amplification'
    WHEN (metrics->>'rocksdb.read-amplification')::FLOAT > 7 THEN 'NOTICE - Elevated, monitor closely'
    ELSE 'OK - Within normal range'
  END AS status
FROM crdb_internal.kv_store_status
WHERE (metrics->>'rocksdb.read-amplification')::FLOAT > 7
ORDER BY read_amp DESC;
```

## Correlating Read Amplification with Query Performance

### Step 1: Identify High Read Amplification Periods

```sql
-- Track read amplification trends (requires time-series data from monitoring)
-- This example uses current snapshot data
SELECT
  store_id,
  (metrics->>'rocksdb.read-amplification')::FLOAT AS current_read_amp,
  (metrics->>'rocksdb.read-amplification')::FLOAT > 10 AS exceeds_threshold
FROM crdb_internal.kv_store_status
ORDER BY current_read_amp DESC;
```

### Step 2: Correlate with Query Latency

```sql
-- Find queries with high p99 latency during read amplification spikes
WITH store_health AS (
  SELECT
    AVG((metrics->>'rocksdb.read-amplification')::FLOAT) AS avg_read_amp
  FROM crdb_internal.kv_store_status
),
slow_queries AS (
  SELECT
    metadata->>'query' AS query,
    (statistics->'statistics'->'latencyInfo'->>'p99')::FLOAT / 1000 AS p99_ms,
    (statistics->'statistics'->>'cnt')::INT AS executions
  FROM crdb_internal.statement_statistics
  WHERE (statistics->'statistics'->>'cnt')::INT > 50
)
SELECT
  query,
  p99_ms,
  executions,
  (SELECT avg_read_amp FROM store_health) AS cluster_read_amp,
  CASE
    WHEN p99_ms > 100 AND (SELECT avg_read_amp FROM store_health) > 10
      THEN 'Likely impacted by read amplification'
    ELSE 'May have other bottlenecks'
  END AS diagnosis
FROM slow_queries
ORDER BY p99_ms DESC
LIMIT 20;
```

### Step 3: Range-Level Analysis Limitations

**Note:** In CockroachDB v26.1.0, per-range query and write rate statistics are not exposed via `crdb_internal.ranges_no_leases`. To identify active ranges, use alternative approaches:

**Alternative 1: Query DB Console Metrics**

Navigate to `http://localhost:8080/metrics` → **Replication Dashboard** → **Ranges** to view per-range statistics graphically.

**Alternative 2: Basic Range Distribution**

```sql
-- View range distribution and leaseholder placement
SELECT
  range_id,
  start_pretty,
  lease_holder,
  array_length(replicas, 1) AS replica_count
FROM crdb_internal.ranges
WHERE lease_holder IS NOT NULL
ORDER BY range_id
LIMIT 50;
```

This provides basic range information but lacks query rate metrics available in earlier versions.

## Using SHOW RANGES for Per-Range Statistics

### Basic Range Inspection

```sql
-- Show detailed statistics for a specific table
SHOW RANGES FROM TABLE your_table_name;
```

**Output columns:**
- `start_key`, `end_key`: Range boundaries
- `range_id`: Unique range identifier
- `replicas`: Nodes holding replicas
- `lease_holder`: Node serving reads
- `locality`: Geographic placement

### Per-Range Read Amplification Analysis

While `SHOW RANGES` doesn't directly expose read amplification per range, you can correlate range-level activity with store-level read amplification:

```sql
-- Identify ranges on stores with high read amplification
-- Note: Per-range query rates not available in v26.1.0
WITH high_amp_stores AS (
  SELECT store_id
  FROM crdb_internal.kv_store_status
  WHERE (metrics->>'rocksdb.read-amplification')::FLOAT > 10
)
SELECT
  r.range_id,
  r.start_pretty,
  r.lease_holder AS leaseholder_store,
  r.range_size / (1024*1024) AS range_size_mb,
  CASE
    WHEN r.lease_holder IN (SELECT store_id FROM high_amp_stores)
      THEN 'Leaseholder on high read-amp store'
    ELSE 'Leaseholder on healthy store'
  END AS impact_assessment
FROM crdb_internal.ranges r
WHERE r.lease_holder IS NOT NULL
ORDER BY r.range_size DESC
LIMIT 50;
```

**Note:** This query identifies potentially affected ranges based on size and leaseholder placement. Per-range query rates are not available in `crdb_internal` tables in v26.1.0. Large ranges on high-amplification stores are more likely to be impacted.

### Range Hotspot Detection

**Note:** Range-level QPS metrics (`queries_per_second`, `writes_per_second`) are not available in `crdb_internal.ranges_no_leases` in v26.1.0. To identify hot ranges:

1. **Use DB Console**: Navigate to `http://localhost:8080/#/overview/list` → **Hot Ranges** tab
2. **Monitor range splits**: Frequent automatic splits indicate hotspots
3. **Analyze by size**: Large ranges may indicate write hotspots

```sql
-- Identify large ranges that may be hotspots
SELECT
  range_id,
  start_pretty,
  lease_holder,
  range_size / (1024*1024) AS range_size_mb
FROM crdb_internal.ranges
WHERE range_size > 64*1024*1024  -- > 64 MB
ORDER BY range_size DESC
LIMIT 20;
```

**Action:** Consider splitting large ranges to distribute load and reduce per-range read amplification impact.

## Correlating with Compaction Activity

### Monitor Compaction Metrics

```sql
-- Compaction health check
SELECT
  store_id,
  ((metrics->>'rocksdb.ingested-bytes')::FLOAT)::BIGINT / (1024*1024*1024) AS ingested_gb,
  ((metrics->>'rocksdb.compacted-bytes-written')::FLOAT)::BIGINT / (1024*1024*1024) AS compacted_gb,
  (metrics->>'rocksdb.estimated-pending-compaction')::BIGINT / (1024*1024*1024) AS pending_compaction_gb,
  (metrics->>'rocksdb.read-amplification')::FLOAT AS read_amp,
  CASE
    WHEN (metrics->>'rocksdb.estimated-pending-compaction')::BIGINT > 10*1024*1024*1024
      THEN 'Compaction falling behind'
    ELSE 'Compaction keeping up'
  END AS compaction_status
FROM crdb_internal.kv_store_status
ORDER BY pending_compaction_gb DESC;
```

### Compaction Backlog Impact

**Relationship:** Compaction merges SSTable files, reducing file count. Slow compaction → more L0 files → higher read amplification. Pending debt > 10 GB indicates backlog.

**Common causes:** High write throughput exceeding compaction bandwidth, disk I/O saturation, bulk imports, insufficient compaction concurrency.

## Optimization Strategies to Reduce Read Amplification

### 1. Tune Compaction Settings

```sql
-- Increase max concurrent compactions (default: min(3, numCPUs-1))
SET CLUSTER SETTING storage.max_compaction_concurrency = 4;
```

**Effect:** More aggressive compaction reduces L0 files. **Caution:** Increases disk I/O and CPU usage.

**Related settings:**
- `storage.compaction_concurrency`: Baseline concurrent compactions (default: 1)
- `storage.max_compaction_concurrency`: Maximum allowed (default: 0 = auto-detect)

### 2. Optimize Write Patterns

Use larger batch inserts, avoid high-frequency small writes to same keys, consider application-layer write buffering.

### 3. Schema Design

- Avoid high-cardinality indexes with frequent updates
- Use range partitioning to co-locate related data
- Minimize secondary indexes on frequently updated columns

### 4. Split Hot Ranges

```sql
ALTER TABLE orders SPLIT AT VALUES (1000000);
```

**Effect:** Distributes writes across more ranges, reducing per-range L0 accumulation.

### 5. Increase Block Cache

Set via `--cache` flag on node startup (e.g., `--cache=4GiB`). More SSTables cached in memory reduces disk reads.

## Troubleshooting High Read Amplification

### Diagnostic Checklist

**Step 1: Verify current read amplification**
```sql
SELECT store_id, (metrics->>'rocksdb.read-amplification')::FLOAT AS read_amp
FROM crdb_internal.kv_store_status
ORDER BY read_amp DESC;
```

**Step 2: Check L0 sublevel count**
```sql
SELECT store_id, ((metrics->>'storage.l0-num-files')::FLOAT)::INT AS l0_files
FROM crdb_internal.kv_store_status
WHERE ((metrics->>'storage.l0-num-files')::FLOAT)::INT > 10
ORDER BY l0_files DESC;
```

**Step 3: Assess compaction debt**
```sql
SELECT
  store_id,
  (metrics->>'rocksdb.estimated-pending-compaction')::BIGINT / (1024*1024*1024) AS pending_gb
FROM crdb_internal.kv_store_status
WHERE (metrics->>'rocksdb.estimated-pending-compaction')::BIGINT > 5*1024*1024*1024
ORDER BY pending_gb DESC;
```

**Step 4: Identify large ranges (potential write hotspots)**
```sql
-- Note: writes_per_second not available in v26.1.0
-- Use range size as proxy for write activity
SELECT range_id, start_pretty, range_size / (1024*1024) AS range_size_mb
FROM crdb_internal.ranges
WHERE range_size > 64*1024*1024
ORDER BY range_size DESC
LIMIT 20;
```

**Note:** Per-range write rates are not available via SQL in v26.1.0. Use DB Console → Hot Ranges to identify write-heavy ranges.

### Common Scenarios and Solutions

**Scenario 1: Sustained high read amplification after bulk import**
- Diagnosis: Read amp > 15, high pending compaction debt
- Solution: Allow compaction to catch up (monitor progress), schedule future imports during low-traffic, use IMPORT vs INSERT

**Scenario 2: Chronic high read amplification on specific stores**
- Diagnosis: Some stores consistently > 10, others healthy
- Solution: Check range distribution imbalance, enable load-based rebalancing

**Scenario 3: Read amplification spikes during peak traffic**
- Diagnosis: Normal off-peak, spikes during high load
- Solution: Increase compaction concurrency, consider horizontal scaling

## Best Practices

1. **Establish baselines:** Typical 4-7, peak 8-10, alert at 7 (warning) and 10 (critical)
2. **Correlate metrics:** Analyze alongside p99 latency, disk I/O, compaction throughput, write QPS
3. **Monitor L0 sublevels:** Leading indicator - alert at 15 (warning), 20 (critical)
4. **Avoid manual compaction:** Let CockroachDB manage automatically except testing/troubleshooting
5. **Plan for write bursts:** Pre-scale capacity, monitor proactively, schedule during low-traffic
6. **Use follower reads:** For read-heavy workloads, use AS OF SYSTEM TIME to offload leaseholders

## Instructions

When the user invokes this skill, guide them through read amplification monitoring:

1. Query current read amplification metrics from `crdb_internal.kv_store_status`
2. Identify stores with read amplification > 10 (critical threshold)
3. Check L0 sublevel count and compaction debt for root cause
4. Correlate with query latency metrics to assess performance impact
5. Use `SHOW RANGES` to identify hot ranges on affected stores
6. Recommend optimization strategies based on findings
7. Establish alert thresholds if not already configured

Always explain findings in terms of storage efficiency and query performance impact, providing actionable remediation steps.

## Related Skills

- **monitor-compaction-performance**: Understanding compaction metrics and tuning
- **analyze-query-latency-percentiles**: Correlating read amplification with query performance
- **troubleshoot-hot-ranges**: Identifying and resolving range hotspots
- **optimize-slow-queries**: Query optimization to reduce read operations
- **configure-prometheus-metrics-export**: Setting up alerting for read amplification
- **understand-pebble-storage-compaction**: Deep dive into LSM-tree compaction mechanics
- **calculate-amplification-metrics-from-range-statistics**: Computing write and read amplification

## Summary

Read amplification measures how many SSTable files must be read per logical read operation. In CockroachDB's Pebble storage engine, high read amplification (> 10) indicates excessive L0 file accumulation, typically caused by compaction falling behind write throughput. Monitor read amplification using `storage.read-amplification` metrics, correlate with L0 sublevel counts, and investigate compaction backlog when thresholds are exceeded. Key optimization strategies include tuning compaction concurrency, optimizing write patterns, and splitting hot ranges. Sustained high read amplification directly degrades query performance by multiplying disk I/O operations, making it a critical metric for production monitoring and alerting.
