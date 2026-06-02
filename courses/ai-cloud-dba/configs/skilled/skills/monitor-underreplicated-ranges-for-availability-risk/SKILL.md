---
name: monitor-underreplicated-ranges-for-availability-risk
description: Monitor under-replicated ranges to identify availability risks in CockroachDB clusters. Use when assessing cluster health, detecting replication issues, or preventing data availability problems during node failures.
metadata:
  domain: Resilience and Failure Handling
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - monitor-unavailable-ranges-for-quorum-loss
    - diagnose-node-failures-using-multiple-signals
    - monitor-replica-rebalancing-after-node-failures
    - verify-cluster-health-between-restarts
  prerequisites:
    - Understanding of replication factor and ranges
    - Basic knowledge of CockroachDB architecture
  estimated_time_minutes: 20
  last_updated: "2026-03-07"
---

# Monitor Under-Replicated Ranges for Availability Risk

## Overview

Under-replicated ranges are ranges that have fewer replicas than the configured replication factor. This condition indicates a degraded state where the cluster has reduced fault tolerance and increased risk of data unavailability if additional nodes fail.

**Critical**: Under-replicated ranges are an early warning signal. While the cluster remains available, it has less resilience to additional failures. Monitoring this metric is essential for maintaining high availability.

## What Are Under-Replicated Ranges?

If a range has fewer replicas than the replication factor (typically 3), the range is "under-replicated". This occurs when:

- A node becomes unresponsive or fails
- A node is being decommissioned
- Disk failures prevent replica creation
- Network partitions isolate nodes
- Rebalancing is in progress after topology changes

**Risk Assessment:**
- **Replication Factor 3 with 2 Replicas**: Can tolerate 0 additional failures (critical risk)
- **Replication Factor 5 with 3-4 Replicas**: Can tolerate 0-1 additional failures (moderate risk)
- **Normal State**: Full replication factor maintained across all ranges

## Detection Methods

### 1. Query System Replication Stats

```sql
-- Check for under-replicated ranges by database
SELECT
  database_name,
  table_name,
  total_ranges,
  under_replicated_ranges,
  CASE
    WHEN under_replicated_ranges > 0
    THEN 'AT RISK'
    ELSE 'HEALTHY'
  END as status
FROM system.replication_stats
WHERE under_replicated_ranges > 0
ORDER BY under_replicated_ranges DESC;
```

**Expected output when healthy:**
```
(0 rows)
```

**Example output during degradation:**
```
  database_name | table_name  | total_ranges | under_replicated_ranges | status
----------------+-------------+--------------+-------------------------+---------
  movr          | rides       |          156 |                      42 | AT RISK
  movr          | users       |           24 |                       8 | AT RISK
```

### 2. Check Overall Cluster Status

```sql
-- Get cluster-wide under-replicated count
SELECT
  count(*) as total_underreplicated_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;  -- Assumes RF=3
```

**Threshold interpretation:**
- 0 ranges: Healthy cluster
- 1-10 ranges: Minor issue, investigate cause
- 10-100 ranges: Moderate concern, take action
- 100+ ranges: Critical situation, immediate attention required

### 3. Identify Specific Under-Replicated Ranges

```sql
-- Find which ranges are under-replicated and their details
SET allow_unsafe_internals = true;

SELECT
  range_id,
  database_name,
  table_name,
  start_pretty,
  array_length(replicas, 1) as current_replicas,
  replicas,
  lease_holder
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3
ORDER BY range_id
LIMIT 20;
```

**Example output:**
```
  range_id | database_name | table_name | start_pretty | current_replicas | replicas  | lease_holder
-----------+---------------+------------+--------------+------------------+-----------+--------------
       156 | movr          | rides      | /156         |                2 | {1,2}     |            1
       157 | movr          | rides      | /157         |                2 | {1,3}     |            1
       158 | movr          | users      | /158         |                1 | {2}       |            2
```

### 4. Monitor via DB Console

**Navigate to Replication Dashboard:**
1. Access DB Console at `https://localhost:8080`
2. Click **Metrics** in left navigation
3. Select **Dashboard > Replication**
4. View **Ranges** section

**Key metrics to watch:**
- **Under-replicated Ranges**: Should be 0
- **Ranges**: Total range count (should be stable)
- **Replicas per Store**: Should be balanced

### 5. Use Prometheus Metrics

```bash
# Query Prometheus endpoint for under-replicated ranges
curl -s http://localhost:8080/_status/vars | grep ranges_underreplicated

# Expected output when healthy:
# ranges_underreplicated 0
```

**Alerting threshold:**
```yaml
# Prometheus alert rule
- alert: UnderReplicatedRanges
  expr: ranges_underreplicated > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Cluster has {{ $value }} under-replicated ranges"
```

### 6. Check Critical Nodes Report

```sql
-- Identify nodes critical for under-replicated ranges
SELECT
  node_id,
  locality,
  ranges,
  is_live,
  is_available
FROM crdb_internal.kv_node_liveness
WHERE is_live = false OR is_available = false;
```

## Monitoring Patterns

### Pattern 1: Scheduled Health Check

```bash
#!/bin/bash
# check-underreplicated.sh

THRESHOLD=0
UNDERREPLICATED=$(cockroach sql --host=localhost:26257 --certs-dir=certs -e "
  SELECT count(*)
  FROM crdb_internal.ranges
  WHERE array_length(replicas, 1) < 3;" -t)

if [ "$UNDERREPLICATED" -gt "$THRESHOLD" ]; then
  echo "WARNING: $UNDERREPLICATED under-replicated ranges detected"
  exit 1
else
  echo "OK: No under-replicated ranges"
  exit 0
fi
```

**Usage:**
```bash
chmod +x check-underreplicated.sh
./check-underreplicated.sh

# Add to cron for periodic checks
echo "*/5 * * * * /path/to/check-underreplicated.sh" | crontab -
```

### Pattern 2: Continuous Monitoring Dashboard

```sql
-- Create monitoring view for ongoing observation
CREATE VIEW IF NOT EXISTS monitoring.replication_health AS
SELECT
  now() as check_time,
  (SELECT count(*) FROM crdb_internal.ranges
   WHERE array_length(replicas, 1) < 3) as underreplicated,
  (SELECT count(*) FROM crdb_internal.ranges
   WHERE array_length(replicas, 1) = 0) as unavailable,
  (SELECT count(*) FROM crdb_internal.ranges) as total_ranges;

-- Query the view
SELECT * FROM monitoring.replication_health;
```

### Pattern 3: Detailed Diagnostic Report

```sql
-- Generate comprehensive under-replication report
WITH range_stats AS (
  SELECT
    database_name,
    table_name,
    count(*) as underreplicated_count,
    array_agg(range_id ORDER BY range_id) as affected_ranges
  FROM crdb_internal.ranges
  WHERE array_length(replicas, 1) < 3
  GROUP BY database_name, table_name
),
node_stats AS (
  SELECT
    node_id,
    is_live,
    is_available,
    ranges
  FROM crdb_internal.kv_node_liveness
)
SELECT
  rs.*,
  (SELECT count(*) FROM node_stats WHERE is_live = false) as dead_nodes,
  (SELECT count(*) FROM node_stats WHERE is_available = false) as unavailable_nodes
FROM range_stats rs
ORDER BY underreplicated_count DESC;
```

## Root Cause Analysis

When under-replicated ranges are detected, investigate these common causes:

### 1. Node Failures

```bash
# Check node status
cockroach node status --host=localhost:26257 --certs-dir=certs

# Look for nodes that are not live
# is_live=false indicates node failure
```

### 2. Decommissioning in Progress

```bash
# Check for ongoing decommissions
cockroach node status --decommission --host=localhost:26257 --certs-dir=certs

# Look for is_decommissioning=true
```

### 3. Insufficient Cluster Capacity

```sql
-- Check if cluster has capacity for replication
SELECT
  node_id,
  used / capacity * 100 as pct_used,
  available / (1024*1024*1024) as available_gb
FROM crdb_internal.kv_store_status
ORDER BY pct_used DESC;
```

**Issue if:** Nodes are >80% full, preventing replica placement

### 4. Zone Configuration Conflicts

```sql
-- Check zone configurations for constraints
SELECT target, config
FROM crdb_internal.zones
WHERE target LIKE '%movr%';
```

**Issue if:** Constraints cannot be satisfied (e.g., requiring 3 replicas across 2 available zones)

### 5. Rebalancing Rate Limits

```sql
-- Check rebalancing settings
SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;
SHOW CLUSTER SETTING kv.snapshot_recovery.max_rate;
```

**Slow recovery if:** Rates are too conservative (default: 32 MiB/s)

## Remediation Actions

### If Under-Replicated Ranges Detected:

**1. Wait for Automatic Recovery (5 minutes)**
```bash
# CockroachDB will automatically attempt to up-replicate
# Monitor progress:
watch -n 10 'cockroach sql --host=localhost:26257 --certs-dir=certs \
  -e "SELECT count(*) FROM crdb_internal.ranges
      WHERE array_length(replicas, 1) < 3;"'
```

**2. Restart Dead Nodes if Temporary**
```bash
# If node failure was temporary, restart the node
cockroach start --certs-dir=certs --store=node3 \
  --advertise-addr=node3:26257 \
  --join=node1:26257,node2:26257,node3:26257
```

**3. Increase Rebalancing Rate (if needed)**
```sql
-- Temporarily increase snapshot rate for faster recovery
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '128 MiB';
SET CLUSTER SETTING kv.snapshot_recovery.max_rate = '128 MiB';

-- Monitor progress, then reset to default
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = DEFAULT;
SET CLUSTER SETTING kv.snapshot_recovery.max_rate = DEFAULT;
```

**4. Add Capacity if Needed**
```bash
# If cluster is at capacity, add new nodes
cockroach start --certs-dir=certs --store=node4 \
  --advertise-addr=node4:26257 \
  --join=node1:26257,node2:26257,node3:26257
```

## Best Practices

1. **Set up automated monitoring**: Configure alerts for `ranges_underreplicated > 0` lasting more than 5 minutes
2. **Establish baselines**: Know your normal range count and replication status
3. **Monitor during maintenance**: Always check before and after node operations
4. **Capacity planning**: Keep nodes below 70% capacity to allow room for rebalancing
5. **Regular health checks**: Include under-replication checks in daily operational reviews
6. **Document thresholds**: Define what constitutes "normal" vs "critical" for your cluster size

## Troubleshooting

### Issue: Under-replicated ranges persist after 10+ minutes

**Diagnosis:**
```sql
-- Check if constraint satisfaction is impossible
SELECT
  database_name,
  table_name,
  array_length(replicas, 1) as current_replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3
LIMIT 5;

-- Check available nodes by locality
SELECT node_id, locality
FROM crdb_internal.kv_node_liveness
WHERE is_live = true AND is_available = true;
```

**Resolution:** Verify zone constraints can be satisfied with available nodes/localities

### Issue: High number of under-replicated ranges (100+)

**Diagnosis:**
```bash
# Check for multiple node failures
cockroach node status --host=localhost:26257 --certs-dir=certs | grep -v "true.*true"
```

**Resolution:** This indicates a critical situation. Restore failed nodes or add replacement capacity immediately.

### Issue: Under-replication during decommission

**Expected behavior:** Temporary under-replication is normal during decommissioning

**Monitor:**
```bash
watch -n 10 'cockroach node status --decommission --host=localhost:26257 --certs-dir=certs'
```

**Wait for:** `membership=decommissioned` before considering complete

## Related Documentation

- [Replication Reports](https://www.cockroachlabs.com/docs/stable/query-replication-reports)
- [Monitoring and Alerting](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting)
- [Replication Dashboard](https://www.cockroachlabs.com/docs/stable/ui-replication-dashboard)
- [Troubleshoot Replication Zones](https://www.cockroachlabs.com/docs/stable/troubleshoot-replication-zones)
- [Cluster API](https://www.cockroachlabs.com/docs/stable/cluster-api)

## Summary

Under-replicated ranges indicate reduced fault tolerance and must be monitored actively. Key takeaways:

- Under-replication means fewer replicas than configured replication factor
- Monitor via `system.replication_stats`, DB Console, or Prometheus metrics
- Automatic recovery typically completes within 5-10 minutes
- Persistent under-replication indicates capacity, configuration, or availability issues
- Set up automated alerts for early detection and rapid response
