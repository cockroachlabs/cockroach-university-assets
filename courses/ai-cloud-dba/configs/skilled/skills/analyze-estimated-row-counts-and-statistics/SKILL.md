---
name: analyze-estimated-row-counts-and-statistics
description: Analyze table statistics and estimated row counts to understand optimizer decisions and diagnose plan quality issues
metadata:
  domain: Workload Management and Performance
  bloom_level: Analyze
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: active
---

# Analyze Estimated Row Counts and Statistics

**Domain**: Workload Management and Performance
**Bloom's Level**: Analyze

## What This Skill Teaches

This skill teaches you how to analyze table statistics and estimated row counts to understand query optimizer decisions. You'll learn what statistics CockroachDB collects, how the optimizer uses them for cost estimation, how to identify stale or inaccurate statistics, and when to manually refresh statistics to improve plan quality.

**Learning Objectives:**
- Understand what statistics the cost-based optimizer collects and maintains
- Interpret estimated row counts in EXPLAIN output
- View and analyze table statistics using SHOW STATISTICS
- Identify when statistics are stale or inaccurate
- Determine when to manually refresh statistics with ANALYZE
- Diagnose optimizer problems caused by poor statistics

## Understanding Table Statistics

### What Statistics CockroachDB Collects

The cost-based optimizer maintains several types of statistics:

**Per Table:**
- Total row count
- Statistics creation timestamp

**Per Column:**
- Distinct value count (NDV/cardinality)
- NULL count
- Histogram (value distribution)
- Average column size in bytes

The optimizer uses these statistics to estimate:
- How many rows each operation will produce
- Which index to use for scans
- Which join algorithm to choose (hash vs merge)
- Optimal join order for multi-table queries

### Automatic Statistics Collection

CockroachDB automatically collects statistics via background job:

- Runs every 2 hours by default
- Triggers after 20% of rows change since last collection
- Activates after bulk loads (IMPORT, RESTORE)
- Samples rows for efficiency (doesn't scan entire table)

**Check Auto-Collection Status:**

```sql
SHOW CLUSTER SETTING sql.stats.automatic_collection.enabled;
-- Should return: true

SHOW CLUSTER SETTING sql.stats.automatic_collection.fraction_stale_rows;
-- Default: 0.2 (20% threshold)
```

## Viewing Table Statistics

### SHOW STATISTICS Command

```sql
SHOW STATISTICS FOR TABLE orders;
```

**Output Columns:**
- `statistics_name`: Internal identifier (usually `__auto__`)
- `column_names`: Column(s) covered by statistic
- `created`: When statistics were collected
- `row_count`: Total rows at collection time
- `distinct_count`: Number of unique values
- `null_count`: Number of NULL values
- `avg_size`: Average bytes per value
- `histogram_id`: Reference to histogram (if exists)

**Example Output:**

```sql
SHOW STATISTICS FOR TABLE users;

  column_names | created              | row_count | distinct_count | null_count
---------------+----------------------+-----------+----------------+------------
  {id}         | 2026-03-07 10:30:00  | 1000000   | 1000000        | 0
  {email}      | 2026-03-07 10:30:00  | 1000000   | 995000         | 50
  {status}     | 2026-03-07 10:30:00  | 1000000   | 3              | 0
  {created_at} | 2026-03-07 10:30:00  | 1000000   | 365000         | 0
```

**Interpreting Cardinality:**
- `id`: High cardinality (1M distinct) - excellent for selective filtering
- `email`: Near-unique (995K distinct) - good index candidate
- `status`: Very low cardinality (3 values) - poor for selective queries
- `created_at`: Medium cardinality - selectivity depends on range

### System Tables for Statistics

```sql
-- Detailed statistics view
SELECT
  table_name,
  column_names,
  row_count,
  distinct_count,
  created_at
FROM crdb_internal.table_row_statistics
WHERE table_name = 'orders'
ORDER BY created_at DESC;
```

### Histogram Analysis

Histograms show value distribution for skewed data:

```sql
-- Find histogram ID from SHOW STATISTICS
SHOW STATISTICS FOR TABLE orders;

-- View histogram details
SHOW HISTOGRAM <histogram_id>;
```

**Example Histogram:**

```
  upper_bound | range_rows | distinct_range_rows | equal_rows
--------------+------------+---------------------+------------
  100         | 0          | 0                   | 5000
  500         | 15000      | 400                 | 3000
  1000        | 25000      | 500                 | 2000
  10000       | 950000     | 9000                | 1000
```

This shows heavy skew toward high values (95% of data above 1000).

## Analyzing Estimated Row Counts

### Reading Estimates in EXPLAIN

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'pending';

       tree       |    field    |      description
------------------+-------------+-----------------------
  scan            |             |
                  | estimated row count | 15000
                  | table       | orders@status_idx
                  | spans       | [/'pending' - /'pending']
```

The `estimated row count` shows the optimizer's prediction. This drives all plan decisions.

### Estimated vs. Actual Row Counts

Use EXPLAIN ANALYZE to compare estimates with reality:

```sql
EXPLAIN ANALYZE SELECT * FROM orders
WHERE created_at >= '2026-01-01';

       tree       |    field    |      description
------------------+-------------+-----------------------
  scan            |             |
                  | estimated row count | 50000       -- Prediction
                  | actual row count    | 150000      -- Reality
                  | table       | orders@created_idx
```

**Problem**: Estimate is 3x too low. This may cause:
- Wrong join algorithm selection
- Insufficient memory allocation
- Poor performance

## Identifying Statistics Problems

### Sign 1: Wildly Inaccurate Row Estimates

```sql
EXPLAIN ANALYZE SELECT * FROM recent_orders WHERE status = 'pending';

  estimated row count | 1000        -- Estimate
  actual row count    | 500000      -- Reality (500x difference!)
```

**Cause**: Statistics collected when table had 1000 rows, now has 500K after bulk load.

### Sign 2: Old Statistics Timestamps

```sql
SHOW STATISTICS FOR TABLE recent_orders;

  column_names | created             | row_count
---------------+---------------------+-----------
  {status}     | 2026-01-15 08:00:00 | 1000      -- 6 weeks old!
```

### Sign 3: Suboptimal Index Selection

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'cancelled';

  scan            |             |
                  | estimated row count | 900000      -- Wrong!
                  | table       | orders@primary      -- Full scan
                  | spans       | FULL SCAN
```

If only 1% of orders are cancelled but statistics show 90%, optimizer won't use the status index.

### Common Causes of Stale Statistics

**Bulk Data Loads:**

```sql
-- After IMPORT added 1M rows
SHOW STATISTICS FOR TABLE products;
-- row_count: 10000 (STALE - should be 1,010,000)
```

**Mass Updates/Deletes:**

```sql
-- Deleted 80% of data
DELETE FROM logs WHERE created_at < '2025-01-01';

-- Statistics still show old count
SHOW STATISTICS FOR TABLE logs;
-- row_count: 5000000 (actually 1000000 now)
```

**Skewed Data Distribution Changes:**

New data has different distribution than when statistics were collected. Example: old data evenly distributed across regions, new data 90% in one region.

## Manual Statistics Refresh

### When to Use ANALYZE

Manually refresh statistics when:

1. After bulk data loads (IMPORT, RESTORE, large INSERTs)
2. After mass modifications (large UPDATEs or DELETEs)
3. When query plans suddenly degrade
4. Before critical queries if statistics are known to be stale
5. When EXPLAIN ANALYZE shows large estimate/actual discrepancies

### ANALYZE Syntax

```sql
-- Analyze entire table
ANALYZE orders;

-- Analyze multiple tables
ANALYZE users, orders, products;

-- Analyze entire database
ANALYZE DATABASE movr;
```

The ANALYZE statement:
- Samples rows from the table (doesn't full scan)
- Computes row counts, distinct values, histograms
- Updates system.table_statistics
- Blocks until complete (foreground operation)

### Verify Statistics Were Updated

```sql
-- Before ANALYZE
SHOW STATISTICS FOR TABLE orders;
-- created: 2026-02-01 (old)
-- row_count: 50000

-- Run refresh
ANALYZE orders;

-- After ANALYZE
SHOW STATISTICS FOR TABLE orders;
-- created: 2026-03-07 14:30:00 (current timestamp)
-- row_count: 500000 (accurate)
```

### Monitor ANALYZE Jobs

```sql
-- Check running ANALYZE jobs
SHOW JOBS
WHERE job_type = 'CREATE STATS'
  AND status = 'running';

-- View recent completed jobs
SHOW JOBS
WHERE job_type = 'CREATE STATS'
ORDER BY created DESC
LIMIT 10;
```

## Impact on Query Plans

### Case Study: Stale Statistics

**Before Statistics Refresh:**

```sql
EXPLAIN SELECT o.*, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'pending';

       tree       |    field    |      description
------------------+-------------+-----------------------
  hash join       |             |
                  | estimated row count | 450000      -- Way too high
    scan          |             |
                  | estimated row count | 500000
                  | table       | orders@primary      -- Full scan
    scan          |             |
                  | table       | users@primary

Execution Time: 15000ms
```

**Problem**: Optimizer chose hash join expecting 500K pending orders (based on stale 50% pending rate). Actually only 5K pending (1% rate).

**Refresh Statistics:**

```sql
ANALYZE orders;
```

**After Statistics Refresh:**

```sql
EXPLAIN SELECT o.*, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'pending';

       tree       |    field    |      description
------------------+-------------+-----------------------
  merge join      |             |
                  | estimated row count | 5000        -- Accurate
    scan          |             |
                  | estimated row count | 5000
                  | table       | orders@status_idx   -- Better index
                  | spans       | [/'pending' - /'pending']
    scan          |             |
                  | table       | users@primary

Execution Time: 450ms  -- 33x faster
```

**Improvements:**
- Accurate row estimate (5K vs 500K)
- Better index selection (status_idx vs primary)
- Better join algorithm (merge vs hash)
- 33x execution time improvement

### Index Selection Impact

```sql
-- With stale stats: full table scan
EXPLAIN SELECT * FROM products WHERE category = 'electronics';

  scan            | table       | products@primary      -- Wrong
                  | filter      | category = 'electronics'
                  | estimated row count | 500000

-- After ANALYZE: index scan
ANALYZE products;

EXPLAIN SELECT * FROM products WHERE category = 'electronics';

  scan            | table       | products@category_idx -- Correct
                  | spans       | [/'electronics' - /'electronics']
                  | estimated row count | 15000         -- Accurate (3%)
```

## Cardinality Estimation

### Understanding Cardinality

**Cardinality** = Number of distinct values in a column

Used by optimizer for:
- Join selectivity estimates
- Index selection decisions
- GROUP BY efficiency predictions

```sql
SHOW STATISTICS FOR TABLE orders;

  column_names | distinct_count | row_count
---------------+----------------+-----------
  {user_id}    | 50000          | 500000     -- ~10 orders per user
  {status}     | 5              | 500000     -- Very low cardinality
  {product_id} | 10000          | 500000     -- ~50 orders per product
```

### Cardinality Impact on Joins

```sql
-- High cardinality join (user_id)
EXPLAIN SELECT * FROM orders o JOIN users u ON o.user_id = u.id;
  estimated row count | 500000     -- 1:many, reasonable

-- Low cardinality join (status)
EXPLAIN SELECT * FROM orders o1 JOIN orders o2 ON o1.status = o2.status;
  estimated row count | 50000000   -- Cartesian explosion!
```

Low cardinality joins produce massive intermediate results.

## Statistics Settings

### Key Cluster Settings

```sql
-- Enable/disable automatic collection
SET CLUSTER SETTING sql.stats.automatic_collection.enabled = true;

-- Minimum rows that must change
SET CLUSTER SETTING sql.stats.automatic_collection.min_stale_rows = 500;

-- Fraction of rows that must change (default: 0.2 = 20%)
SET CLUSTER SETTING sql.stats.automatic_collection.fraction_stale_rows = 0.2;
```

### Per-Table Control

```sql
-- Disable auto-stats for specific table
ALTER TABLE large_table SET (sql_stats_automatic_collection_enabled = false);

-- Re-enable
ALTER TABLE large_table SET (sql_stats_automatic_collection_enabled = true);
```

**Use Case**: Disable during maintenance windows, manually ANALYZE afterward.

## Troubleshooting Workflow

### Step 1: Check Statistics Age

```sql
SELECT
  table_name,
  column_names,
  row_count,
  created_at,
  NOW() - created_at AS age
FROM crdb_internal.table_row_statistics
WHERE created_at < NOW() - INTERVAL '7 days'
ORDER BY age DESC;
```

### Step 2: Compare Estimated vs. Actual

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'pending';

-- Look for discrepancies:
  estimated row count | 1000
  actual row count    | 100000     -- 100x difference!
```

### Step 3: Refresh Statistics

```sql
ANALYZE orders;

-- Verify update
SHOW STATISTICS FOR TABLE orders;
```

### Step 4: Validate Plan Improvement

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'pending';

-- Verify accurate estimates and better plan
```

## Best Practices

**DO:**
- Monitor statistics age on critical tables
- Run ANALYZE after bulk data loads (IMPORT, RESTORE)
- Keep automatic collection enabled (default)
- Review query plans periodically for estimate accuracy
- Refresh statistics before critical queries if needed

**DON'T:**
- Disable automatic statistics collection without good reason
- Run ANALYZE constantly (it blocks during collection)
- Ignore large estimate/actual discrepancies
- Assume statistics are always accurate

### Performance Considerations

- ANALYZE samples rows, doesn't scan entire table
- Cost: O(sample_size), not O(table_size)
- Time: Seconds to minutes depending on table size
- Schedule during low-traffic periods

### Monitoring Statistics Health

```sql
-- Find tables with potentially stale statistics
WITH table_stats AS (
  SELECT
    table_name,
    MAX(created_at) AS last_stats_update,
    MAX(row_count) AS estimated_rows
  FROM crdb_internal.table_row_statistics
  GROUP BY table_name
)
SELECT
  table_name,
  last_stats_update,
  NOW() - last_stats_update AS stats_age,
  CASE
    WHEN last_stats_update < NOW() - INTERVAL '7 days' THEN 'STALE'
    WHEN last_stats_update < NOW() - INTERVAL '3 days' THEN 'AGING'
    ELSE 'FRESH'
  END AS stats_status
FROM table_stats
ORDER BY stats_age DESC;
```

## Common Patterns

### Pattern 1: Post-Load Statistics Refresh

```sql
-- After bulk load
IMPORT TABLE new_data FROM 's3://bucket/data.csv';

-- Immediately refresh
ANALYZE new_data;

-- Verify
SHOW STATISTICS FOR TABLE new_data;
```

### Pattern 2: Pre-Query Statistics Check

```sql
-- Check stats age before expensive query
SHOW STATISTICS FOR TABLE orders;

-- If stale, refresh
ANALYZE orders;

-- Run query
SELECT ... FROM orders ...;
```

### Pattern 3: Diagnosing Slow Query

```sql
-- 1. Get execution plan with actuals
EXPLAIN ANALYZE SELECT ... FROM table WHERE ...;

-- 2. Identify estimate/actual mismatch
-- 3. Check statistics
SHOW STATISTICS FOR TABLE table;

-- 4. Refresh if stale
ANALYZE table;

-- 5. Re-run and verify improvement
EXPLAIN ANALYZE SELECT ... FROM table WHERE ...;
```

## Related Skills

- **use-explain-to-analyze-query-execution-plans**: Reading estimated row counts in EXPLAIN output
- **use-explain-analyze-for-runtime-execution-analysis**: Comparing estimated vs actual row counts
- **compare-estimated-vs-actual-execution-costs**: Analyzing cost estimation accuracy
- **identify-scan-types-in-execution-plans**: How statistics influence scan selection
- **optimize-queries-based-on-explain-output**: Using statistics insights for performance
- **diagnose-query-performance-regressions**: Identifying stale statistics issues

## References

- [CockroachDB Cost-Based Optimizer Documentation](https://www.cockroachlabs.com/docs/stable/cost-based-optimizer.html#table-statistics)
- [SHOW STATISTICS Documentation](https://www.cockroachlabs.com/docs/stable/show-statistics.html)
- [CREATE STATISTICS Documentation](https://www.cockroachlabs.com/docs/stable/create-statistics.html)
- [Query Optimization Best Practices](https://www.cockroachlabs.com/docs/stable/performance-best-practices-overview.html)
