---
name: monitor-underreplicated-ranges
description: Can query system tables or DB Console Replication dashboard to detect underreplicated ranges (ranges with fewer replicas than configured). Critical metric for availability - alert when non-zero as it indicates risk of data loss or unavailability. Use when user says "check underreplicated ranges", "monitor replication", "check replica health".
metadata:
  domain: Monitoring and Alerting
  tags: cluster-operations, monitoring, resilience
  blooms_level: Apply
  version: 1.0.0
---

# Monitor Underreplicated Ranges

Detects ranges with fewer replicas than configured, which indicates risk of data loss or unavailability. This is a **critical metric** that should trigger immediate alerts.

## Why This Matters

**Underreplicated ranges** are dangerous because:
- ❌ Reduced fault tolerance (can't survive node failures)
- ❌ Risk of data loss if more nodes fail
- ❌ Potential unavailability if quorum lost
- ⚠️ Violation of replication factor guarantees

**Healthy cluster**: **0 underreplicated ranges**

## Instructions

### Method 1: SQL Query (Recommended)

```sql
SET allow_unsafe_internals = true;

SELECT
  range_id,
  database_name,
  table_name,
  array_length(replicas, 1) as current_replicas,
  num_replicas as target_replicas,
  replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < num_replicas
ORDER BY range_id;
```

**Expected**: Empty result (no rows) = healthy

**If rows returned**: CRITICAL - immediate investigation required

### Method 2: DB Console

1. Navigate to **Metrics** > **Replication**
2. Check **Under-Replicated Ranges** graph
3. Look for non-zero values

**Healthy**: Graph shows 0 at all times

### Method 3: Count Only

```sql
SET allow_unsafe_internals = true;

SELECT count(*) as underreplicated_count
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < num_replicas;
```

Alert if `underreplicated_count > 0`

## Example Output

### Healthy Cluster (No Issues)

```sql
SELECT count(*) FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < num_replicas;

-- Result: 0 ✅
```

### Unhealthy Cluster (Critical Issue)

```
range_id | database_name | table_name | current_replicas | target_replicas | replicas
---------+---------------+------------+------------------+-----------------+----------
42       | test_db       | users      | 2                | 3               | {1,2}
43       | test_db       | orders     | 1                | 3               | {1}
```

❌ **CRITICAL**: Ranges have only 2/3 and 1/3 replicas!

## Understanding the Output

**Columns:**
- **range_id**: Unique identifier for the range
- **database_name**: Which database owns the range
- **table_name**: Which table owns the range
- **current_replicas**: How many replicas exist NOW
- **target_replicas**: How many replicas SHOULD exist (from zone config)
- **replicas**: Array of node IDs holding replicas

**Severity levels:**
```
Target: 3, Current: 3  →  ✅ Healthy
Target: 3, Current: 2  →  ⚠️  Warning (can't survive 1 more failure)
Target: 3, Current: 1  →  ❌ Critical (at risk of data loss)
Target: 3, Current: 0  →  💀 Emergency (range unavailable)
```

## Common Causes

### 1. Node Failure

**Symptom:**
```
-- Recent underreplication after node went down
```

**Diagnosis:**
```bash
cockroach node status --certs-dir=certs --host=localhost:26258
# Check for dead nodes (is_live = false)
```

**Resolution:**
- If node temporarily down: Restart it
- If node permanently failed: Wait 5 minutes for automatic rebalancing
- If urgent: Force rebalancing (advanced operation)

### 2. Insufficient Nodes

**Symptom:**
```
Target: 5 replicas, only 3 nodes in cluster
```

**Diagnosis:**
```sql
-- Check replication factor vs node count
SHOW ZONE CONFIGURATION FOR DATABASE mydb;
-- Shows num_replicas

SELECT count(*) FROM crdb_internal.gossip_liveness;
-- Shows total nodes
```

**Resolution:**
- Add more nodes to cluster, OR
- Reduce replication factor:
  ```sql
  ALTER DATABASE mydb CONFIGURE ZONE USING num_replicas = 3;
  ```

### 3. Disk Space Full

**Symptom:**
Nodes can't accept new replicas due to disk full

**Diagnosis:**
```sql
SET allow_unsafe_internals = true;
SELECT
  node_id,
  (metrics->>'capacity.used')::BIGINT / (1024*1024*1024) as used_gb,
  (metrics->>'capacity.available')::BIGINT / (1024*1024*1024) as available_gb
FROM crdb_internal.kv_store_status;
```

**Resolution:**
- Free up disk space
- Add more nodes with storage
- Increase disk capacity

### 4. Replication Queue Stalled

**Symptom:**
Ranges remain underreplicated for > 10 minutes

**Diagnosis:**
Check logs for replication queue errors

**Resolution:**
```bash
# Check cluster health
cockroach node status --certs-dir=certs --host=localhost:26258

# Restart nodes if necessary
```

## Monitoring and Alerting

### Critical Alert Threshold

```sql
-- Alert if ANY underreplicated ranges
SET allow_unsafe_internals = true;
SELECT count(*) as alert_count
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < num_replicas;

-- Alert if alert_count > 0
```

### Alert Configuration

**Prometheus Alert Example:**
```yaml
- alert: UnderreplicatedRanges
  expr: replicas_underreplicated > 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Cluster has underreplicated ranges"
    description: "{{ $value }} ranges are underreplicated"
```

### Check Frequency

- **Production**: Every 30-60 seconds
- **Non-production**: Every 5 minutes

**Why frequent**: Underreplication indicates immediate risk

## Detailed Investigation

When underreplication detected:

### Step 1: Identify Affected Data

```sql
SET allow_unsafe_internals = true;
SELECT
  database_name,
  table_name,
  count(*) as underreplicated_ranges,
  min(array_length(replicas, 1)) as min_replicas,
  max(num_replicas) as target_replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < num_replicas
GROUP BY database_name, table_name
ORDER BY underreplicated_ranges DESC;
```

### Step 2: Check Node Availability

```bash
cockroach node status --certs-dir=certs --host=localhost:26258
```

Look for:
- Dead nodes (is_live = false)
- Decommissioning nodes
- Low replica counts on specific nodes

### Step 3: Check Replication Queue

```sql
SET allow_unsafe_internals = true;
SELECT
  range_id,
  database_name,
  table_name,
  replicas,
  voting_replicas,
  non_voting_replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < num_replicas
LIMIT 10;
```

### Step 4: Monitor Automatic Recovery

After identifying cause:
```bash
# Watch replication recovery
watch -n 5 "cockroach sql --certs-dir=certs --host=localhost:26258 --execute='SET allow_unsafe_internals = true; SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < num_replicas;'"
```

Should see count decrease to 0 over time.

## Automatic Recovery Process

CockroachDB automatically repairs underreplication:

1. **Detection**: Cluster detects underreplicated range
2. **Queue**: Range added to replication queue
3. **Upreplicate**: New replica created on available node
4. **Sync**: New replica catches up with current data
5. **Complete**: Range back to target replica count

**Timeline:**
- Detection: Immediate
- Start upereplication: Within seconds
- Complete: Seconds to minutes (depends on range size)

**Default timeout**: 5 minutes before dead node triggers rebalancing

## Impact on Availability

### Fault Tolerance

| Replicas | Can Survive | Quorum |
|----------|-------------|---------|
| 3 → 3 | 1 node failure | 2 of 3 |
| 3 → 2 | 0 node failures ⚠️ | 2 of 2 |
| 3 → 1 | 0 node failures ❌ | 1 of 1 |

**Example:**
- Normal: 3 replicas → survives 1 failure
- Underreplicated (2): Cannot survive ANY failure
- **Risk**: One more failure = data loss or unavailability

## Best Practices

1. **Monitor continuously** - Check every 30-60 seconds
2. **Alert immediately** - Any underreplication is critical
3. **Investigate quickly** - Determine root cause
4. **Document incidents** - Track patterns
5. **Test recovery** - Simulate node failures in non-prod
6. **Maintain capacity** - Keep nodes available for replication

## Verification Checklist

Cluster is healthy when:
- ✅ Zero underreplicated ranges
- ✅ All nodes available and healthy
- ✅ Sufficient disk space on all nodes
- ✅ Replication queue processing normally
- ✅ All ranges meet target replica count

## Related Skills

- `monitor-unavailable-ranges` - Detect ranges with lost quorum
- `monitor-node-liveness-and-health` - Node availability
- `monitor-storage-capacity-and-growth` - Disk space
- `configure-zone-replication-factor` - Set replica count

## Documentation

- Replication: https://www.cockroachlabs.com/docs/stable/architecture/replication-layer.html
- Monitoring: https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html#replication-metrics
