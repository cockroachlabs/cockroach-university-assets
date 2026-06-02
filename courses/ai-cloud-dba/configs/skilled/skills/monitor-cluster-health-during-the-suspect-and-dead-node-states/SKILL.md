---
name: monitor-cluster-health-during-the-suspect-and-dead-node-states
description: Monitor cluster health during node state transitions from healthy to suspect to dead. Use when user asks "check node liveness", "monitor suspect nodes", "track dead nodes", "node state transitions", or "gossip protocol health".
metadata:
  domain: Cluster Maintenance
  bloom_level: Evaluate
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Monitor Cluster Health During Suspect and Dead Node States

## What This Skill Teaches

Understanding and monitoring node liveness states is critical for cluster health. This skill covers tracking node transitions from healthy → suspect → dead, and how to monitor and respond to each state.

## Node Liveness States

### State Transitions

```
Healthy → Suspect → Dead → Removed
```

**Timeline**:
```
T+0s:   Node healthy (regular heartbeats)
T+30s:  Network issue (heartbeats missed)
T+45s:  Node marked SUSPECT
T+5m:   Node marked DEAD (server.time_until_store_dead expired)
T+5m+:  Cluster begins replica rebalancing
```

---

## Understanding Each State

### Healthy State

**Definition**: Node sending regular heartbeats via gossip protocol

**Query**:
```sql
SET allow_unsafe_internals = true;

SELECT l.node_id, n.address, l.membership, l.updated_at,
       now() - l.updated_at AS time_since_last_heartbeat
FROM crdb_internal.gossip_liveness l
JOIN crdb_internal.gossip_nodes n ON l.node_id = n.node_id
WHERE l.membership = 'active'
ORDER BY l.node_id;
```

**Expected**: `time_since_last_heartbeat` < 5 seconds

---

### Suspect State

**Definition**: Node missed heartbeats but not yet declared dead

**Characteristics**:
- No heartbeats for 10-60 seconds
- NOT yet triggering replica rebalancing
- May recover without data movement

**When this happens**: Temporary network partition, CPU saturation, GC pause, OS issues

**Query**:
```sql
SET allow_unsafe_internals = true;

-- Nodes with stale liveness data (suspect)
SELECT l.node_id, n.address, l.updated_at,
       now() - l.updated_at AS staleness,
       l.membership
FROM crdb_internal.gossip_liveness l
JOIN crdb_internal.gossip_nodes n ON l.node_id = n.node_id
WHERE now() - l.updated_at > INTERVAL '10 seconds'
  AND l.membership = 'active'
ORDER BY staleness DESC;
```

**Alert threshold**: Staleness > 30 seconds

---

### Dead State

**Definition**: Node silent beyond `server.time_until_store_dead` timeout

**Characteristics**:
- No heartbeats for > 5 minutes (default)
- Node marked as dead
- Cluster begins self-healing (replica rebalancing)
- Cannot rejoin without operator intervention

**Query**:
```sql
SET allow_unsafe_internals = true;

SELECT l.node_id, n.address, l.membership, l.updated_at,
       now() - l.updated_at AS time_dead
FROM crdb_internal.gossip_liveness l
JOIN crdb_internal.gossip_nodes n ON l.node_id = n.node_id
WHERE l.membership = 'decommissioned'
   OR now() - l.updated_at > INTERVAL '5 minutes'
ORDER BY time_dead DESC;
```

**Self-healing**:
```sql
SET allow_unsafe_internals = true;

-- Ranges being up-replicated from dead node
SELECT count(*) AS under_replicated_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;

-- Decreases over time as cluster rebalances
```

---

## Monitoring Node Liveness

### Primary Monitoring Query

```sql
SET allow_unsafe_internals = true;

SELECT
    l.node_id, n.address, l.membership, l.updated_at,
    now() - l.updated_at AS staleness,
    CASE
        WHEN now() - l.updated_at < INTERVAL '10 seconds' THEN 'HEALTHY'
        WHEN now() - l.updated_at < INTERVAL '5 minutes' THEN 'SUSPECT'
        ELSE 'DEAD'
    END AS health_status
FROM crdb_internal.gossip_liveness l
JOIN crdb_internal.gossip_nodes n ON l.node_id = n.node_id
ORDER BY staleness DESC;
```

---

### Gossip Network Health

```sql
SET allow_unsafe_internals = true;

SELECT node_id, network, address, locality, is_live
FROM crdb_internal.gossip_nodes
ORDER BY node_id;
```

**Key fields**:
- `is_live`: Should be `true` for all healthy nodes
- `epoch`: Increments on restart (check for unexpected restarts)

---

## Alert Thresholds

### Recommended Alerts

**Warning (Suspect)**:
```sql
SELECT count(*) AS suspect_nodes
FROM crdb_internal.gossip_liveness
WHERE now() - updated_at > INTERVAL '30 seconds'
  AND now() - updated_at < INTERVAL '5 minutes'
  AND membership = 'active';

-- Alert if suspect_nodes > 0
```

**Critical (Dead)**:
```sql
SELECT count(*) AS dead_nodes
FROM crdb_internal.gossip_liveness
WHERE now() - updated_at > INTERVAL '5 minutes'
  AND membership = 'active';

-- Alert if dead_nodes > 0
```

**Emergency (Multiple Dead)**:
```sql
-- Critical if >1 node dead (quorum risk!)
SELECT count(*) AS dead_nodes
FROM crdb_internal.gossip_liveness
WHERE now() - updated_at > INTERVAL '5 minutes';

-- CRITICAL if dead_nodes > 1
```

---

## Cluster Setting Impact

### server.time_until_store_dead

**Controls**: How long cluster waits before declaring node dead

```sql
SHOW CLUSTER SETTING server.time_until_store_dead;
-- Default: 00:05:00

-- Shorter (faster recovery, more false positives)
SET CLUSTER SETTING server.time_until_store_dead = '2m';

-- Longer (fewer false positives, slower recovery)
SET CLUSTER SETTING server.time_until_store_dead = '10m';
```

**Recommendation**: Keep default (5m) unless specific need

---

## Impact on Cluster Availability

### Quorum and Fault Tolerance

**3-node cluster** (replication factor 3):
- 1 node dead: ✅ Cluster healthy (quorum: 2/3)
- 2 nodes dead: ❌ Cluster unavailable (no quorum)

**5-node cluster**:
- 1-2 nodes dead: ✅ Cluster healthy
- 3 nodes dead: ❌ Partial unavailability

**Monitoring**:
```sql
SET allow_unsafe_internals = true;

-- Check quorum for all ranges
SELECT database_name, table_name,
       array_length(replicas, 1) AS replica_count,
       count(*) AS range_count
FROM crdb_internal.ranges
GROUP BY database_name, table_name, array_length(replicas, 1)
HAVING array_length(replicas, 1) < 2  -- Less than quorum!
ORDER BY database_name, table_name;
```

---

## Recovery Procedures

### Suspect Node Recovery

**If node in suspect state**:

1. **Check network connectivity**:
```bash
ping <suspect-node-address>
nc -zv <suspect-node-ip> 26257
```

2. **Check node resources**:
```bash
ssh <node>
top -bn1 | grep cockroach
free -h
iostat -x 1 5
```

3. **Check CockroachDB process**:
```bash
ps aux | grep cockroach
sudo journalctl -u cockroach -n 100 | grep -i error
```

4. **Monitor recovery**:
```sql
SET allow_unsafe_internals = true;

SELECT node_id, now() - updated_at AS staleness
FROM crdb_internal.gossip_liveness
WHERE node_id = 2
ORDER BY updated_at DESC
LIMIT 10;

-- Staleness decreasing = recovering
-- Staleness increasing = truly down
```

---

### Dead Node Recovery

**If node declared dead**:

1. **Verify node is down**:
```bash
cockroach node status --host=<dead-node-ip>:26257 --certs-dir=/tmp/certs
```

2. **Check self-healing progress**:
```sql
SET allow_unsafe_internals = true;

SELECT count(*) AS under_replicated
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;

-- Monitor every 30 seconds - should decrease
```

3. **Choose action**:

**Option A: Restart node**:
```bash
sudo systemctl restart cockroach
```

**Option B: Replace node** (if hardware failed):
```bash
cockroach start --join=<nodes> --store=... --certs-dir=...
```

**Option C: Decommission** (if not returning):
```bash
cockroach node decommission <dead-node-id> \
  --host=localhost:26257 --certs-dir=/tmp/certs
```

---

## Troubleshooting

### Issue 1: Nodes Flapping (Suspect ↔ Healthy)

**Symptom**: Node repeatedly going suspect and recovering

**Causes**: Network instability, resource saturation, clock drift

**Diagnosis**:
```bash
# Check network
ping -c 100 <node-ip> | tail -5

# Check CPU
top -bn1 | grep cockroach

# Check clock sync
timedatectl status
```

**Solutions**:
```bash
# Enable NTP
sudo systemctl enable --now systemd-timesyncd
timedatectl status
```

---

### Issue 2: False Dead Declaration

**Symptom**: Node declared dead but process running

**Cause**: Clock drift or network partition

**Diagnosis**:
```bash
# Check clock on all nodes
for node in node1 node2 node3; do
  echo "$node:"
  ssh $node date +%s
done

# Should be within 1-2 seconds
```

**Solution**:
```bash
sudo systemctl enable --now chronyd
timedatectl status
```

---

## Best Practices

1. **Monitor liveness continuously** - Alert on suspect nodes (>30s staleness)
2. **Investigate suspect states immediately** - Don't wait for dead
3. **Maintain NTP sync** - Clock drift causes false declarations
4. **Keep default timeout** - 5 minutes works for most deployments
5. **Plan for 1 dead node** - 3-node tolerates 1, 5-node tolerates 2
6. **Document escalation** - Know when to restart vs decommission

---

## Related Skills

- `demonstrate-how-servertimeuntilstoredead-impacts-the-clusters-self-healing-behavior` - Timeout behavior
- `perform-pre-upgrade-health-assessments` - Health checks
- `verify-cluster-replication-and-size` - Replication monitoring
- `drain-nodes-for-maintenance` - Graceful shutdown
