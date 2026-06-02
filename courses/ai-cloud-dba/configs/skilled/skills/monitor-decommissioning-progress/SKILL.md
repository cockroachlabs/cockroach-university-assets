---
name: monitor-decommissioning-progress
description: Monitor node decommissioning progress using cockroach node status and SQL queries. Track replica count decreasing to zero, membership status transitions, and verify completion. Essential for long-running decommission operations and troubleshooting stalled decommissions.
metadata:
  domain: Resilience and Failure Handling
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - decommission-nodes-permanently
    - check-node-decommission-status
    - monitor-data-movement-during-node-decommissioning
    - verify-cluster-after-node-removal
    - inspect-range-distribution-replicas-and-leaseholder-placement
  prerequisites:
    - Understanding of node decommissioning concepts
    - Knowledge of replica distribution
    - Familiarity with SQL queries
  estimated_time_minutes: 20
  last_updated: "2026-03-07"
---

# Monitor Decommissioning Progress

## Overview

Node decommissioning can take hours to complete, especially for nodes with large amounts of data. **Active monitoring** is essential to ensure the process completes successfully and to detect any issues early.

This skill covers how to track decommissioning progress using:
- `cockroach node status --decommission` command
- SQL queries against internal tables
- Network traffic monitoring
- Log file analysis

**Why monitoring matters:**
- Decommissioning large nodes can take 4-12+ hours
- Stalled decommissions need intervention
- Resource bottlenecks require adjustment
- Completion verification prevents premature node shutdown

## Key Metrics to Monitor

When monitoring decommissioning progress, track these critical metrics:

1. **Replica Count**: Number of replicas remaining on decommissioning node (must reach 0)
2. **Membership Status**: Transitions from `active` → `decommissioning` → `decommissioned`
3. **is_decommissioning Flag**: Shows `true` during process, `false` when complete
4. **Network Traffic**: Data transfer rates during replica migration
5. **Time Elapsed**: Total duration to estimate completion time

## Primary Monitoring Method: cockroach node status

### Basic Status Check

```bash
# Check decommission status for all nodes
cockroach node status --decommission --host=localhost:26257 --certs-dir=certs
```

**Example output:**
```
  id | is_live | replicas | is_decommissioning |   membership    | is_draining
-----+---------+----------+--------------------+-----------------+--------------
   1 | true    |      245 | false              | active          | false
   2 | true    |      238 | false              | active          | false
   3 | true    |      156 | true               | decommissioning | false
   4 | true    |      241 | false              | active          | false
   5 | true    |      240 | false              | active          | false
```

**Key columns to watch:**
- `replicas`: Should decrease steadily toward 0 for decommissioning node
- `is_decommissioning`: `true` means decommission in progress
- `membership`: Shows current status in lifecycle

### Real-Time Monitoring with watch

```bash
# Update every 10 seconds
watch -n 10 'cockroach node status --decommission --host=localhost:26257 --certs-dir=certs'
```

**Best practice**: Use `watch` for continuous monitoring during active decommission.

### Monitoring Specific Node

```bash
# Filter output to show only decommissioning node
cockroach node status --decommission --host=localhost:26257 --certs-dir=certs | grep -E "id|^\s*3"
```

Replace `3` with the actual node ID being decommissioned.

## SQL-Based Monitoring Queries

### Query Node Liveness and Decommission Status

```sql
-- Check decommissioning status via gossip_liveness
SELECT node_id,
       decommissioning,
       draining,
       membership,
       updated_at
FROM crdb_internal.gossip_liveness
WHERE decommissioning = true;
```

**Expected output during decommission:**
```
  node_id | decommissioning | draining |   membership    |        updated_at
----------+-----------------+----------+-----------------+---------------------------
        3 | true            | false    | decommissioning | 2026-03-07 14:23:45+00:00
```

### Monitor Replica Count Decreasing

```sql
-- Track replica count on decommissioning node
SELECT node_id,
       replicas,
       ranges,
       leases,
       used_capacity_bytes / (1024*1024*1024) as used_gb
FROM crdb_internal.kv_store_status
WHERE node_id = 3;
```

**What to watch:**
- `replicas`: Should decrease steadily
- `ranges`: Decreases as ranges move off node
- `leases`: Should drop to 0 early in process

**Typical progression:**
```
Time     | Replicas | Ranges | Leases
---------|----------|--------|--------
0:00     |      156 |     52 |     18
0:15     |      142 |     47 |      0  (leases transferred)
0:30     |      118 |     39 |      0
1:00     |       89 |     29 |      0
2:00     |       45 |     15 |      0
3:00     |       12 |      4 |      0
3:45     |        0 |      0 |      0  (complete!)
```

### Identify Specific Ranges Remaining on Node

```sql
-- Find ranges still on decommissioning node
SET allow_unsafe_internals = true;

SELECT range_id,
       start_key,
       array_length(replicas, 1) as replica_count,
       replicas
FROM crdb_internal.ranges
WHERE 3 = ANY(replicas)
ORDER BY range_id
LIMIT 20;
```

**Use case**: Diagnose which ranges are slow to move or stuck.

### Check for Under-Replicated Ranges

```sql
-- Verify no under-replicated ranges during decommission
SET allow_unsafe_internals = true;

SELECT count(*) as under_replicated_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
```

**Expected result**: Should be `0` throughout decommission. Non-zero indicates a problem.

## Monitor Network Traffic During Decommission

### Track Network Bytes Transferred

```sql
-- Monitor network I/O across nodes
SELECT node_id,
       network_bytes_sent / (1024*1024*1024) as gb_sent,
       network_bytes_recv / (1024*1024*1024) as gb_recv
FROM crdb_internal.gossip_network
ORDER BY gb_sent DESC;
```

**What to expect:**
- High network traffic on nodes receiving replicas
- Outbound traffic from decommissioning node
- Traffic proportional to data being moved

### Monitor Cluster-Wide Rebalancing Activity

```sql
-- Check rebalancing metrics
SELECT store_id,
       replicas,
       replica_count,
       range_count,
       bytes_per_replica::FLOAT / (1024*1024) as avg_mb_per_replica
FROM crdb_internal.kv_store_status
ORDER BY store_id;
```

## Log File Analysis

### Check Decommission Progress in Logs

```bash
# Search logs for decommission-related messages
grep -i "decommission" /var/log/cockroach/cockroach.log | tail -50
```

**Key log messages to look for:**

**Decommission started:**
```
I260307 14:15:23.456789 server/status.go:234 ⋮ marking node n3 as decommissioning
```

**Replica movement:**
```
I260307 14:18:45.123456 storage/replica.go:567 ⋮ replica moved from node 3 to node 2 for range 245
```

**Stalled decommission warning:**
```
W260307 15:30:12.789012 server/decommission.go:123 ⋮ possible decommission stall detected for node 3
```

**Decommission complete:**
```
I260307 17:45:33.456789 server/status.go:345 ⋮ node n3 successfully decommissioned
```

### Monitor for Errors

```bash
# Check for errors during decommission
grep -E "(ERROR|FATAL)" /var/log/cockroach/cockroach.log | grep -i decommission
```

**Common error patterns:**
- `insufficient capacity` - Remaining nodes full
- `replication error` - Network or disk issues
- `under-replicated` - Quorum problems

## Estimate Time to Completion

### Calculate Decommission Rate

Track replica count over time to estimate completion:

```bash
# Initial reading at time T0
# replicas_t0 = 156

# Reading 30 minutes later at T1
# replicas_t1 = 118

# Calculate rate
# rate = (156 - 118) / 30 = 1.27 replicas/minute

# Estimate time remaining
# time_remaining = 118 / 1.27 ≈ 93 minutes
```

**Note**: Rate varies based on replica size, network speed, and cluster load.

### SQL Query for Rate Calculation

```sql
-- Track replica count over time (run periodically)
SELECT node_id,
       replicas,
       now() as measured_at
FROM crdb_internal.kv_store_status
WHERE node_id = 3;
```

Save results and compare to calculate decommission velocity.

## Detect Stalled Decommissions

### Symptoms of Stalled Decommission

**A decommission is stalled if:**
- Replica count unchanged for >30 minutes
- No network traffic from decommissioning node
- Logs show "possible decommission stall detected" warning
- `replicas` stuck at non-zero value for hours

### Diagnose Stall Cause

```sql
-- Check if remaining nodes have capacity
SELECT node_id,
       used_capacity_bytes::FLOAT / capacity_bytes::FLOAT * 100 as pct_used,
       available_capacity_bytes / (1024*1024*1024) as available_gb
FROM crdb_internal.kv_store_status
WHERE node_id != 3
ORDER BY pct_used DESC;
```

**Common stall causes:**
1. **No capacity**: Remaining nodes >85% full
2. **Under-replication**: Existing under-replicated ranges blocking movement
3. **Network issues**: Connectivity problems between nodes
4. **Resource exhaustion**: CPU/memory bottleneck on receiving nodes
5. **Meta range delays**: System ranges slow to move

### Check for Blocking Ranges

```sql
-- Identify ranges preventing decommission completion
SET allow_unsafe_internals = true;

SELECT range_id,
       start_key,
       end_key,
       array_length(replicas, 1) as replica_count,
       replicas
FROM crdb_internal.ranges
WHERE 3 = ANY(replicas)
  AND array_length(replicas, 1) < 3
ORDER BY range_id;
```

**Action**: If ranges are under-replicated, decommission cannot complete until replication is restored.

## Monitor Remaining Nodes During Decommission

### Check Disk Space on Receiving Nodes

```sql
-- Monitor disk usage on nodes receiving replicas
SELECT node_id,
       capacity_bytes / (1024*1024*1024) as capacity_gb,
       available_capacity_bytes / (1024*1024*1024) as available_gb,
       used_capacity_bytes::FLOAT / capacity_bytes::FLOAT * 100 as pct_used
FROM crdb_internal.kv_store_status
WHERE node_id != 3
ORDER BY pct_used DESC;
```

**Warning threshold**: Alert if any node exceeds 85% during decommission.

### Monitor CPU and Memory Usage

```bash
# Check resource usage on remaining nodes via DB Console
# Navigate to: http://localhost:8080/metrics/hardware

# Or via metrics API
curl -k https://localhost:8080/_status/vars | grep -E "(cpu|memory)"
```

**Watch for:**
- CPU spikes during replica writes
- Memory pressure from increased replica count
- Disk I/O saturation

## Completion Verification

### Verify Decommission Fully Complete

```bash
# Final status check
cockroach node status --decommission --host=localhost:26257 --certs-dir=certs
```

**Success criteria:**
```
  id | is_live | replicas | is_decommissioning |   membership    | is_draining
-----+---------+----------+--------------------+-----------------+--------------
   3 | false   |        0 | false              | decommissioned  | false
```

**All must be true:**
- ✅ `replicas` = 0
- ✅ `is_decommissioning` = false
- ✅ `membership` = `decommissioned`

### SQL Verification Query

```sql
-- Confirm node has no replicas remaining
SET allow_unsafe_internals = true;

SELECT count(*) as ranges_on_node_3
FROM crdb_internal.ranges
WHERE 3 = ANY(replicas);
```

**Expected result**: `ranges_on_node_3` = 0

### Post-Decommission Cluster Health Check

```sql
-- Verify no under-replicated ranges
SET allow_unsafe_internals = true;

SELECT count(*) as under_replicated
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
```

**Expected result**: `under_replicated` = 0

## Monitoring Best Practices

1. **Use automated monitoring**: Set up `watch` command or cron job to track progress
2. **Log metrics periodically**: Record replica counts every 15 minutes for analysis
3. **Set alert thresholds**: Notify if progress stalls for >30 minutes
4. **Monitor cluster health**: Check remaining nodes' capacity and performance
5. **Document baseline**: Record starting replica count and timestamp
6. **Watch for warnings**: Check logs for "decommission stall" messages
7. **Verify network**: Ensure sustained network traffic during migration
8. **Plan for duration**: Expect 1-4 hours for typical nodes, 4-12+ hours for large nodes

## Troubleshooting Monitoring Issues

### Problem: Cannot Connect to Check Status

```bash
# Try different node in cluster
cockroach node status --decommission --host=node2:26257 --certs-dir=certs
```

**Note**: Any live node can report status for all nodes in cluster.

### Problem: Status Shows Same Replica Count

**If stuck for >30 minutes:**
1. Check logs for errors
2. Verify network connectivity
3. Confirm remaining nodes have capacity
4. Look for under-replicated ranges

### Problem: Replicas Increase Instead of Decrease

**Unlikely but possible if:**
- New data written to cluster during decommission
- Rebalancing adds replicas before removing them
- Should still trend toward 0 overall

## Example Monitoring Script

```bash
#!/bin/bash
# monitor_decommission.sh - Track decommission progress

NODE_ID=${1:-3}
INTERVAL=${2:-60}  # seconds
HOST=${3:-localhost:26257}
CERTS_DIR=${4:-certs}

echo "Monitoring decommission of node ${NODE_ID}"
echo "Timestamp,Replicas,Ranges,Leases,Membership" > decommission_log_${NODE_ID}.csv

while true; do
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

  # Query node status
  RESULT=$(cockroach sql --host=${HOST} --certs-dir=${CERTS_DIR} --format=csv -e "
    SELECT replicas, ranges, leases, membership
    FROM crdb_internal.kv_store_status
    JOIN crdb_internal.gossip_liveness USING (node_id)
    WHERE node_id = ${NODE_ID};
  " | tail -1)

  echo "${TIMESTAMP},${RESULT}" >> decommission_log_${NODE_ID}.csv
  echo "${TIMESTAMP},${RESULT}"

  # Check if complete
  REPLICAS=$(echo ${RESULT} | cut -d',' -f1)
  if [ "${REPLICAS}" = "0" ]; then
    echo "Decommission complete!"
    exit 0
  fi

  sleep ${INTERVAL}
done
```

**Usage:**
```bash
chmod +x monitor_decommission.sh
./monitor_decommission.sh 3 60 localhost:26257 certs
```

Creates CSV log file tracking progress over time.

## References

- [Node Shutdown](https://www.cockroachlabs.com/docs/stable/node-shutdown)
- [cockroach node](https://www.cockroachlabs.com/docs/stable/cockroach-node)
- [Monitoring and Alerting](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting)
- [Cluster Settings](https://www.cockroachlabs.com/docs/stable/cluster-settings)

## Summary

Effective decommission monitoring requires:
- ✅ Regular status checks using `cockroach node status --decommission`
- ✅ SQL queries to track replica count decreasing
- ✅ Network traffic monitoring for data migration
- ✅ Log analysis for errors and warnings
- ✅ Capacity monitoring on remaining nodes
- ✅ Completion verification before stopping node

**Key takeaway**: Never assume decommission completed without verifying `replicas` = 0 and `membership` = `decommissioned`.
