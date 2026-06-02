---
name: monitor-cluster-health-during-maintenance
description: Monitor CockroachDB cluster health metrics during maintenance operations including node liveness, range replication status, lease distribution, and query performance to ensure zero downtime and prevent service degradation
metadata:
  domain: Resilience and Failure Handling
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: stable
  cluster_required: true
  min_nodes: 3
  monitoring_tools:
    - DB Console
    - Prometheus endpoint
    - cockroach node status
    - crdb_internal views
  key_metrics:
    - node_liveness
    - under_replicated_ranges
    - unavailable_ranges
    - liveness_heartbeat_latency
    - lease_transfers
  related_skills:
    - perform-rolling-restarts-for-zero-downtime-maintenance
    - verify-cluster-health-between-restarts
    - inspect-range-distribution-replicas-and-leaseholder-placement
    - configure-and-understand-critical-cluster-settings-that-control-failure-detection-and-recovery
---

# Monitor cluster health during maintenance

**Domain**: Resilience and Failure Handling
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you to actively monitor CockroachDB cluster health during maintenance operations such as rolling restarts, version upgrades, node decommissioning, or hardware replacements. You'll learn which metrics indicate healthy vs. degraded cluster state, how to identify issues before they impact applications, and when it's safe to proceed with the next maintenance step.

Effective health monitoring during maintenance is critical to achieving zero downtime. By tracking node liveness, range replication status, lease distribution, and query performance in real-time, you can detect problems early and prevent cascading failures or data unavailability.

**Key Concepts Covered**:
- Node liveness monitoring and heartbeat latency thresholds
- Range replication status (under-replicated, unavailable, over-replicated)
- Lease distribution and transfer monitoring
- Query latency and throughput tracking
- Circuit breaker activation and replica unavailability errors
- Using DB Console, SQL queries, and Prometheus for monitoring

## Instructions

### Prerequisites

Before beginning maintenance operations:

1. **Establish baseline metrics** (normal operating conditions)
2. **Configure monitoring dashboards** (DB Console and/or external tools)
3. **Set up alerting** for critical health indicators
4. **Document expected values** for key metrics

### Monitoring Tool Overview

CockroachDB provides multiple tools for health monitoring:

| Tool | Use Case | Strengths |
|------|----------|-----------|
| **DB Console** | Real-time visual monitoring | Easy to interpret, range details, query insights |
| **SQL Queries** | Programmatic health checks | Scriptable, precise control, automation-friendly |
| **Prometheus Endpoint** | External monitoring | Historical data, alerting, multi-cluster visibility |
| **cockroach node status** | CLI-based checks | Quick status, ranges detail with `--ranges` flag |

### Step 1: Monitor Node Liveness Status

Node liveness is the most fundamental health indicator during maintenance. A node must be both **live** and **available** to participate in the cluster.

**Check node liveness via SQL**:
```sql
-- View all nodes with liveness status
SELECT
  node_id,
  address,
  is_live,
  is_available,
  is_decommissioning,
  membership,
  updated_at
FROM crdb_internal.kv_node_status
ORDER BY node_id;
```

**Expected output (healthy cluster)**:
```
 node_id |   address    | is_live | is_available | is_decommissioning | membership |        updated_at
---------+--------------+---------+--------------+--------------------+------------+---------------------------
    1    | node1:26257  |  true   |     true     |       false        |   active   | 2026-03-07 10:15:23.456
    2    | node2:26257  |  true   |     true     |       false        |   active   | 2026-03-07 10:15:22.891
    3    | node3:26257  |  true   |     true     |       false        |   active   | 2026-03-07 10:15:23.112
```

**Check via CLI**:
```bash
# Quick node status check
cockroach node status --host=localhost:26257

# Expected output shows all nodes with is_live=true
```

**Critical thresholds**:
- **is_live = true**: Node is updating its liveness record
- **is_available = true**: Node can serve traffic
- Both must be true for healthy operation

**During maintenance**:
- When draining a node, `is_live` remains true but node stops accepting new requests
- After shutdown, `is_live` changes to false after heartbeat timeout
- After restart, node should return to `is_live = true` within 30-60 seconds

### Step 2: Monitor Liveness Heartbeat Latency

Heartbeat latency indicates how quickly nodes can update their liveness records. High latency warns of storage or network issues.

**Query heartbeat latency**:
```sql
-- Check liveness heartbeat latency (in nanoseconds)
SELECT
  node_id,
  address,
  is_live,
  liveness_heartbeat_latency_ns / 1000000 as heartbeat_latency_ms
FROM crdb_internal.kv_node_status
ORDER BY heartbeat_latency_ms DESC;
```

**Critical thresholds** (from Essential Alerts):
- **WARNING**: heartbeat_latency > 500ms
- **CRITICAL**: heartbeat_latency > 3000ms (3 seconds)

**Interpretation**:
- High heartbeat latency indicates node is struggling to write to liveness range
- May signal disk I/O issues, network problems, or overload
- Can lead to node being marked as dead if sustained

**Via Prometheus**:
```promql
# Heartbeat latency in seconds
liveness_heartbeatlatency{cluster="production"} > 0.5
```

### Step 3: Monitor Range Replication Status

Range health is critical during maintenance. Under-replicated or unavailable ranges indicate data at risk.

**Check range replication status**:
```sql
-- Count ranges by replication status
SELECT
  count(*) FILTER (WHERE under_replicated = true) as under_replicated,
  count(*) FILTER (WHERE over_replicated = true) as over_replicated,
  count(*) FILTER (WHERE unavailable = true) as unavailable,
  count(*) as total_ranges
FROM crdb_internal.ranges_no_leases;
```

**Expected output (healthy)**:
```
 under_replicated | over_replicated | unavailable | total_ranges
------------------+-----------------+-------------+--------------
        0         |        0        |      0      |     1247
```

**Identify specific problematic ranges**:
```sql
-- List under-replicated ranges with details
SELECT
  range_id,
  start_pretty,
  end_pretty,
  replicas,
  voting_replicas,
  non_voting_replicas,
  learner_replicas
FROM crdb_internal.ranges_no_leases
WHERE under_replicated = true
ORDER BY range_id
LIMIT 20;
```

**Check unavailable ranges** (most critical):
```sql
-- Unavailable ranges prevent queries from succeeding
SELECT
  range_id,
  start_pretty,
  end_pretty,
  replicas,
  unavailable_reason
FROM crdb_internal.ranges_no_leases
WHERE unavailable = true;
```

**Definitions**:
- **Under-replicated**: Fewer replicas than replication factor (e.g., 2 replicas when factor is 3)
- **Over-replicated**: More replicas than replication factor (temporary during rebalancing)
- **Unavailable**: Majority of replicas are on unavailable nodes (critical issue)

**During maintenance**:
- **Immediately after draining**: Under-replicated ranges may appear as leases transfer
- **Expected recovery time**: 1-5 minutes for cluster to re-replicate
- **Safe to proceed**: When under-replicated and unavailable both return to 0

### Step 4: Monitor Lease Distribution

Lease distribution impacts query routing and load balancing. Uneven distribution can cause hotspots.

**Check lease counts per node**:
```sql
-- Count leases by node
SELECT
  lease_holder as node_id,
  count(*) as lease_count
FROM crdb_internal.ranges
GROUP BY lease_holder
ORDER BY node_id;
```

**Expected output (balanced)**:
```
 node_id | lease_count
---------+-------------
    1    |     415
    2    |     418
    3    |     414
```

**Check leases on draining node**:
```sql
-- During drain, this should decrease to 0
SELECT count(*) as leases_remaining
FROM crdb_internal.ranges
WHERE lease_holder = <draining-node-id>;
```

**Via CLI**:
```bash
# Detailed range and lease information
cockroach node status --ranges --host=localhost:26257

# Shows replica count, lease count, and under-replicated ranges per node
```

**During drain**:
- Lease count on draining node should steadily decrease
- Leases transfer to other available nodes
- Drain completes only when lease count reaches 0

### Step 5: Monitor Query Performance Metrics

Query latency and throughput indicate application-level health during maintenance.

**Check recent query latency**:
```sql
-- P50, P90, P99 latency from recent queries
SELECT
  percentile_disc(0.5) WITHIN GROUP (ORDER BY service_lat) as p50_latency_ms,
  percentile_disc(0.9) WITHIN GROUP (ORDER BY service_lat) as p90_latency_ms,
  percentile_disc(0.99) WITHIN GROUP (ORDER BY service_lat) as p99_latency_ms,
  count(*) as query_count
FROM crdb_internal.node_statement_statistics
WHERE aggregated_ts > now() - INTERVAL '5 minutes';
```

**Monitor query errors and retries**:
```sql
-- Check for transaction retry errors
SELECT
  app_name,
  count(*) as retry_count,
  sum(rows_affected) as total_rows
FROM crdb_internal.node_transaction_statistics
WHERE aggregated_ts > now() - INTERVAL '5 minutes'
  AND error NOT LIKE ''
GROUP BY app_name
ORDER BY retry_count DESC;
```

**Check for circuit breaker errors**:
```sql
-- Circuit breaker indicates unavailable ranges being accessed
SELECT
  count(*) as circuit_breaker_errors
FROM crdb_internal.node_statement_statistics
WHERE aggregated_ts > now() - INTERVAL '5 minutes'
  AND last_error LIKE '%ReplicaUnavailableError%';
```

**DB Console - SQL Dashboard**:
- Navigate to: **Metrics > SQL Dashboard**
- Watch graphs for:
  - **SQL Queries**: Queries per second (should remain stable)
  - **Service Latency P99**: Latency percentiles (temporary spikes during drain are normal)
  - **Query Errors**: Should not increase during maintenance

### Step 6: Use DB Console for Visual Monitoring

The DB Console provides real-time visual dashboards optimized for maintenance monitoring.

**Access DB Console**:
```
https://<any-node-address>:8080
```

**Key dashboards to monitor**:

#### Cluster Overview Page
- Navigate to: **Overview**
- Shows:
  - **Node status**: Live vs. Suspect vs. Dead
  - **Capacity Used**: Storage utilization
  - **Replication Status**: Unavailable, under-replicated, over-replicated ranges
  - **Node List**: Uptime, memory, CPU, storage per node

**What to watch**:
- During drain: Node should remain "Live" until shutdown
- After restart: Node should return to "Live" within 1 minute
- Unavailable ranges should never exceed 0 (unless draining)

#### Replication Dashboard
- Navigate to: **Metrics > Dashboard > Replication**
- Shows:
  - **Ranges**: Total range count over time
  - **Replicas per Store**: Distribution across nodes
  - **Leaseholders per Store**: Lease distribution
  - **Range Operations**: Splits, merges, rebalances

**Critical metrics**:
- **Ranges Unavailable**: Must be 0 for production traffic
- **Ranges Under-replicated**: Should return to 0 within 5 minutes after node restart

#### Runtime Dashboard
- Navigate to: **Metrics > Dashboard > Runtime**
- Shows:
  - **Live Node Count**: Should match expected cluster size
  - **Memory Usage**: Per-node memory consumption
  - **CPU Usage**: Per-node CPU utilization

**During maintenance**:
- Live node count temporarily decreases by 1 during node restart
- Memory/CPU should remain within normal operating ranges

#### SQL Dashboard
- Navigate to: **Metrics > Dashboard > SQL**
- Shows:
  - **SQL Connections**: Active connections per node
  - **SQL Queries**: Queries per second
  - **Service Latency**: P50, P90, P99 latency percentiles
  - **Query Errors**: Error rate over time

**Expected behavior**:
- During drain: SQL connections on that node drop to 0
- Query latency may spike briefly during lease transfers
- Query errors should not increase significantly

### Step 7: Set Up Prometheus Alerting (Optional but Recommended)

For production clusters, export metrics to Prometheus for historical tracking and alerting.

**Configure Prometheus scraping**:
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'cockroachdb'
    static_configs:
      - targets:
        - 'node1:8080'
        - 'node2:8080'
        - 'node3:8080'
    scrape_interval: 15s
    metrics_path: '/_status/vars'
```

**Example alert rules**:
```yaml
# alerts.yml
groups:
  - name: cockroachdb_maintenance
    rules:
      # Alert on unavailable ranges
      - alert: RangesUnavailable
        expr: ranges_unavailable > 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "CockroachDB has unavailable ranges"
          description: "{{ $value }} ranges are unavailable"

      # Alert on under-replicated ranges
      - alert: RangesUnderReplicated
        expr: ranges_underreplicated > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CockroachDB has under-replicated ranges"
          description: "{{ $value }} ranges are under-replicated"

      # Alert on high heartbeat latency
      - alert: LivenessHeartbeatSlow
        expr: liveness_heartbeatlatency > 3
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Node liveness heartbeat is slow"
          description: "Heartbeat latency is {{ $value }} seconds"

      # Alert on node down
      - alert: NodeDown
        expr: liveness_livenodes < 3
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "CockroachDB node is down"
          description: "Only {{ $value }} live nodes detected"
```

**Key metrics to export**:
- `liveness_livenodes`: Number of live nodes
- `liveness_heartbeatlatency`: Heartbeat latency (seconds)
- `ranges_unavailable`: Count of unavailable ranges
- `ranges_underreplicated`: Count of under-replicated ranges
- `sql_conns`: Active SQL connections
- `sql_query_count`: Queries per second

## Common Patterns

### Pattern 1: Pre-Maintenance Health Check Script

Run before starting maintenance to establish baseline:

```bash
#!/bin/bash
# pre-maintenance-health-check.sh

HOST="localhost:26257"

echo "=== Pre-Maintenance Health Check ==="
echo

# Check all nodes are live
echo "Node Liveness:"
cockroach sql --host=$HOST --execute \
  "SELECT node_id, address, is_live, is_available
   FROM crdb_internal.kv_node_status
   ORDER BY node_id" \
  --format=table

echo

# Check range replication status
echo "Range Replication Status:"
cockroach sql --host=$HOST --execute \
  "SELECT
     count(*) FILTER (WHERE under_replicated) as under_replicated,
     count(*) FILTER (WHERE unavailable) as unavailable,
     count(*) as total_ranges
   FROM crdb_internal.ranges_no_leases" \
  --format=table

echo

# Check heartbeat latency
echo "Heartbeat Latency:"
cockroach sql --host=$HOST --execute \
  "SELECT node_id,
          liveness_heartbeat_latency_ns / 1000000 as latency_ms
   FROM crdb_internal.kv_node_status
   ORDER BY latency_ms DESC" \
  --format=table

echo

# Verify no critical issues
UNAVAILABLE=$(cockroach sql --host=$HOST --execute \
  "SELECT count(*) FROM crdb_internal.ranges_no_leases WHERE unavailable = true" \
  --format=tsv | tail -n1)

if [ "$UNAVAILABLE" -gt 0 ]; then
  echo "❌ FAIL: $UNAVAILABLE unavailable ranges detected"
  echo "Do not proceed with maintenance!"
  exit 1
fi

echo "✅ PASS: Cluster is healthy for maintenance"
```

### Pattern 2: Continuous Monitoring During Rolling Restart

Monitor health between each node restart:

```bash
#!/bin/bash
# monitor-during-maintenance.sh

HOST="localhost:26257"
NODE_ID=$1

if [ -z "$NODE_ID" ]; then
  echo "Usage: $0 <node-id>"
  exit 1
fi

echo "=== Monitoring node $NODE_ID restart ==="

# Wait for node to become live
echo "Waiting for node $NODE_ID to rejoin..."
while true; do
  IS_LIVE=$(cockroach sql --host=$HOST --execute \
    "SELECT is_live FROM crdb_internal.kv_node_status WHERE node_id = $NODE_ID" \
    --format=tsv 2>/dev/null | tail -n1)

  if [ "$IS_LIVE" = "true" ]; then
    echo "✅ Node $NODE_ID is live"
    break
  fi

  echo "⏳ Waiting for node to rejoin..."
  sleep 5
done

# Wait for under-replicated ranges to clear
echo "Waiting for range re-replication..."
WAIT_COUNT=0
MAX_WAIT=60  # 5 minutes maximum

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  UNDER_REP=$(cockroach sql --host=$HOST --execute \
    "SELECT count(*) FROM crdb_internal.ranges_no_leases WHERE under_replicated = true" \
    --format=tsv 2>/dev/null | tail -n1)

  UNAVAIL=$(cockroach sql --host=$HOST --execute \
    "SELECT count(*) FROM crdb_internal.ranges_no_leases WHERE unavailable = true" \
    --format=tsv 2>/dev/null | tail -n1)

  echo "Under-replicated: $UNDER_REP, Unavailable: $UNAVAIL"

  if [ "$UNDER_REP" -eq 0 ] && [ "$UNAVAIL" -eq 0 ]; then
    echo "✅ All ranges fully replicated and available"
    break
  fi

  WAIT_COUNT=$((WAIT_COUNT + 1))
  sleep 5
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
  echo "⚠️  WARNING: Ranges still under-replicated after 5 minutes"
  echo "Manual investigation required before proceeding"
  exit 1
fi

echo "✅ Node $NODE_ID restart verified - safe to proceed"
```

### Pattern 3: Real-Time Dashboard with watch Command

Use `watch` to continuously display health metrics:

```bash
# Monitor node status every 5 seconds
watch -n 5 'cockroach node status --host=localhost:26257'

# Monitor range replication every 10 seconds
watch -n 10 'cockroach sql --host=localhost:26257 --execute \
  "SELECT count(*) FILTER (WHERE under_replicated) as under_rep,
          count(*) FILTER (WHERE unavailable) as unavail
   FROM crdb_internal.ranges_no_leases" --format=table'

# Monitor query latency every 30 seconds
watch -n 30 'cockroach sql --host=localhost:26257 --execute \
  "SELECT percentile_disc(0.99) WITHIN GROUP (ORDER BY service_lat) as p99_latency_ms
   FROM crdb_internal.node_statement_statistics
   WHERE aggregated_ts > now() - INTERVAL '\''5 minutes'\''" --format=table'
```

### Pattern 4: Post-Maintenance Validation

Verify cluster health after all nodes restarted:

```bash
#!/bin/bash
# post-maintenance-validation.sh

HOST="localhost:26257"
EXPECTED_NODES=5

echo "=== Post-Maintenance Validation ==="

# Verify all nodes are live
LIVE_NODES=$(cockroach sql --host=$HOST --execute \
  "SELECT count(*) FROM crdb_internal.kv_node_status
   WHERE is_live = true AND is_available = true" \
  --format=tsv | tail -n1)

echo "Live nodes: $LIVE_NODES / $EXPECTED_NODES"

if [ "$LIVE_NODES" -ne "$EXPECTED_NODES" ]; then
  echo "❌ FAIL: Not all nodes are live"
  exit 1
fi

# Verify no replication issues
UNDER_REP=$(cockroach sql --host=$HOST --execute \
  "SELECT count(*) FROM crdb_internal.ranges_no_leases WHERE under_replicated = true" \
  --format=tsv | tail -n1)

UNAVAIL=$(cockroach sql --host=$HOST --execute \
  "SELECT count(*) FROM crdb_internal.ranges_no_leases WHERE unavailable = true" \
  --format=tsv | tail -n1)

echo "Under-replicated ranges: $UNDER_REP"
echo "Unavailable ranges: $UNAVAIL"

if [ "$UNDER_REP" -gt 0 ] || [ "$UNAVAIL" -gt 0 ]; then
  echo "❌ FAIL: Replication issues detected"
  exit 1
fi

# Check cluster version (if upgrade was performed)
echo
echo "Cluster version:"
cockroach sql --host=$HOST --execute "SHOW CLUSTER SETTING version" --format=table

echo
echo "✅ PASS: All post-maintenance validations successful"
```

## Troubleshooting

### Issue: Unavailable Ranges Not Clearing

**Symptom**: Unavailable ranges persist after node restart

**Diagnosis**:
```sql
-- Identify which ranges are unavailable
SELECT
  range_id,
  start_pretty,
  end_pretty,
  replicas,
  voting_replicas
FROM crdb_internal.ranges_no_leases
WHERE unavailable = true;

-- Check node status
SELECT node_id, is_live, is_available, membership
FROM crdb_internal.kv_node_status;
```

**Common causes**:
1. **Insufficient live nodes**: Need majority of replicas available
   - 3-replica range needs 2+ live nodes
   - 5-replica range needs 3+ live nodes

2. **Network partition**: Nodes can't communicate
```bash
# Test connectivity from each node
telnet <other-node> 26257
```

3. **Clock skew**: Nodes have clock drift > 500ms
```bash
# Check clock offsets
cockroach debug time-travel --host=<node>:26257
```

**Solutions**:
- Ensure majority of nodes are live and available
- Fix network connectivity issues
- Synchronize clocks with NTP
- Wait for automatic recovery (up-replication takes 5-10 minutes)

### Issue: Under-Replicated Ranges Increasing During Maintenance

**Symptom**: Under-replicated count grows instead of decreasing

**Diagnosis**:
```sql
-- Check if cluster has capacity for re-replication
SELECT
  node_id,
  used_capacity_bytes,
  available_capacity_bytes,
  (available_capacity_bytes::FLOAT / (used_capacity_bytes + available_capacity_bytes)) * 100 as pct_available
FROM crdb_internal.kv_node_status;
```

**Common causes**:
1. **Insufficient storage space**: Nodes can't accept new replicas
   - Need 20%+ free space for rebalancing

2. **Too many concurrent node drains**: Multiple nodes down simultaneously
   - Only drain one node at a time

3. **Replication too slow**: `server.time_until_store_dead` set too low
```sql
-- Check current setting
SHOW CLUSTER SETTING server.time_until_store_dead;

-- Increase if needed (default 5m)
SET CLUSTER SETTING server.time_until_store_dead = '10m';
```

**Solutions**:
- Free up disk space on nodes
- Slow down maintenance pace (wait longer between nodes)
- Increase `server.time_until_store_dead` for maintenance window

### Issue: High Heartbeat Latency During Maintenance

**Symptom**: `liveness_heartbeat_latency` exceeds 500ms

**Diagnosis**:
```sql
-- Identify nodes with high latency
SELECT
  node_id,
  address,
  liveness_heartbeat_latency_ns / 1000000 as latency_ms
FROM crdb_internal.kv_node_status
WHERE liveness_heartbeat_latency_ns > 500000000  -- 500ms in nanoseconds
ORDER BY latency_ms DESC;
```

**Common causes**:
1. **Disk I/O saturation**: Liveness writes competing with rebalancing
```bash
# Check disk I/O wait
iostat -x 5
```

2. **Network congestion**: High lease transfer activity
```bash
# Monitor network bandwidth
iftop -i <interface>
```

3. **CPU exhaustion**: Node overloaded during maintenance
```bash
# Check CPU usage
top -bn1 | grep cockroach
```

**Solutions**:
- Slow down maintenance operations
- Temporarily reduce application load
- Increase hardware resources (if consistently high)
- Consider scheduled maintenance during low-traffic periods

### Issue: Query Latency Spikes During Drain

**Symptom**: P99 latency increases during node drain

**Expected behavior**: Temporary latency spikes during lease transfers are normal

**Diagnosis**:
```sql
-- Check if spikes correlate with lease transfers
SELECT
  metadata -> 'desc' ->> 'range_id' as range_id,
  timestamp,
  "eventType",
  info
FROM system.eventlog
WHERE timestamp > now() - INTERVAL '10 minutes'
  AND "eventType" = 'lease_transferred'
ORDER BY timestamp DESC
LIMIT 50;
```

**Mitigation strategies**:

1. **Use follower reads** for read-heavy workloads:
```sql
-- Avoid leaseholder dependency
SELECT * FROM table AS OF SYSTEM TIME follower_read_timestamp();
```

2. **Increase application timeout thresholds**:
```python
# Example with psycopg2
conn = psycopg2.connect(
    host="localhost",
    port=26257,
    statement_timeout=60000  # 60 seconds during maintenance
)
```

3. **Slow down drain pace**:
```sql
-- Allow more time for lease transfers
SET CLUSTER SETTING server.shutdown.drain_wait = '15m';
```

4. **Schedule during low-traffic windows**:
   - Minimize user impact during peak latency

## Best Practices

### 1. Establish Baseline Metrics Before Maintenance

Before starting any maintenance:
- Record normal node liveness values
- Document typical range replication counts
- Measure baseline query latency (P50, P90, P99)
- Capture lease distribution across nodes

**Why**: Baselines help you identify deviations and determine when cluster has returned to normal.

### 2. Monitor Continuously, Not Just Pre/Post

Health monitoring must be **active and continuous** during maintenance:
- Check metrics between each node restart
- Don't proceed to next node until current node is stable
- Watch for degradation trends, not just point-in-time snapshots

**Anti-pattern**: Only checking health before starting and after completing maintenance.

### 3. Set Up Automated Alerting

Manual monitoring doesn't scale for large clusters or off-hours maintenance:
- Configure Prometheus/Grafana alerts for critical metrics
- Set up PagerDuty/Opsgenie integration for on-call engineers
- Use DB Console email alerts for unavailable ranges

**Key alerts**:
- Unavailable ranges > 0 (critical)
- Under-replicated ranges > 100 (warning)
- Heartbeat latency > 3s (critical)
- Node count < expected (critical)

### 4. Use DB Console for Visual Correlation

While SQL queries provide precise values, DB Console graphs show **trends over time**:
- Easier to spot gradual degradation
- Visual correlation between metrics (e.g., node restart → range under-replication → recovery)
- Historical view helps identify slow recovery

**Recommended**: Keep DB Console open during maintenance for real-time visual feedback.

### 5. Document Your Monitoring Runbook

Create a standardized monitoring checklist for your team:
```
[ ] All nodes show is_live = true
[ ] Heartbeat latency < 500ms for all nodes
[ ] Under-replicated ranges = 0
[ ] Unavailable ranges = 0
[ ] Lease distribution balanced (±10%)
[ ] Query P99 latency within 2x baseline
[ ] No circuit breaker errors in last 5 minutes
```

**Benefits**: Consistency across team members, training new operators, audit trail.

### 6. Know When to Abort Maintenance

Define clear abort criteria before starting:
- Unavailable ranges persist > 10 minutes
- Under-replicated ranges increasing instead of decreasing
- Query error rate exceeds threshold
- Multiple nodes showing heartbeat latency > 3s

**If abort criteria met**: Stop maintenance, restore cluster to stable state, investigate root cause.

### 7. Maintain Historical Metrics

Keep metrics history outside the cluster:
- Export to Prometheus/Datadog/CloudWatch
- Retain for 30+ days minimum
- Use for capacity planning and trend analysis

**Why**: If cluster becomes unavailable, DB Console is also unavailable. External metrics remain accessible.

### 8. Test Monitoring in Non-Production

Before relying on monitoring in production maintenance:
- Verify alerts trigger correctly in staging
- Practice interpreting metrics during simulated failures
- Validate your monitoring scripts and dashboards

## Related Skills

- **perform-rolling-restarts-for-zero-downtime-maintenance**: Apply health monitoring during restarts
- **verify-cluster-health-between-restarts**: Comprehensive validation procedures
- **inspect-range-distribution-replicas-and-leaseholder-placement**: Deep dive into range distribution metrics
- **configure-and-understand-critical-cluster-settings-that-control-failure-detection-and-recovery**: Tune failure detection thresholds

## Additional Resources

- [Monitoring and Alerting](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting) - Comprehensive monitoring guide
- [Essential Alerts for Self-Hosted Deployments](https://www.cockroachlabs.com/docs/stable/essential-alerts-self-hosted) - Recommended alert thresholds
- [Common Issues to Monitor](https://www.cockroachlabs.com/docs/stable/common-issues-to-monitor) - Known health indicators
- [DB Console Overview](https://www.cockroachlabs.com/docs/dev/ui-overview) - Dashboard navigation
- [Replication Dashboard](https://www.cockroachlabs.com/docs/stable/ui-replication-dashboard) - Range replication metrics
- [Cluster Overview Page](https://www.cockroachlabs.com/docs/stable/ui-cluster-overview-page) - Node status and health
- [Replication Reports](https://www.cockroachlabs.com/docs/stable/query-replication-reports) - SQL-based range queries
