---
name: monitor-unavailable-ranges-for-quorum-loss
description: Monitor unavailable ranges that have lost quorum and cannot serve reads or writes. Use when detecting critical cluster failures, assessing data availability during outages, or responding to majority replica loss.
metadata:
  domain: Resilience and Failure Handling
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - monitor-underreplicated-ranges-for-availability-risk
    - restore-cluster-quorum-after-majority-failure
    - diagnose-node-failures-using-multiple-signals
    - understand-quorum-requirements-for-resilience
  prerequisites:
    - Understanding of Raft consensus and quorum
    - Knowledge of replication factor requirements
  estimated_time_minutes: 25
  last_updated: "2026-03-07"
---

# Monitor Unavailable Ranges for Quorum Loss

## Overview

Unavailable ranges are ranges that have lost quorum due to a majority of their replicas being inaccessible. Unlike under-replicated ranges (which are degraded but functional), unavailable ranges **cannot serve any requests** and represent actual data unavailability.

**Critical**: Unavailable ranges indicate a cluster outage affecting specific data. This is a production-critical condition requiring immediate investigation and remediation.

## Understanding Quorum Loss

### Quorum Requirements

CockroachDB uses the Raft consensus protocol, which requires a majority (quorum) of replicas to be available:

**Replication Factor 3**: Requires 2 of 3 replicas (can tolerate 1 failure)
**Replication Factor 5**: Requires 3 of 5 replicas (can tolerate 2 failures)
**Replication Factor 7**: Requires 4 of 7 replicas (can tolerate 3 failures)

**Formula**: `(Replication Factor - 1) / 2` = maximum tolerable failures

### What Causes Unavailable Ranges?

A range becomes unavailable when a majority of its replicas are unreachable:

**With RF=3:**
- 2 or more replicas down → Range unavailable
- All 3 replicas down → Range unavailable

**Common causes:**
- Multiple simultaneous node failures
- Network partition isolating majority of replicas
- Cascading failures across multiple nodes
- Zone/region outage affecting majority of replicas
- Decommissioning errors removing too many nodes
- Disk failures on nodes hosting multiple replicas

### Impact on Applications

When ranges are unavailable:

```
ERROR: result is ambiguous (unavailable replicas)
ERROR: the transaction is retryable, but you should not retry it because it was already aborted
ERROR: range unavailable: unable to reach quorum
```

**Effects:**
- Reads to affected ranges: **Fail immediately**
- Writes to affected ranges: **Fail immediately**
- Queries spanning unavailable ranges: **Partial or complete failure**
- Transactions touching unavailable ranges: **Abort**

## Detection Methods

### 1. Query for Unavailable Ranges

```sql
-- Check for unavailable ranges using system reports
SELECT
  database_name,
  table_name,
  total_ranges,
  unavailable_ranges,
  CASE
    WHEN unavailable_ranges > 0
    THEN 'CRITICAL - DATA UNAVAILABLE'
    ELSE 'AVAILABLE'
  END as status
FROM system.replication_stats
WHERE unavailable_ranges > 0
ORDER BY unavailable_ranges DESC;
```

**Expected output when healthy:**
```
(0 rows)
```

**Example during outage:**
```
  database_name | table_name | total_ranges | unavailable_ranges |          status
----------------+------------+--------------+--------------------+---------------------------
  movr          | rides      |          156 |                 42 | CRITICAL - DATA UNAVAILABLE
  defaultdb     | system     |           24 |                  3 | CRITICAL - DATA UNAVAILABLE
```

### 2. Count Unavailable Ranges Cluster-Wide

```sql
-- Get total count of unavailable ranges
SET allow_unsafe_internals = true;

SELECT
  count(*) as total_unavailable_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) = 0;
```

**Severity interpretation:**
- **0 ranges**: Cluster fully available
- **1+ ranges**: CRITICAL - Data unavailable, immediate action required
- **Any non-zero count**: Production incident

### 3. Identify Specific Unavailable Ranges

```sql
-- Find which ranges are unavailable
SET allow_unsafe_internals = true;

SELECT
  range_id,
  database_name,
  table_name,
  start_pretty,
  end_pretty,
  array_length(replicas, 1) as replica_count,
  replicas,
  lease_holder
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) = 0
ORDER BY database_name, table_name, range_id
LIMIT 50;
```

**Example output:**
```
  range_id | database_name | table_name | start_pretty | end_pretty | replica_count | replicas | lease_holder
-----------+---------------+------------+--------------+------------+---------------+----------+--------------
       156 | movr          | rides      | /156         | /157       |             0 | {}       | NULL
       157 | movr          | rides      | /157         | /158       |             0 | {}       | NULL
       158 | movr          | users      | /158         | /159       |             0 | {}       | NULL
```

**Interpretation:** Empty `replicas` array and NULL `lease_holder` confirm total unavailability.

### 4. Monitor via DB Console

**Navigate to Replication Dashboard:**
1. Access DB Console at `https://localhost:8080`
2. Click **Metrics** → **Dashboard** → **Replication**
3. View **Ranges** section

**Key metrics:**
- **Unavailable Ranges**: Must be 0 for full availability
- **Under-replicated Ranges**: Leading indicator (should also be 0)

**Alert threshold:**
- Any non-zero value for unavailable ranges = CRITICAL incident

### 5. Prometheus Metrics Monitoring

```bash
# Query Prometheus endpoint for unavailable ranges
curl -s http://localhost:8080/_status/vars | grep ranges_unavailable

# Expected output when healthy:
# ranges_unavailable 0

# During outage:
# ranges_unavailable 42
```

**Critical alerting rule:**
```yaml
# Prometheus alert - highest priority
- alert: UnavailableRanges
  expr: ranges_unavailable > 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "CRITICAL: {{ $value }} ranges are unavailable (quorum lost)"
    description: "Data is unavailable. Immediate action required."
```

### 6. Check Node Availability

```sql
-- Identify which nodes are down
SELECT
  node_id,
  locality,
  is_live,
  is_available,
  ranges,
  CASE
    WHEN is_live = false OR is_available = false
    THEN 'DOWN'
    ELSE 'UP'
  END as status
FROM crdb_internal.kv_node_liveness
ORDER BY node_id;
```

**Pattern recognition:**
- If 2+ nodes DOWN in 3-node cluster → Expect unavailable ranges
- If 3+ nodes DOWN in 5-node cluster → Expect unavailable ranges

### 7. Critical Nodes Endpoint (API)

```bash
# Use Cluster API to check critical status
curl -k --cert certs/client.root.crt --key certs/client.root.key \
  https://localhost:8080/api/v2/nodes/

# Look for criticalNodes field in response
```

**Example response snippet:**
```json
{
  "nodes": [...],
  "criticalNodes": [1, 2],
  "unavailableRanges": 42
}
```

## Monitoring Patterns

### Pattern 1: Real-Time Availability Check

```bash
#!/bin/bash
# check-availability.sh

UNAVAILABLE=$(cockroach sql --host=localhost:26257 --certs-dir=certs -e "
  SELECT count(*)
  FROM crdb_internal.ranges
  WHERE array_length(replicas, 1) = 0;" -t)

if [ "$UNAVAILABLE" -gt 0 ]; then
  echo "CRITICAL: $UNAVAILABLE ranges are UNAVAILABLE"
  echo "Data is currently inaccessible. Immediate action required."
  exit 2
else
  echo "OK: All ranges are available"
  exit 0
fi
```

**Usage:**
```bash
chmod +x check-availability.sh
./check-availability.sh

# Integrate with monitoring system
# Nagios/Icinga check with CRITICAL severity
```

### Pattern 2: Comprehensive Availability Report

```sql
-- Generate detailed availability status report
WITH availability_summary AS (
  SELECT
    count(*) FILTER (WHERE array_length(replicas, 1) = 0) as unavailable,
    count(*) FILTER (WHERE array_length(replicas, 1) < 3) as underreplicated,
    count(*) as total_ranges
  FROM crdb_internal.ranges
),
node_status AS (
  SELECT
    count(*) FILTER (WHERE is_live = false) as dead_nodes,
    count(*) FILTER (WHERE is_available = false) as unavailable_nodes,
    count(*) as total_nodes
  FROM crdb_internal.kv_node_liveness
)
SELECT
  a.unavailable as unavailable_ranges,
  a.underreplicated as underreplicated_ranges,
  a.total_ranges,
  n.dead_nodes,
  n.unavailable_nodes,
  n.total_nodes,
  CASE
    WHEN a.unavailable > 0 THEN 'CRITICAL - DATA UNAVAILABLE'
    WHEN a.underreplicated > 0 THEN 'WARNING - DEGRADED'
    ELSE 'HEALTHY'
  END as overall_status
FROM availability_summary a, node_status n;
```

**Example healthy output:**
```
  unavailable_ranges | underreplicated_ranges | total_ranges | dead_nodes | unavailable_nodes | total_nodes | overall_status
---------------------+------------------------+--------------+------------+-------------------+-------------+-----------------
                   0 |                      0 |         1247 |          0 |                 0 |           5 | HEALTHY
```

**Example during outage:**
```
  unavailable_ranges | underreplicated_ranges | total_ranges | dead_nodes | unavailable_nodes | total_nodes | overall_status
---------------------+------------------------+--------------+------------+-------------------+-------------+-------------------------
                  42 |                     89 |         1247 |          2 |                 2 |           5 | CRITICAL - DATA UNAVAILABLE
```

### Pattern 3: Continuous Monitoring with Alerting

```bash
#!/bin/bash
# monitor-availability.sh - Run as background daemon or cron

while true; do
  UNAVAILABLE=$(cockroach sql --host=localhost:26257 --certs-dir=certs -e "
    SELECT count(*) FROM crdb_internal.ranges
    WHERE array_length(replicas, 1) = 0;" -t 2>/dev/null)

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  if [ "$UNAVAILABLE" -gt 0 ]; then
    # Send alert via PagerDuty/Slack/Email
    echo "[$TIMESTAMP] CRITICAL: $UNAVAILABLE unavailable ranges" | \
      mail -s "CockroachDB CRITICAL: Data Unavailable" ops@example.com

    # Log to syslog
    logger -p local0.crit -t cockroachdb \
      "CRITICAL: $UNAVAILABLE ranges unavailable"
  fi

  sleep 60  # Check every minute
done
```

## Root Cause Analysis

When unavailable ranges are detected, immediately investigate:

### 1. Check for Multiple Node Failures

```bash
# Identify all failed nodes
cockroach node status --host=localhost:26257 --certs-dir=certs

# Count failures
cockroach sql --host=localhost:26257 --certs-dir=certs -e "
  SELECT count(*) as failed_nodes
  FROM crdb_internal.kv_node_liveness
  WHERE is_live = false OR is_available = false;"
```

**Pattern:** If failures ≥ (RF+1)/2, expect unavailable ranges

### 2. Check Node Distribution of Affected Ranges

```sql
-- Before the failure, where were the replicas?
-- This requires checking logs or previous range reports
SELECT
  range_id,
  database_name,
  table_name,
  replicas  -- Will be empty for unavailable ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) = 0
LIMIT 20;
```

### 3. Review Recent Changes

```bash
# Check cluster logs for recent events
grep -i "node.*down\|partition\|disconnect" cockroach-data/logs/*.log | tail -50

# Look for patterns:
# - Multiple nodes failing simultaneously
# - Network connectivity errors
# - Disk I/O errors
```

### 4. Network Partition Detection

```bash
# From each node, check connectivity to others
for node in node1 node2 node3; do
  echo "Testing from $node:"
  cockroach node status --host=$node:26257 --certs-dir=certs
done

# Compare outputs - if inconsistent, network partition exists
```

### 5. Check Locality Distribution

```sql
-- Verify replica placement across localities
SELECT
  locality,
  count(*) as node_count,
  count(*) FILTER (WHERE is_live = true) as live_nodes
FROM crdb_internal.kv_node_liveness
GROUP BY locality;
```

**Issue if:** Entire locality is down and ranges required majority in that locality

## Immediate Response Actions

### Action 1: Assess Scope of Impact

```sql
-- Determine which tables/databases are affected
SELECT
  database_name,
  table_name,
  unavailable_ranges
FROM system.replication_stats
WHERE unavailable_ranges > 0
ORDER BY unavailable_ranges DESC;
```

**Prioritize recovery** based on business criticality of affected tables.

### Action 2: Attempt to Restore Failed Nodes

```bash
# If nodes failed due to temporary issues, restart them
# Example: Restart node 2 and node 3
cockroach start --certs-dir=certs --store=node2 \
  --advertise-addr=node2:26257 \
  --join=node1:26257,node2:26257,node3:26257 &

cockroach start --certs-dir=certs --store=node3 \
  --advertise-addr=node3:26257 \
  --join=node1:26257,node2:26257,node3:26257 &

# Monitor recovery
watch -n 5 'cockroach sql --host=localhost:26257 --certs-dir=certs \
  -e "SELECT count(*) FROM crdb_internal.ranges
      WHERE array_length(replicas, 1) = 0;"'
```

**Expected:** Unavailable ranges drop to 0 within 1-2 minutes after quorum restored.

### Action 3: If Nodes Cannot Be Restored

**For temporary outages:**
- Add replacement nodes to restore capacity
- Wait for automatic up-replication (requires quorum on remaining ranges)

**For permanent failures (majority of cluster lost):**
- **Restore from backup** (see `restore-cluster-quorum-after-majority-failure`)
- This is a disaster recovery scenario

### Action 4: Verify Recovery

```sql
-- Confirm all ranges are available
SELECT
  count(*) FILTER (WHERE array_length(replicas, 1) = 0) as unavailable,
  count(*) FILTER (WHERE array_length(replicas, 1) < 3) as underreplicated,
  count(*) as total
FROM crdb_internal.ranges;
```

**Success criteria:**
- `unavailable = 0`
- `underreplicated` declining toward 0
- Applications can execute queries successfully

## Prevention Strategies

### 1. Configure Proper Replication Factor

```sql
-- For production, use RF=5 to tolerate 2 failures
ALTER RANGE default CONFIGURE ZONE USING num_replicas = 5;

-- For multi-region, set survival goals
ALTER DATABASE movr SET PRIMARY REGION "us-east1";
ALTER DATABASE movr SURVIVE REGION FAILURE;
```

### 2. Distribute Replicas Across Failure Domains

```sql
-- Configure zone constraints to spread replicas
ALTER RANGE default CONFIGURE ZONE USING
  num_replicas = 5,
  constraints = '{"+region=us-east1":2, "+region=us-west1":2, "+region=us-central1":1}';
```

### 3. Monitor Proactively

```yaml
# Set up alerts for early warning
- alert: UnderReplicatedRanges
  expr: ranges_underreplicated > 0
  for: 5m
  labels:
    severity: warning

- alert: UnavailableRanges
  expr: ranges_unavailable > 0
  for: 1m
  labels:
    severity: critical
```

### 4. Implement Regular Backups

```sql
-- Daily full backups with revision history
CREATE SCHEDULE daily_backup
FOR BACKUP INTO 's3://backups/cluster?AUTH=implicit'
WITH revision_history
RECURRING '@daily'
WITH SCHEDULE OPTIONS first_run = 'now';
```

### 5. Test Failure Scenarios

```bash
# Chaos engineering: Test failure tolerance in staging
# Kill 1 node and verify cluster remains available
# Kill 2 nodes in 5-node cluster and verify

# Document expected behavior and recovery procedures
```

## Best Practices

1. **Zero tolerance for unavailable ranges**: Any non-zero count is a critical incident
2. **Immediate escalation**: Alert on-call teams within 1 minute of detection
3. **Plan for majority failure**: Have documented disaster recovery procedures
4. **Regular testing**: Verify backup/restore procedures quarterly
5. **Capacity planning**: Ensure RF allows for expected failure scenarios
6. **Multi-region deployment**: Distribute across failure domains for resilience
7. **Monitoring redundancy**: Monitor from multiple independent systems

## Troubleshooting

### Issue: Unavailable ranges after single node failure in 3-node cluster

**Diagnosis:**
```sql
-- Check replica distribution before failure
-- If all replicas of a range were on only 2 nodes, and both failed, range is unavailable
```

**Resolution:** This indicates insufficient replica distribution. Use RF=5 or better locality distribution.

### Issue: Ranges unavailable but all nodes appear live

**Diagnosis:**
```bash
# Check for network partition
# Each node may think others are down
cockroach node status --host=node1:26257 --certs-dir=certs
cockroach node status --host=node2:26257 --certs-dir=certs
```

**Resolution:** Resolve network partition. Ranges recover automatically once partition heals.

### Issue: Cannot query cluster to check for unavailable ranges

**Diagnosis:** If cluster is completely unavailable, SQL queries will fail.

**Resolution:**
- Use Prometheus metrics endpoint (may still be accessible): `curl http://localhost:8080/_status/vars`
- Check logs on individual nodes
- If majority of cluster lost, restore from backup

## Related Documentation

- [Replication Reports](https://www.cockroachlabs.com/docs/stable/query-replication-reports)
- [Troubleshoot Self-Hosted Setup](https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting)
- [Replication Layer](https://www.cockroachlabs.com/docs/stable/architecture/replication-layer)
- [Disaster Recovery Planning](https://www.cockroachlabs.com/docs/stable/disaster-recovery-planning)
- [Quorum](https://www.cockroachlabs.com/glossary/distributed-db/quorum/)

## Summary

Unavailable ranges represent actual data unavailability and require immediate action. Key points:

- Unavailable ranges have lost quorum (majority of replicas inaccessible)
- Any non-zero count is a critical production incident
- Monitor via `system.replication_stats`, DB Console, or Prometheus
- Immediate response: Restore failed nodes or restore from backup
- Prevention: Use appropriate RF, distribute across failure domains, monitor proactively
