---
name: apply-hash-sharding-to-prevent-sequential-key-hotspots
description: Use USING HASH clause to distribute sequential keys across ranges, preventing write hotspots. Hash function maps sequential values to buckets (default 16) spreading writes across the cluster. Fixes timestamp, auto-increment, and date-based hotspots with trade-off on range scan efficiency.
metadata:
  domain: Schema Design
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags: cdc, indexing, performance
  related_skills:
    - understand-sequential-key-hotspot-issues
    - alter-tables-to-change-primary-keys
    - design-primary-keys-for-even-data-distribution
    - create-composite-primary-keys-with-proper-column-ordering
  prerequisites:
    - Understanding of sequential key hotspot issues
    - Basic knowledge of primary keys and indexes
    - Familiarity with CockroachDB's range-based architecture
  estimated_time_minutes: 45
  last_updated: "2026-03-06"
---

# Apply Hash Sharding to Prevent Sequential Key Hotspots

## Overview

**Hash sharding** distributes sequential key values across multiple ranges to prevent write hotspots in CockroachDB. Instead of all writes targeting a single range (the end of the key space), hash sharding spreads writes across multiple "buckets" that are distributed throughout the cluster.

**Key concept:**
- Sequential keys (timestamps, auto-increment IDs, dates) naturally cause hotspots
- Hash function maps each sequential value to one of N buckets (default: 16)
- Each bucket becomes a separate range on different nodes
- Writes distribute evenly across all buckets/nodes

**When to use hash sharding:**
- High-write tables with sequential primary keys or indexes
- Timestamp-based event/metrics tables
- Date-partitioned data with current-day hotspot
- Cannot migrate to UUIDs due to application constraints
- Hotspots detected on existing tables

**Critical trade-off:**
- ✅ **Benefit**: Even write distribution across cluster
- ❌ **Cost**: Range scans less efficient (must scan all buckets)

## How Hash Sharding Works

### The Hash Sharding Mechanism

**Without hash sharding:**
```
Sequential writes all target the same range:

Time 10:00:01 → Range 3 [10:00:00 - 10:05:00]  ← All writes here
Time 10:00:02 → Range 3
Time 10:00:03 → Range 3
Time 10:00:04 → Range 3

Result: Range 3 becomes hotspot
```

**With hash sharding (16 buckets):**
```
Hash function distributes writes across buckets:

Time 10:00:01 → hash(10:00:01) = bucket 7  → Range 7
Time 10:00:02 → hash(10:00:02) = bucket 2  → Range 2
Time 10:00:03 → hash(10:00:03) = bucket 14 → Range 14
Time 10:00:04 → hash(10:00:04) = bucket 5  → Range 5

Result: Writes distributed across 16 ranges on different nodes
```

### How CockroachDB Implements Hash Sharding

**1. Hidden shard column automatically added**

When you create a hash-sharded primary key, CockroachDB adds a computed shard column:

```sql
CREATE TABLE events (
  event_time TIMESTAMP PRIMARY KEY USING HASH
);

-- CockroachDB creates:
CREATE TABLE events (
  crdb_internal_event_time_shard_16 INT4 NOT NULL AS (mod(fnv32(crdb_internal.datums_to_bytes(event_time)), 16:::INT8)) STORED,
  event_time TIMESTAMP NOT NULL,
  PRIMARY KEY (crdb_internal_event_time_shard_16, event_time)
);
```

**Components:**
- `crdb_internal_event_time_shard_16`: Hidden shard column (0-15)
- `fnv32()`: Fast non-cryptographic hash function
- `mod(..., 16)`: Distributes values into 16 buckets
- Composite primary key: `(shard_column, original_column)`

**2. Data distribution by shard value**

```
Shard 0:  All rows where hash(event_time) % 16 = 0  → Range on Node 1
Shard 1:  All rows where hash(event_time) % 16 = 1  → Range on Node 2
Shard 2:  All rows where hash(event_time) % 16 = 2  → Range on Node 3
...
Shard 15: All rows where hash(event_time) % 16 = 15 → Range on Node 1

Result: Sequential timestamps distributed across 16 ranges
```

**3. Write distribution**

```
100 sequential inserts with hash sharding:

Bucket 0:  ███  (6 rows)   → Node 1
Bucket 1:  ████ (7 rows)   → Node 2
Bucket 2:  ███  (6 rows)   → Node 3
Bucket 3:  ████ (7 rows)   → Node 1
...
Bucket 15: ███  (6 rows)   → Node 3

Average: ~6-7 rows per bucket (evenly distributed)
```

## Syntax: CREATE TABLE with Hash Sharding

### Basic Syntax for Primary Keys

```sql
CREATE TABLE table_name (
  sequential_column TYPE PRIMARY KEY USING HASH
  [WITH (bucket_count = N)],
  other_columns...
);
```

**Parameters:**
- `USING HASH`: Enable hash sharding
- `bucket_count`: Number of shards (default: 16, must be power of 2)

### Example 1: Timestamp Primary Key

**Problem**: Event table with timestamp primary key causing hotspots

```sql
-- ❌ WITHOUT hash sharding - hotspot on latest timestamps
CREATE TABLE events (
  created_at TIMESTAMP PRIMARY KEY DEFAULT now(),
  event_type STRING,
  user_id UUID,
  data JSONB
);

-- All recent inserts hit same range:
-- 10:00:01 → Range 3
-- 10:00:02 → Range 3
-- 10:00:03 → Range 3
```

**Solution**: Add hash sharding

```sql
-- ✅ WITH hash sharding - distributed writes
CREATE TABLE events (
  created_at TIMESTAMP PRIMARY KEY USING HASH,
  event_type STRING,
  user_id UUID,
  data JSONB
);

-- Inserts distributed across ranges:
-- 10:00:01 → Bucket 7  → Range 7
-- 10:00:02 → Bucket 2  → Range 2
-- 10:00:03 → Bucket 14 → Range 14
```

**Verify the structure:**

```sql
SHOW CREATE TABLE events;
```

**Output:**
```sql
CREATE TABLE events (
  crdb_internal_created_at_shard_16 INT4 NOT VISIBLE NOT NULL
    AS (mod(fnv32(crdb_internal.datums_to_bytes(created_at)), 16:::INT8)) STORED,
  created_at TIMESTAMP NOT NULL,
  event_type STRING NULL,
  user_id UUID NULL,
  data JSONB NULL,
  CONSTRAINT events_pkey PRIMARY KEY (crdb_internal_created_at_shard_16 ASC, created_at ASC)
);
```

### Example 2: Date-Based Primary Key

**Problem**: Daily metrics table with date primary key

```sql
-- ❌ Today's date always hotspot
CREATE TABLE daily_metrics (
  metric_date DATE PRIMARY KEY,
  total_sales DECIMAL(12,2),
  order_count INT,
  avg_order_value DECIMAL(10,2)
);

-- All updates for today hit same range:
UPDATE daily_metrics SET order_count = order_count + 1
WHERE metric_date = CURRENT_DATE;
```

**Solution**: Hash-shard the date column

```sql
-- ✅ Distribute by hash-sharded date
CREATE TABLE daily_metrics (
  metric_date DATE PRIMARY KEY USING HASH,
  total_sales DECIMAL(12,2),
  order_count INT,
  avg_order_value DECIMAL(10,2)
);
```

### Example 3: Auto-Increment ID with Hash Sharding

**Problem**: Cannot migrate to UUIDs, need sequential IDs for compatibility

```sql
-- ❌ Sequential IDs cause hotspot
CREATE SEQUENCE order_id_seq;

CREATE TABLE orders (
  order_id INT PRIMARY KEY DEFAULT nextval('order_id_seq'),
  customer_id UUID,
  total DECIMAL(10,2)
);
```

**Solution**: Keep sequential IDs but hash-shard them

```sql
-- ✅ Sequential IDs distributed via hash sharding
CREATE SEQUENCE order_id_seq;

CREATE TABLE orders (
  order_id INT PRIMARY KEY USING HASH DEFAULT nextval('order_id_seq'),
  customer_id UUID,
  total DECIMAL(10,2)
);

-- order_id still sequential: 1, 2, 3, 4...
-- But distributed: 1→bucket 7, 2→bucket 2, 3→bucket 14...
```

### Example 4: Composite Primary Key with Hash-Sharded Column

**Problem**: Composite key where first column is sequential

```sql
-- ❌ Composite key with sequential prefix
CREATE TABLE sensor_readings (
  reading_time TIMESTAMP,
  sensor_id INT,
  temperature FLOAT,
  humidity FLOAT,
  PRIMARY KEY (reading_time, sensor_id)
);
-- Hotspot on reading_time prefix
```

**Solution**: Hash-shard the sequential column

```sql
-- ✅ Hash-shard the timestamp column
CREATE TABLE sensor_readings (
  reading_time TIMESTAMP,
  sensor_id INT,
  temperature FLOAT,
  humidity FLOAT,
  PRIMARY KEY (reading_time, sensor_id) USING HASH
);

-- Creates: PRIMARY KEY (shard_col, reading_time, sensor_id)
```

## Syntax: ALTER TABLE to Add Hash Sharding

### Adding Hash Sharding to Existing Tables

**Syntax:**
```sql
ALTER TABLE table_name
ALTER PRIMARY KEY USING COLUMNS (column_list)
USING HASH [WITH (bucket_count = N)];
```

### Example 1: Add Hash Sharding to Timestamp Key

**Current state**: Sequential timestamp causing hotspot

```sql
-- Existing table with hotspot
CREATE TABLE page_views (
  view_time TIMESTAMP PRIMARY KEY,
  user_id UUID,
  page_url STRING,
  session_id UUID
);

-- Check for hotspot
SELECT range_id, lease_holder, qps, writes_per_second
FROM crdb_internal.ranges_no_leases
WHERE table_name = 'page_views'
ORDER BY qps DESC
LIMIT 5;

-- One range with 90%+ of writes indicates hotspot
```

**Add hash sharding:**

```sql
-- Add hash sharding to existing primary key
ALTER TABLE page_views
ALTER PRIMARY KEY USING COLUMNS (view_time)
USING HASH;

-- Table remains online during rebuild
-- Progress tracked in SHOW JOBS
```

**Verify distribution improved:**

```sql
-- Check range distribution after hash sharding
SELECT
  crdb_internal_view_time_shard_16 AS shard,
  count(*) AS row_count
FROM page_views
GROUP BY shard
ORDER BY shard;

-- Should see roughly equal counts per shard (0-15)
```

### Example 2: Change from Non-Sharded to Sharded Composite Key

```sql
-- Current: composite key without sharding
CREATE TABLE metrics (
  timestamp TIMESTAMP,
  metric_type STRING,
  value FLOAT,
  PRIMARY KEY (timestamp, metric_type)
);

-- Add hash sharding
ALTER TABLE metrics
ALTER PRIMARY KEY USING COLUMNS (timestamp, metric_type)
USING HASH;

-- Result: PRIMARY KEY (shard_col, timestamp, metric_type)
```

## Hash Sharding for Secondary Indexes

### Secondary Index Hotspots

Secondary indexes can also hotspot on sequential values:

```sql
-- Primary key: random UUIDs (good!)
-- But index on created_at: hotspot!
CREATE TABLE orders (
  order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID,
  total DECIMAL(10,2),
  created_at TIMESTAMP DEFAULT now(),
  INDEX idx_created (created_at)  -- ❌ Hotspot on index writes
);
```

### Syntax: Hash-Sharded Indexes

```sql
CREATE TABLE table_name (
  columns...,
  INDEX index_name (sequential_column) USING HASH
  [WITH (bucket_count = N)]
);
```

### Example 1: Hash-Shard Timestamp Index

```sql
-- ✅ Hash-shard the timestamp index
CREATE TABLE orders (
  order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID,
  total DECIMAL(10,2),
  created_at TIMESTAMP DEFAULT now(),
  INDEX idx_created (created_at) USING HASH WITH (bucket_count = 16)
);

-- Index writes distributed across 16 buckets
```

### Example 2: Add Hash-Sharded Index to Existing Table

```sql
-- Drop non-sharded index
DROP INDEX orders@idx_created;

-- Create hash-sharded replacement
CREATE INDEX idx_created ON orders (created_at)
USING HASH WITH (bucket_count = 16);
```

## Bucket Count Configuration

### Choosing the Right Bucket Count

**Default: 16 buckets**
- Good for most workloads
- Balances distribution vs overhead
- Works well for 3-9 node clusters

**Guidelines:**

```
Cluster Size → Recommended Bucket Count
3 nodes      → 8-16 buckets
6 nodes      → 16-32 buckets
12+ nodes    → 32-64 buckets

Write Volume → Recommended Bucket Count
< 1K/sec     → 16 buckets (default)
1K-10K/sec   → 32 buckets
> 10K/sec    → 64 buckets

Rule of thumb: bucket_count >= 2 × node_count
```

**Must be power of 2**: 2, 4, 8, 16, 32, 64, 128

### Example: High-Volume Event Table

```sql
-- Very high write volume: 50,000 events/sec
-- 12-node cluster
CREATE TABLE high_volume_events (
  event_time TIMESTAMP PRIMARY KEY USING HASH
  WITH (bucket_count = 64),
  event_type STRING,
  payload JSONB
);

-- 64 buckets spread across 12 nodes
-- ~5-6 buckets per node
-- Better write distribution than 16 buckets
```

### Example: Custom Bucket Count on ALTER

```sql
-- Add hash sharding with 32 buckets
ALTER TABLE metrics
ALTER PRIMARY KEY USING COLUMNS (timestamp)
USING HASH WITH (bucket_count = 32);
```

## Performance Trade-offs

### Write Performance: Significant Improvement

**Before hash sharding:**
```
3-node cluster, timestamp primary key:
- Node 1: 0 writes/sec     (idle)
- Node 2: 0 writes/sec     (idle)
- Node 3: 10,000 writes/sec (saturated)

Result: Limited to single node capacity
```

**After hash sharding (16 buckets):**
```
3-node cluster, hash-sharded timestamp:
- Node 1: 3,333 writes/sec (6 buckets)
- Node 2: 3,333 writes/sec (5 buckets)
- Node 3: 3,334 writes/sec (5 buckets)

Result: Full cluster capacity utilized
```

### Read Performance: Range Scans Slower

**Point lookups**: No significant impact

```sql
-- Single-value lookup: fast (still O(log n))
SELECT * FROM events
WHERE created_at = '2026-03-06 10:00:00';

-- Query planner knows exact shard to scan
```

**Range scans**: Must scan all buckets

```sql
-- ❌ Range scan with hash sharding: slower
SELECT * FROM events
WHERE created_at BETWEEN '2026-03-06 09:00:00'
                     AND '2026-03-06 10:00:00';

-- Without sharding: Scan 1 range
-- With 16 buckets:  Scan 16 ranges (must check all buckets)
```

**EXPLAIN output shows multi-shard scan:**

```sql
EXPLAIN SELECT * FROM events
WHERE created_at > '2026-03-06 09:00:00';
```

**Output:**
```
  distribution: full
  vectorized: true

  • filter
  │ filter: created_at > '2026-03-06 09:00:00'
  │
  └── • scan
        table: events@events_pkey
        spans: 16 spans  ← Must scan all 16 shard buckets
```

### When Hash Sharding is Worth It

**✅ Use hash sharding when:**
- Write-heavy workload (writes > reads)
- Write hotspots detected or anticipated
- Point lookups dominate read queries
- Range scans are infrequent
- Cluster has idle capacity being wasted

**❌ Avoid hash sharding when:**
- Read-heavy workload with frequent range scans
- Write volume is low (< 100 writes/sec)
- Sequential scans are performance-critical
- Table size is small (< 1GB)

### Mitigating Range Scan Impact

**Strategy 1: Use secondary indexes for range queries**

```sql
-- Hash-sharded primary key for write distribution
CREATE TABLE events (
  event_id UUID PRIMARY KEY USING HASH,
  created_at TIMESTAMP NOT NULL,
  event_type STRING,
  INDEX idx_created_range (created_at)  -- NOT hash-sharded
);

-- Range scans use non-sharded index:
SELECT * FROM events
WHERE created_at BETWEEN '2026-03-06 09:00:00'
                     AND '2026-03-06 10:00:00';

-- Uses idx_created_range: single range scan
```

**Strategy 2: Partition data by time window**

```sql
-- Combine hash sharding with filtering
CREATE TABLE events (
  created_at TIMESTAMP PRIMARY KEY USING HASH,
  event_type STRING,
  INDEX idx_type_time (event_type, created_at)
);

-- Query with type filter reduces shard scans
SELECT * FROM events
WHERE event_type = 'purchase'
  AND created_at > now() - INTERVAL '1 hour';
```

## Before/After Comparison

### Test Setup: Metrics Table

**Create test table without hash sharding:**

```sql
CREATE TABLE metrics_nohash (
  metric_time TIMESTAMP PRIMARY KEY DEFAULT now(),
  metric_name STRING,
  value FLOAT
);

-- Insert 100,000 sequential timestamps
INSERT INTO metrics_nohash (metric_name, value)
SELECT
  'cpu_usage',
  random() * 100
FROM generate_series(1, 100000);
```

**Check distribution:**

```sql
SELECT
  range_id,
  lease_holder,
  replicas,
  writes_per_second
FROM crdb_internal.ranges_no_leases
WHERE table_name = 'metrics_nohash'
ORDER BY writes_per_second DESC
LIMIT 5;
```

**Result: Hotspot on one range**
```
 range_id | lease_holder | replicas | writes_per_second
----------+--------------+----------+-------------------
     156  |      3       | {1,2,3}  |      9,847
     155  |      2       | {1,2,3}  |         12
     154  |      1       | {1,2,3}  |          8

99%+ of writes on Range 156
```

**Create hash-sharded version:**

```sql
CREATE TABLE metrics_hash (
  metric_time TIMESTAMP PRIMARY KEY USING HASH,
  metric_name STRING,
  value FLOAT
);

-- Insert same 100,000 rows
INSERT INTO metrics_hash (metric_name, value)
SELECT
  'cpu_usage',
  random() * 100
FROM generate_series(1, 100000);
```

**Check distribution:**

```sql
SELECT
  range_id,
  lease_holder,
  writes_per_second
FROM crdb_internal.ranges_no_leases
WHERE table_name = 'metrics_hash'
ORDER BY writes_per_second DESC
LIMIT 10;
```

**Result: Even distribution**
```
 range_id | lease_holder | writes_per_second
----------+--------------+-------------------
     201  |      1       |       612
     202  |      2       |       608
     203  |      3       |       615
     204  |      1       |       605
     205  |      2       |       618
     ...

Writes evenly distributed across 16 ranges
```

**Verify shard distribution:**

```sql
SELECT
  crdb_internal_metric_time_shard_16 AS shard,
  count(*) AS row_count
FROM metrics_hash
GROUP BY shard
ORDER BY shard;
```

**Result:**
```
 shard | row_count
-------+-----------
   0   |    6,234
   1   |    6,187
   2   |    6,301
   3   |    6,289
   ...
  15   |    6,198

Average: ~6,250 rows per shard (evenly distributed)
```

## Practical Examples

### Example 1: Time-Series Events Table

**Scenario**: IoT platform collecting 100,000 sensor events/second

```sql
-- High-volume time-series data
CREATE TABLE sensor_events (
  event_time TIMESTAMP PRIMARY KEY USING HASH
    WITH (bucket_count = 32),
  sensor_id UUID NOT NULL,
  temperature FLOAT,
  humidity FLOAT,
  battery_level FLOAT,
  INDEX idx_sensor_time (sensor_id, event_time)
);

-- Write distribution:
-- 100K events/sec ÷ 32 buckets = ~3,125 events/sec per bucket
-- Distributed across cluster nodes

-- Point lookup: still fast
SELECT * FROM sensor_events
WHERE event_time = '2026-03-06 10:15:32.123456';

-- Sensor-specific range query: uses non-sharded index
SELECT * FROM sensor_events
WHERE sensor_id = '550e8400-e29b-41d4-a716-446655440000'
  AND event_time > now() - INTERVAL '1 hour';
```

### Example 2: Audit Logs with Compliance Requirements

**Scenario**: Must retain sequential IDs for audit trail

```sql
-- Compliance requires sequential audit_id
CREATE SEQUENCE audit_id_seq;

CREATE TABLE audit_logs (
  audit_id BIGINT PRIMARY KEY USING HASH DEFAULT nextval('audit_id_seq'),
  user_id UUID NOT NULL,
  action STRING NOT NULL,
  resource_type STRING,
  resource_id UUID,
  timestamp TIMESTAMP DEFAULT now(),
  details JSONB,
  INDEX idx_user_time (user_id, timestamp),
  INDEX idx_resource (resource_type, resource_id)
);

-- Benefits:
-- - Sequential audit_id preserved for compliance
-- - Hash sharding distributes writes
-- - Indexes optimized for common queries
```

### Example 3: Multi-Tenant Application Events

```sql
-- Events table for multi-tenant SaaS
CREATE TABLE tenant_events (
  tenant_id UUID,
  event_time TIMESTAMP,
  event_id UUID DEFAULT gen_random_uuid(),
  event_type STRING,
  payload JSONB,
  PRIMARY KEY (tenant_id, event_time, event_id)
);

-- Problem: Large tenants create hotspots on event_time
-- Solution: Hash-shard the composite key
ALTER TABLE tenant_events
ALTER PRIMARY KEY USING COLUMNS (tenant_id, event_time, event_id)
USING HASH WITH (bucket_count = 32);

-- Result: PRIMARY KEY (shard_col, tenant_id, event_time, event_id)
-- Both cross-tenant and same-tenant writes distributed
```

## Monitoring Hash-Sharded Tables

### Check Shard Distribution

```sql
-- Verify even distribution across shards
SELECT
  crdb_internal_<column>_shard_16 AS shard,
  count(*) AS row_count,
  round(count(*) * 100.0 / sum(count(*)) OVER (), 2) AS pct
FROM your_table
GROUP BY shard
ORDER BY shard;
```

**Expected result**: Each shard has ~6.25% of rows (100% ÷ 16 shards)

### Check Write Distribution Across Nodes

```sql
-- Check writes per node
SELECT
  node_id,
  sum(writes_per_second) AS total_writes
FROM crdb_internal.kv_node_status
GROUP BY node_id
ORDER BY total_writes DESC;
```

**Expected result**: Roughly equal writes per node

### Identify Range Distribution

```sql
-- Check range distribution for hash-sharded table
SELECT
  lease_holder AS node_id,
  count(*) AS range_count
FROM crdb_internal.ranges_no_leases
WHERE table_name = 'your_table'
GROUP BY lease_holder
ORDER BY range_count DESC;
```

## Best Practices

### When to Apply Hash Sharding

**✅ Apply hash sharding for:**
- Tables with > 1,000 writes/second
- Timestamp-based primary keys or indexes
- Auto-increment sequences in high-write tables
- Date-based partitioning on current data
- Detected hotspots via monitoring

**❌ Don't use hash sharding for:**
- Small tables (< 10,000 rows)
- Read-heavy tables with frequent range scans
- Low write volume (< 100 writes/second)
- Tables where sequential scanning is critical

### Design Recommendations

1. **Test impact on range scans**
   - Benchmark your query patterns before/after
   - Measure P99 latency for range queries
   - Ensure acceptable trade-off

2. **Start with default bucket count (16)**
   - Increase only if needed for very high write volume
   - Monitor distribution before adjusting
   - More buckets = more overhead

3. **Combine with appropriate indexes**
   - Create non-sharded indexes for range queries
   - Use composite indexes to reduce shard scanning
   - Balance index maintenance vs query performance

4. **Monitor after deployment**
   - Check shard distribution monthly
   - Watch for uneven write patterns
   - Alert on hotspot return

## Troubleshooting

### Problem: Range Scans Much Slower After Hash Sharding

**Symptom**: Queries with time ranges now timeout or very slow

**Diagnosis:**
```sql
EXPLAIN ANALYZE SELECT * FROM events
WHERE created_at BETWEEN '2026-03-06 00:00:00'
                     AND '2026-03-06 23:59:59';

-- Check "spans" count - should see 16 spans for 16 buckets
```

**Solutions:**

1. **Add non-sharded secondary index for range queries:**
```sql
CREATE INDEX idx_created_range ON events (created_at);

-- Range queries will use this index instead
```

2. **Add filtering column to reduce span scans:**
```sql
-- Add event_type to query
SELECT * FROM events
WHERE event_type = 'purchase'
  AND created_at BETWEEN '2026-03-06 00:00:00'
                     AND '2026-03-06 23:59:59';
```

3. **Consider if hash sharding is necessary:**
   - Measure actual write QPS
   - If < 100 writes/sec, may not need sharding

### Problem: Uneven Shard Distribution

**Symptom**: Some shards have 3x more rows than others

**Diagnosis:**
```sql
SELECT
  crdb_internal_<column>_shard_16 AS shard,
  count(*) AS row_count
FROM your_table
GROUP BY shard
ORDER BY row_count DESC;

-- Expected: ~equal counts
-- Actual: Large variance
```

**Causes:**
- Hash function is deterministic and should distribute evenly
- Uneven distribution suggests data skew or corruption

**Solution:**
```sql
-- Rebuild table to recalculate shards
ALTER TABLE your_table
ALTER PRIMARY KEY USING COLUMNS (<columns>)
USING HASH WITH (bucket_count = 16);
```

### Problem: Still See Hotspots After Hash Sharding

**Diagnosis:**
```sql
-- Check which ranges are hot
SELECT
  range_id,
  start_pretty,
  lease_holder,
  qps,
  writes_per_second
FROM crdb_internal.ranges_no_leases
WHERE table_name = 'your_table'
ORDER BY qps DESC
LIMIT 5;
```

**Possible causes:**

1. **Hot secondary index (not sharded)**
```sql
-- Fix: Add hash sharding to index
DROP INDEX IF EXISTS idx_timestamp;
CREATE INDEX idx_timestamp ON your_table (timestamp_col)
USING HASH WITH (bucket_count = 16);
```

2. **Insufficient bucket count**
```sql
-- Increase from 16 to 32 buckets
ALTER TABLE your_table
ALTER PRIMARY KEY USING COLUMNS (<columns>)
USING HASH WITH (bucket_count = 32);
```

3. **Different hotspot source**
   - Check for non-sharded composite key prefix
   - Verify all sequential columns are hash-sharded

## Related Skills

**Prerequisites:**
- **understand-sequential-key-hotspot-issues** - Learn why sequential keys cause hotspots

**Primary Key Management:**
- **alter-tables-to-change-primary-keys** - Add hash sharding to existing tables
- **design-primary-keys-for-even-data-distribution** - PK design principles
- **create-composite-primary-keys-with-proper-column-ordering** - Composite key best practices

**Alternative Solutions:**
- **generate-uuids-for-primary-keys** - Use UUIDs instead of sequential keys
- **use-unordered-unique-rowid-for-primary-keys** - Alternative to sequences

**Monitoring:**
- **identify-hot-ranges-in-cluster** - Detect hotspots
- **monitor-range-distribution-and-rebalancing** - Track data distribution

**Performance:**
- **optimize-query-performance-with-indexes** - Balance hash sharding with index strategy
- **understand-query-execution-plans** - Analyze impact of hash sharding on queries

## References

- [CockroachDB Docs: Hash-Sharded Indexes](https://www.cockroachlabs.com/docs/stable/hash-sharded-indexes.html)
- [Blog: Hash-Sharded Indexes Unlock Linear Scaling](https://www.cockroachlabs.com/blog/hash-sharded-indexes-unlock-linear-scaling/)
- [Docs: Primary Key Best Practices](https://www.cockroachlabs.com/docs/stable/schema-design-table.html#primary-key-best-practices)
- [Architecture: Distribution Layer](https://www.cockroachlabs.com/docs/stable/architecture/distribution-layer.html)

---

**Version**: 1.0.0
**Last Updated**: March 6, 2026
**Tested Against**: CockroachDB v26.1.0
