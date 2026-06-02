---
name: monitor-replica-rebalancing-after-node-failures
description: Monitor automatic replica rebalancing after node failures to verify cluster self-healing and assess recovery progress. Use when responding to node outages, validating recovery completion, or troubleshooting slow rebalancing.
metadata:
  domain: Resilience and Failure Handling
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - monitor-underreplicated-ranges-for-availability-risk
    - understand-automatic-rebalancing-mechanisms
    - understand-node-state-transitions-during-failures
    - recover-from-temporary-node-outages
  prerequisites:
    - Understanding of replication factor and ranges
    - Knowledge of automatic recovery mechanisms
  estimated_time_minutes: 30
  last_updated: "2026-03-07"
---

# Monitor Replica Rebalancing After Node Failures

## Overview

When a node fails and is declared DEAD (after `server.time_until_store_dead`, default 5 minutes), CockroachDB automatically initiates replica rebalancing to restore full replication factor across remaining nodes. Monitoring this rebalancing process ensures the cluster returns to a fully healthy state and helps identify issues that may slow or prevent complete recovery.

**Critical**: Rebalancing is automatic, but monitoring is essential to verify completion, identify bottlenecks, and ensure the cluster returns to optimal replica distribution.

## When Rebalancing Occurs

### Automatic Triggers

**1. Node declared DEAD:**
- Node fails to update liveness for 5 minutes (default)
- Cluster marks node as dead
- Replicas on dead node become under-replicated
- Automatic up-replication begins immediately

**2. Node decommissioned:**
- Manual decommission initiated
- Replicas systematically moved off target node
- Up-replication to other nodes

**3. New node added:**
- Node joins existing cluster
- Excess replicas rebalanced to new node for even distribution

**4. Disk space imbalance:**
- One node significantly more full than others
- Rebalancer redistributes ranges to balance capacity usage

### Rebalancing Phases

**Phase 1: Detection (0-5 minutes)**
- Cluster detects node is unresponsive
- Liveness record expires
- Node marked as DEAD

**Phase 2: Up-replication (5+ minutes)**
- Under-replicated ranges identified
- New replicas created on available nodes
- Snapshots transferred to bring replicas up to date

**Phase 3: Rebalancing (ongoing)**
- Once full replication restored, cluster optimizes placement
- Balances replica count across nodes
- Optimizes for zone constraints and load distribution

## Monitoring Rebalancing Progress

### 1. Track Under-Replicated Range Count

```sql
-- Monitor under-replicated ranges over time
SELECT
  count(*) FILTER (WHERE array_length(replicas, 1) < 3) as underreplicated,
  count(*) as total_ranges,
  count(*) FILTER (WHERE array_length(replicas, 1) < 3)::FLOAT /
    count(*)::FLOAT * 100 as pct_underreplicated
FROM crdb_internal.ranges;
```

**Expected progression after node failure:**
```
Time    underreplicated   total_ranges   pct_underreplicated
------  ----------------  -------------  -------------------
0:00    0                 1247           0.00%
5:00    420               1247           33.68%      (node declared dead)
6:00    387               1247           31.03%      (rebalancing started)
8:00    245               1247           19.65%
10:00   156               1247           12.51%
15:00   42                1247           3.37%
20:00   0                 1247           0.00%       (fully recovered)
```

**Continuous monitoring:**
```bash
# Watch under-replicated count every 30 seconds
watch -n 30 'cockroach sql --host=localhost:26257 --certs-dir=certs -e "
  SELECT count(*) as underreplicated
  FROM crdb_internal.ranges
  WHERE array_length(replicas, 1) < 3;"'
```

### 2. Monitor Replica Distribution Across Nodes

```sql
-- Check replica count per node
SELECT
  store_id,
  node_id,
  range_count,
  ROUND(used::DECIMAL / capacity::DECIMAL * 100, 2) as pct_used
FROM crdb_internal.kv_store_status
WHERE node_id != 3  -- Exclude dead node
ORDER BY range_count DESC;
```

**Before failure (3 nodes, balanced):**
```
  store_id | node_id | range_count | pct_used
-----------+---------+-------------+----------
         1 |       1 |        1245 |    42.35
         2 |       2 |        1247 |    43.12
         3 |       3 |        1250 |    44.05
```

**During rebalancing (node 3 failed, rebalancing to nodes 1 and 2):**
```
  store_id | node_id | range_count | pct_used
-----------+---------+-------------+----------
         1 |       1 |        1654 |    58.23    (increased)
         2 |       2 |        1672 |    59.87    (increased)
```

**After completion (balanced across 2 nodes):**
```
  store_id | node_id | range_count | pct_used
-----------+---------+-------------+----------
         1 |       1 |        1872 |    65.14    (balanced)
         2 |       2 |        1875 |    65.42    (balanced)
```

### 3. Monitor Snapshot Transfer Activity

```bash
# Check snapshot metrics via Prometheus endpoint
curl -s http://localhost:8080/_status/vars | grep "range_snapshot"

# Key metrics:
# range_snapshots_generated: Snapshots created (should increase during rebalancing)
# range_snapshots_applied_voter: Snapshots applied to voting replicas
# range_snapshots_applied_initial: Initial snapshots for new replicas
```

**Example output during active rebalancing:**
```
range_snapshots_generated 1523
range_snapshots_applied_voter 1487
range_snapshots_applied_initial 142
range_snapshots_preemptive_throttled 23
```

**Interpretation:**
- `generated` increasing rapidly: Active snapshot creation for new replicas
- `applied_voter` tracking close to generated: Snapshots successfully applied
- `preemptive_throttled`: Snapshot rate limiting engaged (normal under high rebalancing)

### 4. Check Rebalancing Rate Limits

```sql
-- View current snapshot rate limits
SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;
SHOW CLUSTER SETTING kv.snapshot_recovery.max_rate;
SHOW CLUSTER SETTING kv.snapshot_delegation.enabled;
```

**Typical output:**
```
  kv.snapshot_rebalance.max_rate
----------------------------------
  32 MiB

  kv.snapshot_recovery.max_rate
---------------------------------
  32 MiB

  kv.snapshot_delegation.enabled
----------------------------------
  true
```

**Impact on rebalancing speed:**
- Higher rates = faster recovery, more network bandwidth used
- Lower rates = slower recovery, less impact on production traffic
- Delegation = allow follower replicas to send snapshots (recommended)

### 5. Monitor Via DB Console Replication Dashboard

**Access the dashboard:**
1. Navigate to `https://localhost:8080`
2. Click **Metrics** in left navigation
3. Select **Dashboard > Replication**

**Key graphs to monitor:**

**Ranges Graph:**
- Under-replicated Ranges (should decrease to 0)
- Over-replicated Ranges (may temporarily spike)
- Unavailable Ranges (should remain 0)

**Replicas per Store:**
- Should show increasing replica counts on remaining nodes
- Eventually should balance evenly

**Snapshot Queue:**
- Shows queue depth for pending snapshots
- High queue depth indicates active rebalancing

**Example progression:**
```
Time    Under-replicated   Snapshot Queue Depth
------  -----------------  --------------------
5:00    420                215
7:00    287                198
10:00   156                142
15:00   42                 68
20:00   0                  0
```

### 6. Query Replication Reports

```sql
-- Detailed replication status by table
SELECT
  database_name,
  table_name,
  total_ranges,
  under_replicated_ranges,
  over_replicated_ranges
FROM system.replication_stats
WHERE under_replicated_ranges > 0
   OR over_replicated_ranges > 0
ORDER BY under_replicated_ranges DESC;
```

**During recovery:**
```
  database_name | table_name | total_ranges | under_replicated_ranges | over_replicated_ranges
----------------+------------+--------------+-------------------------+------------------------
  movr          | rides      |          456 |                     142 |                      0
  movr          | users      |          123 |                      38 |                      0
  system        | jobs       |           45 |                      12 |                      0
```

**After recovery:**
```
(0 rows)
```

### 7. Monitor Network Bandwidth Usage

```bash
# Check network I/O on receiving nodes
ssh node1.example.com
sudo iftop -i eth0

# Or using Prometheus metrics
curl -s http://node1:8080/_status/vars | grep "network_bytes"
```

**During active rebalancing:**
- Expect sustained network ingress on nodes receiving replicas
- Network utilization may reach snapshot rate limits
- Outbound traffic from nodes with surviving replicas

## Expected Rebalancing Timeline

### Small Cluster (3 nodes, 100GB per node)

```
Time    Event
------  ---------------------------------------------------------------
0:00    Node 3 fails
5:00    Node 3 declared DEAD, rebalancing begins
5:30    10% of under-replicated ranges recovered
6:30    25% recovered
8:00    50% recovered
10:00   75% recovered
12:00   90% recovered
15:00   100% recovered - all ranges at full replication factor
```

**Total recovery time**: ~10-15 minutes for 100GB

### Large Cluster (10 nodes, 500GB per failed node)

```
Time    Event
------  ---------------------------------------------------------------
0:00    Node 7 fails
5:00    Node 7 declared DEAD, rebalancing begins
6:00    5% of under-replicated ranges recovered
10:00   15% recovered
20:00   35% recovered
40:00   60% recovered
60:00   80% recovered
90:00   95% recovered
120:00  100% recovered
```

**Total recovery time**: ~90-120 minutes for 500GB

**Factors affecting timeline:**
- Data volume on failed node
- Network bandwidth between nodes
- Snapshot rate limit settings
- Cluster load during recovery
- Number of surviving nodes (more nodes = faster parallel recovery)

## Optimizing Rebalancing Performance

### Temporarily Increase Snapshot Rate

```sql
-- Increase snapshot rate for faster recovery (if network can handle it)
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '128 MiB';
SET CLUSTER SETTING kv.snapshot_recovery.max_rate = '128 MiB';

-- Monitor progress, then reset to default
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = DEFAULT;
SET CLUSTER SETTING kv.snapshot_recovery.max_rate = DEFAULT;
```

**Considerations:**
- Only increase if network has spare capacity
- Monitor impact on application latency
- Higher rates may saturate network and affect production traffic

### Enable Snapshot Delegation (if not already enabled)

```sql
-- Allow follower replicas to send snapshots
SET CLUSTER SETTING kv.snapshot_delegation.enabled = true;
```

**Benefit:** Distributes snapshot load across multiple nodes instead of requiring leaseholder to send all snapshots

### Monitor for Bottlenecks

```sql
-- Check if any nodes are at capacity (preventing replica placement)
SELECT
  node_id,
  used / capacity * 100 as pct_used,
  available / (1024*1024*1024) as available_gb
FROM crdb_internal.kv_store_status
WHERE used / capacity > 0.80
ORDER BY pct_used DESC;
```

**If nodes >80% full:**
- Rebalancing may slow or stall
- Add capacity or remove data before continuing

## Troubleshooting Slow or Stalled Rebalancing

### Issue 1: Rebalancing Not Starting

**Symptoms:**
- Under-replicated range count not decreasing after 10+ minutes
- No snapshot activity in metrics

**Diagnosis:**
```sql
-- Check if cluster has available capacity
SELECT
  count(*) FILTER (WHERE is_live = true AND is_available = true) as available_nodes,
  count(*) as total_nodes
FROM crdb_internal.kv_node_liveness;

-- Check for zone constraint violations
SELECT target, config
FROM crdb_internal.zones
WHERE target = 'RANGE default';
```

**Common causes:**
- Insufficient live nodes to satisfy replication factor
- Zone constraints cannot be satisfied
- All remaining nodes at capacity

**Resolution:**
- Add new nodes to cluster
- Adjust zone constraints
- Free up disk space

### Issue 2: Rebalancing Very Slow

**Symptoms:**
- Under-replicated ranges decreasing, but very slowly
- Recovery taking hours instead of minutes

**Diagnosis:**
```bash
# Check snapshot rate limits
cockroach sql --host=localhost:26257 --certs-dir=certs -e "
  SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;
  SHOW CLUSTER SETTING kv.snapshot_recovery.max_rate;"

# Check network bandwidth utilization
ssh node1.example.com "sar -n DEV 1 10 | grep eth0"
```

**Common causes:**
- Conservative snapshot rate limits (default 32 MiB/s)
- Network bandwidth saturation
- High cluster load competing for resources
- Disk I/O saturation on receiving nodes

**Resolution:**
- Temporarily increase snapshot rates (if network permits)
- Reduce application load during recovery
- Upgrade network infrastructure
- Add SSD storage for faster I/O

### Issue 3: Rebalancing Stalls Before Completion

**Symptoms:**
- Some under-replicated ranges remain for extended period
- Count decreases then stops improving

**Diagnosis:**
```sql
-- Identify specific stuck ranges
SET allow_unsafe_internals = true;

SELECT
  range_id,
  database_name,
  table_name,
  array_length(replicas, 1) as replica_count,
  replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3
LIMIT 10;

-- Check zone constraints for these tables
SELECT target, config
FROM crdb_internal.zones
WHERE target LIKE '%<table_name>%';
```

**Common causes:**
- Zone constraints impossible to satisfy (e.g., requiring 3 zones but only 2 available)
- Specific nodes at capacity
- Replica placement issues with locality requirements

**Resolution:**
- Modify zone constraints to match available topology
- Add capacity to specific localities
- Manual intervention may be required for stuck ranges

## Automated Monitoring Script

```bash
#!/bin/bash
# monitor-rebalancing.sh - Track rebalancing progress

THRESHOLD=0
INTERVAL=30  # Check every 30 seconds
MAX_WAIT=3600  # Max 1 hour

START_TIME=$(date +%s)

echo "=== Monitoring Rebalancing Progress ==="
echo "Start time: $(date)"
echo ""

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))

  if [ $ELAPSED -gt $MAX_WAIT ]; then
    echo "WARNING: Rebalancing taking longer than expected (>1 hour)"
    break
  fi

  UNDERREPLICATED=$(cockroach sql --host=localhost:26257 --certs-dir=certs -e "
    SELECT count(*) FROM crdb_internal.ranges
    WHERE array_length(replicas, 1) < 3;" -t 2>/dev/null)

  TIMESTAMP=$(date '+%H:%M:%S')
  echo "[$TIMESTAMP] Under-replicated ranges: $UNDERREPLICATED"

  if [ "$UNDERREPLICATED" -le "$THRESHOLD" ]; then
    echo ""
    echo "=== Rebalancing Complete ==="
    echo "Total time: $((ELAPSED / 60)) minutes"
    break
  fi

  sleep $INTERVAL
done
```

**Usage:**
```bash
chmod +x monitor-rebalancing.sh
./monitor-rebalancing.sh
```

## Best Practices

1. **Monitor actively during recovery**: Don't assume automatic recovery completes successfully
2. **Set up alerting**: Alert if under-replicated ranges persist >30 minutes
3. **Verify completion**: Ensure under-replicated count reaches 0 before considering recovery complete
4. **Plan for recovery time**: Factor recovery duration into maintenance windows
5. **Test failure scenarios**: Simulate node failures in staging to understand recovery behavior
6. **Capacity planning**: Maintain <70% disk usage to allow room for rebalancing
7. **Network capacity**: Ensure network can handle snapshot traffic during recovery
8. **Document baselines**: Know typical recovery times for your cluster size

## Verification After Rebalancing

### Final Health Check

```sql
-- Verify no under-replicated or unavailable ranges
SELECT
  count(*) FILTER (WHERE array_length(replicas, 1) = 0) as unavailable,
  count(*) FILTER (WHERE array_length(replicas, 1) < 3) as underreplicated,
  count(*) as total_ranges
FROM crdb_internal.ranges;
```

**Expected result:**
```
  unavailable | underreplicated | total_ranges
--------------+-----------------+--------------
            0 |               0 |         1247
```

### Verify Balanced Distribution

```sql
-- Check replica distribution is balanced
SELECT
  node_id,
  range_count,
  AVG(range_count) OVER () as avg_range_count,
  ROUND((range_count - AVG(range_count) OVER ()) /
        AVG(range_count) OVER () * 100, 2) as pct_variance
FROM crdb_internal.kv_store_status
WHERE node_id != 3  -- Exclude dead node
ORDER BY node_id;
```

**Expected result:**
```
  node_id | range_count | avg_range_count | pct_variance
----------+-------------+-----------------+--------------
        1 |        1872 |          1873.5 |        -0.08
        2 |        1875 |          1873.5 |         0.08
```

**Good variance**: Within ±5%
**Acceptable variance**: Within ±10%
**Investigate if**: Variance >15%

## Related Documentation

- [Replication and Rebalancing](https://www.cockroachlabs.com/docs/stable/demo-replication-and-rebalancing)
- [Replication Dashboard](https://www.cockroachlabs.com/docs/stable/ui-replication-dashboard)
- [Fault Tolerance & Recovery](https://www.cockroachlabs.com/docs/stable/demo-fault-tolerance-and-recovery)
- [Automated Rebalance and Repair](https://www.cockroachlabs.com/blog/automated-rebalance-and-repair/)
- [Replication Layer](https://www.cockroachlabs.com/docs/stable/architecture/replication-layer)

## Summary

Effective rebalancing monitoring after node failures involves:

1. Track under-replicated range count over time (should decrease to 0)
2. Monitor replica distribution across surviving nodes
3. Watch snapshot transfer activity and queue depth
4. Verify completion with comprehensive health checks
5. Tune snapshot rates if necessary for faster recovery
6. Troubleshoot bottlenecks preventing complete recovery
7. Expect 10-120 minutes recovery depending on data volume
8. Always verify balanced distribution after rebalancing completes
