---
name: monitor-rebalancing-progress
description: Monitor how CockroachDB automatically redistributes data across nodes after topology changes. Use SHOW RANGES WITH DETAILS to track replica placement changes, query ranges metrics, and monitor DB Console dashboards during rebalancing triggered by node additions, decommissions, or zone configuration changes.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - inspect-range-distribution-replicas-and-leaseholder-placement
    - monitor-replica-distribution-balance
    - monitor-underreplicated-ranges
    - decommission-nodes-safely
    - understand-automatic-rebalancing-mechanisms
    - monitor-leaseholder-distribution
  prerequisites:
    - Understanding of ranges and replicas
    - Familiarity with SHOW RANGES commands
    - Access to cluster with monitoring permissions
  estimated_time_minutes: 25
  tags:
    - cluster-operations
    - data-import-export
    - monitoring
    - resilience
  last_updated: "2026-03-06"
---

# Monitor Rebalancing Progress

## Overview

**Rebalancing** is CockroachDB's automatic process of redistributing data (ranges) across nodes to maintain even load distribution, satisfy zone configurations, and respond to topology changes.

**Key concepts:**
- **Range**: Unit of data distribution (default ~512 MiB max)
- **Replica**: Copy of a range stored on a node (typically 3 replicas per range)
- **Rebalancing**: Moving replicas between nodes to achieve balance

**Common triggers:**
- Node additions, decommissions, or failures
- Zone configuration changes
- Load imbalances

**Why monitor:**
- Verify topology changes complete successfully
- Estimate completion time for maintenance windows
- Detect rebalancing stalls or performance impact

## When Rebalancing Occurs

### Node Addition
Replicas gradually move from existing nodes to new node until balanced.
```
Before:  Node 1: 150, Node 2: 148, Node 3: 152, Node 4: N/A
After:   Node 1: 112, Node 2: 113, Node 3: 113, Node 4: 112
```

### Node Decommission
All replicas move OFF target node to remaining nodes.
```
Before:  Node 1: 150, Node 2: 148, Node 3: 152 (target)
After:   Node 1: 225, Node 2: 225, Node 3: 0
```

### Zone Configuration Change
Changing replication factor from 3 to 5 creates 2 additional replicas per range.

### Load Imbalance
Leaseholders transferred to less busy nodes (seconds to minutes).

## Monitoring with SHOW RANGES

### Track Replica Count Per Node

**Primary monitoring query:**
```sql
SET allow_unsafe_internals = true;

-- Count replicas per node
WITH unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM crdb_internal.ranges
),
replica_counts AS (
  SELECT
    node_id,
    count(*) as replica_count
  FROM unnested_replicas
  GROUP BY node_id
)
SELECT
  node_id,
  replica_count,
  (SELECT avg(replica_count)::int FROM replica_counts) as avg_replicas,
  replica_count - (SELECT avg(replica_count)::int FROM replica_counts) as diff_from_avg
FROM replica_counts
ORDER BY node_id;
```

**Example output during rebalancing:**
```
 node_id | replica_count | avg_replicas | diff_from_avg
---------+---------------+--------------+---------------
    1    |     340       |     300      |      +40
    2    |     335       |     300      |      +35
    3    |     325       |     300      |      +25
    4    |     200       |     300      |     -100  ← Still rebalancing
```

**Completion criteria**: `diff_from_avg` should be small (±5-10%)

Run query every 30-60 seconds. New nodes start negative, decommissioning nodes decrease to 0.

### Monitor Specific Table Rebalancing

```sql
SET allow_unsafe_internals = true;

-- Count replicas per node for specific table
-- Use SHOW RANGES to get table-specific data
WITH range_data AS (
  SELECT * FROM [SHOW RANGES FROM TABLE users]
),
unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM range_data
)
SELECT
  node_id,
  count(*) as replica_count
FROM unnested_replicas
GROUP BY node_id
ORDER BY node_id;
```

### Check for Underreplicated Ranges

```sql
SET allow_unsafe_internals = true;

-- Find ranges missing replicas
-- Use SHOW RANGES WITH DETAILS to get num_replicas
WITH range_details AS (
  SELECT * FROM [SHOW CLUSTER RANGES WITH DETAILS]
)
SELECT
  range_id,
  array_length(replicas, 1) as current_replicas,
  num_replicas as target_replicas,
  replicas,
  start_key,
  end_key
FROM range_details
WHERE array_length(replicas, 1) < num_replicas
ORDER BY range_id
LIMIT 20;
```

**Expected:**
- During rebalancing: Some ranges temporarily underreplicated (acceptable)
- After completion: 0 rows returned (all ranges at target)
- Persistent underreplication > 10 minutes: Investigate stall

## Monitoring with DB Console

**Navigate to**: DB Console → Metrics → Replication

**Key metrics:**
- **Replicas per Store**: Lines converge toward same value (new nodes start at 0)
- **Range Add/Remove Events**: Spike during rebalancing, drops to near-zero when complete
- **Underreplicated Ranges**: Should be 0 (temporary spike acceptable)
- **Network Throughput**: High during rebalancing, returns to baseline after completion

## Tracking Metrics with SQL

### Monitor Replica Distribution Balance

```sql
SET allow_unsafe_internals = true;

-- Calculate standard deviation of replica distribution
WITH unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM crdb_internal.ranges
),
replica_counts AS (
  SELECT
    node_id,
    count(*) as replica_count
  FROM unnested_replicas
  GROUP BY node_id
)
SELECT
  stddev(replica_count)::int as std_dev,
  min(replica_count) as min_replicas,
  max(replica_count) as max_replicas,
  avg(replica_count)::int as avg_replicas
FROM replica_counts;

-- Well balanced: std_dev < 50
```


## Estimating Completion Time

### Calculate Remaining Work

```sql
SET allow_unsafe_internals = true;

-- Show how far each node is from ideal balance
WITH unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM crdb_internal.ranges
),
replica_stats AS (
  SELECT
    node_id,
    count(*) as replica_count
  FROM unnested_replicas
  GROUP BY node_id
),
stats_with_avg AS (
  SELECT
    node_id,
    replica_count,
    avg(replica_count) OVER () as avg_replicas
  FROM replica_stats
)
SELECT
  node_id,
  replica_count as current_replicas,
  avg_replicas::int as target_replicas,
  abs(replica_count - avg_replicas)::int as replicas_to_move
FROM stats_with_avg
ORDER BY replicas_to_move DESC;
```

**Estimate time**: Replicas to move ÷ rate (~5 replicas/sec typical). Actual time depends on range sizes, network bandwidth, cluster load, and throttle settings.

## Understanding Rebalancing Performance Impact

**Expected effects:**
- Network traffic increases (data transfers)
- CPU/Disk I/O moderate increase
- Query latency minimal impact (1-5% typical)

Rebalancing is throttled and foreground traffic prioritized. Snapshot transfers rate-limited to 8 MiB/s per store by default.

## Controlling Rebalancing Speed

### Rebalancing Throttle Settings

**Key cluster setting**: `kv.snapshot_rebalance.max_rate`

```sql
-- View current setting
SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;
-- Default: 8 MiB/s

-- Increase speed (faster completion, higher load)
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '32MiB';

-- Decrease speed (slower completion, lower load)
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '4MiB';

-- Pause rebalancing (emergency only)
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '1KiB';
```

**When to adjust:**
- **Increase rate**: Off-peak hours, urgent rebalancing needed
- **Decrease rate**: Peak hours, performance-sensitive workloads
- **Pause**: Emergency only (resume ASAP)


## Common Monitoring Workflows

### Workflow 1: Monitor Node Addition Rebalancing

```sql
-- Step 1: Capture baseline before adding node
SET allow_unsafe_internals = true;

WITH unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM crdb_internal.ranges
)
SELECT node_id, count(*) as replicas
FROM unnested_replicas
GROUP BY node_id ORDER BY node_id;

-- Step 2: Add new node (cockroach start --join=...)

-- Step 3: Monitor progress (run every 60 seconds)
WITH unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM crdb_internal.ranges
)
SELECT node_id, count(*) as replicas
FROM unnested_replicas
GROUP BY node_id ORDER BY node_id;

-- Step 4: Verify completion (standard deviation < 50)
WITH unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM crdb_internal.ranges
),
replica_counts AS (
  SELECT count(*) as replica_count
  FROM unnested_replicas
  GROUP BY node_id
)
SELECT stddev(replica_count)::int as std_dev FROM replica_counts;
```

### Workflow 2: Monitor Zone Config Change

```sql
SET allow_unsafe_internals = true;

-- Step 1: Apply change
ALTER DATABASE mydb CONFIGURE ZONE USING num_replicas = 5;

-- Step 2: Monitor progress using SHOW RANGES
WITH range_data AS (
  SELECT * FROM [SHOW RANGES FROM DATABASE mydb]
)
SELECT
  array_length(replicas, 1) as replica_count,
  count(*) as range_count
FROM range_data
GROUP BY array_length(replicas, 1)
ORDER BY replica_count;

-- Step 3: Verify completion (should return 0)
WITH range_data AS (
  SELECT * FROM [SHOW RANGES FROM DATABASE mydb]
)
SELECT count(*) FROM range_data
WHERE array_length(replicas, 1) < 5;
```

### Workflow 3: Monitor Decommission Progress

```bash
# Step 1: Start decommission
cockroach node decommission 3 --certs-dir=certs --host=localhost:26258

# Step 2: Monitor via CLI
watch -n 5 "cockroach node status --decommission --certs-dir=certs --host=localhost:26258"

# Step 3: Monitor via SQL
```

```sql
SET allow_unsafe_internals = true;
SELECT count(*) as replicas_remaining
FROM crdb_internal.ranges
WHERE 3 = ANY(replicas);
-- Goal: 0 replicas
```

```bash
# Step 4: Verify completion
cockroach node status 3 --certs-dir=certs --host=localhost:26258
# Look for: is_decommissioning = true, replicas = 0
```

## Troubleshooting

### Problem: Rebalancing Stalled

**Symptoms**: Replica counts not changing, underreplicated ranges persist

**Diagnosis:**
```sql
SET allow_unsafe_internals = true;

-- 1. Check underreplicated ranges using SHOW RANGES
WITH range_details AS (
  SELECT * FROM [SHOW CLUSTER RANGES WITH DETAILS]
)
SELECT count(*) FROM range_details
WHERE array_length(replicas, 1) < num_replicas;

-- 2. Check throttle setting
SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;

-- 3. Check disk space
SELECT
  node_id,
  (metrics->>'capacity.available')::BIGINT / (1024*1024*1024) as available_gb,
  ((metrics->>'capacity.used')::FLOAT /
   (metrics->>'capacity')::FLOAT * 100)::int as percent_used
FROM crdb_internal.kv_store_status
ORDER BY percent_used DESC;
```

**Solutions:**
- **Disk full**: Free space or add nodes
- **Throttle too low**: Increase `kv.snapshot_rebalance.max_rate`
- **Network issues**: Check connectivity between nodes

### Problem: Rebalancing Too Slow

**Symptoms**: Taking hours/days, maintenance window too short

**Solution:**
```sql
-- Increase rate during off-peak hours
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '64MiB';

-- Calculate expected time:
-- Data to move: 100 GB
-- Rate: 64 MiB/s = ~27 minutes (vs 3.5 hours at 8 MiB/s)
```

### Problem: Rebalancing Impacting Performance

**Symptoms**: Increased query latency, high CPU/disk, user complaints

**Solution:**
```sql
-- Reduce rebalancing rate
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '4MiB';

-- Schedule aggressive rebalancing for off-peak (requires automation)
```

### Problem: Replicas Imbalanced After Completion

**Symptoms**: Nodes have significantly different replica counts (20%+ variance)

**Possible causes:**
- Zone constraints preventing even distribution
- Node locality mismatches
- Disk space constraints on some nodes

**Solution**: Check zone configurations, node localities, and disk space

## Best Practices

1. **Monitor proactively**: Set up alerting for underreplicated ranges > 0, track replica distribution in dashboards
2. **Plan maintenance windows**: Small clusters (< 100 GB) take minutes, large clusters (> 1 TB) take hours; test in staging
3. **Adjust throttle appropriately**: Increase during off-peak for faster completion, decrease during peak hours
4. **Verify completion**: Underreplicated ranges = 0, replica distribution balanced (std_dev < 50), zone config compliance confirmed
5. **Document baselines**: Record normal replica counts, typical completion times, and throttle settings
6. **Test in non-production**: Simulate changes, measure impact, tune settings before production

## Summary

**Rebalancing monitoring checklist:**

✅ Track replica distribution with `crdb_internal.ranges`
✅ Monitor DB Console Replication dashboard
✅ Check underreplicated ranges = 0
✅ Estimate completion time from remaining work
✅ Adjust throttle if needed (balance speed vs impact)
✅ Verify balanced distribution at completion

**Essential queries:**
```sql
SET allow_unsafe_internals = true;

-- Replica count per node
WITH unnested_replicas AS (
  SELECT unnest(replicas) as node_id
  FROM crdb_internal.ranges
)
SELECT node_id, count(*)
FROM unnested_replicas GROUP BY node_id;

-- Underreplicated ranges
WITH range_details AS (
  SELECT * FROM [SHOW CLUSTER RANGES WITH DETAILS]
)
SELECT count(*) FROM range_details
WHERE array_length(replicas, 1) < num_replicas;

-- Rebalancing rate
SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;
```

**Remember**: Rebalancing is automatic and self-healing. Monitor to verify completion and adjust throttle when needed.

## Related Skills

- `inspect-range-distribution-replicas-and-leaseholder-placement` - Inspect current state
- `monitor-replica-distribution-balance` - Verify balanced distribution
- `monitor-underreplicated-ranges` - Detect replication issues
- `decommission-nodes-safely` - Trigger rebalancing via decommission
- `understand-automatic-rebalancing-mechanisms` - Theory behind rebalancing
- `monitor-leaseholder-distribution` - Track leaseholder rebalancing

## Documentation

- Rebalancing: https://www.cockroachlabs.com/docs/stable/architecture/replication-layer.html#rebalancing
- SHOW RANGES: https://www.cockroachlabs.com/docs/stable/show-ranges.html
- Cluster settings: https://www.cockroachlabs.com/docs/stable/cluster-settings.html
