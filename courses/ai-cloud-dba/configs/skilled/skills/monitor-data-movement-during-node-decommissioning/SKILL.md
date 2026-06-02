---
name: monitor-data-movement-during-node-decommissioning
description: Monitor data movement and replica rebalancing during node decommissioning. Use when user asks "monitor decommission progress", "track replica movement", "check decommissioning status", or "decommission stuck".
metadata:
  domain: Cluster Maintenance
  bloom_level: Evaluate
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Monitor Data Movement During Node Decommissioning

## What This Skill Teaches

When decommissioning a node, CockroachDB must safely move all data (replicas and leaseholders) to other nodes. This skill covers monitoring that data movement process and troubleshooting stuck decommissions.

## Decommissioning Overview

### What Happens During Decommission

```
Node Active → Draining → Decommissioning → Decommissioned
```

**Timeline** (example 100GB node):
```
T+0s:     Start decommission
T+10s:    Draining complete
T+10s:    Replica transfer begins
T+60m:    All replicas moved → DECOMMISSIONED
```

**Speed depends on**: Data volume, network bandwidth, cluster load, disk I/O capacity.

---

## Monitoring Decommission Progress

### Primary Monitoring Command

```bash
cockroach node status --decommission \
  --host=localhost:26257 \
  --certs-dir=/tmp/certs
```

**Output interpretation**:
```
  id |     address     |  membership      | is_live | replicas | is_draining
-----+-----------------+------------------+---------+----------+-------------
   1 | localhost:26257 | active           | true    |      42  | false
   2 | localhost:26258 | active           | true    |      45  | false
   3 | localhost:26259 | decommissioning  | true    |      28  | true
```

**Key fields**:
- `membership`: `active` → `decommissioning` → `decommissioned`
- `replicas`: Should decrease to 0

---

### Detailed Replica Tracking

**Count replicas on decommissioning node**:
```sql
SET allow_unsafe_internals = true;

-- Replicas remaining on node 3
SELECT count(*) AS remaining_replicas
FROM crdb_internal.ranges
WHERE array_position(replicas, 3) IS NOT NULL;

-- Expected: Decreases over time, reaches 0 when done
```

**Track by database/table**:
```sql
SET allow_unsafe_internals = true;

SELECT database_name, table_name,
       count(*) AS replicas_on_node_3
FROM crdb_internal.ranges
WHERE array_position(replicas, 3) IS NOT NULL
GROUP BY database_name, table_name
ORDER BY replicas_on_node_3 DESC
LIMIT 10;
```

---

### Leaseholder Tracking

**Leaseholders transfer before replicas**:

```sql
SET allow_unsafe_internals = true;

-- Leaseholders remaining on node 3
SELECT count(*) AS remaining_leases
FROM crdb_internal.ranges
WHERE lease_holder = 3;

-- Should drop to 0 quickly (within seconds)
```

**Why leaseholders transfer first**: Fast metadata update vs slow data movement.

---

## Complete Monitoring Workflow

### Before Starting Decommission

```sql
SET allow_unsafe_internals = true;

-- Baseline: How much data to move?
SELECT count(*) AS total_replicas
FROM crdb_internal.ranges
WHERE array_position(replicas, 3) IS NOT NULL;
```

### Start Decommission

```bash
cockroach node decommission 3 \
  --host=localhost:26257 \
  --certs-dir=/tmp/certs
```

### Monitor Every 60 Seconds

```bash
watch -n 60 'cockroach node status --decommission \
  --host=localhost:26257 \
  --certs-dir=/tmp/certs'
```

### Check Replica Count

```sql
SET allow_unsafe_internals = true;

SELECT count(*) AS remaining,
       round(100.0 * count(*) /
         (SELECT count(*) FROM crdb_internal.ranges
          WHERE array_position(replicas, 3) IS NOT NULL),
         1) AS percent_remaining
FROM crdb_internal.ranges
WHERE array_position(replicas, 3) IS NOT NULL;
```

---

## Understanding Decommission Phases

### Phase 1: Draining (seconds to minutes)

**What happens**:
- Connections close gracefully
- No new SQL connections accepted
- Leaseholders transferred away

**Duration**: Typically 30-120 seconds

---

### Phase 2: Decommissioning (minutes to hours)

**What happens**:
- Replicas transferred to other nodes
- Uses Raft snapshots
- Network and disk I/O intensive

**Duration**:
- 10GB: ~5-10 minutes
- 100GB: ~30-60 minutes
- 1TB: ~5-10 hours

---

### Phase 3: Decommissioned (instant)

**What happens**:
- All replicas successfully moved
- Node marked `membership: decommissioned`
- Safe to shut down

**Verification**:
```bash
cockroach node status --decommission
# Node shows: membership: decommissioned, replicas: 0
```

---

## Estimating Time to Completion

### Calculate Transfer Rate

```sql
SET allow_unsafe_internals = true;

-- Take snapshot at start
SELECT count(*) AS replicas_at_start, now() AS start_time
FROM crdb_internal.ranges
WHERE array_position(replicas, 3) IS NOT NULL;
-- Result: 1,000 replicas at 10:00:00

-- Wait 5 minutes, query again
-- Result: 800 replicas at 10:05:00

-- Calculate: (1000 - 800) = 200 in 5 min = 40 replicas/min
-- Estimate: 800 remaining / 40 per min = 20 minutes
```

---

## Troubleshooting

### Issue 1: Decommission Not Starting

**Symptom**: Replica count not decreasing

**Check decommission status**:
```bash
cockroach node status --decommission
# Verify membership shows "decommissioning" (not "active")
```

**If still "active"**:
```bash
# Retry decommission command
cockroach node decommission 3 --host=localhost:26257 --certs-dir=/tmp/certs
```

---

### Issue 2: Stuck at Non-Zero Replicas

**Possible causes**:
1. Insufficient nodes for replication factor
2. Zone config constraints cannot be satisfied
3. Cluster overloaded

**Check replication factor**:
```sql
-- Need enough nodes for replication
SHOW ZONE CONFIGURATION FOR RANGE default;
-- num_replicas = 3

-- Count active nodes
SELECT count(*) FROM crdb_internal.gossip_liveness
WHERE membership = 'active';

-- If 3x replication and only 3 nodes: Cannot decommission!
```

**Check zone constraints**:
```sql
SHOW ZONE CONFIGURATION FOR DATABASE mydb;
-- Constraints might prevent replica placement
```

**Solution**:
```bash
# Add new node before decommissioning
cockroach start --join=existing-nodes ...

# Or temporarily reduce replication (RISKY)
ALTER RANGE default CONFIGURE ZONE USING num_replicas = 2;
```

---

### Issue 3: Very Slow Transfer Rate

**Check cluster load**:
```sql
-- CPU usage
SELECT node_id, sum(cpu_percentage) AS total_cpu
FROM crdb_internal.statement_statistics
GROUP BY node_id;

-- If >90% CPU: Cluster too busy
```

**Check disk I/O**:
```bash
iostat -x 5
# Look for %util >80%
```

**Solutions**:
- Reduce cluster load
- Schedule during low-traffic period
- Add more nodes to distribute load

---

### Issue 4: Ranges Not Balancing

**Check for stuck ranges**:
```sql
SET allow_unsafe_internals = true;

SELECT range_id, database_name, table_name,
       replicas, lease_holder
FROM crdb_internal.ranges
WHERE array_position(replicas, 3) IS NOT NULL
LIMIT 20;
```

**Force faster rebalance**:
```sql
-- Increase snapshot rate temporarily
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '128 MiB';

-- Restore after
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '32 MiB';
```

---

## Canceling a Decommission

### When to Cancel

- Taking too long
- Cluster becoming unstable
- Need the node back urgently

### How to Cancel

```bash
cockroach node recommission 3 \
  --host=localhost:26257 \
  --certs-dir=/tmp/certs
```

**Effect**: Node returns to `active`, stops replica transfers.

---

## Best Practices

1. **Check replication math first** - Ensure enough nodes
2. **Decommission during low traffic** - Faster and less disruptive
3. **Monitor continuously** - Check every 5-10 minutes
4. **One node at a time** - Never decommission multiple simultaneously
5. **Estimate completion time** - Calculate transfer rate early
6. **Don't shut down early** - Wait for `decommissioned` status

---

## Monitoring Script

```bash
#!/bin/bash
# monitor-decommission.sh <node_id>

NODE_ID=$1
CERTS_DIR="/tmp/certs"
HOST="localhost:26257"

while true; do
  echo "=== $(date) ==="

  cockroach node status --decommission --host=$HOST --certs-dir=$CERTS_DIR | grep "^  $NODE_ID"

  REPLICAS=$(cockroach sql --host=$HOST --certs-dir=$CERTS_DIR --execute="
    SET allow_unsafe_internals = true;
    SELECT count(*) FROM crdb_internal.ranges
    WHERE array_position(replicas, $NODE_ID) IS NOT NULL;" --format=csv | tail -n 1)

  echo "Remaining replicas: $REPLICAS"

  if [ "$REPLICAS" -eq 0 ]; then
    echo "✅ Decommission complete!"
    break
  fi

  sleep 60
done
```

---

## Related Skills

- `decommission-nodes-gracefully` - How to start decommission
- `recommission-nodes-after-maintenance` - How to cancel
- `verify-cluster-replication-and-size` - Replication health
- `monitor-cluster-health-during-the-suspect-and-dead-node-states` - Node liveness
