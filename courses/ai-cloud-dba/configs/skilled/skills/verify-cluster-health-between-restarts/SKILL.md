---
name: verify-cluster-health-between-restarts
description: Verify cluster health between individual node restarts during rolling maintenance to ensure each node rejoins successfully before proceeding to the next. Use when performing rolling restarts, upgrades, or sequential node maintenance.
metadata:
  domain: Cluster Maintenance
  bloom_level: Evaluate
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - rolling-restart
    - cluster-health
    - maintenance
    - operations
    - safety
---

# Verify Cluster Health Between Restarts

## Overview

This skill teaches you how to verify cluster health between individual node restarts during rolling maintenance operations. Proper verification between restarts ensures each node successfully rejoins before proceeding to the next, preventing cascading failures and maintaining cluster availability.

## Use Cases

Use this skill when you need to:
- Perform rolling restarts safely
- Execute rolling upgrades node-by-node
- Apply configuration changes across cluster
- Restart nodes after certificate updates
- Verify stability during sequential maintenance
- Detect problems before they compound
- Maintain SLAs during maintenance windows
- Document maintenance progress

## Core Concepts

### Why Check Between Each Restart?

**Sequential safety**: If node 1 fails to rejoin, you know immediately and can fix it before touching node 2.

**Prevents compounding issues**: Don't create multiple simultaneous problems. Fix one node before proceeding.

**Maintains quorum**: In a 3-node cluster, never have 2+ nodes down simultaneously.

### Wait Time Guidelines

| Cluster Size | Recommended Wait | Why |
|--------------|------------------|-----|
| 3 nodes | 5-10 minutes | Allow full lease rebalancing |
| 5-10 nodes | 3-5 minutes | Faster rebalancing with more nodes |
| 10+ nodes | 2-3 minutes | Replicas distribute quickly |

**Minimum wait**: 60 seconds (allow gossip stabilization)
**Maximum wait**: 15 minutes (if still issues, investigate)

### Health Check Progression

After restarting each node:

1. **Immediate** (0-30s): Node process starts
2. **Early** (30-60s): Node joins gossip network
3. **Stable** (1-5m): Replicas rebalance, leases transfer
4. **Ready** (5-10m): Full participation, metrics normal

Don't proceed to next restart until "Ready" state.

## Instructions

### Basic Workflow

```bash
# For each node in cluster:
#   1. Restart node
#   2. Wait for rejoin
#   3. Verify health
#   4. Proceed to next node

for NODE_ID in 1 2 3; do
  echo "=== Restarting node $NODE_ID ==="
  
  # Restart node
  systemctl restart cockroachdb-$NODE_ID
  
  # Wait for node to start
  sleep 60
  
  # Verify node rejoined
  ./verify-node-health.sh $NODE_ID
  
  # Wait before next restart
  echo "Waiting 5 minutes before next restart..."
  sleep 300
done
```

### Step 1: Verify Node Rejoined Cluster

After restarting a node, confirm it rejoined:

```bash
NODE_ID=1
HOST="localhost:26257"

# Check node is live
cockroach node status $NODE_ID --insecure --host=$HOST

# Expected output includes:
# is_live: true
# is_available: true
# updated_at: recent timestamp (< 30s ago)
```

**Success criteria**:
- Node appears in output
- `is_live = true`
- `is_available = true`
- `updated_at` recent (within last 30 seconds)

### Step 2: Check for Under-Replicated Ranges

After each restart, verify no ranges lost replicas:

```sql
-- Should return 0
SELECT count(*) as under_replicated
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
```

**Why this matters**: If restarting node 1 causes under-replication, fix it before touching node 2.

**If non-zero**:
```bash
# Wait and recheck every 30s
for i in {1..10}; do
  UNDER_REP=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
    SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;" | tail -1)
  
  echo "Attempt $i: $UNDER_REP under-replicated ranges"
  
  if [ "$UNDER_REP" -eq 0 ]; then
    echo "✓ Replication complete"
    break
  fi
  
  sleep 30
done
```

### Step 3: Verify Lease Distribution

Check that leases are rebalancing properly:

```sql
-- Check lease counts per node
SELECT 
  node_id,
  count(*) as lease_count
FROM crdb_internal.ranges_no_leases
GROUP BY node_id
ORDER BY node_id;
```

**Expected**: Leases roughly evenly distributed

**Red flag**: Node just restarted has 0 leases after 5+ minutes

### Step 4: Monitor Query Latency

Ensure cluster is serving queries normally:

```bash
# Run test query and measure latency
time cockroach sql --insecure --host=$HOST -e "SELECT 1;"
```

**Expected**: < 100ms
**Yellow flag**: > 500ms (investigate load)
**Red flag**: Timeout or error

### Step 5: Check Node Metrics

Verify restarted node is participating normally:

```sql
-- Check range counts on restarted node
SELECT 
  node_id,
  ranges,
  replicas_leaders,
  replicas_leaseholders
FROM crdb_internal.kv_store_status
WHERE node_id = 1;  -- Replace with restarted node ID
```

**Expected**:
- `ranges` > 0 (node has ranges)
- `replicas_leaders` > 0 (node is leading some ranges)
- `replicas_leaseholders` > 0 (node has leases)

### Step 6: Verify Version (if upgrade)

If performing rolling upgrade, confirm node version:

```sql
-- Check specific node version
SELECT node_id, build_tag
FROM crdb_internal.gossip_liveness
WHERE node_id = 1;  -- Replace with restarted node ID
```

**Expected**: Shows new version after upgrade

## Complete Verification Script

```bash
#!/bin/bash
# verify-node-health.sh <node_id>

NODE_ID=$1
HOST="localhost:26257"
MAX_WAIT=600  # 10 minutes

if [ -z "$NODE_ID" ]; then
  echo "Usage: $0 <node_id>"
  exit 1
fi

echo "=== Verifying Node $NODE_ID Health ==="
echo "Timestamp: $(date)"
echo ""

# Test 1: Node is live
echo -n "Test 1: Node liveness... "
IS_LIVE=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
  SELECT is_live FROM crdb_internal.gossip_liveness WHERE node_id = $NODE_ID;" | tail -1)

if [ "$IS_LIVE" != "true" ]; then
  echo "FAIL: Node not live"
  exit 1
fi
echo "PASS"

# Test 2: Wait for replication
echo -n "Test 2: Checking replication... "
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  UNDER_REP=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
    SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;" | tail -1)
  
  if [ "$UNDER_REP" -eq 0 ]; then
    echo "PASS"
    break
  fi
  
  if [ $ELAPSED -eq 0 ]; then
    echo ""
    echo "  Waiting for replication ($UNDER_REP under-replicated ranges)..."
  fi
  
  sleep 30
  ELAPSED=$((ELAPSED + 30))
done

if [ "$UNDER_REP" -ne 0 ]; then
  echo "FAIL: Still have $UNDER_REP under-replicated ranges after ${MAX_WAIT}s"
  exit 1
fi

# Test 3: Node has ranges
echo -n "Test 3: Node participation... "
RANGE_COUNT=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
  SELECT ranges FROM crdb_internal.kv_store_status WHERE node_id = $NODE_ID;" | tail -1)

if [ "$RANGE_COUNT" -eq 0 ]; then
  echo "FAIL: Node has no ranges"
  exit 1
fi
echo "PASS (node has $RANGE_COUNT ranges)"

# Test 4: Test query latency
echo -n "Test 4: Query latency... "
START=$(date +%s%N)
cockroach sql --insecure --host=$HOST -e "SELECT 1;" > /dev/null 2>&1
END=$(date +%s%N)
LATENCY_MS=$(( (END - START) / 1000000 ))

if [ $LATENCY_MS -gt 1000 ]; then
  echo "WARN: High latency (${LATENCY_MS}ms)"
else
  echo "PASS (${LATENCY_MS}ms)"
fi

echo ""
echo "✓ Node $NODE_ID health verified"
echo "Safe to proceed to next node"
```

## Common Patterns

### Pattern 1: Rolling Restart with Health Checks

```bash
#!/bin/bash
# rolling-restart.sh

NODES=(1 2 3)
WAIT_BETWEEN=300  # 5 minutes

for NODE_ID in "${NODES[@]}"; do
  echo "=== Restarting node $NODE_ID ==="
  
  # Restart node
  systemctl restart cockroachdb-$NODE_ID
  echo "Node $NODE_ID restarted at $(date)"
  
  # Wait for node to start
  echo "Waiting 60s for node startup..."
  sleep 60
  
  # Verify health
  if ! ./verify-node-health.sh $NODE_ID; then
    echo "✗ Node $NODE_ID failed health check"
    echo "ABORTING rolling restart"
    exit 1
  fi
  
  # Wait before next restart
  if [ "$NODE_ID" != "${NODES[-1]}" ]; then
    echo "Waiting ${WAIT_BETWEEN}s before next restart..."
    sleep $WAIT_BETWEEN
  fi
done

echo ""
echo "✓ Rolling restart completed successfully"
```

### Pattern 2: Upgrade with Version Verification

```bash
#!/bin/bash
# rolling-upgrade.sh

NODES=(1 2 3)
NEW_VERSION="v26.1.0"

for NODE_ID in "${NODES[@]}"; do
  echo "=== Upgrading node $NODE_ID to $NEW_VERSION ==="
  
  # Replace binary
  cp /tmp/cockroach-$NEW_VERSION /usr/local/bin/cockroach
  
  # Restart node
  systemctl restart cockroachdb-$NODE_ID
  sleep 60
  
  # Verify health
  ./verify-node-health.sh $NODE_ID || exit 1
  
  # Verify version
  VERSION=$(cockroach sql --insecure --host=localhost:26257 --format=tsv -e "
    SELECT build_tag FROM crdb_internal.gossip_liveness WHERE node_id = $NODE_ID;" | tail -1)
  
  if [[ "$VERSION" != *"$NEW_VERSION"* ]]; then
    echo "✗ Version mismatch: expected $NEW_VERSION, got $VERSION"
    exit 1
  fi
  
  echo "✓ Node $NODE_ID upgraded to $VERSION"
  sleep 300
done

echo "✓ All nodes upgraded to $NEW_VERSION"
```

### Pattern 3: Monitor Rebalancing Progress

```bash
#!/bin/bash
# monitor-rebalancing.sh <node_id>

NODE_ID=$1
MAX_WAIT=600
INTERVAL=30

echo "Monitoring rebalancing after node $NODE_ID restart"

for ((ELAPSED=0; ELAPSED<MAX_WAIT; ELAPSED+=INTERVAL)); do
  # Get metrics
  UNDER_REP=$(cockroach sql --insecure --host=localhost:26257 --format=tsv -e "
    SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;" | tail -1)
  
  RANGE_COUNT=$(cockroach sql --insecure --host=localhost:26257 --format=tsv -e "
    SELECT ranges FROM crdb_internal.kv_store_status WHERE node_id = $NODE_ID;" | tail -1)
  
  LEASE_COUNT=$(cockroach sql --insecure --host=localhost:26257 --format=tsv -e "
    SELECT replicas_leaseholders FROM crdb_internal.kv_store_status WHERE node_id = $NODE_ID;" | tail -1)
  
  echo "[${ELAPSED}s] Under-rep: $UNDER_REP, Ranges: $RANGE_COUNT, Leases: $LEASE_COUNT"
  
  if [ "$UNDER_REP" -eq 0 ] && [ "$RANGE_COUNT" -gt 0 ] && [ "$LEASE_COUNT" -gt 0 ]; then
    echo "✓ Rebalancing complete"
    break
  fi
  
  sleep $INTERVAL
done
```

## Troubleshooting

### Node Not Rejoining

**Problem**: After restart, node doesn't appear as live

**Diagnosis**:
```bash
# Check if process started
ps aux | grep cockroach

# Check logs
tail -100 /var/log/cockroachdb/cockroach.log | grep -i "error\|fatal"

# Try direct connection
cockroach sql --insecure --host=localhost:26257 -e "SELECT 1;"
```

**Common causes**:
- Process failed to start (check logs)
- Port conflict (another process using 26257)
- Certificate issues (secure clusters)
- Insufficient resources (OOM kill)

**Fix**:
```bash
# Check system resources
free -h
df -h

# Restart with logging
systemctl restart cockroachdb
journalctl -u cockroachdb -f
```

### Replication Stuck

**Problem**: Under-replicated ranges persist after 10+ minutes

**Diagnosis**:
```sql
-- Identify stuck ranges
SELECT range_id, start_key, replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3
LIMIT 10;

-- Check rebalancing settings
SHOW CLUSTER SETTING kv.snapshot_recovery.max_rate;
```

**Causes**:
- Snapshot rate throttled
- Node under heavy load
- Disk I/O saturation
- Network issues between nodes

**Fix**:
```sql
-- Temporarily increase snapshot rate
SET CLUSTER SETTING kv.snapshot_recovery.max_rate = '128 MiB';

-- Monitor progress
-- Wait 5 minutes and recheck
```

### High Latency After Restart

**Problem**: Queries slow after node restart

**Diagnosis**:
```sql
-- Check for admission control queuing
SELECT count(*) FROM crdb_internal.admission_control_events
WHERE event_time > now() - interval '5 minutes';

-- Check CPU usage
SELECT * FROM crdb_internal.node_metrics
WHERE name = 'sys.cpu.combined.percent-normalized'
ORDER BY updated_at DESC LIMIT 5;
```

**Causes**:
- Lease rebalancing in progress
- Range rebalancing causing I/O
- Admission control throttling
- Compaction after restart

**Fix**: Wait longer (up to 15 minutes) for stabilization

## Best Practices

### 1. Always Wait Between Restarts

```bash
# Bad - restart all nodes quickly
for node in 1 2 3; do systemctl restart cockroachdb-$node; done

# Good - wait and verify between each
for node in 1 2 3; do
  systemctl restart cockroachdb-$node
  sleep 60
  ./verify-node-health.sh $node
  sleep 300  # 5 minute buffer
done
```

### 2. Start with Least Critical Node

```bash
# Restart order: followers first, then leaders
# Identify leader-heavy nodes
cockroach sql --insecure -e "
  SELECT node_id, replicas_leaders
  FROM crdb_internal.kv_store_status
  ORDER BY replicas_leaders ASC;"

# Restart nodes from least to most leaders
```

### 3. Monitor Throughout Process

```bash
# Run monitoring in separate terminal
watch -n 30 'cockroach sql --insecure -e "
  SELECT count(*) as under_rep FROM crdb_internal.ranges 
  WHERE array_length(replicas, 1) < 3;"'
```

### 4. Have Rollback Plan

```bash
# Before upgrading, know how to rollback
# Keep old binary accessible
cp /usr/local/bin/cockroach /usr/local/bin/cockroach.old

# Document rollback procedure
# If node fails to start with new version:
# 1. Stop process
# 2. Restore old binary
# 3. Restart
```

## Related Skills

- **verify-cluster-health-before-and-after-maintenance**: Complete health checks
- **perform-rolling-restarts**: Execute rolling restart procedures
- **verify-cluster-membership**: Check node membership
- **verify-cluster-replication-and-size**: Detailed replication checks

## Examples

### Example: 3-Node Rolling Restart

```bash
# Complete rolling restart with health checks
NODES=(1 2 3)

for NODE_ID in "${NODES[@]}"; do
  echo "=== Restarting node $NODE_ID ==="
  
  systemctl restart cockroachdb-$NODE_ID
  sleep 60
  
  # Verify rejoined
  cockroach node status $NODE_ID --insecure --host=localhost:26257
  
  # Check replication
  UNDER_REP=$(cockroach sql --insecure --format=tsv -e "
    SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;" | tail -1)
  
  echo "Under-replicated ranges: $UNDER_REP"
  
  # Wait 5 minutes
  sleep 300
done

echo "✓ Rolling restart complete"
```

## Testing

```bash
# Test verification script
./verify-node-health.sh 1
# Expected: All tests pass

# Test rolling restart
./rolling-restart.sh
# Expected: Completes without errors

# Test with simulated failure
# (stop one node, verify script detects it)
systemctl stop cockroachdb-1
./verify-node-health.sh 1
# Expected: FAIL detected
```

---

**Version**: 1.0.0
**Last Updated**: March 6, 2026
**Tested Against**: CockroachDB v26.1.0
