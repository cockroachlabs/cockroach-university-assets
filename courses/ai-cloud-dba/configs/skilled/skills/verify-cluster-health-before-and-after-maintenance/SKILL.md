---
name: verify-cluster-health-before-and-after-maintenance
description: Verify cluster health before and after maintenance operations to ensure cluster is ready for changes and to confirm successful completion. Use when performing any cluster maintenance, upgrades, node changes, or configuration updates.
metadata:
  domain: Cluster Maintenance
  bloom_level: Evaluate
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - cluster-health
    - maintenance
    - verification
    - operations
    - best-practices
---

# Verify Cluster Health Before and After Maintenance

## Overview

This skill teaches you how to perform comprehensive cluster health verification before and after maintenance operations. Proper health checks ensure your cluster is in a stable state before making changes and confirm that changes completed successfully without introducing problems.

## Use Cases

Use this skill when you need to:
- Verify cluster readiness before rolling upgrades
- Confirm cluster stability before node decommissioning
- Validate health after node replacement
- Establish baseline metrics before configuration changes
- Detect issues introduced by maintenance operations
- Document pre/post-maintenance state
- Determine go/no-go for maintenance windows
- Provide evidence of successful maintenance completion

## Core Concepts

### Why Health Checks Matter

**Before maintenance**:
- Identifies existing issues that could complicate maintenance
- Establishes baseline for comparison
- Prevents cascading failures
- Provides go/no-go decision criteria

**After maintenance**:
- Confirms changes completed successfully
- Detects new issues introduced by changes
- Validates cluster returned to healthy state
- Documents maintenance success

### Health Check Categories

| Category | What It Checks | Impact |
|----------|----------------|--------|
| **Node Liveness** | All nodes live and responding | Availability |
| **Replication** | No under-replicated ranges | Data durability |
| **Cluster Capacity** | Sufficient disk/CPU/memory | Performance |
| **Version Consistency** | All nodes same version | Upgrade progress |
| **Network Health** | Node-to-node connectivity | Distributed operations |
| **Job Status** | No failed/stuck jobs | Background operations |

### Go/No-Go Criteria

**RED FLAGS (do not proceed)**:
- Under-replicated ranges present
- Any node dead or unavailable
- Critical jobs failed
- Disk space < 10% remaining on any node
- Clock offset > 500ms

**YELLOW FLAGS (investigate before proceeding)**:
- High CPU/memory usage (>80%)
- Recent schema changes in progress
- Recent node state transitions
- Admission control queuing

**GREEN (proceed)**:
- All nodes live and available
- All ranges fully replicated
- No critical alerts
- Sufficient resources

## Instructions

### Pre-Maintenance Health Check

Execute this complete checklist before any maintenance:

#### Step 1: Verify Node Liveness

```bash
# Check all nodes are live
cockroach node status --insecure --host=localhost:26257

# Expected: All nodes show is_live=true, is_available=true
```

**Look for**:
- All expected nodes present
- `is_live = true` for all nodes
- `is_available = true` for all nodes
- Recent `updated_at` timestamps (< 30s old)

**Fail criteria**: Any node dead or unavailable

#### Step 2: Check Replication Status

```sql
-- Count under-replicated ranges
SELECT count(*) as under_replicated_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;

-- Expected: 0
```

**Critical**: Under-replicated ranges mean data is at risk. Do not proceed with maintenance if any exist.

**If non-zero**:
```sql
-- Identify which ranges are under-replicated
SELECT range_id, start_key, end_key, replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3
LIMIT 10;
```

Wait for replication to catch up before proceeding.

#### Step 3: Verify Cluster Capacity

```bash
# Check disk space on all nodes
cockroach node status --insecure --host=localhost:26257 --format=table | grep -E "id|node"
```

```sql
-- Check detailed storage
SELECT 
  store_id,
  node_id,
  round(capacity / 1024^3, 2) as capacity_gb,
  round(available / 1024^3, 2) as available_gb,
  round((available::float / capacity::float) * 100, 2) as pct_available
FROM crdb_internal.kv_store_status
ORDER BY pct_available ASC;
```

**Fail criteria**: Any node < 10% available disk

#### Step 4: Check Active Jobs

```sql
-- Look for failed or paused jobs
SELECT job_id, job_type, status, error
FROM crdb_internal.jobs
WHERE status IN ('failed', 'paused', 'cancel-requested')
ORDER BY created DESC
LIMIT 10;
```

**Investigate**: Any failed jobs, especially backups or schema changes

#### Step 5: Verify Network Health

```bash
# Check for high network latency
cockroach sql --insecure --host=localhost:26257 -e "
SELECT MAX(p99) as max_p99_latency_ms
FROM crdb_internal.node_metrics
WHERE name = 'network.latency';"
```

**Yellow flag**: Latency > 100ms (investigate)
**Red flag**: Latency > 500ms (likely network issue)

#### Step 6: Check Version Consistency

```bash
# Ensure all nodes on same version
cockroach sql --insecure --host=localhost:26257 -e "
SELECT DISTINCT build_tag FROM crdb_internal.gossip_liveness;"
```

**Expected**: Single row (all nodes same version)
**Red flag**: Multiple versions (mixed-version state)

### Document Baseline State

Capture baseline before maintenance:

```bash
#!/bin/bash
# pre-maintenance-snapshot.sh

echo "=== Pre-Maintenance Health Check ==="
echo "Date: $(date)"
echo ""

echo "Node Status:"
cockroach node status --insecure --host=localhost:26257

echo ""
echo "Under-Replicated Ranges:"
cockroach sql --insecure --host=localhost:26257 -e "
SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;"

echo ""
echo "Cluster Size:"
cockroach sql --insecure --host=localhost:26257 -e "
SELECT 
  count(*) as num_nodes,
  sum(range_count) as total_ranges,
  sum(replicas_leaders) as total_leaders
FROM crdb_internal.kv_store_status;"

echo ""
echo "Storage Capacity:"
cockroach sql --insecure --host=localhost:26257 -e "
SELECT 
  node_id,
  round((available::float / capacity::float) * 100, 2) as pct_available
FROM crdb_internal.kv_store_status
ORDER BY node_id;"
```

Save output for comparison after maintenance.

### Post-Maintenance Health Check

Execute after maintenance to confirm success:

#### Step 1: Wait for Stability

After restarting nodes or configuration changes:

```bash
# Wait 60s for gossip to stabilize
sleep 60
```

Don't check health immediately - allow cluster to stabilize.

#### Step 2: Verify All Nodes Rejoined

```bash
# Check expected node count
cockroach node status --insecure --host=localhost:26257 | wc -l

# Compare to pre-maintenance count
```

**Expected**: Same number of live nodes (unless decommissioning)

#### Step 3: Check for Under-Replicated Ranges

```sql
-- Should return 0
SELECT count(*) as under_replicated_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
```

**If non-zero**: Wait and recheck. Replication may be catching up.

```bash
# Monitor replication progress
for i in {1..10}; do
  echo "Check $i:"
  cockroach sql --insecure --host=localhost:26257 -e "
    SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;"
  sleep 30
done
```

#### Step 4: Verify Version (if upgrade performed)

```bash
# Check all nodes upgraded
cockroach sql --insecure --host=localhost:26257 -e "
SELECT node_id, build_tag
FROM crdb_internal.gossip_liveness
ORDER BY node_id;"
```

**Expected after upgrade**: All nodes show new version

#### Step 5: Check for Errors in Logs

```bash
# Check for errors in last 5 minutes
tail -100 node1/logs/cockroach.log | grep -i "error\|fatal\|panic"
```

**Investigation needed**: Any ERROR or FATAL messages

#### Step 6: Verify Health Endpoints

```bash
# Check health endpoint
curl http://localhost:8080/health?ready=1
# Expected: HTTP 200 OK

# Check DB Console accessible
curl -I http://localhost:8080/
# Expected: HTTP 200 OK
```

### Compare Pre vs Post State

```bash
#!/bin/bash
# compare-state.sh

echo "=== State Comparison ==="
echo ""

echo "BEFORE:"
cat pre-maintenance-snapshot.txt | grep "num_nodes\|total_ranges"

echo ""
echo "AFTER:"
cockroach sql --insecure --host=localhost:26257 -e "
SELECT 
  count(*) as num_nodes,
  sum(range_count) as total_ranges
FROM crdb_internal.kv_store_status;"

echo ""
echo "Storage Change:"
diff <(cat pre-maintenance-snapshot.txt | grep "pct_available") \
     <(cockroach sql --insecure --host=localhost:26257 -e "
       SELECT node_id, round((available::float / capacity::float) * 100, 2) as pct_available
       FROM crdb_internal.kv_store_status ORDER BY node_id;")
```

## Common Patterns

### Pattern 1: Pre-Flight Check Script

```bash
#!/bin/bash
# pre-flight-check.sh

set -e  # Exit on any error

HOST="localhost:26257"

echo "=== Pre-Flight Cluster Health Check ==="

# Test 1: All nodes live
echo -n "Checking node liveness... "
DEAD_NODES=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
  SELECT count(*) FROM crdb_internal.gossip_liveness WHERE is_live = false;" | tail -1)

if [ "$DEAD_NODES" -ne 0 ]; then
  echo "FAIL: $DEAD_NODES dead nodes"
  exit 1
fi
echo "OK"

# Test 2: No under-replicated ranges
echo -n "Checking replication... "
UNDER_REP=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
  SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;" | tail -1)

if [ "$UNDER_REP" -ne 0 ]; then
  echo "FAIL: $UNDER_REP under-replicated ranges"
  exit 1
fi
echo "OK"

# Test 3: Sufficient disk space (>10% available)
echo -n "Checking disk space... "
LOW_DISK=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
  SELECT count(*) FROM crdb_internal.kv_store_status 
  WHERE (available::float / capacity::float) < 0.10;" | tail -1)

if [ "$LOW_DISK" -ne 0 ]; then
  echo "FAIL: $LOW_DISK nodes with < 10% disk available"
  exit 1
fi
echo "OK"

# Test 4: No failed jobs
echo -n "Checking job status... "
FAILED_JOBS=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
  SELECT count(*) FROM crdb_internal.jobs WHERE status = 'failed' AND created > now() - interval '1 hour';" | tail -1)

if [ "$FAILED_JOBS" -ne 0 ]; then
  echo "WARN: $FAILED_JOBS failed jobs in last hour"
fi
echo "OK"

echo ""
echo "✓ All pre-flight checks passed"
echo "Cluster is ready for maintenance"
```

### Pattern 2: Post-Maintenance Validation

```bash
#!/bin/bash
# post-maintenance-validation.sh

HOST="localhost:26257"
EXPECTED_NODES=3  # Update for your cluster

echo "=== Post-Maintenance Validation ==="
echo "Waiting for cluster to stabilize..."
sleep 60

# Verify node count
ACTUAL_NODES=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
  SELECT count(*) FROM crdb_internal.gossip_liveness WHERE is_live = true;" | tail -1)

if [ "$ACTUAL_NODES" -ne "$EXPECTED_NODES" ]; then
  echo "✗ Expected $EXPECTED_NODES live nodes, found $ACTUAL_NODES"
  exit 1
fi
echo "✓ All $EXPECTED_NODES nodes live"

# Wait for replication
echo "Waiting for replication to complete..."
for i in {1..20}; do
  UNDER_REP=$(cockroach sql --insecure --host=$HOST --format=tsv -e "
    SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;" | tail -1)
  
  if [ "$UNDER_REP" -eq 0 ]; then
    echo "✓ All ranges fully replicated"
    break
  fi
  
  echo "  Attempt $i: $UNDER_REP under-replicated ranges remaining"
  sleep 30
done

if [ "$UNDER_REP" -ne 0 ]; then
  echo "✗ Still have $UNDER_REP under-replicated ranges after waiting"
  exit 1
fi

echo ""
echo "✓ Post-maintenance validation passed"
```

## Troubleshooting

### Under-Replicated Ranges Won't Clear

**Problem**: After waiting, still have under-replicated ranges

**Diagnosis**:
```sql
-- Check if rebalancing is happening
SELECT count(*) as moving_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) != 3;

-- Check replica queue status
SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;
SHOW CLUSTER SETTING kv.snapshot_recovery.max_rate;
```

**Causes**:
- Rebalancing rate throttled (default: 32 MiB/s)
- Node under heavy load
- Network issues
- Not enough time elapsed

**Fix**:
```sql
-- Temporarily increase snapshot rate
SET CLUSTER SETTING kv.snapshot_recovery.max_rate = '128 MiB';

-- Wait and monitor
```

### Node Not Rejoining After Restart

**Problem**: Node shows as dead after restart

**Diagnosis**:
```bash
# Check if process is running
ps aux | grep cockroach

# Check logs for errors
tail -100 node1/logs/cockroach.log | grep -i "error\|fatal"

# Verify connectivity
nc -zv localhost 26257
```

**Common causes**:
- Process failed to start (check logs)
- Wrong join list configuration
- Certificate issues (secure clusters)
- Port already in use

### Health Check Fails After Upgrade

**Problem**: Pre-flight passes, but post-upgrade validation fails

**Diagnosis**:
```bash
# Check if upgrade actually completed
cockroach sql --insecure --host=localhost:26257 -e "
  SELECT node_id, build_tag FROM crdb_internal.gossip_liveness;"

# Look for nodes still on old version
```

**Causes**:
- Node failed to restart with new binary
- Binary not replaced correctly
- Node stuck in restart loop

**Fix**:
- Check individual node logs
- Verify binary version: `cockroach version`
- Restart failed nodes

## Best Practices

### 1. Always Run Pre-Flight Checks

Never skip pre-flight checks, even for "quick" changes:

```bash
# Bad
cockroach node drain 1 --insecure --host=localhost:26257

# Good
./pre-flight-check.sh && cockroach node drain 1 --insecure --host=localhost:26257
```

### 2. Document Baseline State

Save snapshots before maintenance:

```bash
# Capture state
./pre-maintenance-snapshot.sh > pre-maintenance-$(date +%Y%m%d-%H%M%S).txt

# After maintenance, compare
diff pre-maintenance-20260306-100000.txt post-maintenance-20260306-103000.txt
```

### 3. Wait for Stabilization

Don't check health immediately after changes:

```bash
# After node restart
systemctl restart cockroachdb

# Wait for node to rejoin and stabilize
sleep 60

# Then check health
./post-maintenance-validation.sh
```

### 4. Use Timeouts

Set reasonable timeouts for health checks:

```bash
# Wait up to 10 minutes for replication
TIMEOUT=600
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
  UNDER_REP=$(cockroach sql --insecure --host=localhost:26257 --format=tsv -e "
    SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;" | tail -1)
  
  if [ "$UNDER_REP" -eq 0 ]; then
    echo "✓ Replication complete"
    break
  fi
  
  sleep 30
  ELAPSED=$((ELAPSED + 30))
done

if [ "$UNDER_REP" -ne 0 ]; then
  echo "✗ Timeout: replication incomplete"
  exit 1
fi
```

## Related Skills

- **verify-cluster-membership**: Check all expected nodes joined
- **verify-cluster-health-between-restarts**: Health checks during rolling operations
- **verify-cluster-replication-and-size**: Detailed replication verification
- **perform-pre-upgrade-health-assessments**: Specific upgrade pre-checks

## Examples

### Example 1: Pre-Upgrade Health Check

**Scenario**: Verify cluster ready for upgrade from v25.2 to v26.1

```bash
#!/bin/bash
HOST="localhost:26257"

echo "Pre-Upgrade Health Check"

# 1. All nodes live
cockroach node status --insecure --host=$HOST

# 2. No under-replicated ranges
cockroach sql --insecure --host=$HOST -e "
  SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;"

# 3. All nodes same version
cockroach sql --insecure --host=$HOST -e "
  SELECT DISTINCT build_tag FROM crdb_internal.gossip_liveness;"

# 4. No active schema changes
cockroach sql --insecure --host=$HOST -e "
  SELECT count(*) FROM crdb_internal.jobs 
  WHERE job_type = 'SCHEMA CHANGE' AND status = 'running';"

# If all pass, proceed with upgrade
echo "✓ Cluster ready for upgrade"
```

### Example 2: Post-Decommission Validation

**Scenario**: Verify cluster healthy after decommissioning node 3

```bash
# After: cockroach node decommission 3

echo "Post-Decommission Validation"

# Wait for stabilization
sleep 120

# Verify node 3 decommissioned
cockroach node status 3 --insecure --host=localhost:26257
# Should show: is_decommissioning=true, replicas=0

# Verify replication on remaining nodes
cockroach sql --insecure --host=localhost:26257 -e "
  SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;"
# Should be 0

# Verify cluster still serving queries
cockroach sql --insecure --host=localhost:26257 -e "SELECT 1;"
# Should succeed

echo "✓ Decommission successful"
```

## Testing

```bash
# Test pre-flight script
./pre-flight-check.sh
# Expected: All checks pass

# Test post-maintenance script
./post-maintenance-validation.sh
# Expected: All validations pass

# Test comparison script
./compare-state.sh
# Expected: Shows differences between snapshots
```

---

**Version**: 1.0.0
**Last Updated**: March 6, 2026
**Tested Against**: CockroachDB v26.1.0
