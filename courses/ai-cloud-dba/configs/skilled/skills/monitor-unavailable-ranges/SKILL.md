---
name: monitor-unavailable-ranges
description: Can detect unavailable ranges that have lost quorum and cannot serve reads or writes using DB Console Replication page or system.replication_stats table. Immediate critical alert requiring operator intervention to restore quorum or recover from disaster. Use when user says "monitor unavailable ranges", "check range health", "quorum loss", "unavailable ranges".
metadata:
  domain: Monitoring and Alerting
  tags: replication, cluster-operations, monitoring, disaster-recovery
  phase: 1
  version: 1.1.0
  min_crdb_version: 26.1.0
  complexity: apply
  status: complete
---

# Monitor Unavailable Ranges

Detect and respond to unavailable ranges that have lost quorum and cannot serve reads or writes. This is a **critical cluster emergency** requiring immediate operator intervention.

## Overview

### What Are Unavailable Ranges?

An **unavailable range** is a range that has lost quorum and cannot serve reads or writes. In CockroachDB:

- Each range maintains multiple replicas (default: 3) across nodes
- Quorum requires a majority of replicas (2 out of 3) to be available
- When quorum is lost, the range becomes **unavailable**
- Unavailable ranges block all operations on affected data

### Impact of Unavailable Ranges

**Critical Severity**:
- Reads and writes to affected data **fail immediately**
- Transactions touching unavailable ranges cannot commit
- Applications experience errors and outages
- Data is inaccessible until quorum is restored

**Scope**:
- Single range: Specific table rows or index entries unavailable
- Multiple ranges: Partial or complete database unavailability
- System ranges: Cluster metadata operations affected

### Common Causes of Quorum Loss

1. **Multiple Node Failures**: Network partitions, hardware failures, cloud outages, simultaneous crashes
2. **Decommissioning Errors**: Removing nodes before replication completes, forcing decommission
3. **Disk Failures**: Correlated disk failures, storage outages, filesystem corruption
4. **Configuration Issues**: Insufficient replicas, unsatisfiable constraints, incorrect replication factor
5. **Operational Mistakes**: Manual data directory deletion, terminating without draining

## Instructions

### Prerequisites

All queries in this skill require elevated permissions:

```sql
SET allow_unsafe_internals = true;
```

**Note**: This setting grants access to internal cluster tables and should only be used by cluster administrators.

### Important: v26.1.0 Behavior

In CockroachDB v26.1.0, unavailable ranges are tracked at the **zone level** in `system.replication_stats`, not at the individual range level in `crdb_internal.ranges`. This means:

- You can determine **how many** unavailable ranges exist per zone
- You can identify **which zones/tables** are affected
- You **cannot** query individual unavailable range IDs or their specific replica locations
- The `system.replication_stats` table is the authoritative source for replication health metrics

This zone-level aggregation is sufficient for monitoring and alerting purposes.

### Step 1: Detect Unavailable Ranges

#### Using DB Console (Recommended)

Navigate to **Replication Dashboard**:

1. Open DB Console: `http://<node-address>:8080`
2. Go to **Metrics** → **Replication**
3. Check **Unavailable Ranges** graph
4. View **Ranges** page for detailed status

**Critical Indicators**:
- Unavailable ranges count > 0 (red alert)
- Under-replicated ranges increasing
- Replica quorum problems

#### Using SQL Queries

**Important**: In v26.1.0, unavailable ranges are tracked at the **zone level** in `system.replication_stats`, not at the individual range level.

**Quick check for unavailable ranges**:

```sql
SET allow_unsafe_internals = true;

-- Quick check for unavailable ranges (cluster-wide)
SELECT SUM(unavailable_ranges) AS unavailable_ranges
FROM system.replication_stats;
```

**Detailed unavailable range information by zone**:

```sql
-- View replication health by zone with detailed context
SELECT
  z.zone_id,
  z.target,
  z.database_name,
  z.schema_name,
  z.table_name,
  rs.unavailable_ranges,
  rs.under_replicated_ranges,
  rs.over_replicated_ranges,
  rs.total_ranges
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE rs.unavailable_ranges > 0
ORDER BY rs.unavailable_ranges DESC;
```

**Find affected tables and databases**:

```sql
-- View unavailable ranges by database and table
SELECT
  z.database_name,
  z.schema_name,
  z.table_name,
  z.target,
  rs.unavailable_ranges,
  rs.total_ranges,
  round(rs.unavailable_ranges::FLOAT / NULLIF(rs.total_ranges, 0) * 100, 2) AS pct_unavailable
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE rs.unavailable_ranges > 0
ORDER BY rs.unavailable_ranges DESC;
```

#### Using SHOW RANGES

```sql
-- Check specific database for range details
SHOW RANGES FROM DATABASE mydb WITH DETAILS;

-- Check specific table
SHOW RANGES FROM TABLE mytable WITH DETAILS;

-- Look for ranges with fewer replicas than expected
-- Note: Individual range unavailability status not directly available
```

### Step 2: Assess the Situation

**Determine Scope by Zone Type**:

```sql
-- Count unavailable ranges by zone type
SELECT
  CASE
    WHEN z.database_name = 'system' THEN 'System Ranges'
    WHEN z.range_name IS NOT NULL THEN 'Meta Ranges'
    WHEN z.table_name IS NOT NULL THEN 'User Data Ranges'
    ELSE 'Other'
  END AS range_type,
  SUM(rs.unavailable_ranges) AS unavailable_count,
  SUM(rs.total_ranges) AS total_ranges
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE rs.unavailable_ranges > 0
GROUP BY range_type
ORDER BY unavailable_count DESC;
```

**Check node status**:

```sql
-- Identify dead or problematic nodes
SELECT
  g.node_id,
  g.address,
  g.locality,
  g.is_live,
  g.started_at,
  l.draining,
  l.decommissioning,
  l.membership,
  l.updated_at
FROM crdb_internal.gossip_nodes g
LEFT JOIN crdb_internal.gossip_liveness l ON g.node_id = l.node_id
WHERE g.is_live = false OR l.membership <> 'active'
ORDER BY g.node_id;
```

**Identify affected zones and their replica counts**:

```sql
-- View zones with unavailable ranges and their configuration
SELECT
  z.target,
  z.database_name,
  z.table_name,
  rs.unavailable_ranges,
  rs.under_replicated_ranges,
  rs.total_ranges,
  -- Extract num_replicas from zone config
  CASE
    WHEN z.raw_config_sql LIKE '%num_replicas = %'
    THEN substring(z.raw_config_sql from 'num_replicas = ([0-9]+)')::INT
    ELSE 3  -- default
  END AS expected_replicas
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE rs.unavailable_ranges > 0
ORDER BY rs.unavailable_ranges DESC;
```

### Step 3: Immediate Response Actions

**Priority 1: Restore Node Availability**

If nodes are down but recoverable:

```bash
# Attempt to restart failed nodes
cockroach start \
  --certs-dir=certs \
  --advertise-addr=<node-address> \
  --join=<join-addresses> \
  --cache=.25 \
  --max-sql-memory=.25

# Check node rejoins cluster
cockroach node status --certs-dir=certs --host=<any-live-node>
```

**Priority 2: Monitor Recovery**

```sql
-- Watch unavailable ranges decrease (run every 30 seconds)
SELECT
  now() AS check_time,
  SUM(unavailable_ranges) AS unavailable,
  SUM(under_replicated_ranges) AS under_replicated,
  SUM(over_replicated_ranges) AS over_replicated,
  SUM(total_ranges) AS total_ranges
FROM system.replication_stats;
```

**Priority 3: Identify Root Cause**

```bash
# Check node logs for errors
grep -i "quorum\|replica\|range.*unavailable" cockroach.log

# Check for network issues
grep -i "connection.*refused\|timeout\|network" cockroach.log

# Check for disk issues
grep -i "disk\|i/o error\|storage" cockroach.log
```

### Step 4: Restore Quorum (Emergency Procedures)

**WARNING**: Use only as last resort when nodes cannot be recovered.

**Option 1 - Wait for Node Recovery (Preferred)**:
```sql
-- Check recovery window setting (default: 5m)
SHOW CLUSTER SETTING server.time_until_store_dead;
-- Ranges remain unavailable until nodes return or timeout expires
```

**Option 2 - Force Up-Replication**:
If nodes permanently lost, wait for automatic up-replication after store death timeout. Cluster creates new replicas on available nodes automatically.

**Option 3 - Disaster Recovery (Data Loss Risk)**:
If majority of cluster lost, contact Cockroach Labs support before using unsafe recovery procedures. See: https://www.cockroachlabs.com/docs/stable/disaster-recovery

### Step 5: Prevent Future Unavailability

**Implement Proper Zone Configuration**:

```sql
-- Ensure sufficient replicas across failure domains
ALTER DATABASE mydb CONFIGURE ZONE USING
  num_replicas = 5,
  constraints = '{"+region=us-east":2, "+region=us-west":2, "+region=us-central":1}';

-- Verify configuration
SHOW ZONE CONFIGURATION FROM DATABASE mydb;
```

**Configure Appropriate Timeouts**:

```sql
-- Increase store death timeout for slower recovery scenarios
SET CLUSTER SETTING server.time_until_store_dead = '10m';

-- Allow more time for suspect nodes before declaring dead
SET CLUSTER SETTING server.clock.persist_upper_bound_interval = '1s';
```

**Implement Monitoring and Alerting**:

```sql
-- Create metric export for unavailable ranges
-- Use Prometheus or other monitoring system
-- Alert when: unavailable_ranges > 0
```

### Step 6: Verify Recovery

**Confirm ranges are available**:

```sql
-- Should return 0
SELECT SUM(unavailable_ranges) AS unavailable_ranges
FROM system.replication_stats;

-- Check overall replication health
SELECT
  SUM(unavailable_ranges) AS unavailable,
  SUM(under_replicated_ranges) AS under_replicated,
  SUM(over_replicated_ranges) AS over_replicated,
  SUM(total_ranges) AS total_ranges
FROM system.replication_stats;
```

**Test data access**:

```sql
-- Attempt reads from previously unavailable ranges
SELECT count(*) FROM affected_table;

-- Attempt writes
INSERT INTO affected_table VALUES (...);
```

**Review cluster health**:

```bash
# Check overall cluster status
cockroach node status --certs-dir=certs --host=<node>

# Verify all nodes are live
# Verify no decommissioning nodes
# Verify storage metrics are normal
```

## Alerting Thresholds

### Critical Alerts (Immediate Response)

**Unavailable Ranges**:
- Threshold: `unavailable_ranges > 0`
- Severity: **Critical**
- Action: Page on-call immediately
- SLA: Respond within 5 minutes

**Query**:
```sql
SET allow_unsafe_internals = true;

SELECT SUM(unavailable_ranges) AS unavailable
FROM system.replication_stats;
```

### Warning Alerts (Proactive Monitoring)

**Under-Replicated Ranges**:
- Threshold: `under_replicated_ranges > 10`
- Severity: **Warning**
- Action: Investigate within 30 minutes
- May lead to unavailability if nodes fail

**Multiple Node Unavailability**:
- Threshold: `dead_nodes >= 2`
- Severity: **Warning**
- Action: Check quorum status
- Risk of range unavailability

## Troubleshooting

### Issue: Ranges Remain Unavailable After Node Recovery

**Diagnosis**:

```sql
-- Check overall replication health by zone
SELECT
  z.target,
  z.database_name,
  z.table_name,
  rs.unavailable_ranges,
  rs.under_replicated_ranges,
  rs.total_ranges
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE rs.unavailable_ranges > 0 OR rs.under_replicated_ranges > 0
ORDER BY rs.unavailable_ranges DESC
LIMIT 10;
```

**Solution**:
- Verify nodes fully rejoined cluster
- Check network connectivity between nodes
- Review logs for replication errors
- Allow time for lease rebalancing (5-10 minutes)

### Issue: System Ranges Unavailable

**Diagnosis**:

```sql
-- Check system range replication health
SELECT
  z.target,
  rs.unavailable_ranges,
  rs.under_replicated_ranges,
  rs.total_ranges
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE z.database_name = 'system'
  AND (rs.unavailable_ranges > 0 OR rs.under_replicated_ranges > 0);
```

**Solution**:
- System range unavailability prevents cluster operations
- Requires immediate node recovery
- May need unsafe recovery procedures
- Contact Cockroach Labs support

### Issue: Unavailability After Decommissioning

**Diagnosis**:

```sql
-- Check if decommissioned nodes held critical replicas
SELECT node_id, draining, decommissioning, membership, updated_at
FROM crdb_internal.gossip_liveness
WHERE membership = 'decommissioned';
```

**Solution**:
- Stop additional decommissioning immediately
- If recent, recommission nodes:
  ```bash
  cockroach node recommission <node-id> --certs-dir=certs
  ```
- Restart decommissioned nodes if still available
- Learn: Always verify replication before decommissioning

### Issue: Persistent Unavailability Despite Sufficient Nodes

**Diagnosis**:

```sql
-- Check zone configuration constraints
SHOW ZONE CONFIGURATIONS;

-- Check zones with unavailable ranges
SELECT
  z.target,
  z.database_name,
  z.table_name,
  rs.unavailable_ranges,
  z.raw_config_sql
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE rs.unavailable_ranges > 0;
```

**Solution**:
- Zone constraints may be unsatisfiable
- Adjust constraints to match available nodes:
  ```sql
  ALTER RANGE default CONFIGURE ZONE USING
    constraints = '[]',
    num_replicas = 3;
  ```
- Allow 10-15 minutes for replication

## Best Practices

### Prevention
- **Multi-Zone Deployment**: Deploy across 3+ zones, use 5 replicas for critical data
- **Capacity Planning**: Maintain N+2 capacity, monitor disk space below 80%
- **Operational Discipline**: Never decommission multiple nodes simultaneously, always drain first
- **Monitoring**: Alert on unavailable_ranges > 0, monitor under-replicated ranges, 24/7 on-call

### Detection
- **Automated Monitoring**: Export to Prometheus/Datadog, PagerDuty integration, 30-second intervals
- **Regular Checks**: Daily verification, weekly reviews, monthly DR drills, quarterly capacity planning

### Response
- **Incident Response**: Document procedures, maintain contacts, define escalation, practice scenarios
- **Communication**: Notify stakeholders immediately, update every 15 minutes, post-incident review
- **Priorities**: (1) Restore quorum, (2) Identify root cause, (3) Prevent recurrence, (4) Document lessons

## See Also

- **inspect-range-distribution-replicas-and-leaseholder-placement**: Understanding replica placement
- **decommission-nodes-safely**: Proper node removal procedures
- **verify-cluster-health-between-restarts**: Health verification
- **configure-and-understand-critical-cluster-settings-that-control-failure-detection-and-recovery**: Recovery settings
- CockroachDB Docs: [Disaster Recovery](https://www.cockroachlabs.com/docs/stable/disaster-recovery)
- CockroachDB Docs: [Replication Layer](https://www.cockroachlabs.com/docs/stable/architecture/replication-layer)
- CockroachDB Docs: [Production Checklist](https://www.cockroachlabs.com/docs/stable/recommended-production-settings)
