---
name: diagnose-node-failures-using-multiple-signals
description: Diagnose node failures by correlating multiple signals including liveness, health checks, logs, and metrics. Use when investigating cluster instability, troubleshooting node outages, or determining root causes of failures.
metadata:
  domain: Resilience and Failure Handling
  bloom_level: Analyze
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - understand-node-state-transitions-during-failures
    - monitor-node-liveness-and-health
    - monitor-underreplicated-ranges-for-availability-risk
    - recover-from-temporary-node-outages
  prerequisites:
    - Understanding of CockroachDB architecture
    - Basic knowledge of node liveness mechanisms
    - Familiarity with cluster health indicators
  estimated_time_minutes: 35
  last_updated: "2026-03-07"
---

# Diagnose Node Failures Using Multiple Signals

## Overview

Node failure diagnosis requires correlating multiple signals to determine the root cause and appropriate remediation. A comprehensive diagnostic approach examines liveness status, health endpoints, logs, metrics, and system resources to distinguish between network issues, hardware failures, resource exhaustion, and software bugs.

**Critical**: Single signals can be misleading. A node might appear "dead" due to network partition while actually running normally, or appear "live" while experiencing severe performance degradation. Always cross-reference multiple signals.

## Node Failure Signals Overview

### Primary Signals

1. **Node Liveness**: Is the node updating its liveness record?
2. **Health Endpoints**: Are HTTP health checks responding?
3. **Process Status**: Is the CockroachDB process running?
4. **Network Connectivity**: Can other nodes reach this node?
5. **Resource Utilization**: CPU, memory, disk I/O status
6. **Log Messages**: Critical errors or warnings in logs
7. **Metrics**: Prometheus endpoint availability and values

### Signal Correlation Matrix

| Signal | Network Partition | Node Crash | Disk Failure | Resource Exhaustion | Clock Skew |
|--------|------------------|------------|--------------|---------------------|------------|
| Liveness = false | ✓ | ✓ | ✓ | ✓ | ✓ |
| Health endpoint down | ✓ | ✓ | Partial | Partial | ✗ |
| Process not running | ✗ | ✓ | ✗ | ✗ | ✗ |
| Network unreachable | ✓ | ✓ | ✗ | ✗ | ✗ |
| High CPU/Memory | ✗ | ✗ | ✗ | ✓ | ✗ |
| Disk I/O errors in logs | ✗ | ✗ | ✓ | Partial | ✗ |
| Clock offset errors | ✗ | ✗ | ✗ | ✗ | ✓ |

## Diagnostic Workflow

### Step 1: Check Node Liveness Status

```bash
# Primary check: Node status from cluster perspective
cockroach node status --host=localhost:26257 --certs-dir=certs

# Look for is_live=false or is_available=false
```

**Expected output (healthy node):**
```
  id |     address      |   build   |            started_at           |            updated_at           | locality | is_live | is_available
-----+------------------+-----------+---------------------------------+---------------------------------+----------+---------+--------------
   1 | node1:26257      | v26.1.0   | 2026-03-07 10:15:23.123456+00   | 2026-03-07 14:22:15.987654+00   |          | true    | true
   2 | node2:26257      | v26.1.0   | 2026-03-07 10:15:45.234567+00   | 2026-03-07 14:22:16.123456+00   |          | true    | true
   3 | node3:26257      | v26.1.0   | 2026-03-07 10:16:12.345678+00   | 2026-03-07 13:45:30.987654+00   |          | false   | false
```

**Interpretation:**
- `is_live=false`: Node hasn't updated liveness record recently (likely down or partitioned)
- `is_available=false`: Node not participating in cluster operations
- Large gap between `updated_at` and current time: Node not responding

**Query alternative:**
```sql
-- Detailed liveness information
SELECT
  node_id,
  is_live,
  is_available,
  epoch,
  expiration,
  draining,
  decommissioning,
  membership
FROM crdb_internal.kv_node_liveness
ORDER BY node_id;
```

### Step 2: Verify Process Status on Node

```bash
# SSH to the suspect node and check process
ssh node3.example.com

# Check if CockroachDB process is running
ps aux | grep cockroach

# Expected output if running:
# cockroach 12345 0.5 2.1 4234567 876543 ? Ssl 10:15 2:34 /usr/local/bin/cockroach start ...

# Check systemd status if using systemd
sudo systemctl status cockroachdb

# Expected: active (running)
```

**Diagnosis:**
- **Process not found**: Node crashed or was stopped → Check logs for crash reason
- **Process found, zombie state**: Process hung → May need force restart
- **Process running normally**: Issue is network or liveness-related, not process crash

### Step 3: Test Network Connectivity

```bash
# From another node, test connectivity to suspect node

# Test TCP connectivity to CockroachDB port
nc -zv node3.example.com 26257
# Expected: "Connection to node3.example.com 26257 port [tcp/*] succeeded!"

# Test with telnet
telnet node3.example.com 26257
# Expected: Connected to node3.example.com

# Ping test
ping -c 3 node3.example.com

# From suspect node, test reverse connectivity
# SSH to node3
ssh node3.example.com
ping -c 3 node1.example.com
nc -zv node1.example.com 26257
```

**Diagnosis:**
- **Cannot connect from any node**: Complete network isolation → Network infrastructure issue
- **Can connect from some nodes, not others**: Asymmetric network partition
- **Can ping but cannot connect to port**: Firewall blocking CockroachDB port or process not listening
- **All connectivity works**: Issue is not network-related → Check resources/logs

### Step 4: Check Health Endpoints

```bash
# Test HTTP health endpoint
curl -k https://node3.example.com:8080/health?ready=1
# Expected when healthy: {"status":"ok"}

# Test from suspect node itself (localhost)
ssh node3.example.com
curl http://localhost:8080/health?ready=1

# Check liveness endpoint
curl http://localhost:8080/health?liveness=1
```

**Response interpretation:**
- **200 OK with {"status":"ok"}**: Node is healthy from its own perspective
- **503 Service Unavailable**: Node is not ready (still starting or shutting down)
- **Connection refused**: Process not running or HTTP server not started
- **Timeout**: Process hung or severely resource-constrained

### Step 5: Analyze Resource Utilization

```bash
# SSH to suspect node
ssh node3.example.com

# Check CPU usage
top -b -n 1 | head -20
# Look for cockroach process CPU %

# Check memory
free -h
# Look for available memory

# Check disk space
df -h
# Ensure adequate free space (>15% recommended)

# Check disk I/O
iostat -x 5 3
# Look for %util near 100% indicating I/O saturation

# Check for disk errors
sudo dmesg | grep -i error | tail -20
```

**Critical thresholds:**
- **CPU >90% sustained**: Resource exhaustion, may cause liveness failures
- **Memory <10% free**: OOM risk, potential node crash
- **Disk >90% full**: Can cause node to refuse writes
- **Disk I/O >95% util**: Severe I/O contention affecting performance

### Step 6: Examine CockroachDB Logs

```bash
# View recent logs on suspect node
ssh node3.example.com
tail -100 /var/lib/cockroach/logs/cockroach.log

# Search for critical errors
grep -i "error\|fatal\|panic" /var/lib/cockroach/logs/cockroach.log | tail -50

# Check for specific failure patterns
grep -i "liveness" /var/lib/cockroach/logs/cockroach.log | tail -20
grep -i "disk\|I/O" /var/lib/cockroach/logs/cockroach.log | tail -20
grep -i "clock" /var/lib/cockroach/logs/cockroach.log | tail -20
```

**Key log patterns:**

**Pattern 1: Liveness failure**
```
liveness: failed to heartbeat own liveness record
liveness: failed to update liveness record
node liveness expired
```
**Cause**: Node cannot write to liveness range (network, I/O, or consensus issue)

**Pattern 2: Disk failure**
```
storage: disk stall detected
storage: failed to write to disk
pebble: write stall
I/O error
```
**Cause**: Disk hardware failure or severe I/O contention

**Pattern 3: Memory pressure**
```
out of memory
runtime: out of memory
server is currently under heavy load
```
**Cause**: Insufficient memory for workload

**Pattern 4: Clock skew**
```
clock offset exceeds maximum
clock synchronization error
rejecting command due to clock offset
```
**Cause**: NTP not configured or failing

### Step 7: Query Prometheus Metrics

```bash
# From suspect node, check if metrics endpoint is accessible
curl http://localhost:8080/_status/vars | head -50

# From monitoring server, check if scraping metrics
curl http://node3.example.com:8080/_status/vars | grep "node_id\|uptime"
```

**Key metrics to check:**
```bash
# Node uptime
curl http://node3:8080/_status/vars | grep sys_uptime
# sys_uptime 86400  (in seconds)

# CPU utilization
curl http://node3:8080/_status/vars | grep cpu_percent
# sys_cpu_user_percent 45.2
# sys_cpu_sys_percent 12.3

# Memory
curl http://node3:8080/_status/vars | grep rss
# sys_rss 4234567890  (bytes)

# Disk capacity
curl http://node3:8080/_status/vars | grep capacity_available
# capacity_available 53687091200  (bytes available)

# Liveness heartbeats
curl http://node3:8080/_status/vars | grep liveness_heartbeat
# liveness_heartbeatfailures 0
# liveness_heartbeatsuccesses 14523
```

**Red flags:**
- `liveness_heartbeatfailures` increasing: Node cannot update liveness
- `capacity_available` < 10GB: Disk space critically low
- `sys_cpu_user_percent` + `sys_cpu_sys_percent` > 90: CPU exhaustion
- Metrics endpoint not responding: Severe node degradation or crash

### Step 8: Check System Logs

```bash
# Check system-level logs for hardware/OS issues
ssh node3.example.com

# System journal
sudo journalctl -u cockroachdb -n 100

# Kernel logs
sudo dmesg | tail -50

# Look for OOM killer
sudo grep -i "out of memory\|oom" /var/log/syslog
sudo grep -i "kill" /var/log/kern.log

# Check for hardware errors
sudo grep -i "hardware error\|mce\|edac" /var/log/syslog
```

**Critical patterns:**
- **OOM Killer activated**: `kernel: Out of memory: Kill process [pid]`
- **Hardware errors**: `mce: Machine check events logged`
- **Disk errors**: `ata.*error\|sd.*error`

## Common Failure Scenarios and Diagnosis

### Scenario 1: Node Shows as Dead but Process is Running

**Symptoms:**
- `is_live=false` in `node status`
- Process running normally on node
- Health endpoint returns 200 OK locally

**Diagnostic steps:**
```bash
# 1. Check network connectivity from other nodes
nc -zv node3.example.com 26257

# 2. Check liveness heartbeat failures
curl http://node3:8080/_status/vars | grep liveness_heartbeat

# 3. Check clock offset
cockroach debug zip /tmp/debug.zip --host=node3:26257 --certs-dir=certs
unzip -p /tmp/debug.zip */nodes/*/gossip.json | grep clock_offset
```

**Common causes:**
- Network partition between node and liveness range leaseholder
- Clock skew preventing liveness updates
- Severe I/O contention delaying liveness writes

**Resolution:**
- Fix network connectivity issues
- Ensure NTP is running and synchronized
- Investigate and resolve I/O bottlenecks

### Scenario 2: Node Crash with No Warning

**Symptoms:**
- Process not running
- Recent `updated_at` timestamp, then sudden death
- No graceful shutdown messages in logs

**Diagnostic steps:**
```bash
# 1. Check for OOM killer
sudo grep -i "oom" /var/log/syslog | grep cockroach

# 2. Check for panic/crash in logs
grep -i "panic\|fatal" /var/lib/cockroach/logs/cockroach.log | tail -20

# 3. Check system crash dumps
ls -lh /var/crash/

# 4. Check systemd status
sudo systemctl status cockroachdb
```

**Common causes:**
- Out of memory (OOM killer terminated process)
- Software panic/bug
- Hardware failure (power, motherboard)
- Kernel crash

**Resolution:**
- If OOM: Increase node memory or reduce workload
- If panic: Collect debug zip and report to Cockroach Labs
- If hardware: Replace hardware and restart node

### Scenario 3: Gradual Performance Degradation Leading to Failure

**Symptoms:**
- Increasing latency over time
- `updated_at` timestamp increasingly stale before failure
- Health checks becoming slow before failing

**Diagnostic steps:**
```bash
# 1. Check historical resource utilization
# From monitoring system:
# CPU, memory, disk I/O trends over past hours

# 2. Check for memory leaks
curl http://node3:8080/_status/vars | grep rss
# Compare to historical values

# 3. Check for write amplification
curl http://node3:8080/_status/vars | grep compactions

# 4. Check for increased query latency
cockroach sql --host=node3:26257 --certs-dir=certs -e "
  SELECT * FROM crdb_internal.node_runtime_info;" --timing
```

**Common causes:**
- Memory leak (gradual memory exhaustion)
- Disk space exhaustion
- LSM tree compaction backlog
- Hot range causing CPU saturation

**Resolution:**
- Restart node to clear memory leaks (temporary)
- Add disk space
- Investigate and redistribute hot ranges
- Upgrade to version with bug fixes

### Scenario 4: Split Brain / Network Partition

**Symptoms:**
- Different nodes show conflicting cluster state
- Some nodes see node3 as live, others see it as dead
- Node can query itself but not other nodes

**Diagnostic steps:**
```bash
# From node1
cockroach node status --host=node1:26257 --certs-dir=certs

# From node2
cockroach node status --host=node2:26257 --certs-dir=certs

# From node3
cockroach node status --host=node3:26257 --certs-dir=certs

# Compare outputs - if different, partition exists

# Test connectivity matrix
for src in node1 node2 node3; do
  for dst in node1 node2 node3; do
    echo "Testing $src -> $dst"
    ssh $src "nc -zv $dst 26257"
  done
done
```

**Common causes:**
- Asymmetric network routing
- Firewall rules blocking specific node pairs
- Switch/router failure affecting subset of nodes

**Resolution:**
- Fix network infrastructure
- Partition will heal automatically once network restored
- Cluster continues operating with majority partition

## Automated Diagnostic Script

```bash
#!/bin/bash
# diagnose-node-failure.sh - Comprehensive node failure diagnostic

NODE_ID=$1
NODE_HOST=$2
CERTS_DIR=${3:-certs}

if [ -z "$NODE_ID" ] || [ -z "$NODE_HOST" ]; then
  echo "Usage: $0 <node-id> <node-host> [certs-dir]"
  echo "Example: $0 3 node3.example.com certs"
  exit 1
fi

echo "=== CockroachDB Node Failure Diagnostic ==="
echo "Node ID: $NODE_ID"
echo "Node Host: $NODE_HOST"
echo "Timestamp: $(date)"
echo ""

# Check 1: Liveness status
echo "=== Check 1: Liveness Status ==="
cockroach sql --host=localhost:26257 --certs-dir=$CERTS_DIR -e "
  SELECT node_id, is_live, is_available, draining, decommissioning
  FROM crdb_internal.kv_node_liveness
  WHERE node_id = $NODE_ID;"
echo ""

# Check 2: Network connectivity
echo "=== Check 2: Network Connectivity ==="
if nc -zv -w 2 $NODE_HOST 26257 2>&1; then
  echo "✓ Port 26257 accessible"
else
  echo "✗ Port 26257 NOT accessible"
fi
echo ""

# Check 3: Health endpoint
echo "=== Check 3: Health Endpoint ==="
if curl -sf -m 5 http://$NODE_HOST:8080/health?ready=1 > /dev/null 2>&1; then
  echo "✓ Health endpoint responding"
  curl -s http://$NODE_HOST:8080/health?ready=1
else
  echo "✗ Health endpoint NOT responding"
fi
echo ""

# Check 4: Process status
echo "=== Check 4: Process Status on Node ==="
ssh $NODE_HOST "ps aux | grep '[c]ockroach start' || echo 'Process not found'"
echo ""

# Check 5: Recent log errors
echo "=== Check 5: Recent Log Errors ==="
ssh $NODE_HOST "tail -50 /var/lib/cockroach/logs/cockroach.log | grep -i 'error\|fatal\|panic' | tail -10"
echo ""

# Check 6: Resource utilization
echo "=== Check 6: Resource Utilization ==="
ssh $NODE_HOST "echo 'CPU:'; top -b -n 1 | grep cockroach | head -1; \
  echo 'Memory:'; free -h | grep Mem; \
  echo 'Disk:'; df -h | grep -v tmpfs | grep -v devtmpfs"
echo ""

# Check 7: Prometheus metrics
echo "=== Check 7: Key Metrics ==="
curl -s http://$NODE_HOST:8080/_status/vars 2>/dev/null | \
  grep -E "sys_uptime|liveness_heartbeat|capacity_available" | head -10
echo ""

echo "=== Diagnostic Complete ==="
```

**Usage:**
```bash
chmod +x diagnose-node-failure.sh
./diagnose-node-failure.sh 3 node3.example.com certs
```

## Best Practices

1. **Establish baseline metrics**: Know normal CPU, memory, disk I/O for each node
2. **Monitor multiple signals**: Never rely on single indicator
3. **Automate health checks**: Use monitoring system (Prometheus, Datadog, etc.)
4. **Log aggregation**: Centralize logs for easy cross-node correlation
5. **Document common patterns**: Maintain runbook of observed failure modes
6. **Regular testing**: Simulate failures in staging to understand behavior
7. **Quick access to nodes**: Ensure SSH access and credentials are readily available
8. **Time synchronization**: Always ensure NTP is configured and working

## Troubleshooting Complex Scenarios

### Multiple Nodes Showing as Dead

**Check cluster-wide issues:**
```bash
# Check if cluster has quorum
cockroach sql --host=localhost:26257 --certs-dir=certs -e "
  SELECT count(*) FILTER (WHERE is_live = true) as live_nodes,
         count(*) as total_nodes
  FROM crdb_internal.kv_node_liveness;"

# If live_nodes < (total_nodes / 2) + 1, cluster lost quorum
```

**Check for common infrastructure failure:**
- Network switch failure
- Data center power outage
- DNS resolution failure
- NTP server failure causing widespread clock skew

### Node Appears Healthy but Underperforming

**Investigate subtle performance issues:**
```sql
-- Check for high query latency on this node
SELECT
  node_id,
  count,
  mean_latency,
  p99_latency
FROM crdb_internal.node_statement_statistics
WHERE node_id = 3
ORDER BY p99_latency DESC
LIMIT 10;

-- Check for hot ranges on this node
SELECT
  range_id,
  qps,
  writes_per_second
FROM crdb_internal.kv_node_status
WHERE node_id = 3 AND qps > 1000
ORDER BY qps DESC;
```

## Related Documentation

- [Troubleshoot Self-Hosted Setup](https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting)
- [Node Shutdown](https://www.cockroachlabs.com/docs/stable/node-shutdown)
- [Critical Log Messages](https://www.cockroachlabs.com/docs/stable/critical-log-messages)
- [Monitoring and Alerting](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting)
- [cockroach node](https://www.cockroachlabs.com/docs/stable/cockroach-node)

## Summary

Effective node failure diagnosis requires systematic correlation of multiple signals:

1. Start with liveness status from cluster perspective
2. Verify process status and network connectivity
3. Check health endpoints and resource utilization
4. Analyze logs for error patterns
5. Review metrics for performance indicators
6. Correlate findings to identify root cause
7. Apply appropriate remediation based on diagnosis
