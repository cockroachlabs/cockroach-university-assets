---
name: analyze-range-distribution-across-regions
description: Analyze how ranges and replicas are distributed across regions in multi-region clusters. Query range placement, verify regional constraints, identify misplaced ranges, and detect rebalancing issues. Essential for troubleshooting latency, verifying compliance, and optimizing multi-region performance.
metadata:
  domain: Multi-Region
  bloom_level: Analyze
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: ready
  related_skills:
    - verify-zone-configurations-for-multi-region-tables
    - inspect-range-distribution-replicas-and-leaseholder-placement
    - configure-zone-constraints-for-replica-placement
    - optimize-multi-region-deployments-for-low-latency
    - view-database-multi-region-configuration
    - verify-table-locality-configuration
  prerequisites:
    - Multi-region database configured
    - Understanding of range and replica concepts
    - Knowledge of table locality types
  estimated_time_minutes: 30
  last_updated: "2026-03-06"
  testing_notes: |
    Tested against v26.1.0 multi-region cluster (3 nodes across us-east, us-west, eu-west).
    Major schema changes in v26.1:
    - crdb_internal.ranges no longer has table_name/database_name columns
    - All range-to-table mapping now uses SHOW RANGES commands
    - All crdb_internal queries require SET allow_unsafe_internals = true
    - Locality is STRING type, not JSONB - use substring/LIKE for parsing
---

# Analyze Range Distribution Across Regions

## Overview

In multi-region CockroachDB clusters, **range distribution across regions** determines data placement, read/write latency, availability, and compliance with data domiciling requirements.

**Key concepts:**
- **Range**: Unit of data distribution (contiguous key space)
- **Replica**: Copy of range on a node (typically 3-5 in multi-region)
- **Region**: Geographic locality tier (e.g., us-east, eu-west)
- **Leaseholder**: Replica serving reads (placement affects latency)

**Analysis goals:**
- Verify REGIONAL BY TABLE stays in single region
- Confirm REGIONAL BY ROW distributes by row region
- Check GLOBAL tables have non-voting replicas in all regions
- Identify misplaced ranges violating zone constraints
- Monitor rebalancing progress across regions

## v26.1 Schema Changes

**CRITICAL:** In v26.1.0, `crdb_internal.ranges` removed `table_name` and `database_name` columns. Use `SHOW RANGES` commands instead.

**Changed approach:**
- ❌ `SELECT * FROM crdb_internal.ranges WHERE table_name = 'users'` (BROKEN)
- ✅ `SHOW RANGES FROM TABLE users WITH DETAILS` (v26.1)
- ✅ `SHOW CLUSTER RANGES WITH TABLES` (cluster-wide view)

All `crdb_internal` queries require:
```sql
SET allow_unsafe_internals = true;
```

## Step 1: Map Cluster Topology

**View cluster regions:**
```sql
SHOW REGIONS FROM CLUSTER;
```

**Output example:**
```
   region   | zones
------------+----------------
  us-east   | {us-east-1a}
  us-west   | {us-west-1a}
  eu-west   | {eu-west-1a}
```

**Map nodes to regions:**
```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  substring(locality FROM 'region=([^,]+)') as region,
  substring(locality FROM 'zone=([^,]+)') as zone,
  is_live
FROM crdb_internal.gossip_nodes
ORDER BY region, node_id;
```

**Output example:**
```
 node_id |  region  |    zone     | is_live
---------+----------+-------------+---------
    3    | eu-west  | eu-west-1a  |  true
    1    | us-east  | us-east-1a  |  true
    2    | us-west  | us-west-1a  |  true
```

**Why this matters:** You'll see node IDs in `SHOW RANGES` output - this mapping lets you determine which region each replica is in.

## Step 2: View Database Multi-Region Config

```sql
SHOW REGIONS FROM DATABASE;
```

**Output example:**
```
database              | region   | primary | secondary | zones          | zone_level_survival
----------------------+----------+---------+-----------+----------------+---------------------
test_global_locality  | eu-west  | false   | false     | {eu-west-1a}   |        NULL
test_global_locality  | us-east  | true    | false     | {us-east-1a}   |        NULL
test_global_locality  | us-west  | false   | false     | {us-west-1a}   |        NULL
```

**Key insights:**
- **primary = true**: Default region for REGIONAL BY TABLE
- All regions listed are available for data placement

## Step 3: Check Table Localities

```sql
SET allow_unsafe_internals = true;

SELECT
  name AS table_name,
  locality
FROM crdb_internal.tables
WHERE database_name = current_database()
  AND schema_name = 'public'
  AND locality IS NOT NULL
ORDER BY name;
```

**Output example:**
```
table_name       | locality
-----------------+----------------------------------
countries        | GLOBAL
currencies       | GLOBAL
test_conversion  | REGIONAL BY TABLE IN "us-east"
```

## Step 4: Analyze Range Distribution with SHOW RANGES

**For specific tables:**
```sql
SHOW RANGES FROM TABLE countries WITH DETAILS;
```

**Output example (GLOBAL table):**
```
range_id | start_key | end_key | replicas | replica_localities                              | voting_replicas | non_voting_replicas | lease_holder | lease_holder_locality
---------+-----------+---------+----------+-------------------------------------------------+-----------------+---------------------+--------------+-----------------------
   42    | NULL      | /10     | {1,2,3}  | {"region=us-east,zone=us-east-1a",             | {1}             | {2,3}               |      1       | region=us-east,...
         |           |         |          |  "region=us-west,zone=us-west-1a",             |                 |                     |              |
         |           |         |          |  "region=eu-west,zone=eu-west-1a"}             |                 |                     |              |
```

**Key columns:**
- `replica_localities`: Full locality strings for each replica
- `voting_replicas`: Node IDs of voting replicas (serve writes)
- `non_voting_replicas`: Node IDs of non-voting replicas (GLOBAL tables)
- `lease_holder_locality`: Region serving reads

**For REGIONAL BY TABLE:**
```sql
SHOW RANGES FROM TABLE test_conversion WITH DETAILS;
```

**Expected output:** All `replica_localities` should show same region.

## Step 5: Verify Distribution Patterns by Locality Type

### REGIONAL BY TABLE Verification

**Expected:** All replicas in single region

**Check using SHOW RANGES:**
```sql
-- All localities should match the table's designated region
SHOW RANGES FROM TABLE test_conversion WITH DETAILS;
```

**Verification:** Count distinct regions in `replica_localities` - should be 1.

**Problem detection:** If you see replicas in multiple regions for REGIONAL BY TABLE, investigate zone configuration:
```sql
SHOW ZONE CONFIGURATION FOR TABLE test_conversion;
```

### GLOBAL Table Verification

**Expected:**
- Voting replicas in primary region
- Non-voting replicas in all other regions
- All leaseholders in primary region

**Check:**
```sql
SHOW RANGES FROM TABLE countries WITH DETAILS;
```

**Look for:**
- `voting_replicas`: Should be in primary region nodes
- `non_voting_replicas`: Should span secondary regions
- `lease_holder_locality`: Should always show primary region

### REGIONAL BY ROW Verification

**Expected:** Ranges partitioned by `crdb_region` column

**Check partition keys:**
```sql
SHOW RANGES FROM TABLE rides;
```

**Look for:** `start_key` and `end_key` values showing partition boundaries (e.g., `/Table/X/"us-east"`, `/Table/X/"eu-west"`).

**Check distribution:**
```sql
-- Verify rows are distributed across regions
SELECT crdb_region, count(*) as row_count
FROM rides
GROUP BY crdb_region
ORDER BY crdb_region;
```

## Step 6: Analyze Leaseholder Distribution

**Check leaseholder placement across tables:**

For each table, run:
```sql
SHOW RANGES FROM TABLE <table_name>;
```

**Analysis by locality type:**

**REGIONAL BY TABLE:** All leaseholders should be in table's region

**GLOBAL:** All leaseholders should be in primary region (fast local reads)

**REGIONAL BY ROW:** Leaseholders should follow partition region (each partition's leaseholders in corresponding region)

**Common issue:** Manual leaseholder preferences overriding locality behavior
```sql
-- Check for manual overrides
SHOW ZONE CONFIGURATION FOR TABLE <table_name>;
-- Look for explicit lease_preferences
```

## Step 7: Detect Range Distribution Violations

**Cluster-wide range view:**
```sql
SHOW CLUSTER RANGES WITH TABLES;
```

**This shows ALL ranges with their table mappings** - useful for finding anomalies.

**Common violations to look for:**

1. **REGIONAL BY TABLE with cross-region replicas**
   - Check `replica_localities` - should all show same region

2. **GLOBAL table missing non-voting replicas**
   - Check `non_voting_replicas` - should have nodes from secondary regions

3. **Under-replicated ranges**
   - Count replicas - should match replication factor (3 for ZONE, 5 for REGION survival)

4. **Leaseholders in wrong region**
   - For REGIONAL BY TABLE: leaseholder should be in table's region
   - For GLOBAL: leaseholder should be in primary region

## Step 8: Monitor Rebalancing Progress

**Check for active rebalancing jobs:**
```sql
SET allow_unsafe_internals = true;

SELECT
  job_id,
  job_type,
  description,
  status,
  fraction_completed,
  running_status
FROM crdb_internal.jobs
WHERE job_type = 'AUTO SPAN CONFIG RECONCILIATION'
  AND status IN ('running', 'pending')
ORDER BY created DESC;
```

**Check rebalance settings:**
```sql
SHOW CLUSTER SETTING kv.snapshot_rebalance.max_rate;
-- Default: 32MiB (increase for faster rebalancing)

SHOW CLUSTER SETTING kv.allocator.range_rebalance_threshold;
-- Default: 0.05 (5% imbalance triggers rebalancing)
```

**Monitor progress:**
- Re-run `SHOW RANGES FROM TABLE` periodically
- Check `fraction_completed` in rebalancing jobs
- Look for decreasing `replica_localities` mismatches

## Troubleshooting Common Issues

### Issue 1: REGIONAL BY TABLE Has Cross-Region Replicas

**Diagnosis:**
```sql
SHOW ZONE CONFIGURATION FOR TABLE <table_name>;
```

**Possible causes:**
- Manual zone config overriding locality
- Table locality not set correctly
- Rebalancing in progress

**Solution:**
```sql
-- Option 1: Reset to use locality-based config
ALTER TABLE <table_name> CONFIGURE ZONE DISCARD;

-- Option 2: Explicitly set regional constraint
ALTER TABLE <table_name> CONFIGURE ZONE USING
  constraints = '{+region=<region_name>: 3}',
  lease_preferences = '[[+region=<region_name>]]';
```

### Issue 2: GLOBAL Table Missing Non-Voting Replicas

**Diagnosis:**
```sql
SHOW RANGES FROM TABLE <table_name> WITH DETAILS;
-- Check non_voting_replicas column
```

**Possible causes:**
- Not enough nodes in secondary regions
- Table not configured as GLOBAL
- Rebalancing in progress

**Solution:**
```sql
-- Ensure GLOBAL locality
ALTER TABLE <table_name> SET LOCALITY GLOBAL;

-- Verify zone config
SHOW ZONE CONFIGURATION FOR TABLE <table_name>;
-- Should show: global_reads = true
```

### Issue 3: Leaseholders in Wrong Region

**Diagnosis:**
```sql
SHOW RANGES FROM TABLE <table_name>;
-- Check lease_holder_locality column
```

**Possible causes:**
- Manual lease preferences set
- Recent configuration change still propagating

**Solution:**
```sql
-- Remove manual lease preferences
ALTER TABLE <table_name> CONFIGURE ZONE USING
  lease_preferences = NULL;

-- Let CockroachDB auto-manage leaseholder placement
```

### Issue 4: Rebalancing Stuck/Slow

**Diagnosis:**
```sql
SET allow_unsafe_internals = true;

-- Check for dead nodes
SELECT node_id, locality, is_live
FROM crdb_internal.gossip_nodes
WHERE is_live = false;

-- Check for under-replicated ranges
SELECT count(*) as under_replicated_ranges
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
```

**Solution:**
```sql
-- Increase rebalance rate if slow
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '64MiB';

-- If dead nodes exist, decommission them (cluster admin required)
-- This allows ranges to be properly replicated
```

## Best Practices

**1. Regular Distribution Audits**
- Run weekly checks on critical tables
- Verify REGIONAL BY TABLE stays single-region
- Confirm GLOBAL tables have proper non-voting replicas

**2. Document Expected Distribution**
```sql
COMMENT ON TABLE eu_customers IS
  'REGIONAL BY TABLE in eu-west for GDPR compliance.
   Expected: 100% replicas in eu-west, 0% elsewhere.
   Last verified: 2026-03-06';
```

**3. Monitor After Configuration Changes**
- Wait 60 seconds for changes to propagate
- Re-run `SHOW RANGES FROM TABLE` to verify
- Check DB Console for rebalancing activity

**4. Use DB Console for Visual Analysis**
- Access at `http://<cluster-node>:8080`
- Navigate to **Metrics > Replication**
- View range distribution heatmaps

**5. Alert on Violations**
Set up monitoring to detect:
- REGIONAL BY TABLE with cross-region replicas
- Under-replicated ranges
- Leaseholders in unexpected regions

## Summary

**Key v26.1 changes:**
- Use `SHOW RANGES FROM TABLE` instead of querying `crdb_internal.ranges` by table
- Use `SHOW CLUSTER RANGES WITH TABLES` for cluster-wide analysis
- Set `allow_unsafe_internals = true` for all `crdb_internal` queries

**Analysis workflow:**
1. Map cluster topology (nodes to regions)
2. Check database multi-region configuration
3. Review table localities
4. Examine range distribution with SHOW RANGES
5. Verify patterns match locality type expectations
6. Monitor leaseholder placement
7. Detect violations and anomalies
8. Track rebalancing progress

**Expected patterns:**
- **REGIONAL BY TABLE**: All replicas in one region
- **GLOBAL**: Voting in primary, non-voting in others
- **REGIONAL BY ROW**: Partitioned by crdb_region

Regular analysis ensures multi-region deployments work as designed, maintaining compliance, performance, and availability.

## References

- [Multi-Region Capabilities Overview](https://www.cockroachlabs.com/docs/stable/multiregion-overview)
- [Table Localities](https://www.cockroachlabs.com/docs/stable/table-localities)
- [SHOW RANGES](https://www.cockroachlabs.com/docs/stable/show-ranges)
- [crdb_internal Tables](https://www.cockroachlabs.com/docs/stable/crdb-internal)
- [Zone Configuration](https://www.cockroachlabs.com/docs/stable/configure-replication-zones)
