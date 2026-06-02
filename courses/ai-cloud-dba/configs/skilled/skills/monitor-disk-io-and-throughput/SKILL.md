---
name: monitor-disk-io-and-throughput
description: Monitor disk read/write IOPS, throughput (MB/s), and latency using DB Console Storage dashboard and metrics to identify I/O bottlenecks affecting query performance or compaction
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: ready
  testing_notes: Fixed for v26.1.0 schema - all queries tested against cluster at localhost:26258
  related_domains:
    - Cluster Maintenance
    - Performance Optimization
    - Hardware and Infrastructure
---

# Monitor Disk I/O and Throughput

Monitor disk read/write IOPS, throughput (MB/s), and latency using DB Console Storage dashboard and metrics to identify I/O bottlenecks affecting query performance or compaction.

## What This Skill Teaches

Monitor and analyze disk I/O performance in CockroachDB clusters:

- Understand disk I/O metrics: IOPS, throughput, and latency
- Use DB Console Storage dashboard for visual I/O monitoring
- Query disk I/O metrics via crdb_internal tables
- Identify read/write patterns and workload characteristics
- Detect I/O bottlenecks impacting query performance or compaction
- Differentiate SSD and HDD performance profiles
- Correlate disk I/O with query latency and cluster health
- Establish baseline I/O performance for capacity planning

**Bloom's Taxonomy Level**: Apply - Execute disk I/O monitoring procedures, interpret metrics, and diagnose performance issues.

## Overview

CockroachDB's performance depends heavily on disk I/O subsystem capabilities. Understanding disk metrics is essential for identifying bottlenecks, planning capacity, and ensuring optimal query performance.

### Key I/O Metrics Explained

**IOPS (Input/Output Operations Per Second)**
- Number of read/write operations completed per second
- Critical for random access patterns (point lookups, index operations)
- Typical values: HDD 100-200 IOPS, SSD 10,000-100,000+ IOPS

**Throughput (MB/s or GB/s)**
- Volume of data transferred per second
- Critical for sequential operations (scans, backups, compaction)
- Typical values: HDD 100-200 MB/s, SSD 500-7,000 MB/s

**Latency (milliseconds)**
- Time to complete individual I/O operations
- Directly impacts query response times
- Typical values: HDD 5-15ms, SSD 0.1-1ms
- Monitor P50, P95, P99 percentiles

### Why Disk I/O Monitoring Matters

- Read latency affects SELECT query response times
- Write latency affects INSERT/UPDATE/DELETE operations
- I/O saturation causes query queuing and timeouts
- Compaction is I/O intensive and can create bottlenecks
- Disk I/O bottlenecks can trigger node liveness issues
- I/O metrics identify when to scale storage tier

## Critical Disk I/O Metrics

### Host-Level Metrics

**sys.host.disk.read.bytes** - Total bytes read from disk per second
**sys.host.disk.write.bytes** - Total bytes written to disk per second
**sys.host.disk.read.count** - Read IOPS
**sys.host.disk.write.count** - Write IOPS
**sys.host.disk.io.time** - Time spent performing I/O operations (saturation indicator)
**sys.host.disk.iopsinprogress** - I/O operations currently in flight (queue depth)

### Storage Engine Metrics

**rocksdb.read-amplification** - Number of SSTables read per logical read (high values >10 indicate compaction debt)
**rocksdb.block.cache.hits** - Reads served from cache (target >90% hit rate)
**rocksdb.block.cache.misses** - Reads requiring disk I/O
**storage.l0-sublevels** - L0 sublevels in LSM tree (>20 indicates compaction falling behind)
**rocksdb.estimated-pending-compaction** - Pending compaction bytes

### Latency Metrics

**storage.wal.fsync.latency-p50/p75/p90/p99** - WAL fsync latency percentiles (best proxy for write latency)
**storage.disk.read.time / storage.disk.read.count** - Average read latency (calculated)
**storage.disk.write.time / storage.disk.write.count** - Average write latency (calculated)

Alert thresholds:
- SSD: P99 WAL fsync > 10ms indicates problems
- HDD: P99 WAL fsync > 50ms indicates problems

**Note**: Fine-grained disk read/write latency percentiles not directly exposed via SQL in v26.1. Use WAL fsync latency as write performance proxy, or calculate averages from time/count metrics.

## Using DB Console Storage Dashboard

### Accessing the Dashboard

1. Navigate to `http://<node-address>:8080`
2. Click "Metrics" in left navigation
3. Select "Storage" dashboard
4. Choose time range (hour, day, week)

### Key Dashboard Panels

**Disk Read Throughput** - Shows `sys.host.disk.read.bytes` per node
**Disk Write Throughput** - Shows `sys.host.disk.write.bytes` per node
**IOPS by Node** - Combined read and write operations per second
**Disk Latency** - P50/P95/P99 read and write latencies
**LSM Health** - L0 sublevels and read amplification

### Interpreting Patterns

**Steady High Throughput, Low IOPS** - Sequential operations (scans, backups)
**High IOPS, Lower Throughput** - Random access pattern (OLTP workload)
**Periodic Write Spikes** - Compaction activity (normal)
**Latency Spikes with High IOPS** - Disk saturation or queue depth limits

## Querying Disk I/O Metrics

**Important**: All queries require this session variable for v26.1.0+:

```sql
SET allow_unsafe_internals = true;
```

### Block Cache Efficiency

Measure how effectively cache reduces disk I/O:

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'rocksdb.block.cache.hits')::FLOAT::BIGINT AS cache_hits,
  (metrics->>'rocksdb.block.cache.misses')::FLOAT::BIGINT AS cache_misses,
  ROUND(
    (metrics->>'rocksdb.block.cache.hits')::FLOAT /
    NULLIF((metrics->>'rocksdb.block.cache.hits')::FLOAT +
           (metrics->>'rocksdb.block.cache.misses')::FLOAT, 0) * 100,
    2
  ) AS cache_hit_rate_pct
FROM crdb_internal.kv_store_status
ORDER BY node_id, store_id;
```

Target cache hit rate: >90% for read-heavy workloads, >80% for mixed workloads.

### Disk I/O Summary per Node

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  ROUND((metrics->>'sys.host.disk.read.bytes')::FLOAT / 1024 / 1024, 2) AS read_mb_per_sec,
  ROUND((metrics->>'sys.host.disk.write.bytes')::FLOAT / 1024 / 1024, 2) AS write_mb_per_sec,
  (metrics->>'sys.host.disk.read.count')::FLOAT::BIGINT AS read_iops,
  (metrics->>'sys.host.disk.write.count')::FLOAT::BIGINT AS write_iops
FROM crdb_internal.kv_node_status
ORDER BY node_id;
```

### Compaction and Write Amplification

Monitor compaction I/O overhead:

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'storage.l0-sublevels')::FLOAT AS l0_sublevels,
  (metrics->>'rocksdb.read-amplification')::FLOAT AS read_amplification,
  (metrics->>'rocksdb.num-sstables')::FLOAT AS num_sstables,
  ROUND((metrics->>'rocksdb.estimated-pending-compaction')::FLOAT / 1024 / 1024 / 1024, 2) AS pending_compaction_gb
FROM crdb_internal.kv_store_status
ORDER BY node_id, store_id;
```

Alert thresholds:
- L0 sublevels > 20: compaction falling behind
- Read amplification > 15: excessive I/O overhead
- Pending compaction > 50GB: significant backlog

### I/O Pattern Analysis

Calculate average operation size to identify random vs sequential patterns:

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  ((metrics->>'sys.host.disk.read.bytes')::FLOAT /
   NULLIF((metrics->>'sys.host.disk.read.count')::FLOAT, 0))::INT AS avg_read_size_bytes,
  ((metrics->>'sys.host.disk.write.bytes')::FLOAT /
   NULLIF((metrics->>'sys.host.disk.write.count')::FLOAT, 0))::INT AS avg_write_size_bytes
FROM crdb_internal.kv_node_status
ORDER BY node_id;
```

Interpretation:
- Avg size < 8KB: Random access (OLTP)
- Avg size > 64KB: Sequential pattern (scans, compaction)
- Avg size 8-64KB: Mixed workload

### Read-Heavy vs Write-Heavy Analysis

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  ROUND(
    (metrics->>'sys.host.disk.read.bytes')::FLOAT /
    NULLIF((metrics->>'sys.host.disk.write.bytes')::FLOAT, 0),
    2
  ) AS read_to_write_ratio
FROM crdb_internal.kv_node_status
ORDER BY node_id;
```

Interpretation:
- Ratio > 3: Read-heavy (benefit from cache tuning)
- Ratio < 0.5: Write-heavy (benefit from faster write IOPS)
- Ratio 0.5-3: Balanced workload

## Identifying I/O Bottlenecks

### Symptoms of Disk I/O Saturation

**Performance Indicators**
- Query latencies increasing cluster-wide
- P99 latencies 2-10x higher than P50
- Timeouts on previously fast queries

**Compaction Indicators**
- L0 sublevels growing over time
- Write stalls appearing in logs
- Read amplification increasing

**Metrics Indicators**
- Disk utilization > 80% sustained
- IOPS approaching disk spec limits
- Queue depth consistently > 4

### Correlation Analysis Steps

1. Check DB Console Storage dashboard for disk latency spikes
2. Note times of elevated latency
3. Switch to SQL dashboard
4. Verify if query P99 latency spiked at same times
5. Strong correlation indicates I/O bottleneck

**Distinguish Application Writes from Compaction**
- Sustained high write throughput during low query activity = compaction
- Write spikes correlated with INSERT/UPDATE = application
- Check `rocksdb.compaction.write.bytes` metric to isolate compaction I/O

## SSD vs HDD Performance Profiles

### Expected Performance Baselines

**Enterprise SSD (NVMe)**: 100K-1M+ IOPS, 2-7 GB/s, <1ms P99 latency
**Enterprise SSD (SATA)**: 10K-90K IOPS, 500-600 MB/s, 1-5ms P99 latency
**Enterprise HDD (7200 RPM)**: 100-200 IOPS, 100-200 MB/s, 10-50ms P99 latency
**Cloud Storage**: AWS gp3 (3K-16K IOPS), AWS io2 (64K IOPS), GCP pd-ssd (30 IOPS/GB)

### Identifying Disk Type from Metrics

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'storage.wal.fsync.latency-p99')::FLOAT / 1000000 AS wal_fsync_p99_ms,
  CASE
    WHEN (metrics->>'storage.wal.fsync.latency-p99')::FLOAT / 1000000 < 1 THEN 'NVMe SSD'
    WHEN (metrics->>'storage.wal.fsync.latency-p99')::FLOAT / 1000000 < 5 THEN 'SATA SSD'
    WHEN (metrics->>'storage.wal.fsync.latency-p99')::FLOAT / 1000000 < 20 THEN 'Fast HDD or slow SSD'
    ELSE 'HDD or degraded storage'
  END AS likely_disk_type
FROM crdb_internal.kv_store_status
ORDER BY node_id, store_id;
```

**Note**: Uses WAL fsync latency as proxy for write performance. Direct disk read/write latency percentiles not exposed via SQL in v26.1.

### CockroachDB Recommendations

**Production Deployments**: SSDs strongly recommended (NVMe preferred). HDDs acceptable only for dev/test. Low latency critical for Raft consensus. High IOPS handles random access. Compaction completes faster with SSDs.

## Troubleshooting

### High Disk Latency

**Diagnosis**

Identify nodes with high WAL fsync latency (write performance indicator):

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'storage.wal.fsync.latency-p99')::FLOAT / 1000000 AS wal_fsync_p99_ms,
  ((metrics->>'storage.disk.write.time')::FLOAT /
   NULLIF((metrics->>'storage.disk.write.count')::FLOAT, 0)) / 1000000 AS avg_write_latency_ms
FROM crdb_internal.kv_store_status
WHERE (metrics->>'storage.wal.fsync.latency-p99')::FLOAT / 1000000 > 10
ORDER BY wal_fsync_p99_ms DESC;
```

**Resolution**
- Node-specific: Check host disk health, controller issues
- Cluster-wide: Review workload, consider storage tier upgrade
- Temporary spike: May be compaction burst (monitor for resolution)

### Compaction Cannot Keep Up

**Diagnosis**

L0 sublevels growing, write stalls in logs:

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'storage.l0-sublevels')::FLOAT AS l0_sublevels,
  (metrics->>'rocksdb.estimated-pending-compaction')::FLOAT / 1024 / 1024 / 1024 AS pending_gb
FROM crdb_internal.kv_store_status
WHERE (metrics->>'storage.l0-sublevels')::FLOAT > 20
ORDER BY l0_sublevels DESC;
```

**Resolution**
- Short-term: Reduce write rate if possible
- Medium-term: Increase compaction concurrency (adjust RocksDB settings)
- Long-term: Upgrade to faster storage with higher write IOPS

### Read Amplification Too High

**Diagnosis**

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'rocksdb.read-amplification')::FLOAT AS read_amp
FROM crdb_internal.kv_store_status
WHERE (metrics->>'rocksdb.read-amplification')::FLOAT > 10
ORDER BY read_amp DESC;
```

**Resolution**
- Address compaction backlog first
- Consider manual compaction during maintenance window
- Review data model for excessive updates/deletes
- Evaluate GC TTL settings (long TTL increases old versions)

## Best Practices

### Monitoring and Alerting

**Establish Baselines**
- Record disk I/O metrics during normal operations
- Document per-node IOPS and throughput capacity
- Establish latency percentile baselines by workload type

**Alert Thresholds**
- Disk latency P99 > 2x baseline for 5+ minutes
- IOPS utilization > 80% of disk spec
- L0 sublevels > 20 for 10+ minutes
- Cache hit rate < 80% for 15+ minutes
- Compaction pending > 50GB

**Regular Review**
- Weekly review of Storage dashboard trends
- Monthly capacity planning based on I/O growth
- Quarterly disk performance benchmarking

### Optimization Strategies

**Cache Tuning**
- Increase RocksDB block cache for read-heavy workloads
- Monitor cache hit rate, target >90%
- Balance between cache size and available memory

**Compaction Management**
- Ensure sufficient write I/O headroom for compaction
- Monitor L0 sublevels and read amplification
- Consider scheduled compaction during low-traffic periods

**Workload Optimization**
- Batch writes to reduce IOPS overhead
- Use appropriate indexes to minimize read amplification
- Partition large tables to improve compaction efficiency

**Storage Selection**
- NVMe SSDs for production latency-sensitive workloads
- Provisioned IOPS cloud volumes for predictable performance
- Overprovision capacity (50%+ free) for SSD longevity

### Capacity Planning

**Growth Projection**
- Track monthly I/O trends (IOPS, throughput, latency)
- Project when disk I/O will reach 70% utilization
- Plan storage tier upgrade 2-3 months in advance

**Scaling Triggers**
- Sustained IOPS > 70% of disk capacity
- Latency P99 degrading over time
- Compaction backlog growing despite tuning

## Common Patterns

### Daily Compaction Cycles

**Scenario**: Write-heavy workload during business hours, compaction I/O peaks overnight.

**Metrics Signature**:
- Write IOPS high 9am-5pm
- Write throughput spikes 6pm-2am (compaction)
- Read latency stable during compaction (SSD)

**Best Practice**: Normal pattern, ensure overnight compaction completes. Alert if compaction extends into business hours. Size storage for 2x daytime write rate.

### Cache Warmup After Restart

**Scenario**: Node restart causes cache misses, high read I/O until cache warms.

**Metrics Signature**:
- Read IOPS spike after node startup
- Cache miss rate 100% initially, decreases over 15-60 minutes
- Read latency elevated during warmup period

**Best Practice**: Expected behavior, typically resolves in <30 minutes. Stagger node restarts to avoid cluster-wide cache loss.

### Bulk Import I/O Surge

**Scenario**: Large IMPORT or RESTORE operation saturates disk I/O.

**Metrics Signature**:
- Write throughput spike (sequential writes)
- L0 sublevels spike during import
- Compaction backlog develops, clears post-import

**Best Practice**: Schedule bulk operations during maintenance windows. Throttle import rate if cluster serves live traffic. Monitor for 2-4 hours post-import as compaction catches up.

## Related Skills

**Monitoring and Alerting Domain**
- monitor-storage-capacity-and-usage
- monitor-query-performance-and-latency
- set-up-alerting-rules-for-critical-conditions
- monitor-compaction-activity-and-read-amplification

**Performance Optimization Domain**
- optimize-rocksdb-settings-for-performance
- configure-cache-sizes-for-optimal-performance

**Cluster Maintenance Domain**
- verify-cluster-health-between-restarts
- perform-rolling-restarts-for-zero-downtime-maintenance

**Hardware and Infrastructure Domain**
- configure-hardware-specifications-for-production
- optimize-os-settings-for-database-workloads

## Additional Resources

- CockroachDB Docs: Production Checklist (Storage Requirements)
- CockroachDB Docs: DB Console Storage Dashboard
- Blog: Understanding LSM Trees and Compaction
- RocksDB Wiki: Block Cache Configuration
- Cloud Provider: IOPS and Throughput Provisioning Guides
