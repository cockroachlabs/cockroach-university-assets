---
name: use-show-ranges-to-inspect-range-boundaries
description: Use SHOW RANGES to inspect range start_key and end_key boundaries, decode key encodings to understand boundary alignment, verify range continuity (no gaps), identify split points, check zone config boundary alignment, and find which range contains specific keys using SHOW RANGE FOR ROW.
metadata:
  domain: CockroachDB Architecture
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: active
  related_skills:
    - understand-range-key-boundaries-and-continuity
    - use-show-ranges-to-analyze-data-distribution
    - understand-range-splits-and-merges
    - inspect-range-distribution-replicas-and-leaseholder-placement
    - explain-distribution-layer-functionality
  prerequisites:
    - Understanding of CockroachDB key space and ranges
    - Basic SQL knowledge
    - Access to CockroachDB v26.1+ cluster
  estimated_time_minutes: 30
  last_updated: "2026-03-07"
---

# Use SHOW RANGES to Inspect Range Boundaries

**Domain**: CockroachDB Architecture
**Bloom's Level**: Apply

## What This Skill Teaches

This skill teaches how to use **SHOW RANGES** commands to inspect and verify range boundaries - the start and end keys that define where each range begins and ends in CockroachDB's sorted key space.

You'll learn how to:
- View start_key and end_key boundaries using SHOW RANGES
- Decode and interpret key encodings to understand boundary structure
- Find which range contains a specific key using SHOW RANGE FOR ROW
- Verify range continuity (confirm no gaps between ranges)
- Identify split points after manual or automatic range splits
- Check that range boundaries align with zone configuration partitions
- Use crdb_internal.ranges for programmatic boundary access

**Use cases**:
- Verify range splits occurred at expected boundaries
- Troubleshoot query performance by understanding boundary crossing
- Confirm partition boundaries align with range boundaries
- Debug data distribution issues
- Plan manual range splits for optimal distribution

**Core principle**: Range boundaries define contiguous segments of the key space with the guarantee that `Range[N].end_key = Range[N+1].start_key` - no gaps, no overlaps.

---

## Understanding Range Boundaries

### What Are Range Boundaries?

A **range** is defined by its boundaries:
- **start_key**: Inclusive lower boundary
- **end_key**: Exclusive upper boundary
- **Coverage**: Contains all keys K where `start_key ≤ K < end_key`

**Example**:
```
Range 42: [/Table/50/1/1000, /Table/50/1/2000)
  - Contains: /Table/50/1/1000, /Table/50/1/1001, ..., /Table/50/1/1999
  - Excludes: /Table/50/1/2000 (exclusive upper bound)
```

### Why Boundaries Matter

**Performance impact**:
- Queries within one range → Single RPC to leaseholder (~1-2ms)
- Queries crossing boundaries → Multiple RPCs to different leaseholders (higher latency)

**Data distribution**:
- Boundaries determine how data spreads across nodes
- Split points affect load balancing
- Partition boundaries should align with range boundaries for zone config enforcement

---

## SHOW RANGES Commands for Boundary Inspection

### Basic Syntax

```sql
-- Show ranges for a table (basic boundary info)
SHOW RANGES FROM TABLE database_name.table_name;

-- Show ranges with human-readable keys (recommended)
SHOW RANGES FROM TABLE database_name.table_name WITH DETAILS;

-- Show ranges for entire database
SHOW RANGES FROM DATABASE database_name;
```

### Key Output Columns

**Basic columns**:
- `start_key`: Raw start boundary (encoded bytes)
- `end_key`: Raw end boundary (encoded bytes)
- `range_id`: Unique range identifier
- `replicas`: Array of nodes holding replicas
- `lease_holder`: Node ID with leaseholder

**WITH DETAILS columns** (additional):
- `start_pretty`: Human-readable start key (`/Table/ID/Index/Value`)
- `end_pretty`: Human-readable end key
- `database_name`, `table_name`, `index_name`: Object identifiers

---

## Viewing and Interpreting Range Boundaries

### Example 1: Basic Boundary Inspection

```sql
-- Create test table
CREATE TABLE products (
  product_id INT PRIMARY KEY,
  name TEXT,
  price DECIMAL
);

-- Insert test data
INSERT INTO products (product_id, name, price)
SELECT i, 'Product ' || i, (i * 1.99)::DECIMAL
FROM generate_series(1, 10000) AS i;

-- View range boundaries
SHOW RANGES FROM TABLE products WITH DETAILS;
```

**Output** (before splits):
```
 range_id | start_key   | end_key    | start_pretty | end_pretty
----------+-------------+------------+--------------+-------------
      42  | <before:/1> | <after:/1> | /Table/50/1  | /Table/50/2
```

**Interpretation**:
- `<before:/1>`: Start of table key space
- `<after:/1>`: End of table key space
- `/Table/50/1`: Table ID 50, primary index (1)
- `/Table/50/2`: Next index boundary (table has one index currently)
- Single range contains all 10,000 rows

---

## Identifying Split Points and Boundary Changes

### Example 2: Manual Split and Boundary Verification

```sql
-- Split table at specific keys
ALTER TABLE products SPLIT AT VALUES (3000), (6000), (9000);

-- Verify split boundaries
SHOW RANGES FROM TABLE products WITH DETAILS;
```

**Output after split**:
```
 range_id | start_pretty      | end_pretty        | lease_holder
----------+-------------------+-------------------+--------------
      42  | /Table/50/1       | /Table/50/1/3000  |      1
      51  | /Table/50/1/3000  | /Table/50/1/6000  |      2
      52  | /Table/50/1/6000  | /Table/50/1/9000  |      3
      53  | /Table/50/1/9000  | /Table/50/2       |      1
```

**Boundary analysis**:
- Range 42: Keys 1-2999 (end_key `/Table/50/1/3000` is exclusive)
- Range 51: Keys 3000-5999
- Range 52: Keys 6000-8999
- Range 53: Keys 9000-10000

**Continuity verification**:
```
Range 42 end_key = /Table/50/1/3000 = Range 51 start_key ✅
Range 51 end_key = /Table/50/1/6000 = Range 52 start_key ✅
Range 52 end_key = /Table/50/1/9000 = Range 53 start_key ✅
```

### Example 3: Verify Specific Split Point

```sql
-- Check if split at key 6000 exists
SELECT
  range_id,
  start_pretty,
  end_pretty
FROM [SHOW RANGES FROM TABLE products WITH DETAILS]
WHERE end_pretty LIKE '%/6000%' OR start_pretty LIKE '%/6000%';
```

**Output**:
```
 range_id | start_pretty      | end_pretty
----------+-------------------+-------------------
      51  | /Table/50/1/3000  | /Table/50/1/6000
      52  | /Table/50/1/6000  | /Table/50/1/9000
```

**Confirms**: Range split occurred at key 6000.

---

## Finding Which Range Contains a Specific Key

### Using SHOW RANGE FOR ROW

```sql
-- Find which range contains product_id = 4500
SHOW RANGE FROM TABLE products FOR ROW (4500);
```

**Output**:
```
 start_key         | end_key           | range_id | replicas | lease_holder
-------------------+-------------------+----------+----------+--------------
 …/Table/50/1/3000 | …/Table/50/1/6000 |      51  | {1,2,3}  |      2
```

**Interpretation**:
- Key 4500 is in range 51 (boundaries 3000-6000)
- Leaseholder on node 2
- Queries for `product_id=4500` route to node 2

### Example 4: Composite Primary Key Lookup

```sql
-- Table with composite key
CREATE TABLE orders (
  customer_id INT,
  order_id INT,
  total DECIMAL,
  PRIMARY KEY (customer_id, order_id)
);

INSERT INTO orders VALUES (100, 1, 50.00), (100, 2, 75.00);

-- Find range for composite key
SHOW RANGE FROM TABLE orders FOR ROW (100, 2);
```

**Output shows**: Which range contains the composite key (100, 2).

---

## Verifying Range Continuity

### Example 5: Comprehensive Continuity Check

```sql
-- Query to verify no gaps between ranges
WITH range_boundaries AS (
  SELECT
    range_id,
    start_pretty AS start_key,
    end_pretty AS end_key,
    LEAD(start_pretty) OVER (ORDER BY start_pretty) AS next_start
  FROM [SHOW RANGES FROM TABLE products WITH DETAILS]
)
SELECT
  range_id,
  start_key,
  end_key,
  next_start,
  CASE
    WHEN next_start IS NULL THEN 'Last range'
    WHEN end_key = next_start THEN 'Continuous'
    ELSE 'GAP DETECTED'
  END AS continuity_check
FROM range_boundaries;
```

**Expected output** (healthy):
```
 range_id | start_key         | end_key           | next_start        | continuity_check
----------+-------------------+-------------------+-------------------+------------------
      42  | /Table/50/1       | /Table/50/1/3000  | /Table/50/1/3000  | Continuous
      51  | /Table/50/1/3000  | /Table/50/1/6000  | /Table/50/1/6000  | Continuous
      52  | /Table/50/1/6000  | /Table/50/1/9000  | /Table/50/1/9000  | Continuous
      53  | /Table/50/1/9000  | /Table/50/2       | NULL              | Last range
```

**What to look for**:
- All ranges show "Continuous" except last
- No "GAP DETECTED" entries
- End key of range N equals start key of range N+1

---

## Checking Zone Config Boundary Alignment

### Example 6: Verify Partition Boundaries Match Range Boundaries

```sql
-- Create partitioned table
CREATE TABLE regional_data (
  id INT,
  region TEXT,
  data TEXT,
  PRIMARY KEY (region, id)
) PARTITION BY LIST (region) (
  PARTITION us_east VALUES IN ('us-east'),
  PARTITION us_west VALUES IN ('us-west'),
  PARTITION eu_west VALUES IN ('eu-west')
);

-- Configure partition-specific zone configs
ALTER PARTITION us_east OF TABLE regional_data
  CONFIGURE ZONE USING constraints = '[+region=us-east]';

ALTER PARTITION us_west OF TABLE regional_data
  CONFIGURE ZONE USING constraints = '[+region=us-west]';

-- View range boundaries with partition info
SHOW RANGES FROM TABLE regional_data WITH DETAILS;
```

**Expected output**:
```
 range_id | start_pretty              | end_pretty                | partition_name
----------+---------------------------+---------------------------+----------------
      70  | /Table/60/1/"eu-west"     | /Table/60/1/"us-east"     | eu_west
      71  | /Table/60/1/"us-east"     | /Table/60/1/"us-west"     | us_east
      72  | /Table/60/1/"us-west"     | /Table/60/2               | us_west
```

**Verification**:
- Each partition has dedicated range(s) ✅
- Partition boundaries align with range boundaries ✅
- Allows independent replica placement per partition

### Detecting Misalignment

```sql
-- Check for ranges spanning multiple partitions (bad)
SELECT
  range_id,
  COUNT(DISTINCT partition_name) AS partition_count
FROM [SHOW RANGES FROM TABLE regional_data WITH DETAILS]
GROUP BY range_id
HAVING COUNT(DISTINCT partition_name) > 1;
```

**Expected**: No results (each range maps to one partition)

**If misalignment detected**: Range spans multiple partitions, preventing independent zone config enforcement. Solution: Add manual splits at partition boundaries.

---

## Using crdb_internal.ranges for Programmatic Access

### Example 7: Query Boundaries Programmatically

```sql
SET allow_unsafe_internals = true;

-- Find large ranges that may need splitting
SELECT
  range_id,
  start_pretty,
  end_pretty,
  lease_holder,
  range_size / (1024*1024) AS size_mb
FROM crdb_internal.ranges
WHERE table_name = 'products'
  AND range_size > 100 * 1024 * 1024  -- Ranges > 100 MB
ORDER BY range_size DESC;
```

**Use cases**:
- Automated boundary monitoring
- Identifying ranges needing splits
- Scripted verification after splits

### Example 8: Find Range Containing Specific Key

```sql
SET allow_unsafe_internals = true;

-- Find range containing key 5000
WITH target_key AS (
  SELECT '/Table/50/1/5000' AS key
)
SELECT
  r.range_id,
  r.start_pretty,
  r.end_pretty,
  r.lease_holder
FROM crdb_internal.ranges r, target_key t
WHERE r.table_name = 'products'
  AND r.start_pretty <= t.key
  AND r.end_pretty > t.key;
```

**Output**:
```
 range_id | start_pretty      | end_pretty        | lease_holder
----------+-------------------+-------------------+--------------
      51  | /Table/50/1/3000  | /Table/50/1/6000  |      2
```

**Interpretation**: Range 51 contains key 5000.

---

## Decoding Key Encodings

### Understanding Key Structure

**Key format**: `/KeyspaceType/TableID/IndexID/ColumnValues`

**Examples**:
- `/Table/50/1/12345` → Table 50, primary index (1), PK value 12345
- `/Table/50/2/67890` → Table 50, secondary index (2), index key 67890
- `/Table/50/1` → Start of table 50, index 1
- `/Table/50/2` → Start of next index (or next table if no secondary indexes)

### Example 9: View Raw vs. Pretty Keys

```sql
SELECT
  range_id,
  start_key AS raw_start,
  start_pretty AS decoded_start,
  end_key AS raw_end,
  end_pretty AS decoded_end
FROM [SHOW RANGES FROM TABLE products WITH DETAILS]
LIMIT 1;
```

**Output**:
```
 range_id | raw_start | decoded_start  | raw_end   | decoded_end
----------+-----------+----------------+-----------+------------------
      42  | \x8b89... | /Table/50/1    | \x8b8a... | /Table/50/1/3000
```

**Key takeaway**:
- Raw keys are byte sequences (`\x8b89...`)
- Pretty keys show logical structure (`/Table/50/1/3000`)
- Always use `start_pretty` and `end_pretty` for human interpretation

---

## Common Patterns and Use Cases

### Pattern 1: Pre-Split Table for Bulk Load

**Scenario**: Prevent hotspotting during bulk data import.

```sql
CREATE TABLE bulk_import (id BIGINT PRIMARY KEY, data TEXT);

-- Pre-split at expected boundaries (every 1M keys)
ALTER TABLE bulk_import SPLIT AT VALUES
  (1000000), (2000000), (3000000), (4000000), (5000000);

-- Verify splits
SHOW RANGES FROM TABLE bulk_import WITH DETAILS;

-- Scatter ranges across cluster
ALTER TABLE bulk_import SCATTER;
```

**Benefit**: Parallel bulk load across multiple ranges from start, avoiding single-range hotspot.

### Pattern 2: Isolate Hot Key in Dedicated Range

**Scenario**: Key 5000 experiencing high traffic.

```sql
-- Split to isolate hot key in its own range
ALTER TABLE products SPLIT AT VALUES (4999), (5001);

-- Verify isolation
SHOW RANGES FROM TABLE products WITH DETAILS;

-- Expected output:
-- Range X: [..., /Table/50/1/4999)
-- Range Y: [/Table/50/1/4999, /Table/50/1/5001)  ← Hot key isolated
-- Range Z: [/Table/50/1/5001, ...)
```

**Benefit**: Hot key in dedicated range can be moved to dedicated node or scaled independently.

### Pattern 3: Identify Ranges Affected by Query

**Scenario**: Understand multi-range query impact.

```sql
-- Query: SELECT * FROM products WHERE product_id BETWEEN 4000 AND 7500;
-- Find which ranges this spans

SET allow_unsafe_internals = true;

SELECT
  range_id,
  start_pretty,
  end_pretty,
  lease_holder
FROM crdb_internal.ranges
WHERE table_name = 'products'
  AND NOT (end_pretty <= '/Table/50/1/4000' OR start_pretty >= '/Table/50/1/7500');
```

**Output shows**: All ranges the query will touch (requiring RPCs to each leaseholder).

---

## Troubleshooting with Boundary Inspection

### Problem 1: Query Slower Than Expected

**Symptom**: Query for 100 keys takes 100ms.

**Diagnosis**:
```sql
-- Query: SELECT * FROM products WHERE product_id BETWEEN 5000 AND 5100;

-- Check how many ranges this spans
SET allow_unsafe_internals = true;

SELECT COUNT(*) AS ranges_touched
FROM crdb_internal.ranges
WHERE table_name = 'products'
  AND start_pretty < '/Table/50/1/5101'
  AND end_pretty > '/Table/50/1/5000';
```

**If result > 1**: Query crosses multiple ranges (multiple RPCs).

**Solution**: Wait for automatic range merges or review split strategy.

### Problem 2: Partition Zone Config Not Applied

**Symptom**: Partitioned table replicas in wrong regions.

**Diagnosis**:
```sql
-- Check for ranges spanning multiple partitions
SELECT
  range_id,
  COUNT(DISTINCT partition_name) AS partition_count
FROM [SHOW RANGES FROM TABLE regional_data WITH DETAILS]
GROUP BY range_id
HAVING COUNT(DISTINCT partition_name) > 1;
```

**If results found**: Range boundaries don't align with partition boundaries.

**Solution**:
```sql
-- Add splits at partition boundaries
ALTER TABLE regional_data SPLIT AT VALUES ('us-east'), ('us-west');
```

### Problem 3: Suspected Continuity Gap

**Symptom**: Data seems missing or queries skip keys.

**Diagnosis**: Use continuity check from Example 5.

**If gap found**: Critical issue - CockroachDB should maintain continuity invariant. Contact support.

---

## Best Practices

1. **Use WITH DETAILS for human analysis**
   - Easier to read than raw encoded keys
   - Shows table/index context

2. **Use SHOW RANGE FOR ROW for key lookups**
   - Fastest way to find which range contains a specific key

3. **Verify splits immediately after creation**
   ```sql
   ALTER TABLE mytable SPLIT AT VALUES (1000);
   SHOW RANGES FROM TABLE mytable WITH DETAILS;
   ```

4. **Check continuity after manual operations**
   - After splits/merges
   - After partition changes
   - During troubleshooting

5. **Use crdb_internal.ranges for automation**
   - Monitoring scripts
   - Automated split verification
   - Boundary analysis pipelines

6. **Align boundaries with access patterns**
   - Pre-split at natural boundaries (dates, regions)
   - Split to isolate hot keys
   - Merge small ranges to reduce overhead

7. **Understand query-boundary interaction**
   - Point reads: Single range = single RPC
   - Range scans: Multiple ranges = multiple RPCs
   - Design queries to minimize boundary crossings

---

## Key Concepts Summary

| Concept | Description |
|---------|-------------|
| **start_key** | Inclusive lower boundary of range |
| **end_key** | Exclusive upper boundary of range |
| **Range Coverage** | `[start_key, end_key)` - includes start, excludes end |
| **Continuity** | `Range[N].end_key = Range[N+1].start_key` (no gaps) |
| **Pretty Keys** | Human-readable: `/Table/ID/Index/Values` |
| **Raw Keys** | Byte-encoded format stored internally |
| **SHOW RANGE FOR ROW** | Find range containing specific primary key |
| **Boundary Alignment** | Partition/zone boundaries matching range boundaries |

---

## Related Skills

**Architecture**:
- `understand-range-key-boundaries-and-continuity` - Conceptual foundation
- `understand-range-splits-and-merges` - How boundaries change
- `explain-distribution-layer-functionality` - Routing using boundaries

**Operational**:
- `use-show-ranges-to-analyze-data-distribution` - General range analysis
- `inspect-range-distribution-replicas-and-leaseholder-placement` - Detailed inspection
- `modify-zone-configurations` - Zone config alignment

**Performance**:
- `identify-hot-ranges` - Finding ranges to split
- `design-primary-keys-for-even-data-distribution` - Schema design for good boundaries

---

## References

- [CockroachDB Docs: SHOW RANGES](https://www.cockroachlabs.com/docs/stable/show-ranges.html)
- [CockroachDB Docs: ALTER TABLE SPLIT AT](https://www.cockroachlabs.com/docs/stable/alter-table.html#split-at)
- [CockroachDB Docs: Distribution Layer](https://www.cockroachlabs.com/docs/stable/architecture/distribution-layer.html)
- [CockroachDB Docs: Partitioning](https://www.cockroachlabs.com/docs/stable/partitioning.html)

---

**Version**: 1.0.0
**Last Updated**: March 7, 2026
**Tested Against**: CockroachDB v26.1.0
