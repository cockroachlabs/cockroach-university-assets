---
name: monitor-write-amplification-metrics
description: Monitor write amplification using rocksdb.write-amplification metric. Track bytes written vs bytes ingested, alert when ratio exceeds 10, analyze by store and node, and correlate with compaction settings and workload type.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Monitor Write Amplification Metrics

**Domain**: Monitoring and Alerting
**Bloom's Level**: Apply

## What This Skill Teaches

This skill teaches how to **monitor and analyze** write amplification in CockroachDB using RocksDB metrics to identify storage inefficiencies and optimize compaction.

You'll learn to:
- Monitor rocksdb.write-amplification metric
- Calculate write amplification ratio (bytes written / bytes ingested)
- Set up alerts for high write amplification (ratio > 10)
- Analyze write amplification by store and node
- Correlate write amplification with compaction settings
- Understand workload impact on write amplification
- Troubleshoot storage performance issues

**Key metric**: **Write Amplification Ratio** = `bytes_written_to_disk / bytes_ingested_by_application`

**Thresholds**:
- Healthy: 2-8 (optimal: 3-5)
- Warning: > 10
- Critical: > 20

---

## Understanding Write Amplification

**Write amplification** measures how many times data is rewritten during compaction compared to the original write.

**Example**: Application writes 1 GB → RocksDB writes 5 GB to disk → Write Amplification = 5

**Impact**: Disk wear, I/O saturation, performance degradation, increased latency and cost

| Ratio | Assessment | Typical Cause |
|-------|------------|---------------|
| 2-3 | Excellent | Sequential writes, good LSM tuning |
| 4-6 | Good | Mixed workload, default settings |
| 7-9 | Acceptable | Write-heavy workload, some hot keys |
| 10-15 | Warning | Poor compaction tuning, hot keys |
| > 15 | Critical | Severe compaction issues |

---

## Method 1: DB Console Monitoring

**Navigate to**: DB Console (`http://localhost:8080`) → Metrics → Storage

**Key dashboards**:
- **Write Amplification Graph**: Current ratio per store, red flag when > 10
- **Bytes Written vs Ingested**: Large gap indicates high amplification
- **Per-Store Analysis**: Compare stores to identify outliers

---

## Method 2: SQL-Based Monitoring

### 2.1 Current Write Amplification by Store

```sql
-- Write amplification per store
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  round((metrics->>'storage.write-amplification')::FLOAT, 2) AS write_amplification
FROM crdb_internal.kv_store_status
ORDER BY write_amplification DESC;
```

**Example output**:
```
 store_id | node_id | write_amplification
----------+---------+---------------------
        2 |       2 |               12.50  -- INVESTIGATE
        1 |       1 |                5.20  -- Normal
        3 |       3 |                4.80  -- Normal
```

### 2.2 Write Amplification with Byte Counts

```sql
-- Detailed write metrics per store
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  round((metrics->>'storage.write-amplification')::FLOAT, 2) AS write_amp,
  round((metrics->>'rocksdb.compacted-bytes-written')::FLOAT::INT / 1073741824.0, 2) AS written_gb,
  round((metrics->>'rocksdb.ingested-bytes')::FLOAT::INT / 1073741824.0, 2) AS ingested_gb
FROM crdb_internal.kv_store_status
ORDER BY write_amp DESC;
```

**Example output**:
```
 store_id | node_id | write_amp | written_gb | ingested_gb
----------+---------+-----------+------------+-------------
        2 |       2 |     12.50 |     250.00 |       20.00  -- 12.5x amplification
        1 |       1 |      5.20 |     104.00 |       20.00  -- 5.2x amplification
        3 |       3 |      4.80 |      96.00 |       20.00  -- 4.8x amplification
```

**Analysis**: Store 2 has excessive compaction activity (250 GB written vs 20 GB ingested).

### 2.3 Cluster-Wide Average

```sql
-- Cluster-wide write amplification summary
SET allow_unsafe_internals = true;

SELECT
  round(avg((metrics->>'storage.write-amplification')::FLOAT), 2) AS cluster_avg,
  round(max((metrics->>'storage.write-amplification')::FLOAT), 2) AS cluster_max
FROM crdb_internal.kv_store_status;
```

**Healthy**: avg < 8, max < 12 | **Unhealthy**: avg > 10, max > 15

---

## Method 3: Compaction Correlation

### 3.1 Write Amplification vs Compaction Activity

```sql
-- Correlate write amp with compaction metrics
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  round((metrics->>'storage.write-amplification')::FLOAT, 2) AS write_amp,
  (metrics->>'rocksdb.compactions')::FLOAT::INT AS total_compactions,
  round((metrics->>'rocksdb.estimated-pending-compaction')::FLOAT::INT / 1048576.0, 2) AS pending_mb
FROM crdb_internal.kv_store_status
ORDER BY write_amp DESC;
```

**Example output**:
```
 node_id | store_id | write_amp | total_compactions | pending_mb
---------+----------+-----------+-------------------+------------
       2 |        2 |     12.50 |             1,500 |     500.00
       1 |        1 |      5.20 |               800 |      50.00
```

**Analysis**: High write amp + many total compactions + large pending backlog = compaction can't keep up.

### 3.2 Zone Configuration Impact

**Range size affects compaction**:
- **Larger ranges** (range_max_bytes): Fewer splits, more compaction per range
- **Smaller ranges**: More splits, less compaction per range

---

## Method 4: Workload Analysis

### 4.1 Workload Type Impact

| Workload Type | Expected Write Amp | Characteristics |
|---------------|-------------------|-----------------|
| Sequential inserts | 2-4 | New data appended, minimal compaction |
| Random inserts | 4-6 | Data scattered, moderate compaction |
| Small updates | 6-10 | Old versions created, more compaction |
| Large updates | 8-12 | Significant MVCC versions, heavy compaction |
| Mixed OLTP | 5-8 | Balanced insert/update |
| High-frequency updates | 10-15 | Hot keys, excessive compaction |

### 4.2 Detect Hot Keys

```sql
-- Ranges with highest write activity
SET allow_unsafe_internals = true;

SELECT
  range_id,
  table_name,
  writes_per_second
FROM crdb_internal.ranges
WHERE writes_per_second > 100
ORDER BY writes_per_second DESC
LIMIT 10;
```

**Hot keys** (writes_per_second > 1000) contribute to write amplification.

**Solutions**: Redesign primary key, use HASH SHARDED INDEXES, or increase range_max_bytes

---

## Monitoring Alerts

### Alert 1: High Write Amplification (Store Level)

```sql
-- Alert if any store has write amp > 10
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  round((metrics->>'storage.write-amplification')::FLOAT, 2) AS write_amp
FROM crdb_internal.kv_store_status
WHERE (metrics->>'storage.write-amplification')::FLOAT > 10;
```

**Threshold**: write_amp > 10
**Response**: Investigate specific store for hot keys or compaction issues.

### Alert 2: Cluster Average Elevated

```sql
-- Alert if cluster-wide average > 8
SET allow_unsafe_internals = true;

SELECT round(avg((metrics->>'storage.write-amplification')::FLOAT), 2) AS avg_write_amp
FROM crdb_internal.kv_store_status
HAVING round(avg((metrics->>'storage.write-amplification')::FLOAT), 2) > 8;
```

**Threshold**: avg > 8
**Response**: Cluster-wide issue, analyze workload and compaction settings.

---

## Optimization Strategies

### Strategy 1: Optimize Primary Keys for Distribution

**Problem**: Sequential UUID inserts causing hot keys and high compaction.

```sql
-- Before: Sequential UUIDs
CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  data JSONB
);

-- After: Hash sharded for distribution
CREATE TABLE events (
  id UUID DEFAULT gen_random_uuid(),
  data JSONB,
  PRIMARY KEY (id) USING HASH WITH (bucket_count = 16)
);
```

**Impact**: Reduces write amplification from 10+ to 4-6.

### Strategy 2: Adjust Range Sizing

**Problem**: Ranges too small, causing excessive splits and compaction.

```sql
-- Increase range size (512 MB → 1 GB)
ALTER TABLE write_heavy_table CONFIGURE ZONE USING
  range_max_bytes = 1073741824;
```

**Impact**: Fewer ranges, less compaction overhead.

### Strategy 3: Reduce MVCC Version Accumulation

```sql
-- Reduce GC TTL (default 4 hours → 1 hour)
ALTER TABLE frequently_updated CONFIGURE ZONE USING
  gc.ttlseconds = 3600;
```

**Impact**: Faster MVCC cleanup, less compaction work. **Warning**: Reduces historical query window.

---

## Troubleshooting Scenarios

### Scenario 1: High Amplification on One Store

**Symptoms**: One store with write amp > 12, others normal.

**Investigation**:
```sql
-- 1. Identify problem store
SET allow_unsafe_internals = true;

SELECT node_id, store_id, round((metrics->>'storage.write-amplification')::FLOAT, 2) AS write_amp
FROM crdb_internal.kv_store_status
WHERE (metrics->>'storage.write-amplification')::FLOAT > 10;

-- 2. Find hot ranges on that store
SET allow_unsafe_internals = true;

SELECT range_id, table_name, writes_per_second
FROM crdb_internal.ranges
WHERE store_id = <problem_store_id>
ORDER BY writes_per_second DESC
LIMIT 10;
```

**Likely cause**: Hot key on specific range.
**Action**: Redesign key distribution or split range.

### Scenario 2: Cluster-Wide High Amplification

**Symptoms**: All stores with write amp > 10.

**Investigation**:
```sql
-- Check workload changes
SELECT
  table_name,
  round(total_bytes_written / (1024*1024*1024.0), 2) AS written_gb
FROM crdb_internal.table_statistics
ORDER BY written_gb DESC
LIMIT 10;

-- Check recent jobs
SELECT job_id, job_type, status, created
FROM [SHOW JOBS]
WHERE created > (now() - interval '24 hours')
  AND job_type IN ('IMPORT', 'SCHEMA CHANGE')
ORDER BY created DESC;
```

**Possible causes**: Workload shift, schema change, bulk operations.
**Action**: Analyze pattern changes, review migrations.

### Scenario 3: Sudden Spike Then Recovery

**Symptoms**: Write amp jumps from 5 to 15+, then returns to normal.

**Cause**: Bulk operation (IMPORT, large UPDATE, schema change). No action needed if temporary.

---

## Best Practices

### 1. Establish Baseline Metrics

```sql
-- Record baseline during normal operation
SET allow_unsafe_internals = true;

SELECT
  round(avg((metrics->>'storage.write-amplification')::FLOAT), 2) AS baseline_avg,
  round(max((metrics->>'storage.write-amplification')::FLOAT), 2) AS baseline_max
FROM crdb_internal.kv_store_status;
```

**Use baseline**: Alert when write amp exceeds `baseline × 1.5`.

### 2. Regular Auditing Schedule

**Weekly**: Review trends, identify elevated stores/nodes, correlate with compaction.
**Monthly**: Analyze workload evolution, review zone configs, plan optimizations.

### 3. Document Expected Ranges

**Per-environment targets**: Development < 6, Staging < 8, Production < 10

---

## Related Skills

**Monitoring and Alerting**:
- `monitor-read-amplification-metrics` - Complementary read metrics
- `monitor-compaction-activity-and-read-amplification` - Compaction details
- `monitor-storage-capacity-and-growth` - Storage metrics

**Performance Optimization**:
- `design-primary-keys-to-avoid-hotspots` - Key distribution
- `use-hash-sharded-indexes-for-sequential-keys` - Hot key mitigation
- `configure-zone-replication-settings` - Range sizing

**Data Management**:
- `configure-garbage-collection-ttl-settings` - GC tuning
- `monitor-garbage-collection-effectiveness` - MVCC cleanup

---

## References

- [CockroachDB Docs: Monitoring and Alerting](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html)
- [CockroachDB Docs: DB Console](https://www.cockroachlabs.com/docs/stable/ui-overview.html)
- [RocksDB Wiki: Write Amplification](https://github.com/facebook/rocksdb/wiki/Write-Amplification)
- [Blog: LSM Trees and Write Amplification](https://www.cockroachlabs.com/blog/lsm-tree-compaction/)

---

**Version**: 1.1.0
**Last Updated**: March 6, 2026
**Tested Against**: CockroachDB v26.1.0
