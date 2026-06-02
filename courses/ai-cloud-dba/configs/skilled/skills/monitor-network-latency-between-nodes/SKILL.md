---
name: monitor-network-latency-between-nodes
description: Can monitor network roundtrip latency between nodes using DB Console Network dashboard or crdb_internal.node_metrics. Track metrics like rpc.heartbeat.latency for gossip roundtrip times. Critical for multi-region deployments to detect network degradation. Use when user says "monitor network latency", "check network health", "network performance".
metadata:
  domain: Monitoring and Alerting
  tags: multi-region, monitoring, performance
  blooms_level: Apply
  version: 1.0.0
---

# Monitor Network Latency Between Nodes

Monitors network roundtrip latency between cluster nodes to detect network degradation, connectivity issues, or performance problems. Essential for multi-region deployments.

## Why Monitor Network Latency

Network latency affects:
- **Write latency**: Cross-region consensus requires network roundtrips
- **Read latency**: Follower reads depend on network speed
- **Cluster stability**: High latency can cause gossip delays
- **Replication**: Data transfer between nodes

**Healthy latency ranges:**
- Same AZ: < 1ms
- Same region (different AZs): 1-5ms
- Cross-region (US): 50-80ms
- Cross-region (US-Europe): 100-150ms
- Cross-region (US-Asia): 150-250ms

## Instructions

### Method 1: DB Console Network Dashboard (Recommended)

**Step 1:** Access DB Console
```
https://<node-address>:8080
```

**Step 2:** Navigate to Network Dashboard
- Click "Metrics" in left sidebar
- Select "Network" dashboard
- View "Network Latency" graph

**Step 3:** Interpret Latency Graph
- Each line represents latency from one node to another
- Hover over lines to see specific node pairs
- Look for:
  - ✅ Stable lines (good)
  - ⚠️ Spikes (transient issues)
  - ❌ Sustained increases (network degradation)

### Method 2: Query crdb_internal.node_metrics

**Step 1:** Query RPC Heartbeat Latency

```sql
SELECT
  node_id,
  name,
  value
FROM crdb_internal.node_metrics
WHERE name LIKE '%rpc.heartbeat.latency%'
ORDER BY node_id, name;
```

**Step 2:** Query Network Bytes Sent/Received

```sql
SELECT
  node_id,
  name,
  value / (1024*1024) as value_mb
FROM crdb_internal.node_metrics
WHERE name LIKE '%network%'
ORDER BY node_id, name;
```

### Method 3: Query Gossip Network Info

```sql
-- View gossip network connections
SELECT * FROM crdb_internal.gossip_network;

-- Check gossip liveness
SELECT * FROM crdb_internal.gossip_liveness;
```

## Example: Check Network Latency

```sql
-- Get all network-related metrics
SELECT
  node_id,
  name,
  value,
  CASE
    WHEN value < 1000000 THEN 'Good (< 1ms)'
    WHEN value < 5000000 THEN 'Normal (1-5ms)'
    WHEN value < 100000000 THEN 'Acceptable (5-100ms)'
    ELSE 'High (> 100ms)'
  END as status
FROM crdb_internal.node_metrics
WHERE name = 'rpc.heartbeat.latency-p99'
ORDER BY node_id;
```

**Note:** Latency values are in nanoseconds
- 1ms = 1,000,000 nanoseconds
- 10ms = 10,000,000 nanoseconds
- 100ms = 100,000,000 nanoseconds

## Example Output

```
node_id | name                        | value      | status
--------+-----------------------------+------------+------------------
1       | rpc.heartbeat.latency-p99   | 2500000    | Normal (1-5ms)
2       | rpc.heartbeat.latency-p99   | 75000000   | Acceptable (5-100ms)
3       | rpc.heartbeat.latency-p99   | 120000000  | High (> 100ms)
```

**Interpretation:**
- Node 1: 2.5ms latency (same region) ✅
- Node 2: 75ms latency (cross-region US) ✅
- Node 3: 120ms latency (cross-region US-EU) ⚠️

## Metrics to Monitor

| Metric Name | What it Measures | Healthy Range |
|-------------|------------------|---------------|
| `rpc.heartbeat.latency-p50` | Median gossip roundtrip | < 50ms same region |
| `rpc.heartbeat.latency-p99` | 99th percentile latency | < 200ms cross-region |
| `network.bytes.sent` | Outbound network traffic | Depends on workload |
| `network.bytes.received` | Inbound network traffic | Depends on workload |

## Troubleshooting High Latency

### Symptom: Sudden latency spike

**Possible Causes:**
- Network congestion
- Cloud provider issues
- Routing changes
- DNS issues

**Actions:**
1. Check if spike is transient (wait 5 minutes)
2. Check cloud provider status page
3. Review recent infrastructure changes
4. Compare with baseline metrics

### Symptom: Sustained high latency

**Possible Causes:**
- Increased geographic distance (misconfigured regions)
- Network misconfiguration
- Firewall/security group issues
- Bandwidth saturation

**Actions:**
1. Verify node localities are correct
   ```bash
   cockroach node status --certs-dir=certs --host=localhost:26258
   ```
2. Check network configuration
3. Review security group/firewall rules
4. Monitor bandwidth usage

### Symptom: Asymmetric latency

**Possible Causes:**
- Routing asymmetry
- Bandwidth differences
- Misconfigured load balancers

**Actions:**
1. Check latency in both directions (A→B vs B→A)
2. Review routing tables
3. Check load balancer configuration

## Setting Up Alerts

### Alert Thresholds

**Warning (Yellow):**
- Latency > 200ms between nodes
- Latency increased > 50% from baseline

**Critical (Red):**
- Latency > 500ms between nodes
- Gossip network connectivity issues
- Node unreachable

### Example Alert Query

```sql
-- Find nodes with high latency
SELECT
  node_id,
  value / 1000000.0 as latency_ms
FROM crdb_internal.node_metrics
WHERE name = 'rpc.heartbeat.latency-p99'
  AND value > 200000000  -- > 200ms
ORDER BY value DESC;
```

## Impact of High Latency

### On Write Performance

- **Zone survival**: Writes wait for quorum within region (low latency)
- **Region survival**: Writes wait for quorum across regions (higher latency)
- Formula: Write latency ≈ Network latency + Disk latency

### On Read Performance

- **Leaseholder reads**: No network latency (local)
- **Follower reads**: Bounded staleness, local reads
- **Global reads**: May involve cross-region roundtrips

### On Cluster Health

- **Gossip protocol**: High latency slows cluster state propagation
- **Raft consensus**: Slower leader elections
- **Range rebalancing**: Slower data movement

## Multi-Region Latency Expectations

| Route | Expected Latency | Notes |
|-------|------------------|-------|
| us-east ↔ us-west | 60-80ms | Acceptable for region survival |
| us-east ↔ eu-west | 80-120ms | Expected for transatlantic |
| us-east ↔ ap-south | 150-250ms | High but normal for Asia-Pacific |
| Same AZ | < 1ms | Should be sub-millisecond |
| Same region | 1-5ms | Normal for different AZs |

## Best Practices

1. **Establish baselines** - Know normal latency for your deployment
2. **Monitor continuously** - Set up dashboards and alerts
3. **Test regularly** - Simulate network issues in non-prod
4. **Document topology** - Keep network diagram updated
5. **Plan for degradation** - Design for 2x normal latency

## Verification Checklist

When monitoring network health:
- ✅ Latency between nodes is stable
- ✅ No sudden spikes or sustained increases
- ✅ Latency matches geographic expectations
- ✅ Gossip network is healthy
- ✅ No asymmetric latency issues
- ✅ Network bytes sent/received are balanced

## Related Skills

- `monitor-gossip-network-health` - Check gossip protocol
- `monitor-node-liveness-and-health` - Node availability
- `use-health-check-endpoints` - HTTP health checks
- `monitor-cross-region-query-traffic` - Query-level latency

## Documentation

- Network Latency: https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting.html#network-latency
- Multi-Region Performance: https://www.cockroachlabs.com/docs/stable/topology-patterns.html
