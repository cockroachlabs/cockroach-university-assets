---
name: analyze-key-value-pairs-and-range-distribution-using-show-ranges
description: Use SHOW RANGES commands to analyze how table data and indexes are split into ranges and distributed across cluster nodes. Understand key-value encoding, range boundaries, replica placement, and leaseholder assignment for performance troubleshooting.
metadata:
  domain: Data Distribution
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  related_skills:
    - understand-range-based-data-distribution
    - view-zone-configuration-settings
    - understand-quorum-and-cluster-resilience-under-node-failures
    - identify-hot-ranges
  prerequisites:
    - Understanding of CockroachDB's key-value storage model
    - Knowledge of ranges and replication
  estimated_time_minutes: 25
  last_updated: "2026-03-06"
---

# Analyze Key-Value Pairs and Range Distribution Using SHOW RANGES

## Overview

CockroachDB stores all data as **key-value pairs** in a distributed, sorted key space. This key space is divided into contiguous **ranges** (default ~512 MiB) which are the unit of data distribution and replication.

**Key concepts:**
- **Key-value encoding**: Tables, indexes, and rows → sorted keys
- **Ranges**: Contiguous slices of the key space (start_key to end_key)
- **Range splits**: Automatic division when ranges grow too large
- **Replica placement**: Where range replicas are stored
- **Leaseholder**: Which replica serves reads

**The `SHOW RANGES` command family** reveals how data is distributed, enabling you to:
- Understand how primary keys affect distribution
- Identify hotspots (overloaded ranges)
- Verify zone configuration compliance
- Troubleshoot performance issues
- Plan schema changes

## How Tables Map to Key-Value Pairs

### Table Data Encoding

Every row in a table becomes a key-value pair:

```
Table: users (id INT PRIMARY KEY, name STRING, email STRING)
Row:   (1, 'Alice', 'alice@example.com')

Key:   /Table/53/1/1        (TableID=53, IndexID=1, PK=1)
Value: {name: 'Alice', email: 'alice@example.com'}
```

**Key structure:**
- `/Table/<table_id>/<index_id>/<primary_key_value>`
- Keys are **lexicographically sorted**
- Determines physical storage order

### Index Encoding

Secondary indexes create additional key-value pairs:

```
Index: users@email_idx ON email
Row:   (1, 'Alice', 'alice@example.com')

Key:   /Table/53/2/alice@example.com/1  (TableID=53, IndexID=2, email, PK)
Value: {} (empty, PK back-reference only)
```

**Why understand encoding?**
- Primary key choice determines range distribution
- Sequential keys (auto-increment) create hotspots
- UUID/hash-sharded keys distribute evenly

## Basic SHOW RANGES Commands

### Show Ranges for Table

```sql
-- Basic range information
SHOW RANGES FROM TABLE users;
```

**Output columns:**
- `start_key`: Beginning of range (pretty-printed)
- `end_key`: End of range (exclusive)
- `range_id`: Unique range identifier
- `replicas`: Array of node IDs holding replicas
- `lease_holder`: Node ID serving reads

**Example output:**
```
  start_key | end_key | range_id | replicas | lease_holder
------------+---------+----------+----------+--------------
  <before:/Table/53/1/1> | <before:/Table/53/1/1000> | 42 | {1,2,3} | 1
  <before:/Table/53/1/1000> | <before:/Table/53/1/2000> | 43 | {2,3,4} | 2
  <before:/Table/53/1/2000> | <after:/Max> | 44 | {1,3,5} | 3
```

### Show Ranges with Details

```sql
-- Detailed range information including statistics
SHOW RANGES FROM TABLE users WITH DETAILS;
```

**Additional columns:**
- `lease_holder_locality`: Geographic location of leaseholder
- `replicas_localities`: Locations of all replicas
- `voting_replicas`: Replicas participating in quorum
- `non_voting_replicas`: Replicas for reads only
- `split_enforced_until`: Time range split is protected from merging

**Example:**
```sql
SELECT
  range_id,
  start_key,
  replicas,
  lease_holder,
  lease_holder_locality
FROM [SHOW RANGES FROM TABLE users WITH DETAILS]
LIMIT 5;
```

### Show Ranges for Database

```sql
-- All ranges for database (all tables)
SHOW RANGES FROM DATABASE mydb;

-- Useful for understanding overall database distribution
```

### Show Ranges for Index

```sql
-- Ranges for specific index
SHOW RANGES FROM INDEX users@email_idx;

-- Compare primary table vs secondary index distribution
```

## Interpreting Range Boundaries

### Understanding start_key and end_key

Keys use **pretty-printed format** for readability:

```
<before:/Table/53/1/100>   → Range starts before PK=100
<after:/Table/53/1/999>    → Range starts after PK=999
<before:/Max>              → Range ends at maximum key
```

**Key prefixes:**
- `/Table/<id>/<index>/<pk>` - Table data
- `/NamespaceTable/...` - System metadata
- `<before:` - Exclusive lower bound
- `<after:` - Inclusive lower bound

### Range Continuity

Ranges form **contiguous coverage** with no gaps:

```
Range 1: [A → M)
Range 2: [M → Z)
Range 3: [Z → ∞)
```

**Verification query:**
```sql
-- Check for continuity (end_key of range N = start_key of range N+1)
WITH ranges AS (
  SELECT range_id, start_key, end_key
  FROM [SHOW RANGES FROM TABLE users]
  ORDER BY start_key
)
SELECT
  r1.range_id AS range1,
  r1.end_key AS range1_end,
  r2.range_id AS range2,
  r2.start_key AS range2_start,
  CASE WHEN r1.end_key = r2.start_key THEN 'OK' ELSE 'GAP!' END AS continuity
FROM ranges r1
JOIN ranges r2 ON r2.range_id > r1.range_id;
```

## Analyzing Replica Placement

### Replica Distribution

```sql
-- Count replicas per node
SELECT
  unnest(replicas) AS node_id,
  count(*) AS range_count
FROM [SHOW RANGES FROM TABLE users]
GROUP BY node_id
ORDER BY range_count DESC;
```

**Expected result**: Balanced distribution across nodes.

**Interpretation:**
- Uneven counts indicate ongoing rebalancing
- Or zone constraints forcing specific placement

### Leaseholder Distribution

```sql
-- Leaseholder distribution by node
SELECT
  lease_holder,
  count(*) AS lease_count
FROM [SHOW RANGES FROM TABLE users]
GROUP BY lease_holder
ORDER BY lease_count DESC;
```

**Why it matters**: Leaseholders serve all reads, so balanced distribution prevents hotspots.

### Geographic Distribution

```sql
-- Replica distribution by region
SELECT
  unnest(replicas_localities) AS locality,
  count(*) AS replica_count
FROM [SHOW RANGES FROM TABLE users WITH DETAILS]
GROUP BY locality
ORDER BY replica_count DESC;
```

**Use cases:**
- Verify data domiciling compliance
- Ensure multi-region fault tolerance
- Validate zone constraint application

## Analyzing Range Size and Count

### Count Ranges per Table

```sql
-- How many ranges does table span?
SELECT count(*) AS range_count
FROM [SHOW RANGES FROM TABLE users];
```

**Interpretation:**
- More ranges = more parallel processing capacity
- Fewer ranges = less overhead but potential hotspots
- Default: tables start with 1 range, split automatically

### Estimate Range Sizes

```sql
-- Approximate range sizes (requires details)
SELECT
  range_id,
  start_key,
  end_key,
  (span_stats->>'approximate_disk_bytes')::BIGINT AS disk_bytes,
  (span_stats->>'key_count')::BIGINT AS key_count
FROM [SHOW RANGES FROM TABLE users WITH DETAILS]
ORDER BY disk_bytes DESC
LIMIT 10;
```

**Key metrics:**
- `approximate_disk_bytes`: Total bytes on disk
- `key_count`: Number of key-value pairs
- Ranges split when exceeding ~512 MiB (configurable via zone configs)

### Find Large Ranges

```sql
-- Ranges approaching split threshold
SELECT
  range_id,
  (span_stats->>'approximate_disk_bytes')::BIGINT / (1024*1024) AS size_mb
FROM [SHOW RANGES FROM TABLE users WITH DETAILS]
WHERE (span_stats->>'approximate_disk_bytes')::BIGINT > 400 * 1024 * 1024
ORDER BY size_mb DESC;
```

**Actionable**: Ranges > 400 MiB may split soon; plan for increased range count.

## Identifying Hot Ranges

### What is a Hot Range?

A **hot range** receives disproportionate traffic, causing:
- High CPU on leaseholder node
- Increased query latency
- Unbalanced load distribution

**Common causes:**
- Sequential primary keys (auto-increment IDs)
- All writes hitting same range
- Popular read queries targeting single range

### Detecting Hot Ranges

```sql
-- Find ranges with high key counts (proxy for activity)
SELECT
  range_id,
  start_key,
  end_key,
  (span_stats->>'key_count')::BIGINT AS keys,
  lease_holder,
  lease_holder_locality
FROM [SHOW RANGES FROM TABLE users WITH DETAILS]
ORDER BY keys DESC
LIMIT 10;
```

**Note**: `SHOW RANGES` doesn't show traffic metrics directly. Use DB Console → Metrics for QPS per range.

### Hotspot Patterns

**Sequential key pattern:**
```
Range 1: [1 → 1000)      100 writes/sec
Range 2: [1000 → 2000)   5 writes/sec
Range 3: [2000 → 3000)   5 writes/sec
Range 4: [3000 → ∞)      5000 writes/sec  ← HOTSPOT (newest data)
```

**Uniform distribution (after hash sharding):**
```
Range 1: [hash1 → hash2)   500 writes/sec
Range 2: [hash2 → hash3)   490 writes/sec
Range 3: [hash3 → hash4)   510 writes/sec
Range 4: [hash4 → ∞)       500 writes/sec  ← Even distribution
```

## Common Analysis Scenarios

### Scenario 1: Verify Zone Configuration Applied

**Task**: Confirm payments table has 5 replicas in us-east region

```sql
-- Step 1: Check zone config
SHOW ZONE CONFIGURATION FOR TABLE payments;
-- Look for: num_replicas = 5, constraints = '[+region=us-east]'

-- Step 2: Verify actual placement
SELECT
  range_id,
  array_length(replicas, 1) AS replica_count,
  replicas_localities
FROM [SHOW RANGES FROM TABLE payments WITH DETAILS]
LIMIT 10;

-- Step 3: Verify all localities are us-east
SELECT DISTINCT
  unnest(replicas_localities) AS locality
FROM [SHOW RANGES FROM TABLE payments WITH DETAILS];
-- Should only show us-east localities
```

### Scenario 2: Understand Primary Key Impact

**Task**: Compare range distribution for auto-increment vs UUID keys

```sql
-- Auto-increment table (sequential keys)
SHOW RANGES FROM TABLE orders_autoincrement;
-- Expect: Few ranges, newest range gets all writes

-- UUID table (random keys)
SHOW RANGES FROM TABLE orders_uuid;
-- Expect: More ranges, writes distributed evenly

-- Count ranges for each
SELECT
  'auto_increment' AS table_type,
  count(*) AS range_count
FROM [SHOW RANGES FROM TABLE orders_autoincrement]
UNION ALL
SELECT
  'uuid' AS table_type,
  count(*) AS range_count
FROM [SHOW RANGES FROM TABLE orders_uuid];
```

**Result interpretation**:
- Auto-increment: Fewer ranges (poor distribution)
- UUID: More ranges (better distribution)

### Scenario 3: Identify Unbalanced Leaseholder Distribution

**Task**: Find if one node is overloaded with leaseholders

```sql
-- Leaseholders per node
SELECT
  lease_holder,
  count(*) AS lease_count,
  round(count(*) * 100.0 / sum(count(*)) OVER (), 2) AS percent
FROM [SHOW RANGES FROM TABLE users]
GROUP BY lease_holder
ORDER BY lease_count DESC;
```

**Example output:**
```
lease_holder | lease_count | percent
-------------|-------------|--------
     1       |     450     |  45.0   ← Overloaded!
     2       |     300     |  30.0
     3       |     250     |  25.0
```

**Action**: Consider setting lease preferences to balance load.

### Scenario 4: Trace Key Distribution

**Task**: Understand how specific keys map to ranges

```sql
-- Insert test data with known keys
INSERT INTO users (id, name) VALUES
  (1, 'Alice'),
  (1000, 'Bob'),
  (2000, 'Carol'),
  (3000, 'Dave');

-- Find which range each key belongs to
SHOW RANGES FROM TABLE users;

-- Decode start_key/end_key to see boundaries:
-- Range 1: [1 → 1000)    Contains id=1
-- Range 2: [1000 → 2000) Contains id=1000
-- Range 3: [2000 → 3000) Contains id=2000
-- Range 4: [3000 → ∞)    Contains id=3000
```

### Scenario 5: Multi-Region Compliance Audit

**Task**: Verify EU data stays in EU region

```sql
-- Check all ranges for eu_customers table
SELECT
  range_id,
  replicas,
  replicas_localities,
  lease_holder_locality
FROM [SHOW RANGES FROM TABLE eu_customers WITH DETAILS];

-- Verify no non-EU localities
SELECT DISTINCT
  unnest(replicas_localities) AS locality
FROM [SHOW RANGES FROM TABLE eu_customers WITH DETAILS]
WHERE unnest(replicas_localities) NOT LIKE '%eu-%';
-- Should return empty set
```

## Advanced Analysis: Querying crdb_internal.ranges

For programmatic analysis, query system tables:

```sql
-- Comprehensive range information
SELECT
  range_id,
  start_pretty,
  end_pretty,
  replicas,
  lease_holder,
  range_size,
  split_enforced_until
FROM crdb_internal.ranges
WHERE table_id = (
  SELECT table_id FROM crdb_internal.tables
  WHERE name = 'users'
);
```

**Available fields:**
- `start_pretty` / `end_pretty`: Human-readable keys
- `range_size`: Approximate bytes
- `split_enforced_until`: Protected from merge until this time
- `table_id`: Numeric table identifier

### Find Under-Replicated Ranges

```sql
-- Ranges with fewer than expected replicas
SELECT
  range_id,
  replicas,
  array_length(replicas, 1) AS actual_replicas
FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3
ORDER BY range_id;
```

**Interpretation**: Under-replication indicates:
- Recent node failures
- Insufficient nodes in cluster
- Zone constraints impossible to satisfy

## Best Practices

1. **Check range distribution regularly**: Monitor for hotspots and imbalances
2. **Correlate with query patterns**: Use SHOW RANGES + EXPLAIN to understand query-range mapping
3. **Validate zone configs**: Always verify actual placement matches configuration
4. **Monitor range count growth**: Automatic splits indicate data growth
5. **Use DETAILS for production**: Full locality information critical for multi-region
6. **Automate compliance checks**: Regular audits of geographic placement

## Troubleshooting

### Problem: Too many ranges for small table

**Diagnosis:**
```sql
-- Count ranges
SELECT count(*) FROM [SHOW RANGES FROM TABLE small_table];
-- Returns: 100 ranges for 1 MB table

-- Check split history
SHOW RANGES FROM TABLE small_table WITH DETAILS;
-- Look for split_enforced_until values
```

**Cause**: Manual splits or split from deleted data.

**Solution**: Ranges will merge automatically over time (default after 1 hour).

### Problem: All ranges on single node

**Diagnosis:**
```sql
-- Check replica distribution
SELECT
  unnest(replicas) AS node_id,
  count(*) AS range_count
FROM [SHOW RANGES FROM TABLE mytable]
GROUP BY node_id;
-- Returns: All ranges on node 1
```

**Causes:**
- Single-node cluster (expected)
- Zone constraints too restrictive
- Rebalancing disabled or slow

**Solution**: Check cluster size and zone configs.

### Problem: Cannot interpret start_key/end_key

**Example**: `<before:/Table/53/1/"\x12\x89\x00\x00\x00\x00\x00\x00\x01">`

**Explanation**: Non-printable keys shown as hex. Indicates:
- Composite primary key
- Binary data type (BYTES)
- Multi-column key encoding

**Solution**: Decode manually or focus on range_id for troubleshooting.

### Problem: Leaseholder locality is None

**Diagnosis:**
```sql
SELECT
  range_id,
  lease_holder_locality
FROM [SHOW RANGES FROM TABLE mytable WITH DETAILS]
WHERE lease_holder_locality IS NULL;
```

**Cause**: Nodes started without `--locality` flag.

**Solution**: Restart nodes with proper locality configuration.

## Summary

`SHOW RANGES` reveals how CockroachDB distributes data:

✅ **Range boundaries** - How key space is partitioned
✅ **Replica placement** - Where data is stored geographically
✅ **Leaseholder assignment** - Which nodes serve reads
✅ **Range counts** - Number of parallel processing units
✅ **Compliance verification** - Data domiciling and zone configs

**Key principle**: Understanding range distribution is essential for performance tuning, capacity planning, and compliance validation.

**Common workflow:**
1. Check zone config: `SHOW ZONE CONFIGURATION`
2. Verify actual placement: `SHOW RANGES WITH DETAILS`
3. Analyze distribution: Count ranges per node/region
4. Identify issues: Hotspots, under-replication, imbalance
5. Take action: Adjust zone configs, primary keys, or add capacity
