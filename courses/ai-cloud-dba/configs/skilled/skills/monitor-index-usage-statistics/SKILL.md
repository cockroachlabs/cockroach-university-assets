---
name: monitor-index-usage-statistics
description: Can query crdb_internal.index_usage_statistics joined with table_indexes to identify unused indexes and track read patterns. Use DB Console Insights for optimization recommendations. Critical for identifying drop candidates to reduce storage overhead.
metadata:
  domain: Monitoring and Alerting
  tags: indexing, monitoring, operations, unused-indexes
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
---

# Monitor Index Usage Statistics

Tracks index read patterns to identify unused indexes and optimize database performance by removing unnecessary indexes.

## Why This Matters

**Unused indexes are expensive** because they:
- Consume disk storage unnecessarily
- Slow down ALL writes (INSERT/UPDATE/DELETE maintains every index)
- Waste memory in cache
- Add overhead to backups and replication

**Goal**: Maintain only indexes actively used by queries

## Schema Notes (v26.1.0)

`crdb_internal.index_usage_statistics` stores only numeric IDs and read counts:
- `table_id`, `index_id` (numeric IDs requiring JOINs for names)
- `total_reads` (read count since tracking began)
- `last_read` (most recent read timestamp)

**Note**: Write statistics (`total_writes`) are NOT tracked in v26.1.0. Index optimization focuses on identifying zero-read indexes.

## Instructions

**IMPORTANT**: All queries require `SET allow_unsafe_internals = true;` because `crdb_internal.table_indexes` is an internal table.

### Find Unused Indexes (Primary Method)

```sql
SET allow_unsafe_internals = true;

SELECT
  ti.descriptor_name as table_name,
  ti.index_name,
  ius.total_reads,
  ius.last_read,
  ti.created_at
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ius.total_reads = 0
  AND ti.index_name NOT LIKE '%_pkey'  -- Exclude primary keys
ORDER BY ti.descriptor_name, ti.index_name;
```

**Result**: Indexes with zero reads since tracking began (drop candidates)

**Schema Note**: Must JOIN `table_indexes` to get human-readable names from numeric IDs

### Find Rarely Used Indexes

```sql
SET allow_unsafe_internals = true;

SELECT
  ti.descriptor_name as table_name,
  ti.index_name,
  ius.total_reads,
  ius.last_read,
  CASE
    WHEN ius.total_reads = 0 THEN 'Never used'
    WHEN ius.total_reads < 10 THEN 'Rarely used'
    WHEN ius.total_reads < 100 THEN 'Lightly used'
    ELSE 'Actively used'
  END as usage_category
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ti.index_name NOT LIKE '%_pkey'
  AND ius.total_reads < 100
ORDER BY ius.total_reads ASC, ti.descriptor_name
LIMIT 20;
```

**Key metric:**
- **total_reads**: Times index was used by queries

**Decision thresholds:**
- total_reads = 0: Unused (immediate review for dropping)
- total_reads < 10: Rarely used (strong drop candidate)
- total_reads < 100: Lightly used (consider dropping)

**Note**: v26.1.0 does NOT track write statistics. Focus on identifying zero-read indexes.

### DB Console Insights (Automated Recommendations)

1. Navigate to **Insights** page in DB Console
2. Select **Schema Insights** tab
3. Look for **"Drop unused index"** recommendations
4. Review suggested indexes with usage statistics
5. Copy provided DROP statement

**Advantage**: Automatic analysis with context and ready-to-use SQL.

## Understanding Statistics

### Table Schemas

**crdb_internal.index_usage_statistics** (v26.1.0):
- **table_id**: Numeric table ID (requires JOIN for name)
- **index_id**: Numeric index ID (requires JOIN for name)
- **total_reads**: Count of queries using this index
- **last_read**: Most recent read timestamp (NULL if never read)

**crdb_internal.table_indexes** (for names):
- **descriptor_id**: Table ID (joins to table_id)
- **descriptor_name**: Human-readable table name
- **index_id**: Index ID (joins to index_id)
- **index_name**: Human-readable index name
- **created_at**: Index creation timestamp
- Additional metadata: is_unique, is_inverted, visibility, etc.

### Statistics Reset Behavior

**Statistics reset on:**
- Node restarts
- Cluster upgrades
- Manual reset
- Index recreation

**Best practice**: Analyze after **minimum 7-30 days** of stable operation to capture all workload patterns.

## Example Analysis

### Scenario: Identifying Unused Index

```sql
-- Check specific table's indexes
SET allow_unsafe_internals = true;

SELECT
  ti.descriptor_name as table_name,
  ti.index_name,
  ius.total_reads,
  ius.last_read,
  ti.created_at
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ti.descriptor_name = 'users'
  AND ti.index_name = 'users_email_idx';
```

**Result:**
```
table_name | index_name        | total_reads | last_read | created_at
-----------+-------------------+-------------+-----------+--------------------
users      | users_email_idx   | 0           | NULL      | 2026-02-01 10:00:00
```

**Analysis**: Zero reads over 30 days, never accessed. Strong drop candidate.

### Scenario: Usage Comparison Across Indexes

```sql
SET allow_unsafe_internals = true;

SELECT
  ti.descriptor_name as table_name,
  ti.index_name,
  ius.total_reads,
  ius.last_read,
  CASE
    WHEN ius.total_reads = 0 THEN 'DROP'
    WHEN ius.total_reads < 100 THEN 'REVIEW'
    ELSE 'KEEP'
  END as recommendation
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ti.descriptor_name = 'orders'
  AND ti.index_name NOT LIKE '%_pkey'
ORDER BY ius.total_reads ASC;
```

**Result:**
```
table_name | index_name              | total_reads | last_read           | recommendation
-----------+-------------------------+-------------+---------------------+----------------
orders     | orders_created_date_idx | 0           | NULL                | DROP
orders     | orders_temp_idx         | 15          | 2026-02-15 08:30:00 | REVIEW
orders     | orders_status_idx       | 125000      | 2026-03-06 14:22:00 | KEEP
orders     | orders_user_id_idx      | 480000      | 2026-03-06 14:22:15 | KEEP
```

**Recommendations:**
- **orders_created_date_idx**: Drop (never used)
- **orders_temp_idx**: Review (rarely used, possible test index)
- **orders_status_idx**: Keep (actively used)
- **orders_user_id_idx**: Keep (heavily used)

## Safe Drop Process

### Step 1: Validate Candidate

```sql
-- Verify index is truly unused
SET allow_unsafe_internals = true;

SELECT
  ti.descriptor_name as table_name,
  ti.index_name,
  ius.total_reads,
  ius.last_read,
  ti.created_at,
  age(now(), ti.created_at) as index_age
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ti.index_name = 'target_index_name';
```

**Check:** total_reads = 0 AND index_age > 30 days

### Step 2: Check Constraints

```sql
SHOW CREATE TABLE table_name;
```

**Never drop indexes that:**
- Enforce UNIQUE constraints
- Support FOREIGN KEY constraints
- Are primary keys

### Step 3: Test Query Impact (Optional)

```sql
EXPLAIN SELECT * FROM table_name WHERE indexed_column = 'value';
-- Verify index isn't used in critical queries
```

### Step 4: Drop Index

```sql
DROP INDEX table_name@index_name;
```

### Step 5: Monitor Performance

Watch for:
- Slow query alerts
- Increased query latency in statement statistics
- Application performance degradation

### Step 6: Recreate if Needed

```sql
-- If performance degrades, recreate immediately
CREATE INDEX index_name ON table_name (column_name);
```

## Decision Framework

**Safe to drop when:**
- total_reads = 0 for 30+ days of tracking
- Not enforcing constraints (UNIQUE, FK)
- No seasonal/batch job dependency
- Index age > 30 days (not recently created)

**Review carefully:**
- Recently created (< 7 days tracking)
- Used by periodic batch jobs
- Required for compliance reporting
- Seasonal usage patterns (end-of-month, quarterly reports)

**Never drop:**
- Primary keys (table_pkey)
- UNIQUE constraint indexes
- FOREIGN KEY indexes
- Critical query dependencies confirmed by application teams

## Monitoring Index Health

### Regular Audit Query

```sql
SET allow_unsafe_internals = true;

WITH index_stats AS (
  SELECT
    CASE
      WHEN ius.total_reads = 0 THEN 'Unused'
      WHEN ius.total_reads < 100 THEN 'Rarely used'
      WHEN ius.total_reads < 1000 THEN 'Lightly used'
      ELSE 'Healthy'
    END as health_status,
    ti.index_name
  FROM crdb_internal.index_usage_statistics ius
  JOIN crdb_internal.table_indexes ti
    ON ius.table_id = ti.descriptor_id
    AND ius.index_id = ti.index_id
  WHERE ti.index_name NOT LIKE '%_pkey'
)
SELECT health_status, count(*) as index_count
FROM index_stats
GROUP BY health_status
ORDER BY health_status;
```

**Target**: < 5% unused indexes, < 10% rarely used

### Index Bloat Summary

```sql
SET allow_unsafe_internals = true;

SELECT
  count(*) as total_indexes,
  count(*) FILTER (WHERE ius.total_reads = 0) as unused_indexes,
  count(*) FILTER (WHERE ius.total_reads < 100) as rarely_used_indexes,
  ROUND(100.0 * count(*) FILTER (WHERE ius.total_reads = 0) / count(*), 2) as unused_pct
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ti.index_name NOT LIKE '%_pkey';
```

## Common Patterns

### Pattern 1: Tables with Most Unused Indexes

```sql
-- Tables with most unused indexes
SET allow_unsafe_internals = true;

SELECT
  ti.descriptor_name as table_name,
  count(*) as total_indexes,
  count(*) FILTER (WHERE ius.total_reads = 0) as unused_indexes,
  count(*) FILTER (WHERE ius.total_reads < 100) as rarely_used_indexes
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ti.index_name NOT LIKE '%_pkey'
GROUP BY ti.descriptor_name
HAVING count(*) FILTER (WHERE ius.total_reads = 0) > 0
ORDER BY unused_indexes DESC, rarely_used_indexes DESC
LIMIT 10;
```

**Goal**: Identify tables where index reduction has biggest impact (most cleanup opportunities).

### Pattern 2: Analyze All Indexes on a Table

```sql
-- Check all indexes on a specific table
SET allow_unsafe_internals = true;

SELECT
  ti.index_name,
  ius.total_reads,
  ius.last_read,
  ti.is_unique,
  ti.created_at
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
WHERE ti.descriptor_name = 'target_table'
ORDER BY ius.total_reads DESC;
```

**Optimization**: Identify opportunities to replace multiple lightly-used single-column indexes with one composite index.

## Troubleshooting

### Issue: All Statistics Show Zero

**Cause:**
- Cluster recently restarted (statistics reset)
- Statistics recently reset manually
- No queries executed against indexes
- New cluster with minimal workload

**Resolution:**
```sql
-- Check when tracking started
SET allow_unsafe_internals = true;

SELECT
  ti.descriptor_name as table_name,
  ti.index_name,
  ti.created_at as index_created,
  ius.last_read,
  age(now(), ti.created_at) as tracking_duration
FROM crdb_internal.index_usage_statistics ius
JOIN crdb_internal.table_indexes ti
  ON ius.table_id = ti.descriptor_id
  AND ius.index_id = ti.index_id
LIMIT 5;
```

**Action**: Wait 24-48 hours for representative query load before making drop decisions

### Issue: Performance Degraded After Drop

**Symptom:** Query latency increased

**Resolution:**
```sql
-- Recreate index immediately
CREATE INDEX index_name ON table_name (column_name);
```

**Prevention:**
- Test in staging first
- Review EXPLAIN plans before dropping
- Monitor closely after drop

## Performance Impact

### Expected Improvements

**Per index dropped:**
- Storage: 100 MB - 10+ GB reclaimed (depends on index size)
- Write performance: 5-10% speedup per index removed
- Multiple drops: 20-50% cumulative improvement on write-heavy workloads
- Memory: Reduced cache pressure from index blocks

**Measurement (Write Latency):**
```sql
-- Compare write latency before/after using statement statistics
SELECT
  metadata->>'query' as query,
  (statistics->'statistics'->'runLat'->'mean')::FLOAT / 1000000 as mean_latency_ms,
  (statistics->'statistics'->'cnt')::INT as execution_count,
  aggregated_ts
FROM crdb_internal.statement_statistics
WHERE metadata->>'query' LIKE '%INSERT INTO target_table%'
ORDER BY aggregated_ts DESC
LIMIT 5;
```

**Track storage savings:**
```sql
-- Check table/index sizes before and after
SHOW RANGES FROM TABLE target_table WITH DETAILS;
```

## Best Practices

### 1. Regular Audits
- **Frequency**: Monthly (production), Quarterly (dev)
- **Process**: Generate report → coordinate with teams → test → drop → monitor

### 2. Observation Period
- Development: 7 days minimum
- Staging: 14 days minimum
- Production: 30 days minimum

### 3. Index Creation Discipline
**Before creating:**
- Verify query needs it
- Check if existing index can be modified
- Consider composite vs single-column

**After creating:**
- Review usage after 30 days
- Verify expected queries use it

### 4. Documentation
Maintain index registry:
- Index name and purpose
- Dependent queries
- Creation date and rationale
- Expected usage patterns

### 5. Testing Before Production Drop
**In staging:**
1. Drop candidate index
2. Run full test suite
3. Execute representative query load
4. Monitor performance
5. Confirm no regressions

## Verification Checklist

After optimization:
- Unused indexes identified and documented
- Drop candidates reviewed with application teams
- Testing completed in staging
- Indexes dropped during maintenance window
- Query performance monitored post-drop
- No slow query alerts triggered
- Write performance improved
- Storage savings realized

## Related Skills

- `create-secondary-indexes-on-single-columns` - Creating indexes
- `create-composite-indexes-for-multi-column-queries` - Composite design
- `optimize-composite-index-column-ordering` - Index optimization
- `monitor-statement-statistics` - Query performance
- `use-db-console-insights-for-index-recommendations` - Automated insights

## Documentation

- Index Usage Statistics: https://www.cockroachlabs.com/docs/stable/crdb-internal.html#index_usage_statistics
- DB Console Insights: https://www.cockroachlabs.com/docs/stable/ui-insights-page.html
- Index Best Practices: https://www.cockroachlabs.com/docs/stable/schema-design-indexes.html
