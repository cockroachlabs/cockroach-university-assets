---
name: monitor-leaseholder-distribution
description: Monitor leaseholder distribution across nodes using crdb_internal.ranges to identify uneven load, leaseholder preference misconfigurations, or network partitioning causing imbalanced request serving. Use when checking leaseholder balance, investigating read hotspots, or diagnosing cluster performance issues.
metadata:
  domain: Monitoring and Alerting
  tags: cluster-operations, monitoring, performance, leaseholders, load-balancing
  blooms_level: Apply
  version: 1.1.0
  min_crdb_version: v26.1.0
  status: production-ready
---

# Monitor Leaseholder Distribution

## Overview

Leaseholder distribution monitoring identifies performance bottlenecks and ensures balanced read workloads across CockroachDB clusters. Each range has one leaseholder replica that serves all reads and coordinates writes. Uneven distribution creates hotspots, causing high CPU on some nodes while others remain idle.

**Why it matters:**
- Leaseholder imbalance causes CPU, network, and latency hotspots
- p99 latency spikes without corresponding write volume increases
- Wasted cluster capacity from underutilized nodes

**Common causes:**
- Zone configuration errors (leaseholder preferences)
- Network partitioning or asymmetric latency
- Recent topology changes (node additions/removals)
- Node performance differences

CockroachDB automatically rebalances leaseholders based on QPS, latency, and load metrics, but this takes time (minutes to hours).

## Monitoring Leaseholder Distribution

**IMPORTANT:** All queries in this skill require setting:

```sql
SET allow_unsafe_internals = true;
```

This setting grants access to `crdb_internal.*` tables which expose cluster internals. Only cluster administrators should have this access.

### Basic Distribution Query

Check overall leaseholder count per node:

```sql
SELECT
  lease_holder,
  count(*) as leaseholder_count
FROM crdb_internal.ranges
GROUP BY lease_holder
ORDER BY leaseholder_count DESC;
```

**Expected output (healthy 3-node cluster):**
```
  lease_holder | leaseholder_count
---------------+-------------------
             1 |                45
             2 |                47
             3 |                43
```

**Imbalanced cluster (problem):**
```
  lease_holder | leaseholder_count
---------------+-------------------
             1 |               120
             2 |                10
             3 |                 5
```

### Distribution Statistics with Deviation

```sql
WITH leaseholder_counts AS (
  SELECT
    lease_holder,
    count(*) as leaseholder_count
  FROM crdb_internal.ranges
  GROUP BY lease_holder
),
stats AS (
  SELECT
    avg(leaseholder_count)::INT as avg_count,
    min(leaseholder_count) as min_count,
    max(leaseholder_count) as max_count,
    count(*) as num_nodes
  FROM leaseholder_counts
)
SELECT
  lc.lease_holder,
  lc.leaseholder_count,
  s.avg_count,
  round((lc.leaseholder_count::FLOAT - s.avg_count::FLOAT) / s.avg_count::FLOAT * 100, 2) as pct_deviation,
  CASE
    WHEN lc.leaseholder_count > s.avg_count * 1.5 THEN 'OVERLOADED'
    WHEN lc.leaseholder_count < s.avg_count * 0.5 THEN 'UNDERUTILIZED'
    ELSE 'BALANCED'
  END as status
FROM leaseholder_counts lc
CROSS JOIN stats s
ORDER BY lc.leaseholder_count DESC;
```

### Distribution by Locality

Check distribution across availability zones or regions:

```sql
SELECT
  r.lease_holder,
  n.locality,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
GROUP BY r.lease_holder, n.locality
ORDER BY leaseholder_count DESC;
```

## Detecting Imbalances

### Threshold-Based Alerting

**Rule of thumb for balanced clusters:**
- Maximum deviation: ±20% from average
- Critical threshold: Any node with >2x average leaseholder count
- Warning threshold: Any node with >1.5x average leaseholder count

**Alerting query:**

```sql
WITH leaseholder_counts AS (
  SELECT
    lease_holder,
    count(*) as leaseholder_count
  FROM crdb_internal.ranges
  GROUP BY lease_holder
),
stats AS (
  SELECT avg(leaseholder_count) as avg_count
  FROM leaseholder_counts
)
SELECT
  lc.lease_holder,
  lc.leaseholder_count,
  s.avg_count::INT as avg_count,
  CASE
    WHEN lc.leaseholder_count > s.avg_count * 2 THEN 'CRITICAL'
    WHEN lc.leaseholder_count > s.avg_count * 1.5 THEN 'WARNING'
    WHEN lc.leaseholder_count < s.avg_count * 0.5 THEN 'WARNING'
    ELSE 'OK'
  END as alert_level
FROM leaseholder_counts lc
CROSS JOIN stats s
WHERE lc.leaseholder_count > s.avg_count * 1.5
   OR lc.leaseholder_count < s.avg_count * 0.5
ORDER BY lc.leaseholder_count DESC;
```

### Coefficient of Variation

Calculate statistical measure of distribution uniformity:

```sql
WITH leaseholder_counts AS (
  SELECT count(*) as leaseholder_count
  FROM crdb_internal.ranges
  GROUP BY lease_holder
)
SELECT
  avg(leaseholder_count) as mean,
  stddev(leaseholder_count) as std_dev,
  CASE
    WHEN avg(leaseholder_count) > 0
    THEN round(stddev(leaseholder_count) / avg(leaseholder_count) * 100, 2)
    ELSE 0
  END as coefficient_of_variation_pct
FROM leaseholder_counts;
```

**Interpretation:**
- CV < 10%: Excellent distribution
- CV 10-20%: Good distribution
- CV 20-30%: Moderate imbalance (investigate)
- CV > 30%: Severe imbalance (action required)

## Root Cause Analysis

### Check Zone Configurations

Examine leaseholder preferences:

```sql
SELECT target, raw_config_sql
FROM [SHOW ZONE CONFIGURATIONS]
WHERE raw_config_sql LIKE '%lease_preferences%'
ORDER BY target;
```

### Check Node Status

Identify recently added/removed nodes causing temporary imbalances:

```sql
SELECT
  node_id,
  address,
  locality,
  started_at,
  is_live
FROM crdb_internal.gossip_nodes
ORDER BY started_at DESC;
```

Decommissioning nodes shed leaseholders:

```sql
SELECT
  node_id,
  membership,
  decommissioning,
  draining
FROM crdb_internal.gossip_liveness
WHERE decommissioning = true OR membership != 'active'
ORDER BY node_id;
```

## Leaseholder Rebalancing

### Understanding Automatic Rebalancing

CockroachDB automatically rebalances leaseholders based on:
- **QPS metrics**: Transfers leaseholders from hot to cold nodes
- **Latency**: Moves leaseholders closer to workload sources
- **Load factors**: CPU, network, and disk utilization

**Rebalancing pace:**
- Conservative by default to avoid disruption
- Can take minutes to hours for large imbalances
- Configured via cluster settings

### Relevant Cluster Settings

```sql
-- Check rebalancing settings
SHOW CLUSTER SETTING kv.allocator.load_based_rebalancing;
SHOW CLUSTER SETTING kv.allocator.load_based_lease_rebalancing.enabled;
SHOW CLUSTER SETTING kv.allocator.lease_rebalancing_aggressiveness;
```

**Default values (v26.1):**
- `kv.allocator.load_based_rebalancing`: `leases and replicas`
- `kv.allocator.load_based_lease_rebalancing.enabled`: `true`
- `kv.allocator.lease_rebalancing_aggressiveness`: `1.0`

### Forcing Lease Transfers (Advanced)

**Manual lease transfer** (use with caution):

```sql
-- Transfer lease for specific range to target node
ALTER RANGE <range_id> RELOCATE LEASE TO <target_node_id>;
```

**Use cases:**
- Testing
- Emergency hotspot mitigation
- Validating zone configuration changes

**Warning:** Manual transfers are temporary. Automatic rebalancing may override them.

## Zone Configuration Best Practices

### Setting Leaseholder Preferences

Place leaseholders in specific localities for read latency optimization:

```sql
-- Prefer leaseholders in specific region
ALTER TABLE my_database.my_table
CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east]]';
```

### Multi-Region Leaseholder Preferences

```sql
-- Primary preference with fallback
ALTER DATABASE my_database
CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east], [+region=us-west]]';
```

### Verifying Preference Application

Check leaseholder distribution for specific tables using `SHOW RANGES`:

```sql
-- View leaseholder placement for specific table
SELECT
  lease_holder,
  count(*) as leaseholder_count
FROM [SHOW RANGES FROM TABLE my_database.my_table]
GROUP BY lease_holder
ORDER BY leaseholder_count DESC;
```

Cross-reference with node localities to ensure preferences are honored.

### Common Zone Configuration Mistakes

**Problem 1: Contradictory constraints**
```sql
-- WRONG: Constraints conflict with lease preferences
ALTER TABLE my_table CONFIGURE ZONE USING
  constraints = '[+region=us-west]',
  lease_preferences = '[[+region=us-east]]';
```

**Solution:** Ensure lease preferences reference localities where replicas exist.

**Problem 2: Non-existent locality keys**
```sql
-- WRONG: Typo in locality key
ALTER TABLE my_table CONFIGURE ZONE USING
  lease_preferences = '[[+regoin=us-east]]';  -- "regoin" typo
```

**Solution:** Verify locality keys match node configurations.

## Network Partitioning Impact

When network partitions occur:
- Leaseholders concentrate on majority-side nodes
- Minority-side nodes lose leaseholders
- Latency increases dramatically

**Detect partitioning:**

```sql
-- Check node liveness and membership
SELECT
  g.node_id,
  g.is_live,
  l.membership,
  l.draining,
  l.decommissioning,
  l.updated_at
FROM crdb_internal.gossip_nodes g
JOIN crdb_internal.gossip_liveness l ON g.node_id = l.node_id
ORDER BY g.node_id;

-- Check for unavailable/underreplicated ranges (zone-level view)
SELECT
  z.target,
  z.database_name,
  z.table_name,
  rs.unavailable_ranges,
  rs.under_replicated_ranges,
  rs.total_ranges
FROM system.replication_stats rs
LEFT JOIN crdb_internal.zones z ON rs.zone_id = z.zone_id
WHERE rs.unavailable_ranges > 0 OR rs.under_replicated_ranges > 0;
```

**Recovery:** After network heals, leaseholders rebalance over 10-30 minutes.

## Troubleshooting Common Scenarios

### Single Node Overloaded

**Symptoms:** One node >2x average leaseholder count, high CPU on one node

**Solutions:**
1. Check zone configurations for unintended lease preferences
2. Verify load-based rebalancing enabled
3. Wait 10-30 minutes for automatic rebalancing
4. Review application connection patterns (all queries to one node?)

### Regional Imbalance

**Symptoms:** All leaseholders concentrated in one region

**Solutions:**
1. Review lease_preferences in zone configurations
2. Adjust preferences to distribute across regions
3. Verify network latency between regions is reasonable
4. Check application traffic origin matches expectations

### Post-Scaling Imbalance

**Symptoms:** New nodes have few/no leaseholders

**Solutions:**
1. Wait 30-60 minutes for automatic rebalancing
2. Verify nodes are live: `SELECT * FROM crdb_internal.gossip_liveness;`
3. Check `kv.allocator.lease_rebalancing_aggressiveness`
4. Ensure no zone constraints prevent rebalancing

### Configuration Changes Not Applied

**Symptoms:** Zone config updated but distribution unchanged

**Solutions:**
```sql
-- Verify zone config applied
SHOW ZONE CONFIGURATION FOR TABLE my_table;

-- Ensure rebalancing enabled
SHOW CLUSTER SETTING kv.allocator.load_based_lease_rebalancing.enabled;
```

Wait 30+ minutes. Check DB Console logs for rebalancing errors.

## Best Practices

### Monitoring

1. **Set up automated alerts** for leaseholder imbalance >50% deviation
2. **Track trends** over time, not just snapshots
3. **Correlate with performance metrics** (CPU, query latency, QPS)
4. **Review distribution** after topology changes

### Configuration

1. **Document zone configurations** and their rationale
2. **Test lease preferences** in non-production first
3. **Align preferences with workload geography**
4. **Avoid over-constraining** leaseholder placement

### Operational

1. **Allow time for rebalancing** after changes (30-60 minutes)
2. **Avoid manual lease transfers** except for emergencies
3. **Plan topology changes** during low-traffic periods
4. **Validate rebalancing settings** before scaling operations

## Key Takeaways

1. **Leaseholders serve all reads and coordinate writes** for their ranges
2. **Even distribution is critical** for balanced cluster performance
3. **Automatic rebalancing works** but takes time (minutes to hours)
4. **Monitor using crdb_internal.ranges** and statistical thresholds
5. **Common causes** include zone misconfigurations, network issues, and topology changes
6. **Zone configurations** provide powerful control but require careful planning
7. **Network partitioning** causes severe imbalances; monitor node liveness
8. **Requires `SET allow_unsafe_internals = true`** to access internal tables

## Related Skills

- inspect-range-distribution-replicas-and-leaseholder-placement
- configure-and-understand-critical-cluster-settings-that-control-failure-detection-and-recovery
- modify-zone-configurations
- verify-cluster-health-between-restarts

## References

- CockroachDB Architecture: Replication Layer
- Zone Configuration Documentation (v26.1)
- DB Console: Metrics and Replication Dashboard
- Cluster Settings: Rebalancing Parameters
