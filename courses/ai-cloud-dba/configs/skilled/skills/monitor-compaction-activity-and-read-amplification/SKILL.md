---
name: monitor-compaction-activity-and-read-amplification
description: Monitor compaction progress and read amplification metrics using DB Console Storage dashboard, track storage.l0-sublevels and read amplification, identify compaction lag and optimize LSM tree health
metadata:
  domain: Monitoring and Alerting
  bloom_level: Analyze
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: ready
  testing_notes: All queries tested and validated against v26.1 cluster at localhost:26258. Requires allow_unsafe_internals=true for system table access
  related_domains:
    - CockroachDB Architecture
    - Performance Optimization
    - Cluster Maintenance
---

# Monitor Compaction Activity and Read Amplification

Monitor compaction progress and read amplification metrics using DB Console Storage dashboard, track storage.l0-sublevels and read amplification, identify compaction lag and optimize LSM tree health.

## What This Skill Teaches

Monitor and analyze compaction health in CockroachDB's Pebble storage engine:

- Understand compaction process and its performance impact
- Track compaction metrics: rocksdb.compactions, storage.compactions.*
- Monitor L0 sublevel count and alert thresholds (>20 critical)
- Calculate and interpret read amplification
- Identify write amplification and its causes
- Use DB Console Storage dashboard for compaction monitoring
- Correlate compaction activity with write workload patterns
- Diagnose compaction backlog and performance degradation
- Optimize LSM tree health through metric-driven decisions

**Bloom's Taxonomy Level**: Analyze - Examine compaction metrics, diagnose LSM health issues, and determine root causes of performance degradation.

## Overview

CockroachDB uses Pebble (a RocksDB-compatible LSM tree storage engine) that relies on background compaction to maintain read performance and reclaim storage. Understanding compaction metrics is essential for identifying performance bottlenecks and preventing storage layer degradation.

### What is Compaction?

**Compaction** merges smaller SSTable files into larger, organized files to:
- Reduce read amplification (fewer files to search)
- Purge expired MVCC versions and deleted data
- Free storage space
- Maintain LSM tree level structure (L0 → L6)

Compaction runs asynchronously in the background but consumes CPU and disk I/O. When compaction cannot keep pace with write rate, LSM health degrades.

### Why Compaction Monitoring Matters

- **Read Performance**: High read amplification (>10) slows queries
- **Write Stalls**: Compaction backlog can pause writes
- **Disk Space**: Failed compaction prevents garbage collection
- **Resource Planning**: Compaction needs sufficient I/O headroom
- **Early Warning**: L0 sublevel count predicts performance issues

### LSM Tree Level Structure

**L0**: Newly flushed SSTables, overlapping key ranges, fast writes
**L1-L6**: Non-overlapping key ranges within each level, efficient reads
- Each level roughly 10x larger than the previous
- Lower levels contain older, less frequently updated data
- Compaction moves data from higher levels to lower levels

## Critical Compaction Metrics

### Compaction Activity Metrics

**rocksdb.compactions** - Total number of completed compactions (cumulative counter)
**rocksdb.compacted-bytes-written** - Bytes written during compaction (I/O overhead)
**rocksdb.compacted-bytes-read** - Bytes read during compaction operations
**rocksdb.estimated-pending-compaction** - Pending compaction backlog in bytes

### L0 Sublevel Health Metrics

**storage.l0-sublevels** - Current L0 sublevel count (CRITICAL METRIC)
**storage.l0-num-files** - Number of files in L0
**rocksdb.num-sstables** - Total SSTable files across all levels

**Alert Thresholds**:
- L0 sublevels > 20: Compaction falling behind, alert immediately
- L0 sublevels > 30: Critical, write stalls likely
- L0 sublevels consistently > 10: Investigate write workload

### Read Amplification Metrics

**rocksdb.read-amplification** - Average number of SSTables read per logical read
- Healthy: 1-9 (single digit)
- Concerning: 10-15
- Critical: >15 (indicates severe compaction lag)

**Calculation**: Number of SSTable files consulted per read operation due to overlapping key ranges in L0 and across levels.

### Write Amplification Metrics

**Write Amplification Factor** = Total bytes written to disk / Bytes of user data changes

Measured indirectly via:
- `rocksdb.compacted-bytes-written` (compaction overhead)
- MVCC version counts from `SHOW RANGES`
- Ratio of `val_count / live_count` in span_stats

## Using DB Console Storage Dashboard

### Accessing Compaction Metrics

Navigate to `http://<node-address>:8080` → Metrics → Storage dashboard

**LSM Health Panel**: L0 Sublevels, Read Amplification, Number of SSTables

**Compaction Activity Panel**: Compaction Rate, Pending Compaction Bytes, Compaction Write Throughput

**Disk I/O Correlation**: Compare application writes vs compaction writes (sys.host.disk.write.bytes)

### Interpreting Dashboard Patterns

**Healthy Pattern**
- L0 sublevels: Stable at 5-15
- Read amplification: 1-9
- Compaction rate: Steady, matches write rate
- Pending compaction: Near zero

**Compaction Lag Pattern**
- L0 sublevels: Growing over time, >20
- Read amplification: Increasing, >10
- Pending compaction: Growing backlog (>50GB)
- Disk write throughput: Saturated

**Post-Bulk-Write Recovery**
- L0 sublevels: Spike during import, gradual decrease after
- Compaction rate: Elevated for 1-4 hours post-import
- Pending compaction: Decreases as compaction catches up

## Querying Compaction Metrics

**Important**: All queries in this section require access to `crdb_internal` system tables. You must enable unsafe internals before querying these tables:

```sql
SET allow_unsafe_internals = true;
```

This setting applies to the current session only and must be set each time you connect. Alternatively, include it at the start of each query block.

### L0 Sublevel Count per Store

Monitor the most critical compaction health metric:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) AS l0_sublevels,
  max(CASE WHEN name = 'storage.l0-num-files' THEN value ELSE 0 END) AS l0_files,
  CASE
    WHEN max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) <= 10 THEN 'Healthy'
    WHEN max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) <= 20 THEN 'Elevated'
    WHEN max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) <= 30 THEN 'Critical - Alert'
    ELSE 'Emergency - Write Stalls Likely'
  END AS health_status
FROM crdb_internal.node_metrics
WHERE name IN ('storage.l0-sublevels', 'storage.l0-num-files')
  AND store_id IS NOT NULL
GROUP BY store_id
ORDER BY l0_sublevels DESC;
```

### Read and Write Amplification

Track both read and write amplification for complete LSM health picture:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) AS read_amplification,
  round(max(CASE WHEN name = 'rocksdb.compacted-bytes-written' THEN value ELSE 0 END) / 1024 / 1024, 2) AS compaction_write_mb,
  max(CASE WHEN name = 'rocksdb.num-sstables' THEN value ELSE 0 END) AS total_sstables,
  CASE
    WHEN max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) < 10 THEN 'Healthy'
    WHEN max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) < 15 THEN 'Elevated'
    ELSE 'Critical'
  END AS read_amp_status
FROM crdb_internal.node_metrics
WHERE name IN ('rocksdb.read-amplification', 'rocksdb.compacted-bytes-written', 'rocksdb.num-sstables')
  AND store_id IS NOT NULL
GROUP BY store_id
ORDER BY read_amplification DESC;
```

### Compaction Backlog and Rate

Monitor pending compaction and throughput:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  round(max(CASE WHEN name = 'rocksdb.estimated-pending-compaction' THEN value ELSE 0 END) / 1024 / 1024 / 1024, 2) AS pending_compaction_gb,
  max(CASE WHEN name = 'rocksdb.compactions' THEN value ELSE 0 END) AS total_compactions,
  round(max(CASE WHEN name = 'rocksdb.compacted-bytes-written' THEN value ELSE 0 END) / 1024 / 1024, 2) AS compaction_mb_written
FROM crdb_internal.node_metrics
WHERE name IN (
  'rocksdb.estimated-pending-compaction',
  'rocksdb.compactions',
  'rocksdb.compacted-bytes-written'
)
  AND store_id IS NOT NULL
GROUP BY store_id
ORDER BY pending_compaction_gb DESC;
```

Alert on:
- Pending compaction > 50GB and growing
- Compaction write throughput decreasing while writes continue
- L0 sublevels increasing alongside pending compaction

Note: `rocksdb.compactions` is a cumulative counter, not a rate metric. Monitor the rate of change over time to assess compaction throughput.

### Comprehensive LSM Health Summary

Single query for complete compaction health assessment:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) AS l0_sublevels,
  max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) AS read_amp,
  round(max(CASE WHEN name = 'rocksdb.estimated-pending-compaction' THEN value ELSE 0 END) / 1024 / 1024 / 1024, 2) AS pending_gb,
  max(CASE WHEN name = 'rocksdb.num-sstables' THEN value ELSE 0 END) AS total_sstables,
  round(max(CASE WHEN name = 'rocksdb.compacted-bytes-written' THEN value ELSE 0 END) / 1024 / 1024, 2) AS comp_mb_written,
  CASE
    WHEN max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) > 20 THEN 'CRITICAL'
    WHEN max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) > 15 THEN 'CRITICAL'
    WHEN max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) > 10 THEN 'WARNING'
    WHEN max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) > 10 THEN 'WARNING'
    ELSE 'HEALTHY'
  END AS overall_health
FROM crdb_internal.node_metrics
WHERE name IN (
  'storage.l0-sublevels',
  'rocksdb.read-amplification',
  'rocksdb.estimated-pending-compaction',
  'rocksdb.num-sstables',
  'rocksdb.compacted-bytes-written'
)
  AND store_id IS NOT NULL
GROUP BY store_id
ORDER BY overall_health DESC, l0_sublevels DESC;
```

## Correlating Compaction with Write Workload

### Identify Write-Heavy Tables

Compaction backlog often correlates with high-write tables. Use SHOW RANGES to analyze table size and version counts:

```sql
SET allow_unsafe_internals = true;

-- Get range statistics with table names
SELECT
  database_name,
  table_name,
  count(*) AS range_count,
  round(sum(range_size_mb), 2) AS total_size_mb,
  round(avg(live_percentage), 1) AS avg_live_pct,
  round((100 - avg(live_percentage)), 1) AS avg_garbage_pct
FROM crdb_internal.ranges_no_leases
GROUP BY database_name, table_name
HAVING database_name = current_database()
ORDER BY total_size_mb DESC
LIMIT 10;
```

High garbage percentage (>50%) indicates:
- Frequent updates creating MVCC versions
- Long GC TTL retaining old versions
- Compaction not purging deleted data efficiently
- Potential write amplification issues

Note: For detailed write activity analysis, correlate with statement statistics (see "Query for Recent Write Activity" below).

### Correlate L0 Spikes with Application Activity

**Steps**:
1. Note timestamp of L0 sublevel spike in DB Console
2. Query slow query log for that time period
3. Identify INSERT/UPDATE/DELETE heavy queries
4. Check if bulk operations (IMPORT, RESTORE) occurred
5. Review application deployment times for new write patterns

**Query for Recent Write Activity**:

```sql
SET allow_unsafe_internals = true;

SELECT
  fingerprint_id,
  metadata->>'query' AS query_sample,
  metadata->>'db' AS database,
  (statistics->'statistics'->>'cnt')::INT AS execution_count,
  (statistics->'statistics'->'rowsWritten'->>'mean')::FLOAT AS avg_rows_written
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'rowsWritten'->>'mean')::FLOAT > 100
ORDER BY avg_rows_written DESC
LIMIT 10;
```

### Compaction I/O vs Application I/O

Distinguish between user writes and compaction overhead:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  round(sum(CASE WHEN name = 'sys.host.disk.write.bytes' THEN value ELSE 0 END) / 1024 / 1024, 2) AS total_write_mb,
  round(sum(CASE WHEN name = 'rocksdb.compacted-bytes-written' THEN value ELSE 0 END) / 1024 / 1024, 2) AS compaction_write_mb,
  round(
    (sum(CASE WHEN name = 'rocksdb.compacted-bytes-written' THEN value ELSE 0 END)::FLOAT /
     NULLIF(sum(CASE WHEN name = 'sys.host.disk.write.bytes' THEN value ELSE 0 END), 0)) * 100,
    2
  ) AS compaction_pct_of_total_writes
FROM crdb_internal.node_metrics
WHERE name IN ('sys.host.disk.write.bytes', 'rocksdb.compacted-bytes-written')
  AND store_id IS NOT NULL
GROUP BY store_id
ORDER BY store_id;
```

Interpretation:
- Compaction 30-50% of total writes: Normal
- Compaction >70% of writes: Compaction backlog catching up
- Compaction <10% of writes during high write workload: Compaction falling behind

Note: `sys.host.disk.write.bytes` may show 0 or NULL in some deployment environments (e.g., containerized, cloud managed). If unavailable, use DB Console's Disk I/O dashboard for visual correlation.

## Troubleshooting

### High L0 Sublevel Count (>20)

**Diagnosis**

Check current L0 health and trend:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) AS current_l0_sublevels,
  round(max(CASE WHEN name = 'rocksdb.estimated-pending-compaction' THEN value ELSE 0 END) / 1024 / 1024 / 1024, 2) AS pending_gb
FROM crdb_internal.node_metrics
WHERE name IN ('storage.l0-sublevels', 'rocksdb.estimated-pending-compaction')
  AND store_id IS NOT NULL
GROUP BY store_id
HAVING max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) > 20
ORDER BY current_l0_sublevels DESC;
```

**Root Causes**:
- Write rate exceeds compaction throughput
- Insufficient disk I/O for compaction
- Compaction concurrency too low
- Large bulk write operation (IMPORT, RESTORE)

**Resolution**:
- **Short-term**: Reduce write rate if possible (batch operations, throttle imports)
- **Medium-term**: Increase compaction concurrency via cluster settings
- **Long-term**: Upgrade to faster storage (higher write IOPS)
- **Emergency**: Manual compaction during maintenance window (not recommended for production)

### High Read Amplification (>10)

**Diagnosis**

Identify stores with excessive read amplification:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) AS read_amp,
  max(CASE WHEN name = 'storage.l0-sublevels' THEN value ELSE 0 END) AS l0_sublevels,
  max(CASE WHEN name = 'rocksdb.num-sstables' THEN value ELSE 0 END) AS total_sstables
FROM crdb_internal.node_metrics
WHERE name IN ('rocksdb.read-amplification', 'storage.l0-sublevels', 'rocksdb.num-sstables')
  AND store_id IS NOT NULL
GROUP BY store_id
HAVING max(CASE WHEN name = 'rocksdb.read-amplification' THEN value ELSE 0 END) > 10
ORDER BY read_amp DESC;
```

**Impact**:
- Read queries slower (must scan multiple SSTables)
- Higher disk I/O per read operation
- Increased query latency, especially range scans

**Resolution**:
- Address L0 sublevel backlog first (root cause)
- Review data model: excessive updates create overlapping SSTables
- Check GC TTL: longer TTL retains more MVCC versions
- Monitor cache hit rate: low cache hits amplify disk read impact

### Compaction Cannot Keep Pace

**Diagnosis**

Sustained pending compaction backlog:

```sql
SET allow_unsafe_internals = true;

SELECT
  store_id,
  round(max(CASE WHEN name = 'rocksdb.estimated-pending-compaction' THEN value ELSE 0 END) / 1024 / 1024 / 1024, 2) AS pending_gb,
  max(CASE WHEN name = 'rocksdb.compactions' THEN value ELSE 0 END) AS total_compactions,
  round(max(CASE WHEN name = 'sys.host.disk.write.bytes' THEN value ELSE 0 END) / 1024 / 1024, 2) AS disk_write_mb
FROM crdb_internal.node_metrics
WHERE name IN (
  'rocksdb.estimated-pending-compaction',
  'rocksdb.compactions',
  'sys.host.disk.write.bytes'
)
  AND store_id IS NOT NULL
GROUP BY store_id
ORDER BY pending_gb DESC;
```

**Root Causes**:
- Disk write throughput saturated
- Compaction competing with application writes
- Insufficient compaction threads
- Storage hardware limitations

**Resolution**:
- Check disk write utilization (should be <80%)
- Increase compaction concurrency: `SET CLUSTER SETTING kv.compactor.concurrency = <value>`
- Add write I/O headroom: 50-70% baseline utilization allows compaction bursts
- Upgrade storage tier: faster write IOPS and throughput

### Write Stalls Appearing in Logs

**Log Pattern**: `writes stalled due to pending compaction`

**Diagnosis**: Check L0 sublevel count (typically >25 when stalls occur)

**Impact**: Application writes blocked temporarily, transaction latencies spike, potential timeouts

**Resolution**:
- Immediate: Write stalls self-resolve as compaction catches up
- Short-term: Reduce write rate to prevent recurrence
- Long-term: Address root cause (see "Compaction Cannot Keep Pace")

## Best Practices

### Monitoring and Alerting

**Critical Alerts**: L0 >20 (10min), read amp >15 (15min), pending >50GB and growing, compaction failures >0, write stalls in logs

**Regular Monitoring**: Daily (L0 trends), weekly (read/write amp), monthly (correlate with workload changes)

**Baselines**: L0 typically 5-15, read amp 1-9, compaction I/O 30-50% of writes

### Optimization Strategies

**Workload**: Batch small writes, minimize row updates, use appropriate GC TTL, partition large tables

**Resources**: Size disk I/O for 2x write rate, use SSDs (NVMe for write-heavy), maintain 50%+ free space, allocate sufficient CPU cores

**Configuration**: Default settings work well. Consider increasing `kv.compactor.concurrency` for write-heavy clusters. Adjust L0 triggers only with Cockroach Labs guidance. Monitor changes 7+ days

### Capacity Planning

**Track monthly trends**: L0 sublevels, read amplification, compaction I/O percentage

**Scaling triggers**: L0 consistently >15 (upgrade I/O), read amp trending up (review data model), growing backlog despite tuning (add resources)

## Common Patterns

**Daily Compaction Cycles**: L0 rises during business hours, falls overnight. Normal if L0 stays <20. Size I/O for peak compaction. Alert if overnight compaction doesn't complete.

**Post-Bulk-Import Recovery**: L0 spikes to 25-40 during import, recovers over 2-6 hours. Expected behavior. Schedule imports during maintenance windows. Alert if L0 doesn't return to <15 within 6 hours.

**Gradual LSM Degradation**: L0 trends upward over months (8→12→16→20+). Capacity planning failure. Proactively scale storage I/O when L0 baseline exceeds 15. Review write workload trends monthly.

## Related Skills

**CockroachDB Architecture Domain**
- understand-lsm-tree-structure-and-levels
- understand-pebble-storage-compaction-process
- understand-read-amplification-in-lsm-trees
- understand-write-amplification-in-lsm-trees

**Monitoring and Alerting Domain**
- monitor-disk-io-and-throughput
- monitor-read-amplification-metrics
- monitor-write-amplification-metrics
- observe-and-interpret-compaction-metrics
- set-up-alerting-rules-for-critical-conditions

**Performance Optimization Domain**
- optimize-rocksdb-settings-for-performance
- configure-cache-sizes-for-optimal-performance

**Cluster Maintenance Domain**
- understand-how-mvcc-and-garbage-collection-affect-storage
- configure-garbage-collection-ttl-settings

## Additional Resources

- CockroachDB Docs: Pebble Storage Engine Architecture
- CockroachDB Docs: DB Console Storage Dashboard
- Blog: Understanding LSM Trees and Compaction in CockroachDB
- RocksDB Wiki: Compaction (Pebble is RocksDB-compatible)
- Paper: "The Log-Structured Merge-Tree (LSM-Tree)" by O'Neil et al.
