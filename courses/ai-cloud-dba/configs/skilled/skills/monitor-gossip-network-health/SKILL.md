---
name: monitor-gossip-network-health
description: Understands how to query crdb_internal.gossip_network and crdb_internal.gossip_liveness to monitor cluster communication health. Detect network partitions or gossip propagation delays that could affect cluster coordination. Use when user says "check gossip", "monitor cluster communication", "gossip health".
metadata:
  domain: Monitoring and Alerting
  tags: cluster-operations, monitoring
  blooms_level: Understand
  version: 1.0.0
---

# Monitor Gossip Network Health

Monitors the gossip protocol that CockroachDB uses for cluster-wide communication. The gossip network propagates cluster metadata, node liveness, and range information across all nodes.

## What is Gossip?

The **gossip protocol** is CockroachDB's peer-to-peer communication mechanism:
- Propagates cluster state information
- Maintains node liveness and availability
- Shares range location and replica information
- Enables nodes to discover each other
- Critical for cluster coordination

**Gossip is healthy when:**
- All nodes can communicate
- Information propagates quickly (< 1 second)
- No network partitions
- Heartbeats are regular

## Instructions

### Step 1: Check Gossip Network Connections

```sql
SELECT * FROM crdb_internal.gossip_network;
```

**Output columns:**
- `node_id`: Node ID
- `address`: Node network address
- `locality`: Node locality (region, zone)
- `attrs`: Node attributes
- `server_version`: CockroachDB version
- `is_live`: Whether node is alive

**What to look for:**
- ✅ All nodes present
- ✅ All nodes show `is_live = true`
- ⚠️ Missing nodes indicate connectivity issues
- ❌ `is_live = false` indicates dead/partitioned node

### Step 2: Check Gossip Liveness

```sql
SELECT * FROM crdb_internal.gossip_liveness;
```

**Output columns:**
- `node_id`: Node ID
- `epoch`: Liveness epoch (increments on restart)
- `expiration`: When liveness expires
- `draining`: Whether node is draining
- `decommissioning`: Whether node is decommissioning
- `membership`: Node membership status

**What to look for:**
- ✅ `expiration` in the future (node alive)
- ✅ `draining = false` (unless maintenance)
- ⚠️ `expiration` in past (node might be dead)
- ❌ Missing entries (gossip not propagating)

### Step 3: Check Gossip Alerts

```sql
SELECT * FROM crdb_internal.gossip_alerts;
```

Shows any active gossip-related alerts or issues.

## Example: Complete Gossip Health Check

```sql
-- 1. Check all nodes are connected
SELECT
  node_id,
  address,
  locality,
  is_live
FROM crdb_internal.gossip_network
ORDER BY node_id;

-- 2. Check liveness status
SELECT
  node_id,
  epoch,
  expiration,
  expiration > now() as is_live,
  draining,
  decommissioning
FROM crdb_internal.gossip_liveness
ORDER BY node_id;

-- 3. Count live vs dead nodes
SELECT
  CASE WHEN is_live THEN 'Live' ELSE 'Dead' END as status,
  count(*) as node_count
FROM crdb_internal.gossip_network
GROUP BY is_live;
```

## Example Output

### Healthy Gossip Network

```
node_id | address           | locality                     | is_live
--------+-------------------+------------------------------+---------
1       | localhost:26257   | region=us-east,zone=us-ea-1a | true
2       | localhost:26259   | region=us-west,zone=us-we-1a | true
3       | localhost:26261   | region=eu-west,zone=eu-we-1a | true
```

✅ **All nodes live and connected**

### Unhealthy Gossip Network

```
node_id | address           | locality                     | is_live
--------+-------------------+------------------------------+---------
1       | localhost:26257   | region=us-east,zone=us-ea-1a | true
2       | localhost:26259   | region=us-west,zone=us-we-1a | false
3       | localhost:26261   | region=eu-west,zone=eu-we-1a | true
```

❌ **Node 2 is not live - network partition or node failure**

## Understanding Gossip Metrics

### Key Metrics

| Metric | What it Means | Healthy Value |
|--------|---------------|---------------|
| `gossip.connections.incoming` | Inbound gossip connections | ≥ 1 per node |
| `gossip.connections.outgoing` | Outbound gossip connections | ≥ 1 per node |
| `gossip.bytes.received` | Gossip data received | Stable, non-zero |
| `gossip.bytes.sent` | Gossip data sent | Stable, non-zero |
| `gossip.infos.received` | Gossip messages received | Increasing |
| `gossip.infos.sent` | Gossip messages sent | Increasing |

Query metrics:
```sql
SELECT
  node_id,
  name,
  value
FROM crdb_internal.node_metrics
WHERE name LIKE 'gossip%'
ORDER BY node_id, name;
```

## Common Gossip Issues

### Issue 1: Network Partition

**Symptom:**
```
-- Some nodes missing from gossip_network
SELECT count(*) FROM crdb_internal.gossip_network;
-- Returns < total number of nodes
```

**Cause:**
- Firewall blocking gossip port (26257)
- Network split between data centers
- Routing issues

**Solution:**
1. Check network connectivity between nodes
2. Verify firewall rules allow port 26257
3. Check cloud security groups
4. Review network topology

### Issue 2: Gossip Propagation Delay

**Symptom:**
- Information takes > 1 second to propagate
- Stale range information
- Nodes have different views of cluster

**Cause:**
- High network latency
- Bandwidth saturation
- Too many nodes (> 100)

**Solution:**
1. Check network latency (see monitor-network-latency-between-nodes)
2. Increase network bandwidth
3. Consider cluster splitting for > 100 nodes

### Issue 3: Node Liveness Expiring

**Symptom:**
```sql
SELECT * FROM crdb_internal.gossip_liveness
WHERE expiration < now();
```

**Cause:**
- Node stopped/crashed
- Severe CPU/memory pressure
- Clock skew

**Solution:**
1. Check node process: `ps aux | grep cockroach`
2. Check node resources: CPU, memory, disk
3. Verify NTP synchronization
4. Restart node if necessary

### Issue 4: Asymmetric Connectivity

**Symptom:**
- Node A can reach Node B, but not vice versa
- Gossip working in one direction only

**Cause:**
- Asymmetric routing
- Firewall rules allowing outbound but blocking inbound
- NAT configuration issues

**Solution:**
1. Test bidirectional connectivity
2. Review firewall rules
3. Check NAT configuration
4. Verify advertise-addr settings

## Monitoring Best Practices

### 1. Regular Health Checks

Run every 5 minutes:
```sql
SELECT
  count(*) as total_nodes,
  sum(CASE WHEN is_live THEN 1 ELSE 0 END) as live_nodes,
  sum(CASE WHEN is_live THEN 0 ELSE 1 END) as dead_nodes
FROM crdb_internal.gossip_network;
```

Alert if `dead_nodes > 0`

### 2. Monitor Gossip Latency

```sql
SELECT
  node_id,
  value / 1000000.0 as latency_ms
FROM crdb_internal.node_metrics
WHERE name = 'rpc.heartbeat.latency-p99'
ORDER BY value DESC;
```

Alert if latency > 500ms

### 3. Track Liveness Epochs

Sudden epoch increases indicate node restarts:
```sql
SELECT
  node_id,
  epoch,
  lag(epoch) OVER (PARTITION BY node_id ORDER BY now()) as prev_epoch
FROM crdb_internal.gossip_liveness;
```

### 4. Monitor Gossip Alerts

```sql
SELECT * FROM crdb_internal.gossip_alerts;
```

Should return empty for healthy cluster

## Gossip Architecture

**How gossip works:**

1. Each node maintains connections to ~3-5 other nodes
2. Nodes exchange cluster state information
3. Information propagates exponentially (like rumors)
4. Full cluster convergence typically < 1 second
5. Heartbeats every ~1 second to maintain liveness

**Gossip propagates:**
- Node liveness and membership
- Range locations and replicas
- Cluster settings
- Schema changes
- Zone configurations

## Troubleshooting Commands

### Check if gossip is working

```bash
# Check gossip connections
cockroach node status --certs-dir=certs --host=localhost:26258

# Detailed gossip info (debug)
cockroach debug gossip-values --certs-dir=certs --host=localhost:26258
```

### Force gossip connectivity

If gossip seems stuck:
```sql
-- Restart gossip (requires admin)
SELECT crdb_internal.force_retry_jobs();
```

## Alert Thresholds

| Condition | Severity | Action |
|-----------|----------|--------|
| 1 node not live | Warning | Investigate within 5 minutes |
| 2+ nodes not live | Critical | Immediate investigation |
| Gossip latency > 500ms | Warning | Check network |
| Gossip latency > 1s | Critical | Network issues likely |
| Liveness expiring | Critical | Node failure imminent |

## Verification Checklist

Gossip is healthy when:
- ✅ All nodes appear in `gossip_network`
- ✅ All nodes show `is_live = true`
- ✅ Liveness expirations are in future
- ✅ No nodes draining (unless maintenance)
- ✅ Gossip latency < 100ms
- ✅ No alerts in `gossip_alerts`

## Related Skills

- `monitor-network-latency-between-nodes` - Network performance
- `monitor-node-liveness-and-health` - Node availability
- `use-health-check-endpoints` - HTTP health checks
- `configure-ntp-for-clock-synchronization` - Clock sync for liveness

## Documentation

- Gossip Protocol: https://www.cockroachlabs.com/docs/stable/architecture/replication-layer.html#gossip
- Cluster Troubleshooting: https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting.html
