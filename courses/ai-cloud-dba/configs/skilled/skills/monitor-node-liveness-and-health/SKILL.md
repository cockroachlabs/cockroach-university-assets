---
name: monitor-node-liveness-and-health
description: Can use cockroach node status command or DB Console Overview page to monitor node availability, heartbeat status, and cluster membership. Check is_available and is_live columns to detect failed or partitioned nodes. Use when user says "check node status", "monitor nodes", "node health".
metadata:
  domain: Monitoring and Alerting
  tags: cluster-operations, resilience
  blooms_level: Apply
  version: 1.0.0
---

# Monitor Node Liveness and Health

Monitors node availability, heartbeat status, and cluster membership to detect failed or partitioned nodes. Essential for maintaining cluster health and availability.

## Why Monitor Node Liveness

Node liveness affects:
- **Cluster availability**: Dead nodes can't serve requests
- **Data durability**: Replicas on dead nodes are unavailable
- **Write latency**: Quorum requires live nodes
- **Automatic recovery**: Cluster rebalances after node failures

**Key Questions:**
- Are all nodes alive and available?
- Can nodes communicate with each other?
- Are any nodes suspected or dead?
- Is the cluster at risk of quorum loss?

## Instructions

### Method 1: CLI Command (Recommended)

**Check all nodes:**
```bash
cockroach node status --certs-dir=certs --host=localhost:26258
```

**Output columns:**
- `id`: Node ID
- `address`: RPC address
- `sql_address`: SQL address
- `build`: CockroachDB version
- `started_at`: When node started
- `updated_at`: Last heartbeat timestamp
- `locality`: Node locality (region, zone)
- `is_available`: Can serve traffic (true/false)
- `is_live`: Heartbeat detected (true/false)

**Healthy output:**
```
id  address           sql_address       build    is_available  is_live
1   localhost:26257   localhost:26258   v26.1.0  true          true
2   localhost:26259   localhost:26260   v26.1.0  true          true
3   localhost:26261   localhost:26262   v26.1.0  true          true
```

### Method 2: DB Console (Visual)

**Step 1:** Access DB Console
```
https://<node-address>:8080
```

**Step 2:** Navigate to Overview Page
- Click "Overview" in left sidebar
- View "Cluster Overview" section

**Step 3:** Check Node Status
- Green = Live and available
- Yellow = Suspected (not responding)
- Red = Dead (confirmed offline)

### Method 3: SQL Query

**Query node information:**
```sql
SELECT
  node_id,
  address,
  locality,
  is_live,
  is_available,
  replicas
FROM crdb_internal.gossip_nodes
ORDER BY node_id;
```

**Check for dead nodes:**
```sql
SELECT
  node_id,
  address,
  is_live,
  is_available
FROM crdb_internal.gossip_nodes
WHERE NOT is_live OR NOT is_available;
```

## Understanding Node States

### Node Lifecycle States

| State | is_live | is_available | Description | Action |
|-------|---------|--------------|-------------|--------|
| **LIVE** | true | true | Healthy and serving traffic | ✅ None |
| **SUSPECT** | true | false | Not responding to heartbeats | ⚠️ Investigate |
| **DEAD** | false | false | Confirmed offline (> 5min) | ❌ Urgent action |

### State Transitions

```
LIVE (healthy)
  ↓ (30 seconds no heartbeat)
SUSPECT (timeout: server.time_after_store_suspect)
  ↓ (5 minutes total no heartbeat)
DEAD (timeout: server.time_until_store_dead)
  → Automatic rebalancing begins
```

**Time settings:**
```sql
-- Check current timeouts
SHOW CLUSTER SETTING server.time_after_store_suspect;  -- Default: 30s
SHOW CLUSTER SETTING server.time_until_store_dead;     -- Default: 5m0s
```

## Example: Complete Node Health Check

```bash
#!/bin/bash
# Complete node health check script

echo "=== Node Status ==="
cockroach node status --certs-dir=certs --host=localhost:26258

echo ""
echo "=== Node Liveness ==="
cockroach sql --certs-dir=certs --host=localhost:26258 --execute="
SELECT
  node_id,
  CASE
    WHEN is_live AND is_available THEN 'LIVE'
    WHEN is_live AND NOT is_available THEN 'SUSPECT'
    ELSE 'DEAD'
  END as state,
  locality
FROM crdb_internal.gossip_nodes
ORDER BY node_id;
"

echo ""
echo "=== Cluster Health Summary ==="
cockroach sql --certs-dir=certs --host=localhost:26258 --execute="
SELECT
  count(*) as total_nodes,
  sum(CASE WHEN is_live AND is_available THEN 1 ELSE 0 END) as live_nodes,
  sum(CASE WHEN is_live AND NOT is_available THEN 1 ELSE 0 END) as suspect_nodes,
  sum(CASE WHEN NOT is_live THEN 1 ELSE 0 END) as dead_nodes
FROM crdb_internal.gossip_nodes;
"
```

## Monitoring Node Heartbeats

**Check heartbeat activity:**
```sql
SELECT
  node_id,
  updated_at,
  now() - updated_at as time_since_last_heartbeat
FROM crdb_internal.gossip_liveness
ORDER BY node_id;
```

**Expected:**
- `time_since_last_heartbeat` < 10 seconds

**Warning signs:**
- > 20 seconds: Node may be slow or overloaded
- > 30 seconds: Node entering SUSPECT state
- > 5 minutes: Node will be marked DEAD

## Detecting Node Failures

### Scenario 1: Single Node Failure

**Symptoms:**
```
id  address           is_available  is_live
1   localhost:26257   true          true
2   localhost:26259   false         false   ← DEAD
3   localhost:26261   true          true
```

**Impact:**
- ⚠️ Reduced fault tolerance (only 2 nodes)
- ⚠️ Some ranges may be underreplicated
- ⚠️ Quorum still achievable (2 of 3)

**Actions:**
1. Investigate why node 2 is down
2. Check if node process running
3. Review logs for errors
4. Restart node if necessary

### Scenario 2: Network Partition

**Symptoms:**
```
# From node 1's perspective:
id  address           is_available  is_live
1   localhost:26257   true          true
2   localhost:26259   false         false
3   localhost:26261   false         false

# But nodes 2 and 3 can see each other
```

**Impact:**
- ❌ Cluster may lose quorum
- ❌ Writes may fail
- ❌ Data unavailable

**Actions:**
1. Check network connectivity between nodes
2. Review firewall/security group rules
3. Verify routing tables
4. Check for split-brain scenario

### Scenario 3: Majority Failure (Quorum Loss)

**Symptoms:**
```
id  address           is_available  is_live
1   localhost:26257   true          true
2   localhost:26259   false         false   ← DEAD
3   localhost:26261   false         false   ← DEAD
```

**Impact:**
- ❌ No quorum (1 of 3 nodes)
- ❌ Writes BLOCKED
- ❌ Reads may fail
- ❌ Cluster unavailable

**Actions:**
1. **URGENT**: Restore at least 2 nodes
2. Check all node processes
3. Review infrastructure (cloud provider status)
4. Consider disaster recovery if nodes unrecoverable

## Alerting Thresholds

### Warning Alerts

**Trigger when:**
```sql
-- Any node in SUSPECT state
SELECT count(*) FROM crdb_internal.gossip_nodes
WHERE is_live AND NOT is_available;
-- Alert if > 0
```

**Actions:**
- Investigate suspected node
- Check for resource pressure
- Review recent changes

### Critical Alerts

**Trigger when:**
```sql
-- Any node DEAD
SELECT count(*) FROM crdb_internal.gossip_nodes
WHERE NOT is_live;
-- Alert if > 0

-- Quorum at risk (minority of nodes available)
SELECT
  count(*) as total,
  sum(CASE WHEN is_live THEN 1 ELSE 0 END) as live
FROM crdb_internal.gossip_nodes;
-- Alert if live < (total / 2 + 1)
```

**Actions:**
- Immediate investigation
- Page on-call engineer
- Prepare for disaster recovery if needed

## Monitoring Best Practices

### 1. Automated Monitoring

**Run every 1-5 minutes:**
```bash
cockroach node status --certs-dir=certs --host=localhost:26258 | \
  awk '$8 == "false" || $9 == "false" {print "ALERT: Node", $1, "unhealthy"}'
```

### 2. Track Node Uptime

```sql
SELECT
  node_id,
  started_at,
  now() - started_at as uptime
FROM crdb_internal.gossip_liveness
ORDER BY started_at DESC;
```

**Look for:**
- Recent restarts (investigate cause)
- Frequent restarts (stability issues)

### 3. Monitor Replica Distribution

```sql
SELECT
  node_id,
  replicas
FROM crdb_internal.gossip_nodes
ORDER BY replicas DESC;
```

**Check:**
- Replicas evenly distributed
- No node with 0 replicas (unless new/decommissioning)

### 4. Check for Decommissioning Nodes

```sql
SELECT
  node_id,
  address,
  is_decommissioning,
  is_draining
FROM crdb_internal.gossip_liveness
WHERE is_decommissioning OR is_draining;
```

## Troubleshooting Node Issues

### Issue: Node shows SUSPECT

**Diagnosis:**
```bash
# Check if process is running
ps aux | grep cockroach

# Check CPU/memory usage
top -p $(pgrep cockroach)

# Check network connectivity
ping <node-address>

# Check CockroachDB logs
tail -f <log-directory>/cockroach.log
```

**Common causes:**
- High CPU/memory usage
- Disk I/O saturation
- Network latency spike
- Clock skew

### Issue: Node shows DEAD

**Diagnosis:**
```bash
# Check if process crashed
systemctl status cockroach  # if using systemd

# Check logs for panic/crash
grep -i "panic\|fatal" <log-directory>/cockroach.log

# Check disk space
df -h

# Check for OOM kills
dmesg | grep -i "out of memory"
```

**Recovery:**
```bash
# Restart node
cockroach start --certs-dir=certs ... --background

# Verify it rejoins
cockroach node status --certs-dir=certs --host=localhost:26258
```

## Verification Checklist

Cluster is healthy when:
- ✅ All nodes show `is_live = true`
- ✅ All nodes show `is_available = true`
- ✅ No nodes in SUSPECT state (> 30s no heartbeat)
- ✅ No nodes in DEAD state (> 5min offline)
- ✅ Quorum available (majority of nodes live)
- ✅ Replicas evenly distributed
- ✅ Recent heartbeats (< 10 seconds ago)

## Related Skills

- `monitor-gossip-network-health` - Cluster communication
- `monitor-network-latency-between-nodes` - Network performance
- `use-health-check-endpoints` - HTTP health checks
- `monitor-underreplicated-ranges-for-availability-risk` - Data availability
- `configure-ntp-for-clock-synchronization` - Clock sync

## Documentation

- Node Liveness: https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting.html#node-liveness-issues
- Monitoring: https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html
- Cluster Management: https://www.cockroachlabs.com/docs/stable/node-shutdown.html
