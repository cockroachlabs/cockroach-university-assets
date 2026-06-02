---
name: implement-appropriate-recovery-strategies-based-on-cluster-settings-and-monitoring
description: Implement recovery strategies based on cluster state and failure type. Use when user asks "recover from failure", "node down recovery", "cluster recovery strategy", "choose recovery approach", or "fix cluster issues".
metadata:
  domain: Cluster Maintenance
  bloom_level: Evaluate
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Implement Appropriate Recovery Strategies Based on Cluster Settings and Monitoring

## What This Skill Teaches

Choosing the right recovery strategy depends on understanding the failure type, cluster state, and risk tolerance. This skill covers decision frameworks for selecting recovery approaches based on monitoring data and cluster settings.

## Recovery Decision Framework

### Step 1: Identify Failure Type

**Common failure types**:
1. **Node failure** - Node crashed or unreachable
2. **Disk full** - Node out of disk space
3. **Network partition** - Nodes cannot communicate
4. **Clock drift** - Time sync issues
5. **Performance degradation** - Slow queries, high latency
6. **Data inconsistency** - Under-replication, missing ranges

---

### Step 2: Assess Cluster State

**Critical questions**:
```sql
SET allow_unsafe_internals = true;

-- Do we have quorum?
SELECT count(*) AS dead_nodes
FROM crdb_internal.gossip_liveness
WHERE now() - updated_at > INTERVAL '5 minutes';
-- If dead_nodes >= (total_nodes / 2): NO QUORUM - EMERGENCY

-- Are ranges under-replicated?
SELECT count(*) AS under_replicated
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
-- If >0: Data loss risk

-- Is cluster serving queries?
SELECT count(*) AS slow_queries
FROM crdb_internal.cluster_execution_insights
WHERE problem = 'SlowExecution'
  AND end_time > now() - INTERVAL '10 minutes';
-- If >100: Performance severely degraded
```

---

### Step 3: Choose Recovery Strategy

## Recovery Strategies by Failure Type

### Strategy 1: Node Failure Recovery

**Symptoms**: Node not responding, marked DEAD

**Decision tree**:
```
Node down detected
    ↓
Check: How long down?
    ├─ <5 minutes → WAIT (self-healing not started yet)
    ├─ 5-30 minutes → RESTART (self-healing in progress)
    └─ >30 minutes → EVALUATE (self-healing mostly complete)
         ├─ Hardware OK? → RESTART node
         ├─ Hardware failed? → REPLACE node
         └─ Not coming back? → DECOMMISSION node
```

**Recovery: Restart Node**:
```bash
# If node down <30 minutes and hardware OK
ssh node3 "sudo systemctl restart cockroach"

# Verify node rejoins
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs

# Monitor rebalancing back to node
SET allow_unsafe_internals = true;
SELECT count(*) AS replicas_on_node_3
FROM crdb_internal.ranges
WHERE array_position(replicas, 3) IS NOT NULL;
-- Should increase as cluster rebalances
```

**Recovery: Replace Node**:
```bash
# If hardware failed permanently
# 1. Provision new node
# 2. Start CockroachDB joining cluster
cockroach start --join=node1:26257,node2:26257 \
  --advertise-addr=new-node:26257 \
  --store=/var/lib/cockroach \
  --certs-dir=/tmp/certs

# 3. Cluster automatically rebalances to new node
# 4. Optionally decommission old dead node
cockroach node decommission <old-node-id> \
  --host=localhost:26257 --certs-dir=/tmp/certs
```

---

### Strategy 2: Disk Full Recovery

**Symptoms**: Disk >90% full, ballast deleted, writes failing

**Immediate actions** (within minutes):
```bash
# 1. Delete ballast (frees 1GB)
sudo rm /var/lib/cockroach/EMERGENCY_BALLAST

# 2. Delete old logs
sudo rm -rf /var/lib/cockroach/logs/*.log.2024-*

# 3. Check space
df -h /var/lib/cockroach
```

**Short-term actions** (within hours):
```bash
# Add disk capacity
# AWS: Resize EBS volume
aws ec2 modify-volume --volume-id vol-xxx --size 200

# Restart node to recreate ballast
sudo systemctl restart cockroach
```

**Long-term actions** (within days):
```sql
-- Implement TTL for automatic cleanup
ALTER TABLE logs SET (ttl_expire_after = '7 days');

-- Reduce GC TTL to reclaim space faster
ALTER RANGE default CONFIGURE ZONE USING gc.ttlseconds = 14400;  -- 4 hours
```

---

### Strategy 3: Network Partition Recovery

**Symptoms**: Nodes can't communicate, "majority quorum" errors

**Decision**:
```
Network partition detected
    ↓
Check: Do we have quorum on THIS side?
    ├─ YES (majority of nodes reachable) → WAIT for network restoration
    │   └─ Cluster continues serving requests
    │
    └─ NO (minority of nodes) → EMERGENCY
        └─ Cannot serve requests until network restored
```

**Recovery**:
```bash
# Check network connectivity
ping <other-nodes>
nc -zv <other-node-ip> 26257

# Fix network issues (firewall, routing, VPN)
# Cluster automatically recovers when network restored

# Monitor recovery
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs
# All nodes should show is_live: true
```

**DO NOT** force quorum or skip Raft consensus - can cause data loss!

---

### Strategy 4: Clock Drift Recovery

**Symptoms**: "clock offset too large" errors, node crashes

**Immediate actions**:
```bash
# Check clock on all nodes
for node in node1 node2 node3; do
  echo "$node: $(ssh $node date +%s)"
done
# All should be within 1-2 seconds

# Fix NTP on problem nodes
ssh problem-node "sudo systemctl enable --now systemd-timesyncd"

# Verify sync
ssh problem-node "timedatectl status"
# Should show: System clock synchronized: yes
```

**Recovery**:
```bash
# Restart node with bad clock
ssh problem-node "sudo systemctl restart cockroach"

# Monitor rejoin
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs
```

**Prevention**:
```bash
# Ensure NTP on all nodes
for node in node1 node2 node3; do
  ssh $node "sudo systemctl enable --now chronyd"
done
```

---

### Strategy 5: Performance Degradation Recovery

**Symptoms**: P99 latency >1s, slow queries, admission control queuing

**Diagnosis**:
```sql
-- Check for slow queries
SELECT query, count(*) AS slow_count
FROM crdb_internal.cluster_execution_insights
WHERE problem = 'SlowExecution'
  AND end_time > now() - INTERVAL '1 hour'
GROUP BY query
ORDER BY slow_count DESC
LIMIT 10;

-- Check resource saturation
SET allow_unsafe_internals = true;
SELECT node_id, round(100.0 * used / capacity, 1) AS disk_percent
FROM crdb_internal.kv_store_status
WHERE (used / capacity) > 0.7;  -- >70% full
```

**Recovery options**:
```bash
# Option 1: Add capacity (horizontal scaling)
# Start new node
cockroach start --join=existing-nodes ...

# Option 2: Optimize queries
# Add indexes, reduce scan sizes

# Option 3: Reduce load
# Throttle application traffic temporarily
```

---

### Strategy 6: Under-Replication Recovery

**Symptoms**: Ranges stuck under-replicated for >5 minutes

**Diagnosis**:
```sql
SET allow_unsafe_internals = true;

SELECT count(*) AS under_replicated_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;

-- Check if enough nodes for replication
SELECT count(*) AS active_nodes
FROM crdb_internal.gossip_liveness
WHERE membership = 'active';
-- Need at least 3 nodes for 3x replication
```

**Recovery**:
```bash
# If insufficient nodes: Add new node
cockroach start --join=existing-nodes ...

# If zone constraints unsatisfiable: Relax constraints
ALTER RANGE default CONFIGURE ZONE USING constraints = '[]';

# If rebalancing disabled: Enable it
SET CLUSTER SETTING cluster.auto_rebalance.enabled = true;
```

---

## Risk Assessment

### Data Loss Risk vs Availability Impact

**High data loss risk, low availability impact**:
- Node down <5 minutes (cluster still serving)
- **Action**: Wait for self-healing

**Medium data loss risk, medium availability impact**:
- 1 node dead in 3-node cluster (cluster serving, but 1 failure away from outage)
- **Action**: Restart or replace node within hours

**Low data loss risk, high availability impact**:
- Performance degraded but all data replicated
- **Action**: Add capacity

**High data loss risk, high availability impact**:
- 2+ nodes dead in 3-node cluster (no quorum!)
- **Action**: EMERGENCY - restore nodes immediately

---

## Recovery Validation

### After Any Recovery

**Checklist**:
```bash
# 1. All nodes healthy
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs
# All should show is_live: true

# 2. Replication healthy
SET allow_unsafe_internals = true;
SELECT count(*) FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
# Should be: 0

# 3. Queries fast
SELECT count(*) FROM crdb_internal.cluster_execution_insights
WHERE problem = 'SlowExecution'
  AND end_time > now() - INTERVAL '10 minutes';
# Should be: <10

# 4. Disk space OK
SELECT round(100.0 * sum(used) / sum(capacity), 1) AS percent_used
FROM crdb_internal.kv_store_status;
# Should be: <80%

# 5. No errors in logs
sudo journalctl -u cockroach -n 100 | grep -i error
# Should be: minimal or none
```

---

## Emergency vs Planned Recovery

### Emergency Recovery (Do Immediately)

**Triggers**:
- No quorum (2+ nodes dead in 3-node cluster)
- Disk 100% full (writes failing)
- Clock drift causing crashes
- Data corruption detected

**Actions**:
- Bypass normal change control
- Focus on restoring availability
- Document actions taken for post-mortem

---

### Planned Recovery (Schedule Maintenance)

**Triggers**:
- 1 node dead, cluster stable
- Performance degraded but acceptable
- Need to replace aging hardware

**Actions**:
- Schedule during low-traffic window
- Communicate to stakeholders
- Have rollback plan
- Monitor closely during recovery

---

## Best Practices

1. **Assess before acting** - Understand cluster state first
2. **Minimize risk** - Choose least disruptive recovery
3. **One change at a time** - Don't restart multiple nodes simultaneously
4. **Monitor during recovery** - Watch for unexpected issues
5. **Validate after recovery** - Ensure cluster fully healthy
6. **Document incidents** - Record what happened and why
7. **Automate where possible** - Scripted health checks and recovery

---

## Common Mistakes to Avoid

❌ **Restarting all nodes at once** - Causes cluster outage
✅ **Restart one at a time** - Maintain availability

❌ **Force quorum or skip Raft** - Can cause data loss
✅ **Let Raft consensus work** - Data safety guaranteed

❌ **Decommission too quickly** - Deletes data prematurely
✅ **Wait for decommission complete** - Replicas safely moved

❌ **Ignore monitoring** - Miss early warning signs
✅ **Monitor continuously** - Catch issues early

---

## Related Skills

- `monitor-cluster-health-during-the-suspect-and-dead-node-states` - Identifies failures
- `verify-cluster-replication-and-size` - Validates recovery
- `prevent-out-of-disk-failures` - Disk full prevention
- `handle-clock-drift-issues` - Clock sync recovery
- `optimize-storage-reclamation` - Storage recovery
