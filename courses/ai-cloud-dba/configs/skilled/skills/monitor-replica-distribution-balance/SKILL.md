---
name: monitor-replica-distribution-balance
description: Use DB Console Replication Report to verify replicas are evenly balanced across nodes, verify proper distribution according to zone configurations, and identify nodes with significantly more/fewer replicas indicating rebalancing issues
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.2.0
  cockroachdb_version: v26.1.0+
  status: ready
  testing_notes: |
    Fixed for v26.1.0 compatibility (v1.2.0 updates):
    - Added SET allow_unsafe_internals = true to all crdb_internal queries
    - Fixed column names: replica_count→range_count, leaseholder_count→lease_count
    - Fixed column names: used_capacity→used, available_capacity→available
    - Added NULLIF() checks for division by zero in all calculations
    - Added WHERE capacity > 0 and WHERE range_count > 0 filters
    - Removed database_name/table_name/index_name from ranges_no_leases queries
    - Fixed locality query to use locality STRING field (not locality_key/locality_value)
    - Added notes about using SHOW CLUSTER RANGES WITH TABLES for table identification
    - Updated zone config queries to use crdb_internal.zones table
---

# Monitor Replica Distribution Balance

**Domain**: Monitoring and Alerting
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

Monitor and verify replica distribution balance across CockroachDB cluster nodes using the DB Console and SQL queries. Learn to identify imbalanced replica placement, verify zone configuration compliance, detect rebalancing issues, and maintain even resource utilization.

**Learning Objectives**:
- Interpret DB Console Replication dashboard and SQL metrics
- Identify nodes with significant replica imbalances
- Verify replica placement complies with zone configurations
- Recognize and troubleshoot rebalancing problems

## Overview

### Why Replica Balance Matters

CockroachDB's rebalancer distributes replicas (default factor: 3) evenly across nodes. Unbalanced distribution causes performance hotspots, reduced fault tolerance, uneven resource consumption, and potential zone configuration violations. Rebalancing is rate-limited to prevent performance degradation.

### Key Concepts

**Replica vs Range vs Leaseholder**:
- **Range**: A contiguous segment of the keyspace (64 MiB default target size)
- **Replica**: A copy of a range stored on a node (typically 3 per range)
- **Leaseholder**: The replica that serves reads and coordinates writes (1 per range)

**Distribution Metrics**:
- **Replica Count**: Total number of replicas on a node
- **Range Count**: Total number of ranges on a node (includes leaseholder status)
- **Leaseholder Count**: Number of ranges where the node holds the lease
- **Balance Coefficient**: Measure of distribution evenness (closer to 1.0 is better)

**Rebalancing Triggers**: Node changes, disk imbalances, load patterns, zone configuration updates, locality constraints.

## Instructions

### Access the DB Console Replication Report

**Step 1: Navigate to Replication Dashboard**

Open DB Console at `http://<node-address>:8080` and go to **Metrics** > **Replication**. Key metrics: total replica count, range distribution, replication status (under/over-replicated, unavailable ranges), per-node counts, and rebalancing activity.

**Step 2: Examine Key Graphs**

- **Replicas per Node**: Should be roughly equal (10-15% variation normal during rebalancing)
- **Ranges per Node**: Should correlate with replica counts
- **Range Operations**: High activity during cluster changes is normal; continuous activity suggests instability

### Query Replica Distribution Using SQL

**Step 3: Check Overall Replica Counts Per Node**

Connect to any cluster node and run:

```sql
-- Enable access to crdb_internal tables (required in v26.1.0+)
SET allow_unsafe_internals = true;

-- Check replica distribution across nodes
SELECT
  store_id,
  node_id,
  range_count,          -- Number of ranges (replicas) on this node
  lease_count,          -- Number of leaseholders on this node
  available,            -- Available disk capacity (bytes)
  used,                 -- Used disk capacity (bytes)
  capacity,             -- Total disk capacity (bytes)
  (used::FLOAT / NULLIF(capacity, 0)::FLOAT * 100)::DECIMAL(10,2) AS disk_usage_pct
FROM crdb_internal.kv_store_status
WHERE capacity > 0
ORDER BY node_id;
```

**Expected Output**:
```
  store_id | node_id | range_count | lease_count | available     | used      | capacity      | disk_usage_pct
-----------+---------+-------------+-------------+---------------+-----------+---------------+----------------
         1 |       1 |        1543 |         512 | 450000000000  | 15000000  | 494384795648  |           0.00
         2 |       2 |        1538 |         515 | 448000000000  | 16000000  | 494384795648  |           0.00
         3 |       3 |        1541 |         513 | 449000000000  | 15500000  | 494384795648  |           0.00
```

Range counts should be within 5-10% of each other (each range is a replica). Lease counts should be roughly equal (approximately 1/3 of range count for RF=3). Disk usage affects rebalancing (nodes >90% full are avoided).

**Step 4: Calculate Replica Balance Coefficient**

Calculate the coefficient of variation to quantify balance:

```sql
SET allow_unsafe_internals = true;

WITH replica_stats AS (
  SELECT
    AVG(range_count)::FLOAT AS avg_replicas,
    STDDEV(range_count)::FLOAT AS stddev_replicas,
    MAX(range_count) AS max_replicas,
    MIN(range_count) AS min_replicas,
    COUNT(DISTINCT node_id) AS node_count
  FROM crdb_internal.kv_store_status
)
SELECT
  avg_replicas,
  stddev_replicas,
  max_replicas,
  min_replicas,
  node_count,
  -- Coefficient of variation (lower is better)
  (stddev_replicas / NULLIF(avg_replicas, 0)) AS cv_coefficient,
  -- Balance ratio (closer to 1.0 is better)
  (min_replicas::FLOAT / NULLIF(max_replicas, 0)::FLOAT) AS balance_ratio,
  -- Max deviation percentage
  ((max_replicas - avg_replicas) / NULLIF(avg_replicas, 0) * 100) AS max_deviation_pct
FROM replica_stats;
```

**Interpretation**:
- **cv_coefficient < 0.05**: Excellent balance
- **cv_coefficient 0.05-0.10**: Good balance
- **cv_coefficient 0.10-0.20**: Moderate imbalance, monitor closely
- **cv_coefficient > 0.20**: Significant imbalance, investigate
- **balance_ratio > 0.90**: Well-balanced
- **balance_ratio < 0.80**: Significant imbalance

### Identify Nodes with Significant Imbalances

**Step 5: Find Over-Replicated and Under-Replicated Nodes**

```sql
SET allow_unsafe_internals = true;

WITH cluster_avg AS (
  SELECT AVG(range_count)::FLOAT AS avg_replicas
  FROM crdb_internal.kv_store_status
)
SELECT
  s.node_id,
  s.store_id,
  s.range_count,
  a.avg_replicas,
  s.range_count - a.avg_replicas AS deviation,
  ((s.range_count - a.avg_replicas) / NULLIF(a.avg_replicas, 0) * 100)::DECIMAL(10,2) AS deviation_pct,
  CASE
    WHEN s.range_count > a.avg_replicas * 1.15 THEN 'OVER-REPLICATED'
    WHEN s.range_count < a.avg_replicas * 0.85 THEN 'UNDER-REPLICATED'
    ELSE 'BALANCED'
  END AS status
FROM crdb_internal.kv_store_status s
CROSS JOIN cluster_avg a
WHERE s.range_count > 0
ORDER BY ABS(s.range_count - a.avg_replicas) DESC;
```

Nodes with >15% deviation warrant investigation.

**Step 6: Check for Under-Replicated and Unavailable Ranges**

```sql
SET allow_unsafe_internals = true;

-- Check for under/over-replicated ranges
SELECT
  range_id,
  start_pretty,
  end_pretty,
  ARRAY_LENGTH(replicas, 1) AS actual_replicas,
  voting_replicas,
  non_voting_replicas,
  CASE
    WHEN ARRAY_LENGTH(replicas, 1) < 3 THEN 'UNDER-REPLICATED'
    WHEN ARRAY_LENGTH(replicas, 1) > 3 THEN 'OVER-REPLICATED'
    ELSE 'NORMAL'
  END AS replication_status
FROM crdb_internal.ranges_no_leases
WHERE ARRAY_LENGTH(replicas, 1) != 3
ORDER BY ARRAY_LENGTH(replicas, 1) ASC, range_id
LIMIT 50;
```

Persistent under-replicated ranges indicate replication failures. Check for insufficient capacity, hardware failures, or network partitions.

**Note**: To identify which table/database a range belongs to, use `SHOW CLUSTER RANGES WITH TABLES` or join with `crdb_internal.ranges` table (which includes leaseholder information).

### Verify Zone Configuration Compliance

**Step 7: Compare Actual vs Expected Replica Placement**

```sql
SET allow_unsafe_internals = true;

-- Use SHOW CLUSTER RANGES WITH TABLES to see table info with replica counts
-- This replaces the ranges_no_leases approach since database_name/table_name are no longer in that table
SHOW CLUSTER RANGES WITH TABLES;

-- Alternative: Query zone configurations and compare manually
SELECT
  target,
  range_name,
  config
FROM crdb_internal.zones
WHERE config LIKE '%num_replicas%'
ORDER BY target;
```

**Step 8: Verify Locality-Based Replica Placement**

```sql
SET allow_unsafe_internals = true;

-- Check replica distribution across localities
-- Note: locality is a STRING field in v26.1.0 (e.g., "region=us-east,zone=us-east-1a")
SELECT
  n.node_id,
  n.locality,
  s.range_count,
  s.lease_count,
  s.used,
  s.available,
  (s.used::FLOAT / NULLIF(s.capacity, 0)::FLOAT * 100)::DECIMAL(10,2) AS disk_usage_pct
FROM crdb_internal.kv_node_status n
JOIN crdb_internal.kv_store_status s USING (node_id)
WHERE s.capacity > 0
ORDER BY n.locality, n.node_id;
```

Verify each locality (region/zone) has expected replica counts and diversity constraints are met. Parse the `locality` string to extract region/zone information as needed.

### Monitor Rebalancing Activity

**Step 9: Track Rebalancing Progress**

```sql
SET allow_unsafe_internals = true;

-- Monitor active rebalancing operations (learner replicas indicate rebalancing)
SELECT
  range_id,
  start_pretty,
  end_pretty,
  replicas,
  voting_replicas,
  ARRAY_LENGTH(learner_replicas, 1) AS learner_count
FROM crdb_internal.ranges_no_leases
WHERE ARRAY_LENGTH(learner_replicas, 1) > 0
LIMIT 50;
```

Learner replicas are temporary during rebalancing. High counts indicate active rebalancing; persistent learners suggest stalls. Use `SHOW CLUSTER RANGES WITH TABLES` to identify which tables these ranges belong to.

**Step 10: Review Rebalancer Metrics**

In DB Console **Replication** dashboard, check snapshots/sec, snapshot bytes/sec, and rebalancing writes/sec. Normal: spikes after topology changes with gradual decrease. Problems: continuous high activity without changes, zero activity with imbalance, or extremely high rates.

## Common Patterns

### Pattern 1: Post-Node Addition Imbalance

**Scenario**: New nodes added to cluster have significantly fewer replicas

```sql
SET allow_unsafe_internals = true;

-- Identify recently added nodes with low replica counts
SELECT
  n.node_id,
  n.started_at,
  s.range_count,
  AGE(NOW(), n.started_at) AS node_age,
  (SELECT AVG(range_count) FROM crdb_internal.kv_store_status) AS cluster_avg
FROM crdb_internal.kv_node_status n
JOIN crdb_internal.kv_store_status s USING (node_id)
WHERE AGE(NOW(), n.started_at) < INTERVAL '24 hours'
ORDER BY n.started_at DESC;
```

New nodes should reach cluster average within 24-48 hours. If slow, check `kv.snapshot_rebalance.max_rate` (default 32 MiB/s) and verify network connectivity.

### Pattern 2: Disk Space Imbalance

**Scenario**: Nodes with less available disk space have fewer replicas

```sql
SET allow_unsafe_internals = true;

-- Correlate replica count with disk space
SELECT
  node_id,
  range_count,
  used,
  available,
  capacity,
  (used::FLOAT / NULLIF(capacity, 0)::FLOAT * 100)::DECIMAL(10,2) AS disk_usage_pct
FROM crdb_internal.kv_store_status
WHERE capacity > 0
ORDER BY disk_usage_pct DESC;
```

The rebalancer avoids nodes above 90% disk usage. Resolution: add disk capacity, add new nodes, or clean up data.

### Pattern 3: Zone Configuration Pinning

**Scenario**: Specific tables have custom replica placement creating imbalance

```sql
-- Show tables with custom replication factors
SHOW ZONE CONFIGURATIONS;
```

Tables with custom replica counts consume different storage per node. Evaluate balance relative to zone configuration intent.

### Pattern 4: Leaseholder Concentration

**Scenario**: Replica distribution is balanced but leaseholders are concentrated

```sql
SET allow_unsafe_internals = true;

-- Compare replica count to leaseholder count
SELECT
  node_id,
  range_count,
  lease_count,
  (lease_count::FLOAT / NULLIF(range_count, 0)::FLOAT)::DECIMAL(10,3) AS leaseholder_ratio
FROM crdb_internal.kv_store_status
WHERE range_count > 0
ORDER BY leaseholder_ratio DESC;
```

Expected ratio is approximately 1/3 for a 3-replica cluster. Imbalance causes include lease preferences in zone configurations, query patterns, and network latency differences.

## Troubleshooting

### Issue: Replicas Not Rebalancing After Node Addition

**Symptoms**:
- New node added hours ago still has few/no replicas
- Rebalancer metrics show no activity
- No errors in logs

**Diagnosis Steps**:

1. Verify rebalancer settings enabled and snapshot rate not too restrictive
2. Check for capacity issues in `crdb_internal.kv_store_status`
3. Review `crdb_internal.cluster_events` for rebalancer decisions

Solutions: Temporarily increase `kv.snapshot_rebalance.max_rate` (`SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '64MiB'`), verify zone constraints, or check network connectivity.

### Issue: Continuous Rebalancing Activity

**Symptoms**:
- Rebalancer constantly moving replicas
- High network and disk I/O
- Snapshot metrics never stabilize

**Diagnosis Steps**:

1. Check `crdb_internal.cluster_events` for flapping nodes (multiple join/restart events)
2. Look for frequently rebalanced ranges in cluster events
3. Review recent zone configuration changes

Solutions: Fix flapping nodes, avoid frequent zone configuration changes, increase `kv.allocator.range_rebalance_threshold` (`SET CLUSTER SETTING kv.allocator.range_rebalance_threshold = 0.10`), or check disk space oscillations.

### Issue: Persistent Under-Replicated Ranges

**Symptoms**:
- Ranges remain under-replicated for extended periods
- Cluster has sufficient capacity
- No obvious node failures

**Diagnosis Steps**:

1. Query `crdb_internal.ranges_no_leases` for ranges with `ARRAY_LENGTH(replicas, 1) < 3`
2. Check for zone constraint violations where constraints cannot be satisfied
3. Review logs for allocator errors (`grep "could not find.*allocation target"`)


Solutions: Relax zone constraints, add nodes for diversity requirements, check for network partitions, or verify capacity across localities.

### Issue: Significant Node Imbalance Despite Normal Rebalancing

**Symptoms**:
- One or more nodes have 20%+ more/fewer replicas than average
- Rebalancer metrics show normal activity
- No recent topology changes

**Diagnosis Steps**:

1. Check cluster events for recent range splits/merges
2. Review zone configurations with locality constraints
3. Check `crdb_internal.kv_store_status` for nodes with `capacity_available = false`

Solutions: Review zone configurations, increase capacity on unavailable nodes, wait for rebalancer completion, or temporarily increase rebalance rate.

## Best Practices

### Monitoring

- Record baseline replica counts after achieving balance
- Check balance weekly (daily during topology changes)
- Alert on balance ratio < 0.80 and persistent under-replicated ranges (>10 minutes)
- Maintain 20% free disk space; plan node additions before 70% capacity

### Rebalancing

- Use default `kv.snapshot_rebalance.max_rate = 32MiB` for production
- Add/remove one node at a time; wait for completion before next change
- Minimize custom zone configurations; document and test changes
- Schedule maintenance during low-traffic periods

### Operations

- Use consistent hardware (disk, CPU, memory, network)
- Design locality hierarchy matching failure domains
- Investigate imbalances >15% promptly
- Maintain runbook and document cluster-specific thresholds

## Related Skills

- **inspect-range-distribution-replicas-and-leaseholder-placement**: Deep dive into range-level replica and leaseholder analysis
- **modify-zone-configurations**: Configure zone settings that affect replica placement
- **verify-cluster-health-between-restarts**: Comprehensive cluster health verification including replica status
- **decommission-nodes-safely**: Proper node removal procedures that trigger rebalancing
- **configure-and-understand-critical-cluster-settings-that-control-failure-detection-and-recovery**: Settings affecting replica management and allocation

## References

- CockroachDB Documentation: [Replication Layer](https://www.cockroachlabs.com/docs/v26.1/architecture/replication-layer)
- CockroachDB Documentation: [Rebalancing](https://www.cockroachlabs.com/docs/v26.1/architecture/replication-layer#rebalancing)
- CockroachDB Documentation: [Configure Replication Zones](https://www.cockroachlabs.com/docs/v26.1/configure-replication-zones)
- CockroachDB Documentation: [Metrics Replication Dashboard](https://www.cockroachlabs.com/docs/v26.1/ui-replication-dashboard)
- Cluster Settings Reference: [Allocator Settings](https://www.cockroachlabs.com/docs/v26.1/cluster-settings#setting-kv-allocator-load-based-rebalancing)
