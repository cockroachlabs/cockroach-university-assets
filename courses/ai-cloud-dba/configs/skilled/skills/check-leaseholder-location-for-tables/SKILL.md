---
name: check-leaseholder-location-for-tables
description: Check where leaseholders are located for tables using SHOW RANGES and crdb_internal queries. Verify leaseholder placement matches expected locality, troubleshoot wrong-region leaseholders, and understand how locality affects read performance.
metadata:
  domain: Multi-Region
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - inspect-range-distribution-replicas-and-leaseholder-placement
    - understand-leaseholder-role-and-placement
    - configure-leaseholder-preferences-with-zone-configs
    - verify-follower-reads-are-served-locally
    - analyze-and-optimize-multi-region-latency
  prerequisites:
    - Understanding of ranges and leaseholders
    - Multi-region cluster or cluster with locality labels
    - Access to cluster via SQL client
  estimated_time_minutes: 25
  last_updated: "2026-03-06"
---

# Check Leaseholder Location for Tables

## Overview

The **leaseholder** is the replica that serves all read requests for a range. Leaseholder location is critical for read performance - reads must travel to the leaseholder node, so wrong-region leaseholders cause high latency.

**Why leaseholder location matters:**
- **Reads go to leaseholder**: Every read must contact the leaseholder replica
- **Cross-region reads are slow**: 50-100ms+ latency vs 1-5ms in-region
- **Leaseholder != closest replica**: Just because a replica exists locally doesn't mean reads are local
- **Load balancing**: Leaseholders should be near read workload

**Key concepts:**
- **Leaseholder**: One replica per range that serves reads (identified by node ID)
- **Lease preferences**: Zone config setting to control leaseholder placement
- **Locality**: Node metadata describing geographic location (region, zone, datacenter)
- **Lease transfer**: Automatic movement of leaseholder between replicas

**Common scenarios:**
- Verify leaseholders are in expected region after zone config change
- Troubleshoot slow reads from specific region (check leaseholder locality)
- Confirm leaseholders balanced across zones within region
- Identify tables with leaseholders in wrong region

## Why Leaseholder Location Matters

### Read Path to Leaseholder

```
Client (us-west)
    ↓ SQL query
Load Balancer (us-west)
    ↓
CockroachDB Node (us-west)
    ↓ Range read request
    ↓ (crosses region boundary if leaseholder in us-east!)
Leaseholder Replica (us-east) ← 50-100ms latency
    ↓ Returns data
Client receives result
```

**Performance impact:**
- **In-region read**: 1-5ms (local leaseholder)
- **Cross-region read**: 50-100ms (remote leaseholder)
- **Cross-continent read**: 100-200ms+ (intercontinental leaseholder)

### Example: Regional Table with Wrong Leaseholder

```sql
-- Table configured for us-east region
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email STRING,
  name STRING
);

-- But leaseholders accidentally in us-west
-- Users in us-east experience slow reads!
```

**Solution**: Check leaseholder location, adjust lease preferences.

## Checking Leaseholder Location with SHOW RANGES

### Basic Leaseholder Check

```sql
-- Show ranges with leaseholder information
SHOW RANGES FROM TABLE users;

-- Output:
--  start_key | end_key | range_id | replicas | lease_holder
-- -----------+---------+----------+----------+--------------
--  <min>     | /1000   |    42    | {1,2,3}  |      1
--  /1000     | /5000   |    43    | {2,3,4}  |      3
--  /5000     | <max>   |    44    | {1,3,5}  |      5
```

**Reading the output:**
- `lease_holder`: Node ID holding the leaseholder (e.g., node 1, node 3)
- `replicas`: All replica node IDs (e.g., {1,2,3})
- Each range has exactly one leaseholder

**Limitation**: Shows node ID, not locality. Need to map node ID → region.

### Show Ranges with Locality Details

```sql
-- Show ranges with full locality information
SHOW RANGES FROM TABLE users WITH DETAILS;

-- Output:
--  range_id | lease_holder | lease_holder_locality        | replica_localities
-- ----------+--------------+------------------------------+----------------------------------------
--    42     |      1       | region=us-east,zone=us-e1a  | {region=us-east,zone=us-e1a}, {region=us-east,zone=us-e1b}, {region=us-west,zone=us-w1a}
--    43     |      3       | region=us-west,zone=us-w1a  | {region=us-east,zone=us-e1a}, {region=us-west,zone=us-w1a}, {region=us-west,zone=us-w1b}
--    44     |      5       | region=us-east,zone=us-e1b  | {region=us-east,zone=us-e1b}, {region=us-west,zone=us-w1a}, {region=us-central,zone=us-c1a}
```

**Key columns:**
- `lease_holder_locality`: Full locality string for leaseholder node
- `replica_localities`: Array of locality strings for all replicas

**Use case**: Quickly see which region each leaseholder is in.

### Summarize Leaseholder Distribution by Region

```sql
-- Show leaseholder counts by region for a table
SHOW RANGES FROM TABLE users WITH DETAILS;

-- Manually count by region from output
-- OR query crdb_internal for programmatic analysis (see next section)
```

**Expected result**: If table configured for `region=us-east`, all leaseholders should show `region=us-east` in `lease_holder_locality`.

## Querying Leaseholder Location Programmatically

### Using crdb_internal.ranges

```sql
-- Enable access to internal tables
SET allow_unsafe_internals = true;

-- Count leaseholders by node for specific table
SELECT
  lease_holder as node_id,
  count(*) as leaseholder_count
FROM crdb_internal.ranges
WHERE table_name = 'users'
GROUP BY lease_holder
ORDER BY leaseholder_count DESC;

-- Output:
--  node_id | leaseholder_count
-- ---------+-------------------
--    1     |     15
--    2     |     14
--    3     |     13
--    5     |      8
```

**Use case**: Check leaseholder balance across nodes. Ideally, counts should be similar.

### Map Node ID to Locality (Region)

```sql
-- Join ranges with node locality to see leaseholder regions
SET allow_unsafe_internals = true;

SELECT
  r.lease_holder as node_id,
  n.locality,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'users'
GROUP BY r.lease_holder, n.locality
ORDER BY leaseholder_count DESC;

-- Output:
--  node_id | locality                      | leaseholder_count
-- ---------+-------------------------------+-------------------
--    1     | region=us-east,zone=us-e1a    |     15
--    2     | region=us-east,zone=us-e1b    |     14
--    3     | region=us-west,zone=us-w1a    |     13  ← Wrong region!
--    5     | region=us-east,zone=us-e1c    |      8
```

**Interpretation:**
- Node 3 in `region=us-west` has 13 leaseholders
- If table should be in `region=us-east`, this is a problem
- Users in us-east hitting node 3 leaseholders experience cross-region latency

### Extract Region from Locality String

```sql
-- Parse region from locality for cleaner aggregation
SET allow_unsafe_internals = true;

WITH leaseholder_localities AS (
  SELECT
    r.range_id,
    r.lease_holder,
    n.locality,
    -- Extract region= value from locality string
    substring(n.locality FROM 'region=([^,]+)') as region
  FROM crdb_internal.ranges r
  JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
  WHERE r.table_name = 'users'
)
SELECT
  region,
  count(*) as leaseholder_count,
  round(100.0 * count(*) / sum(count(*)) OVER (), 2) as percentage
FROM leaseholder_localities
GROUP BY region
ORDER BY leaseholder_count DESC;

-- Output:
--  region     | leaseholder_count | percentage
-- ------------+-------------------+------------
--  us-east    |     37            |   74.00
--  us-west    |     13            |   26.00  ← 26% in wrong region
```

**Use case**: High-level view of leaseholder distribution by region.

## Verifying Leaseholders Match Expected Locality

### Scenario: Regional Table Should Have Leaseholders in Home Region

```sql
-- Table configured for us-east region
ALTER TABLE users CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{+region=us-east:2, +region=us-west:1}',
  lease_preferences = '[[+region=us-east]]';

-- Wait 30-60 seconds for lease transfers to complete
```

**Verify leaseholder placement:**

```sql
SET allow_unsafe_internals = true;

-- Check if all leaseholders in us-east
SELECT
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'users'
GROUP BY region;

-- Expected output: All leaseholders in us-east
--  region     | leaseholder_count
-- ------------+-------------------
--  us-east    |     50

-- If you see other regions:
--  region     | leaseholder_count
-- ------------+-------------------
--  us-east    |     43
--  us-west    |      7  ← Problem! These should transfer to us-east
```

**Why might leaseholders be in wrong region?**
- Lease transfers still in progress (wait longer)
- No nodes available in preferred region
- Load-based leaseholder placement overriding preferences (high load)
- Nodes in preferred region unhealthy or down

### Find Specific Ranges with Wrong-Region Leaseholders

```sql
-- Identify exactly which ranges have leaseholders in wrong region
SET allow_unsafe_internals = true;

SELECT
  r.range_id,
  r.start_pretty,
  r.end_pretty,
  r.lease_holder,
  n.locality as leaseholder_locality
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'users'
  AND n.locality NOT LIKE '%region=us-east%'  -- Expected region
ORDER BY r.range_id;

-- Output:
--  range_id | start_pretty | end_pretty | lease_holder | leaseholder_locality
-- ----------+--------------+------------+--------------+-------------------------
--    43     | /1000        | /5000      |      3       | region=us-west,zone=us-w1a
--    47     | /10000       | /15000     |      4       | region=us-west,zone=us-w1b
```

**Use case**: Identify specific ranges for manual investigation or lease transfer.

## Troubleshooting Leaseholders in Wrong Region

### Problem 1: Leaseholders Not Moving After Zone Config Change

**Symptom:**
```sql
-- Set lease preference for us-east
ALTER TABLE orders CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east]]';

-- Check 5 minutes later, still see leaseholders in us-west
```

**Diagnosis:**

```sql
SET allow_unsafe_internals = true;

-- Verify zone config applied
SHOW ZONE CONFIGURATION FOR TABLE orders;
-- Should show lease_preferences = [[+region=us-east]]

-- Check current leaseholder distribution
SELECT
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'orders'
GROUP BY region;

-- Output shows leaseholders still in us-west
--  region     | leaseholder_count
-- ------------+-------------------
--  us-west    |     28
--  us-east    |     22
```

**Possible causes:**

1. **Lease transfers still in progress** (normal delay: 30-60 seconds)
   - Wait longer and re-check

2. **No replicas in preferred region**
   ```sql
   -- Check replica placement
   SHOW RANGES FROM TABLE orders WITH DETAILS;
   -- If replica_localities doesn't include us-east nodes, can't transfer leases there
   ```

   **Solution**: Add us-east to replica constraints:
   ```sql
   ALTER TABLE orders CONFIGURE ZONE USING
     num_replicas = 3,
     constraints = '{+region=us-east:1}',  -- Ensure at least 1 replica in us-east
     lease_preferences = '[[+region=us-east]]';
   ```

3. **Nodes in preferred region down/unhealthy**
   ```sql
   -- Check node health
   SELECT node_id, locality, is_live
   FROM crdb_internal.gossip_nodes
   WHERE locality LIKE '%region=us-east%';
   ```

   **Solution**: Fix node health issues before leases can transfer.

4. **Load-based leaseholder placement**
   - High load on certain ranges can cause leaseholders to move to busiest replica
   - Check if us-west nodes have higher query load

### Problem 2: Unbalanced Leaseholders Within Region

**Symptom:**
```sql
-- Leaseholders in correct region but all on one node
SET allow_unsafe_internals = true;

SELECT
  r.lease_holder,
  n.locality,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'products'
  AND n.locality LIKE '%region=us-east%'
GROUP BY r.lease_holder, n.locality;

-- Output:
--  lease_holder | locality                    | leaseholder_count
-- --------------+-----------------------------+-------------------
--      1        | region=us-east,zone=us-e1a  |     48  ← Heavily loaded!
--      2        | region=us-east,zone=us-e1b  |      2
--      5        | region=us-east,zone=us-e1c  |      0
```

**Diagnosis**: Leaseholders concentrated on node 1, creating hotspot.

**Cause**:
- Zone config has single preferred zone (not region)
- Specific constraint pinning leaseholders

**Solution**: Use broader lease preferences:
```sql
-- Prefer any us-east zone equally
ALTER TABLE products CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east]]';  -- Region-level, not zone-level

-- Or specify multiple zones with equal priority
ALTER TABLE products CONFIGURE ZONE USING
  lease_preferences = '[[+zone=us-e1a], [+zone=us-e1b], [+zone=us-e1c]]';
```

### Problem 3: Global Table with Leaseholders Only in One Region

**Symptom:**
```sql
-- Global table should serve reads from all regions
-- But leaseholders concentrated in us-east
CREATE TABLE reference_data (
  id UUID PRIMARY KEY,
  name STRING,
  value STRING
) LOCALITY GLOBAL;
```

**Diagnosis:**
```sql
SET allow_unsafe_internals = true;

SELECT
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'reference_data'
GROUP BY region;

-- Output:
--  region     | leaseholder_count
-- ------------+-------------------
--  us-east    |     15
--  us-west    |      0  ← No leaseholders in us-west!
```

**Cause**: Global tables should distribute leaseholders, but if no read traffic from us-west, leaseholders may not move there.

**Solution**:
- Generate read traffic from us-west to encourage leaseholder migration
- Or manually set lease preferences to distribute:
  ```sql
  ALTER TABLE reference_data CONFIGURE ZONE USING
    lease_preferences = '[[+region=us-east], [+region=us-west]]';
  ```

## Tools and Queries for Leaseholder Inspection

### Quick Reference: Essential Queries

**1. Show leaseholder counts by region:**
```sql
SET allow_unsafe_internals = true;

SELECT
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'YOUR_TABLE'
GROUP BY region;
```

**2. Find ranges with leaseholders outside expected region:**
```sql
SET allow_unsafe_internals = true;

SELECT
  r.range_id,
  r.lease_holder,
  n.locality
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'YOUR_TABLE'
  AND n.locality NOT LIKE '%region=YOUR_EXPECTED_REGION%';
```

**3. Show leaseholder distribution by zone within region:**
```sql
SET allow_unsafe_internals = true;

SELECT
  substring(n.locality FROM 'zone=([^,]+)') as zone,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'YOUR_TABLE'
  AND n.locality LIKE '%region=us-east%'
GROUP BY zone
ORDER BY leaseholder_count DESC;
```

**4. Check leaseholder locality with SHOW RANGES:**
```sql
SHOW RANGES FROM TABLE your_table WITH DETAILS;
-- Look at lease_holder_locality column
```

### Monitoring Leaseholder Location Over Time

**Set up recurring check:**
```sql
-- Save query as view for easy re-execution
CREATE VIEW leaseholder_distribution_users AS
SELECT
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count,
  round(100.0 * count(*) / sum(count(*)) OVER (), 2) as percentage,
  now() as checked_at
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'users'
GROUP BY region;

-- Query periodically
SELECT * FROM leaseholder_distribution_users;
```

**Export for monitoring dashboard:**
```sql
-- PostgreSQL wire protocol compatible
-- Can connect monitoring tools (Grafana, etc.) to query this
SET allow_unsafe_internals = true;

SELECT
  now() as timestamp,
  table_name,
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.database_name = 'mydb'
GROUP BY table_name, region
ORDER BY table_name, region;
```

## How Locality Affects Leaseholder Placement

### Node Locality Labels

Nodes are tagged with locality metadata at startup:
```bash
cockroach start \
  --locality=region=us-east,zone=us-e1a,datacenter=dc1 \
  --join=...
```

**Locality hierarchy:**
- `region`: Geographic region (us-east, us-west, eu-west)
- `zone`: Availability zone within region (us-e1a, us-e1b)
- `datacenter`: Physical datacenter (dc1, dc2) - optional

**Example cluster:**
- Node 1: `region=us-east,zone=us-e1a`
- Node 2: `region=us-east,zone=us-e1b`
- Node 3: `region=us-west,zone=us-w1a`

### Lease Preferences Use Locality

```sql
-- Prefer leaseholders in us-east region
ALTER TABLE users CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east]]';
```

**Effect:**
- Leaseholders transfer to nodes with `region=us-east` in locality
- Within us-east, balanced across zones (us-e1a, us-e1b, etc.)

**Fallback behavior:**
- If no us-east nodes available, leaseholder stays on current replica
- Leaseholder won't move to unavailable region

### Multi-Region Database Locality

```sql
-- Multi-region database with primary region
CREATE DATABASE mydb PRIMARY REGION "us-east" REGIONS "us-west", "eu-west";

-- Regional table (replicas in all regions, leaseholders in home region)
CREATE TABLE users (id UUID PRIMARY KEY) LOCALITY REGIONAL BY TABLE IN "us-east";
```

**Leaseholder placement:**
- All leaseholders automatically prefer nodes with `region=us-east`
- No manual zone config needed
- Multi-region database handles locality automatically

**Verify:**
```sql
SET allow_unsafe_internals = true;

SELECT
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'users'
GROUP BY region;

-- Should show 100% in us-east
```

## Summary

**Key takeaways:**

1. **Leaseholder location determines read latency** - reads always go to leaseholder
2. **Use SHOW RANGES WITH DETAILS** for quick visual inspection of leaseholder locality
3. **Query crdb_internal.ranges + gossip_nodes** for programmatic leaseholder analysis
4. **Verify leaseholders in expected region** after zone config changes (wait 30-60s)
5. **Troubleshoot wrong-region leaseholders** by checking replica placement, node health, and lease preferences

**Essential commands:**
```sql
-- Quick check: Show ranges with locality
SHOW RANGES FROM TABLE your_table WITH DETAILS;

-- Programmatic: Count leaseholders by region
SET allow_unsafe_internals = true;
SELECT
  substring(n.locality FROM 'region=([^,]+)') as region,
  count(*) as leaseholder_count
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'your_table'
GROUP BY region;

-- Troubleshoot: Find wrong-region leaseholders
SELECT r.range_id, n.locality
FROM crdb_internal.ranges r
JOIN crdb_internal.gossip_nodes n ON r.lease_holder = n.node_id
WHERE r.table_name = 'your_table'
  AND n.locality NOT LIKE '%region=expected-region%';
```

**Best practices:**
- Check leaseholder location when experiencing slow reads from specific region
- Verify leaseholder distribution after zone configuration changes
- Monitor leaseholder balance across zones within region
- Use lease preferences to control leaseholder placement explicitly
- Remember: Lease transfers take 30-60 seconds to complete
