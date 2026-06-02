---
name: use-show-ranges-to-analyze-data-distribution
description: Use SHOW RANGES command variations to analyze how data is distributed across cluster nodes. Inspect range boundaries, replica placement, leaseholder locations, and range sizes. Identify hotspots, verify even distribution, check under-replication, and validate zone configuration compliance. Essential for performance troubleshooting and capacity planning.
metadata:
  domain: CockroachDB Architecture
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: active
  related_skills:
    - understand-range-based-data-distribution
    - use-show-ranges-to-inspect-range-boundaries
    - inspect-range-distribution-replicas-and-leaseholder-placement
    - apply-hash-sharding-to-prevent-sequential-key-hotspots
    - identify-hot-ranges
    - monitor-leaseholder-distribution
    - monitor-replica-distribution-balance
  prerequisites:
    - Understanding of CockroachDB range concepts
    - Basic SQL query knowledge
    - Access to CockroachDB cluster
  estimated_time_minutes: 25
  last_updated: "2026-03-07"
---

# Use SHOW RANGES to Analyze Data Distribution

**Domain**: CockroachDB Architecture
**Bloom's Level**: Apply

## Overview

The `SHOW RANGES` command reveals how CockroachDB distributes your data across the cluster by inspecting **ranges** - the fundamental unit of data distribution and replication. Understanding range distribution is critical for:

- **Performance troubleshooting**: Identifying hotspots and load imbalances
- **Capacity planning**: Understanding how data grows across nodes
- **Replication verification**: Confirming replicas are placed correctly
- **Schema optimization**: Validating that table designs distribute evenly

This skill teaches you how to use three levels of `SHOW RANGES` commands (cluster-level, database-level, table-level) to analyze data distribution patterns, interpret output columns, and diagnose common distribution issues.

---

## SHOW RANGES Command Variations

### Cluster-Level: View All Ranges

```sql
-- Basic cluster-wide range view
SHOW CLUSTER RANGES;

-- With table information
SHOW CLUSTER RANGES WITH TABLES;

-- With full details (replica localities, sizes, etc.)
SHOW CLUSTER RANGES WITH DETAILS;

-- Combination: tables + details
SHOW CLUSTER RANGES WITH TABLES, DETAILS;
```

**Use when**: You need a cluster-wide view of all ranges, including system ranges.

**Output columns** (basic):
- `start_key` - Range start boundary (encoded)
- `end_key` - Range end boundary (encoded)
- `range_id` - Unique range identifier
- `replicas` - Array of store IDs holding replicas
- `lease_holder` - Store ID holding the leaseholder

### Database-Level: View Database Ranges

```sql
-- Show all ranges for a database
SHOW RANGES FROM DATABASE mydb;

-- With full details
SHOW RANGES FROM DATABASE mydb WITH DETAILS;
```

**Use when**: Analyzing a specific database's range distribution.

**Example**:
```sql
SHOW RANGES FROM DATABASE bank WITH DETAILS;
```

### Table-Level: View Table Ranges

```sql
-- Show ranges for specific table
SHOW RANGES FROM TABLE mydb.users;

-- With full details
SHOW RANGES FROM TABLE mydb.users WITH DETAILS;
```

**Use when**: Analyzing how a specific table is split across ranges.

**Most common use case**: Troubleshooting performance issues with a specific table.

---

## Understanding SHOW RANGES Output

### Basic Output Columns

When you run `SHOW RANGES FROM TABLE users`:

```
 start_key          | end_key            | range_id | replicas | lease_holder
--------------------+--------------------+----------+----------+-------------
 …/1                | …/1000             | 42       | {1,2,3}  | 1
 …/1000             | …/5000             | 43       | {2,3,4}  | 2
 …/5000             | <after:/Table/54>  | 44       | {3,4,1}  | 3
```

**Column meanings**:

- **start_key / end_key**: Range boundaries in encoded format
  - Start key is **inclusive** (belongs to this range)
  - End key is **exclusive** (belongs to next range)
  - Keys are sorted lexicographically

- **range_id**: Unique identifier for the range
  - Monotonically increasing as ranges are created
  - Gaps in IDs indicate merged/removed ranges

- **replicas**: Array of **store IDs** (not node IDs) holding replicas
  - Default: 3 replicas per range
  - Format: `{store_1, store_2, store_3}`
  - For single-store-per-node deployments: store ID = node ID

- **lease_holder**: Store ID holding the leaseholder replica
  - Leaseholder serves all reads for this range
  - Coordinates all writes
  - Should be distributed evenly across nodes

### Extended Output with DETAILS

When you add `WITH DETAILS`:

```sql
SHOW RANGES FROM TABLE orders WITH DETAILS;
```

**Additional columns**:

- **database_name**: Database containing the range
- **table_name**: Table containing the range
- **schema_name**: Schema name (usually "public")
- **index_name**: Index name if range belongs to specific index
- **start_pretty**: Human-readable start key (e.g., `/1000`)
- **end_pretty**: Human-readable end key (e.g., `/5000`)
- **lease_holder_locality**: Locality tags of leaseholder node (e.g., `region=us-east,zone=a`)
- **replica_localities**: Locality tags array for all replicas
- **voting_replicas**: Replicas participating in Raft quorum
- **non_voting_replicas**: Non-voting replicas (read-only, don't vote)
- **learner_replicas**: Replicas being added (temporary state)
- **range_size_mb**: Approximate range size in MiB

**Example output interpretation**:

```
 range_id | start_pretty | end_pretty | replicas | lease_holder | range_size_mb | lease_holder_locality
----------+--------------+------------+----------+--------------+---------------+-----------------------
 42       | /1           | /1000      | {1,2,3}  | 1            | 128.5         | region=us-east,zone=a
 43       | /1000        | /5000      | {2,3,4}  | 2            | 256.3         | region=us-east,zone=b
```

**Reading this**:
- Range 42: Contains keys 1-999, replicas on stores {1,2,3}, leaseholder on store 1 (us-east zone a), size ~128 MiB
- Range 43: Contains keys 1000-4999, replicas on stores {2,3,4}, leaseholder on store 2 (us-east zone b), size ~256 MiB

---

## Practical Examples: Analyzing Distribution

### Example 1: Count Total Ranges

```sql
-- Total cluster ranges
SELECT count(*) AS total_ranges
FROM [SHOW CLUSTER RANGES];
```

**Expected output**:
```
 total_ranges
--------------
 347
```

**What this tells you**: Cluster has 347 ranges total (includes system ranges).

### Example 2: Count Ranges Per Table

```sql
-- Ranges per table
SELECT
  database_name,
  table_name,
  count(*) AS range_count
FROM [SHOW CLUSTER RANGES WITH TABLES]
WHERE database_name IS NOT NULL
GROUP BY database_name, table_name
ORDER BY range_count DESC
LIMIT 10;
```

**Expected output**:
```
 database_name | table_name | range_count
---------------+------------+-------------
 bank          | accounts   | 45
 bank          | transfers  | 23
 users_db      | profiles   | 18
```

**What this tells you**:
- `accounts` table has 45 ranges (likely large table or high write volume)
- `transfers` table has 23 ranges
- More ranges = more data or more splits for load distribution

### Example 3: Analyze Range Size Distribution

```sql
-- Find largest ranges approaching split threshold
SELECT
  range_id,
  database_name,
  table_name,
  range_size_mb,
  CASE
    WHEN range_size_mb > 450 THEN 'WARNING: Near split threshold'
    WHEN range_size_mb > 512 THEN 'ERROR: Exceeds default split size'
    ELSE 'OK'
  END AS status
FROM [SHOW CLUSTER RANGES WITH TABLES, DETAILS]
WHERE database_name IS NOT NULL
ORDER BY range_size_mb DESC
LIMIT 10;
```

**Expected output**:
```
 range_id | database_name | table_name | range_size_mb | status
----------+---------------+------------+---------------+--------------------------------
 89       | bank          | accounts   | 487.3         | WARNING: Near split threshold
 102      | bank          | transfers  | 256.1         | OK
 45       | users_db      | profiles   | 128.4         | OK
```

**What this tells you**:
- Range 89 is approaching the default 512 MiB split threshold
- Will likely split soon (automatic)
- If range doesn't split, check zone config for `range_max_bytes`

### Example 4: Check Leaseholder Distribution

```sql
-- Count leaseholders per node
SELECT
  lease_holder AS node_id,
  count(*) AS leaseholder_count
FROM [SHOW CLUSTER RANGES WITH DETAILS]
GROUP BY lease_holder
ORDER BY leaseholder_count DESC;
```

**Expected output (healthy)**:
```
 node_id | leaseholder_count
---------+------------------
 1       | 117
 2       | 115
 3       | 115
```

**What this tells you**: Leaseholders are balanced (~33% each on 3-node cluster).

**Expected output (problem)**:
```
 node_id | leaseholder_count
---------+------------------
 1       | 280
 2       | 45
 3       | 22
```

**What this tells you**:
- Node 1 has 81% of leaseholders (hotspot!)
- Check for leaseholder preferences in zone configs
- May indicate recent node addition (rebalancing in progress)

### Example 5: Verify Replica Placement

```sql
-- Check replica count per range (should be 3 for default config)
WITH range_replica_counts AS (
  SELECT
    range_id,
    table_name,
    array_length(replicas, 1) AS replica_count
  FROM [SHOW CLUSTER RANGES WITH TABLES, DETAILS]
  WHERE database_name = 'bank'
)
SELECT
  replica_count,
  count(*) AS ranges_with_count
FROM range_replica_counts
GROUP BY replica_count
ORDER BY replica_count;
```

**Expected output (healthy)**:
```
 replica_count | ranges_with_count
---------------+------------------
 3             | 68
```

**What this tells you**: All 68 ranges have exactly 3 replicas (healthy).

**Expected output (problem)**:
```
 replica_count | ranges_with_count
---------------+------------------
 1             | 5
 2             | 12
 3             | 51
```

**What this tells you**:
- 5 ranges have only 1 replica (under-replicated, risk of data loss!)
- 12 ranges have 2 replicas (under-replicated, reduced fault tolerance)
- Check for node failures or decommissioning in progress

---

## Identifying Hotspots

### Hotspot Indicator 1: Single Range for Large Table

**Symptom**: Table with millions of rows but only 1 range.

**Diagnosis**:
```sql
SELECT
  table_name,
  count(*) AS range_count,
  sum(range_size_mb) AS total_size_mb
FROM [SHOW RANGES FROM DATABASE mydb WITH DETAILS]
GROUP BY table_name
ORDER BY total_size_mb DESC;
```

**Example output**:
```
 table_name | range_count | total_size_mb
------------+-------------+---------------
 events     | 1           | 2048.5
```

**Problem**: 2 GB table with only 1 range = all reads/writes go to single leaseholder (bottleneck).

**Solution**:
```sql
-- Manually split at key boundaries
ALTER TABLE events SPLIT AT VALUES (1000000), (2000000), (3000000);

-- Or use hash-sharded index
CREATE INDEX ON events (event_id) USING HASH WITH (bucket_count=16);
```

### Hotspot Indicator 2: Uneven Range Sizes

**Diagnosis**:
```sql
SELECT
  range_id,
  table_name,
  range_size_mb,
  (SELECT avg(range_size_mb) FROM [SHOW RANGES FROM TABLE mydb.events WITH DETAILS]) AS avg_size
FROM [SHOW RANGES FROM TABLE mydb.events WITH DETAILS]
ORDER BY range_size_mb DESC;
```

**Example output**:
```
 range_id | table_name | range_size_mb | avg_size
----------+------------+---------------+----------
 89       | events     | 487.2         | 120.5
 90       | events     | 5.3           | 120.5
 91       | events     | 118.4         | 120.5
```

**Problem**: Range 89 is 4x larger than average (likely receiving most writes).

**Cause**: Sequential keys with monotonic inserts (all writes append to last range).

**Solution**: Hash-sharded primary key or UUID keys.

---

## Verifying Even Distribution

### Check 1: Range Count Balance Across Nodes

```sql
-- Count replicas per node
WITH replica_distribution AS (
  SELECT unnest(replicas) AS node_id
  FROM [SHOW CLUSTER RANGES WITH DETAILS]
)
SELECT
  node_id,
  count(*) AS replica_count,
  ROUND(100.0 * count(*) / sum(count(*)) OVER (), 2) AS percent
FROM replica_distribution
GROUP BY node_id
ORDER BY replica_count DESC;
```

**Expected output (healthy 3-node cluster)**:
```
 node_id | replica_count | percent
---------+---------------+--------
 1       | 348           | 33.14
 2       | 351           | 33.43
 3       | 351           | 33.43
```

**What this tells you**: Replicas are evenly distributed (~33% each).

**Expected output (problem)**:
```
 node_id | replica_count | percent
---------+---------------+--------
 1       | 520           | 49.52
 2       | 265           | 25.24
 3       | 265           | 25.24
```

**What this tells you**:
- Node 1 has nearly 50% of replicas (imbalance)
- Recently added nodes 2 and 3, rebalancing in progress
- Or zone config constraints limiting placement

### Check 2: Verify Multi-Region Replica Placement

```sql
-- Check replica localities for geo-distribution
SELECT
  range_id,
  table_name,
  replica_localities
FROM [SHOW RANGES FROM TABLE bank.accounts WITH DETAILS]
LIMIT 10;
```

**Expected output (healthy multi-region)**:
```
 range_id | table_name | replica_localities
----------+------------+----------------------------------------------------
 42       | accounts   | {"region=us-east,zone=a","region=us-west,zone=a","region=eu-west,zone=a"}
 43       | accounts   | {"region=us-east,zone=b","region=us-west,zone=a","region=eu-west,zone=a"}
```

**What this tells you**:
- Each range has replicas in 3 different regions (fault tolerant)
- Survives single region failure

**Expected output (problem)**:
```
 range_id | table_name | replica_localities
----------+------------+----------------------------------------------------
 42       | accounts   | {"region=us-east,zone=a","region=us-east,zone=b","region=us-east,zone=c"}
```

**What this tells you**:
- All replicas in same region (no regional fault tolerance!)
- Check zone configuration constraints

---

## Finding Under-Replicated or Over-Replicated Ranges

### Identify Under-Replicated Ranges

```sql
-- Find ranges with fewer than 3 replicas (default)
SELECT
  range_id,
  database_name,
  table_name,
  array_length(replicas, 1) AS replica_count,
  replicas
FROM [SHOW CLUSTER RANGES WITH TABLES, DETAILS]
WHERE array_length(replicas, 1) < 3
ORDER BY replica_count;
```

**Expected output (problem)**:
```
 range_id | database_name | table_name | replica_count | replicas
----------+---------------+------------+---------------+----------
 89       | bank          | accounts   | 1             | {1}
 102      | bank          | transfers  | 2             | {1,2}
```

**What this tells you**:
- Range 89 has only 1 replica (critical - no fault tolerance!)
- Range 102 has 2 replicas (reduced fault tolerance)
- Check for node failures, decommissioning, or replication in progress

**Next steps**:
1. Check node status: `cockroach node status`
2. Check for unavailable ranges in DB Console
3. Wait for automatic upreplication (usually completes within minutes)

### Identify Over-Replicated Ranges

```sql
-- Find ranges with more than 3 replicas (unusual)
SELECT
  range_id,
  database_name,
  table_name,
  array_length(replicas, 1) AS replica_count,
  replicas
FROM [SHOW CLUSTER RANGES WITH TABLES, DETAILS]
WHERE array_length(replicas, 1) > 3
ORDER BY replica_count DESC;
```

**Use case**: Verify zone configuration with `num_replicas = 5`.

---

## Checking Leaseholder Placement Patterns

### Verify Leaseholder Preferences

**Scenario**: Set leaseholder preference for us-east region, verify compliance.

```sql
-- Set leaseholder preference
ALTER TABLE bank.accounts CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east]]';

-- Wait 30-60 seconds for lease transfers

-- Verify leaseholder locations
SELECT
  lease_holder_locality,
  count(*) AS lease_count
FROM [SHOW RANGES FROM TABLE bank.accounts WITH DETAILS]
GROUP BY lease_holder_locality
ORDER BY lease_count DESC;
```

**Expected output (healthy)**:
```
 lease_holder_locality    | lease_count
--------------------------+------------
 region=us-east,zone=a    | 28
 region=us-east,zone=b    | 17
 region=us-west,zone=a    | 0
```

**What this tells you**: All leaseholders moved to us-east (preference respected).

**Expected output (problem)**:
```
 lease_holder_locality    | lease_count
--------------------------+------------
 region=us-west,zone=a    | 25
 region=us-east,zone=a    | 20
```

**What this tells you**:
- 56% of leaseholders still in us-west (preference NOT respected)
- Check: Are there us-east nodes with replicas?
- Wait longer (lease transfers can take 60+ seconds)
- Check for load-based overrides (high load can pin leaseholders)

---

## Performance Considerations

### SHOW RANGES Can Be Expensive

**Why**:
- Scans range metadata for entire cluster
- On large clusters (1000+ ranges), can take seconds
- Cluster-wide queries scan all nodes

**Best practices**:

1. **Scope to specific tables when possible**:
   ```sql
   -- Faster: specific table
   SHOW RANGES FROM TABLE mydb.users;

   -- Slower: entire cluster
   SHOW CLUSTER RANGES;
   ```

2. **Use WITH DETAILS only when needed**:
   ```sql
   -- Faster: basic info
   SHOW RANGES FROM TABLE mydb.users;

   -- Slower: includes sizes, localities
   SHOW RANGES FROM TABLE mydb.users WITH DETAILS;
   ```

3. **Cache results for repeated analysis**:
   ```sql
   -- Save to temporary table
   CREATE TABLE range_snapshot AS
   SELECT * FROM [SHOW CLUSTER RANGES WITH TABLES, DETAILS];

   -- Run multiple analyses on cached data
   SELECT * FROM range_snapshot WHERE table_name = 'accounts';
   SELECT count(*) FROM range_snapshot GROUP BY database_name;
   ```

4. **Run during off-peak hours**:
   - For large production clusters
   - Especially for cluster-wide analyses

---

## Troubleshooting Common Issues

### Issue 1: Table Not Splitting Despite Large Size

**Symptom**: Table is 2 GB but has only 1 range.

**Diagnosis**:
```sql
SHOW RANGES FROM TABLE large_table WITH DETAILS;
-- If only 1 range with range_size_mb > 512
```

**Possible causes**:
1. Splits disabled in zone config
2. Table recently created (splits happen asynchronously)
3. All data has same key prefix (can't split effectively)

**Solutions**:

**Check zone config**:
```sql
SHOW ZONE CONFIGURATION FOR TABLE large_table;
-- Look for range_max_bytes = 0 (splits disabled)
```

**Re-enable splits**:
```sql
ALTER TABLE large_table CONFIGURE ZONE USING
  range_max_bytes = 536870912;  -- 512 MiB default
```

**Manual split if urgent**:
```sql
ALTER TABLE large_table SPLIT AT VALUES (1000000), (2000000), (3000000);
```

### Issue 2: Excessive Small Ranges

**Symptom**: Many ranges < 10 MiB.

**Diagnosis**:
```sql
SELECT count(*) AS small_ranges
FROM [SHOW CLUSTER RANGES WITH DETAILS]
WHERE range_size_mb < 10;
```

**Cause**: Excessive manual splits or oscillating workload.

**Impact**:
- Metadata overhead
- Slower range scans
- Cache thrashing

**Solution**:
```sql
-- Wait for automatic merging (adjacent ranges < range_min_bytes will merge)
-- Default range_min_bytes = 128 MiB

-- Check zone config
SHOW ZONE CONFIGURATION FOR TABLE problem_table;

-- Verify merging is enabled
-- If range_min_bytes = 0, merging is disabled
```

### Issue 3: Leaseholder Imbalance

**Symptom**: One node has 80% of leaseholders.

**Diagnosis**:
```sql
SELECT
  lease_holder,
  count(*) AS lease_count,
  ROUND(100.0 * count(*) / sum(count(*)) OVER (), 2) AS percent
FROM [SHOW CLUSTER RANGES WITH DETAILS]
GROUP BY lease_holder
ORDER BY lease_count DESC;
```

**Causes**:
1. Recent node addition (rebalancing in progress)
2. Leaseholder preferences in zone config
3. Node affinity due to locality

**Solutions**:

**Wait for automatic rebalancing** (usually 5-10 minutes):
```bash
# Monitor rebalancing
watch -n 5 'cockroach sql --insecure -e "
  SELECT lease_holder, count(*) FROM [SHOW CLUSTER RANGES WITH DETAILS]
  GROUP BY lease_holder ORDER BY lease_holder;"'
```

**Check zone config for preferences**:
```sql
SHOW ZONE CONFIGURATION FOR DATABASE mydb;
-- Look for lease_preferences settings
```

**Verify node health**:
```bash
cockroach node status --insecure
# Ensure all nodes are live and available
```

---

## Complete Analysis Example

**Scenario**: Analyze distribution for new `orders` table after bulk load.

```sql
-- Step 1: Count ranges
SELECT count(*) AS range_count
FROM [SHOW RANGES FROM TABLE bank.orders];

-- Step 2: Check range sizes
SELECT
  range_id,
  range_size_mb,
  start_pretty,
  end_pretty
FROM [SHOW RANGES FROM TABLE bank.orders WITH DETAILS]
ORDER BY range_size_mb DESC;

-- Step 3: Verify replica placement
SELECT
  range_id,
  replicas,
  array_length(replicas, 1) AS replica_count
FROM [SHOW RANGES FROM TABLE bank.orders WITH DETAILS]
WHERE array_length(replicas, 1) != 3;
-- Should return no rows (all ranges have 3 replicas)

-- Step 4: Check leaseholder distribution
SELECT
  lease_holder,
  count(*) AS lease_count
FROM [SHOW RANGES FROM TABLE bank.orders WITH DETAILS]
GROUP BY lease_holder
ORDER BY lease_holder;

-- Step 5: Verify multi-region placement (if applicable)
SELECT
  range_id,
  replica_localities
FROM [SHOW RANGES FROM TABLE bank.orders WITH DETAILS]
LIMIT 5;
```

**Expected healthy results**:
- Range count: ~1 range per 256-512 MiB of data
- Range sizes: Between 128 MiB and 512 MiB
- Replica count: 3 replicas per range
- Leaseholders: Evenly distributed across nodes
- Replica localities: Match zone configuration

---

## Best Practices

1. **Start with table-level queries** for targeted analysis:
   ```sql
   SHOW RANGES FROM TABLE mydb.users WITH DETAILS;
   ```

2. **Use cluster-level queries sparingly** (expensive on large clusters).

3. **Monitor range count over time**:
   - Too few ranges for large table = hotspots
   - Too many small ranges = overhead

4. **Verify distribution after**:
   - Bulk data loads
   - Zone configuration changes
   - Node additions/removals
   - Schema changes

5. **Check leaseholder placement** for read-heavy workloads:
   - Leaseholders should be near users
   - Use `lease_preferences` to optimize read latency

6. **Automate distribution checks**:
   ```bash
   # Weekly distribution health check
   cockroach sql --insecure -e "
     SELECT 'Total Ranges' AS metric, count(*)::TEXT AS value
     FROM [SHOW CLUSTER RANGES]
     UNION ALL
     SELECT 'Avg Range Size (MB)',
       ROUND(avg(range_size_mb), 2)::TEXT
     FROM [SHOW CLUSTER RANGES WITH DETAILS];"
   ```

---

## Verification Checklist

✅ **Healthy distribution when**:
- Total ranges proportional to data size (~1 per 256-512 MiB)
- Range sizes between 128 MiB and 512 MiB
- All ranges have expected replica count (default 3)
- Leaseholders evenly distributed across nodes (±10%)
- Replicas match zone configuration constraints
- No under-replicated ranges
- Replica localities match expected regions/zones

⚠️ **Warning signs**:
- Single range for multi-GB table (hotspot risk)
- Many ranges < 10 MiB (excessive splitting)
- Ranges > 512 MiB (split not happening)
- Leaseholder imbalance > 20% difference
- Under-replicated ranges (replica count < expected)
- All replicas in single region/zone (no fault tolerance)

---

## Related Skills

**Foundational**:
- `understand-range-based-data-distribution` - Range concepts and architecture
- `use-show-ranges-to-inspect-range-boundaries` - Detailed boundary inspection

**Advanced Analysis**:
- `inspect-range-distribution-replicas-and-leaseholder-placement` - Deep replica analysis
- `identify-hot-ranges` - Finding high-traffic ranges
- `monitor-replica-distribution-balance` - Ongoing distribution monitoring
- `monitor-leaseholder-distribution` - Leaseholder balance tracking

**Optimization**:
- `apply-hash-sharding-to-prevent-sequential-key-hotspots` - Fixing hotspot issues
- `create-manual-range-splits-for-load-distribution` - Manual splitting techniques
- `configure-zone-leaseholder-preferences` - Optimizing leaseholder placement

---

## References

- [SHOW RANGES Documentation](https://www.cockroachlabs.com/docs/stable/show-ranges.html)
- [Range Architecture](https://www.cockroachlabs.com/docs/stable/architecture/overview.html#range)
- [Distribution Layer](https://www.cockroachlabs.com/docs/stable/architecture/distribution-layer.html)
- [Configure Replication Zones](https://www.cockroachlabs.com/docs/stable/configure-replication-zones.html)
- [Hash-Sharded Indexes](https://www.cockroachlabs.com/docs/stable/hash-sharded-indexes.html)

---

**Version**: 1.0.0
**Last Updated**: March 7, 2026
**Tested Against**: CockroachDB v26.1.0
