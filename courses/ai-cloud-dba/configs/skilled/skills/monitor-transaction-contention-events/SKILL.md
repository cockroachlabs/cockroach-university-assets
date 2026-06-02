---
name: monitor-transaction-contention-events
description: Query crdb_internal.transaction_contention_events to identify contending transactions, analyze affected tables/keys, measure contention duration, and correlate high contention with schema design issues or workload patterns causing lock conflicts
metadata:
  domain: Monitoring and Alerting
  bloom_level: Analyze
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: production
---

# Monitor Transaction Contention Events

**Domain**: Monitoring and Alerting
**Bloom's Level**: Analyze
**CockroachDB Version**: v26.1.0+

## Overview

Transaction contention occurs when multiple transactions compete for access to the same data, causing waiting transactions to block while others hold locks. CockroachDB records these events in `crdb_internal.transaction_contention_events`, providing visibility into performance bottlenecks from lock conflicts.

This skill covers:
- Querying `transaction_contention_events` to identify problematic transactions
- Analyzing affected tables, indexes, and keys
- Measuring contention duration and severity
- Correlating contention with schema design and workload patterns
- Implementing corrective actions

Contention is a leading cause of performance degradation in distributed databases. Proactive monitoring helps identify hotspots, optimize schemas, and improve throughput.

**v26.1.0 Compatibility Note**: In v26.1.0, accessing `crdb_internal` tables requires setting `allow_unsafe_internals = true` for your session. The table stores statement fingerprint IDs, not full SQL text.

## Understanding transaction_contention_events Table

The `transaction_contention_events` virtual table captures transaction conflicts cluster-wide. Each row represents a blocking event.

### Essential Columns

- `waiting_txn_id`, `blocking_txn_id`: Transaction UUIDs
- `waiting_txn_fingerprint_id`, `blocking_txn_fingerprint_id`: Transaction fingerprints
- `waiting_stmt_id`, `waiting_stmt_fingerprint_id`: Statement identifiers (not full SQL text)
- `database_name`, `schema_name`, `table_name`, `index_name`: Affected objects
- `contending_key`, `contending_pretty_key`: Specific contended key (bytes and readable format)
- `collection_ts`: Timestamp when contention was recorded
- `contention_duration`: Wait time (interval)
- `contention_type`: Type of contention event

**v26.1.0 Limitation**: The table stores statement fingerprint IDs, not actual SQL text. To correlate with statement text, join with `crdb_internal.statement_statistics` using `waiting_stmt_fingerprint_id`.

**Data Retention**: Events persist in memory until SQL stats reset or node restart. Export to external systems for long-term analysis.

## Identifying Contending Transactions

### Query High-Duration Events

Identify the most severe contention by duration:

```sql
SELECT
  contention_duration,
  database_name,
  table_name,
  index_name,
  waiting_txn_id,
  blocking_txn_id,
  collection_ts AS contention_time,
  contending_pretty_key
FROM crdb_internal.transaction_contention_events
ORDER BY contention_duration DESC
LIMIT 20;
```

**Severity thresholds**: 100ms = significant, 1s+ = critical bottleneck.

### Analyze by Table

```sql
SELECT
  table_name,
  COUNT(*) AS events,
  SUM(EXTRACT(epoch FROM contention_duration)) AS total_seconds,
  AVG(EXTRACT(epoch FROM contention_duration)) AS avg_seconds
FROM crdb_internal.transaction_contention_events
GROUP BY table_name
ORDER BY total_seconds DESC
LIMIT 15;
```

### Analyze by Index

```sql
SELECT
  table_name,
  index_name,
  COUNT(*) AS events,
  AVG(EXTRACT(epoch FROM contention_duration)) AS avg_seconds
FROM crdb_internal.transaction_contention_events
WHERE index_name IS NOT NULL
GROUP BY table_name, index_name
ORDER BY events DESC
LIMIT 15;
```

### Identify Blocking Transactions

```sql
SELECT
  blocking_txn_id,
  COUNT(*) AS times_blocked,
  AVG(EXTRACT(epoch FROM contention_duration)) AS avg_duration,
  array_agg(DISTINCT table_name) AS affected_tables
FROM crdb_internal.transaction_contention_events
GROUP BY blocking_txn_id
ORDER BY times_blocked DESC
LIMIT 10;
```

**Note**: Statement text is not available in this table. Use `blocking_txn_fingerprint_id` to correlate with `crdb_internal.statement_statistics` if needed.

## Analyzing Affected Tables and Keys

### Examine Contentious Keys

```sql
SELECT
  table_name,
  contending_pretty_key,
  COUNT(*) AS events,
  AVG(EXTRACT(epoch FROM contention_duration)) AS avg_duration
FROM crdb_internal.transaction_contention_events
WHERE table_name = 'your_table_name'
GROUP BY table_name, contending_pretty_key
ORDER BY events DESC
LIMIT 10;
```

**Patterns**: Same key = single-row hotspot; sequential keys = monotonic key issue.

### Correlate with Schema

```sql
SHOW CREATE TABLE your_database.your_table;
```

Look for sequential primary keys, unique constraints, or frequently updated indexes.

## Measuring Contention Duration

### Duration Distribution

```sql
SELECT
  CASE
    WHEN contention_duration < INTERVAL '10ms' THEN '0-10ms'
    WHEN contention_duration < INTERVAL '50ms' THEN '10-50ms'
    WHEN contention_duration < INTERVAL '100ms' THEN '50-100ms'
    WHEN contention_duration < INTERVAL '500ms' THEN '100-500ms'
    ELSE '500ms+'
  END AS bucket,
  COUNT(*) AS events,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM crdb_internal.transaction_contention_events
GROUP BY bucket;
```

**Impact**: 0-10ms = minimal, 50-100ms = significant, 100ms+ = critical.

### Trend Over Time

```sql
SELECT
  DATE_TRUNC('hour', collection_ts) AS hour,
  COUNT(*) AS events,
  AVG(EXTRACT(epoch FROM contention_duration)) AS avg_seconds
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;
```

### Percentile Analysis

```sql
WITH durations AS (
  SELECT EXTRACT(epoch FROM contention_duration) AS secs
  FROM crdb_internal.transaction_contention_events
)
SELECT
  ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY secs), 3) AS p50,
  ROUND(percentile_cont(0.90) WITHIN GROUP (ORDER BY secs), 3) AS p90,
  ROUND(percentile_cont(0.99) WITHIN GROUP (ORDER BY secs), 3) AS p99
FROM durations;
```

## Correlating with Schema Design

### Sequential Primary Keys

```sql
SELECT
  table_name,
  index_name,
  COUNT(*) AS events
FROM crdb_internal.transaction_contention_events
WHERE index_name LIKE '%pkey%'
GROUP BY table_name, index_name
ORDER BY events DESC;
```

**Common causes**: `TIMESTAMP DEFAULT NOW()`, `SERIAL`, sequential UUIDs.

**Solutions**:
- Use `gen_random_uuid()` for random distribution
- Enable hash sharding: `CREATE TABLE ... USING HASH WITH BUCKET_COUNT = 8`
- Composite keys: `(region, timestamp)`

### Unique Constraints

Unique indexes serialize concurrent writes:

```sql
SELECT
  table_name,
  index_name,
  COUNT(*) AS events
FROM crdb_internal.transaction_contention_events
WHERE index_name IN (
  SELECT index_name FROM crdb_internal.table_indexes WHERE is_unique = true
)
GROUP BY table_name, index_name
ORDER BY events DESC;
```

**Mitigations**: Batch updates, reduce update frequency, reconsider uniqueness requirements.

### Foreign Keys

FK checks can cause contention on parent tables. Add indexes on FK columns and consider denormalization for read-heavy workloads.

## Common Contention Patterns

### Pattern 1: Sequential Key Hotspots

**Symptoms**: High contention on primary key, increases with write volume.

**Resolution**:
- Hash-sharded indexes: `USING HASH WITH BUCKET_COUNT = 8`
- Random UUIDs: `gen_random_uuid()`
- Composite keys with high-cardinality prefix

### Pattern 2: Counter Updates

**Symptoms**: Same row updated repeatedly, simple UPDATEs blocking each other.

**Resolution**:
- Column families for hot columns
- Optimistic locking with retries
- Eventual consistency patterns

### Pattern 3: Read-Modify-Write

**Symptoms**: SELECT + UPDATE in same transaction, contention during writes.

**Resolution**:
- Use `SELECT FOR UPDATE` to lock early
- Reduce transaction scope
- Consider READ COMMITTED isolation

### Pattern 4: Index Maintenance

**Symptoms**: Multiple secondary indexes contending during writes.

**Resolution**:
- Remove unused indexes
- Use partial indexes
- Batch writes

## Resolving Contention

### Immediate Actions

**Identify blocking transactions**:
```sql
SELECT
  blocking_txn_id,
  COUNT(*) AS blocked_events,
  array_agg(DISTINCT table_name) AS affected_tables
FROM crdb_internal.transaction_contention_events
WHERE contention_duration > INTERVAL '1s'
GROUP BY blocking_txn_id
ORDER BY blocked_events DESC;
```

**Check long-running transactions**:
```sql
SELECT txn_id, application_name, (NOW() - start) AS duration
FROM crdb_internal.cluster_transactions
WHERE (NOW() - start) > INTERVAL '10s'
ORDER BY duration DESC;
```

### Schema Optimization

**Hash-sharded keys**:
```sql
CREATE TABLE events (
  event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_time TIMESTAMP DEFAULT NOW(),
  event_data JSONB
) WITH (experimental_hash_sharded_indexes = 'on');
```

**Column families for hot columns**:
```sql
CREATE TABLE user_stats (
  user_id UUID PRIMARY KEY,
  username STRING,
  login_count INT,
  FAMILY f_identity (user_id, username),
  FAMILY f_stats (login_count)
);
```

### Application Changes

**Retry logic** (Python):
```python
from cockroachdb.sqlalchemy import run_transaction
run_transaction(engine, update_counter, counter_id="abc-123")
```

**Minimize transaction scope**:
```sql
-- Avoid: Long transaction with business logic
-- Prefer: Short transactions with minimal lock time
SELECT * FROM orders WHERE user_id = 'user-123';  -- Outside txn
BEGIN;
UPDATE orders SET status = 'processed' WHERE id = 'order-456';
COMMIT;
```

## Best Practices

### Monitoring Strategy

**Create monitoring view**:
```sql
CREATE VIEW v_high_contention AS
SELECT
  table_name,
  COUNT(*) AS events,
  AVG(EXTRACT(epoch FROM contention_duration)) AS avg_seconds
FROM crdb_internal.transaction_contention_events
WHERE contention_duration > INTERVAL '100ms'
GROUP BY table_name
ORDER BY events DESC;
```

**External monitoring**: Export to Prometheus (`sql_txn_contention_events_total`), Datadog, or Grafana. Set alerts for threshold violations.

**Baselines**: Document acceptable contention levels per table and alert on deviations.

**v26.1.0 Note**: Remember to set `allow_unsafe_internals = true` when querying `crdb_internal` tables in monitoring queries.

### Schema Design

1. Avoid sequential primary keys in high-throughput tables
2. Use hash-sharding for monotonic keys
3. Limit secondary indexes (5-7 maximum)
4. Use partial indexes to reduce scope
5. Separate hot columns into column families
6. Consider denormalization for read-heavy workloads

### Application Development

1. Keep transactions short and focused
2. Implement exponential backoff retry logic
3. Batch operations instead of row-by-row updates
4. Use `SELECT FOR UPDATE` for read-modify-write
5. Consider optimistic locking for low contention

### Operations

1. Review contention weekly
2. Correlate with deployments
3. Load test schema changes
4. Document known patterns

## Troubleshooting

### No Events Showing

**Check stats collection**:
```sql
SHOW CLUSTER SETTING sql.stats.automatic_collection.enabled;
```

**Resolution**: Enable with `SET CLUSTER SETTING sql.stats.automatic_collection.enabled = true;`. Data may have reset; wait for new events or use `SHOW TRACE` on slow queries.

### Unknown Blocking Source

**Investigation**:
```sql
SELECT
  table_name,
  contending_pretty_key,
  contention_duration,
  blocking_txn_id
FROM crdb_internal.transaction_contention_events
WHERE blocking_txn_id IS NULL
ORDER BY contention_duration DESC;
```

**Resolution**: Enable statement diagnostics, review application logs, use `SHOW TRACE FOR SESSION`, check external delays.

### Contention After Schema Changes

**Check recent changes**:
```sql
SELECT table_name, index_name, created_at
FROM crdb_internal.table_indexes
WHERE created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC;
```

**Resolution**: Roll back if problematic, analyze index necessity, consider partial indexes, run `ANALYZE table_name;`.

### Single-Row Hotspot

**Identify persistent keys**:
```sql
SELECT
  table_name,
  contending_pretty_key,
  COUNT(*) AS occurrences
FROM crdb_internal.transaction_contention_events
GROUP BY table_name, contending_pretty_key
HAVING COUNT(*) > 10
ORDER BY occurrences DESC;
```

**Solutions**: Redesign counter patterns, use optimistic locking, shard singleton rows, rethink partitioning.

### Memory Pressure

**Check usage**:
```sql
SELECT node_id, used, available
FROM crdb_internal.node_runtime_info
WHERE component = 'go';
```

**Resolution**: Reduce stats retention (`sql.stats.persisted_rows.max`), reset stats with `crdb_internal.reset_sql_stats()` (loses history), export data first.

## Related Skills

- **query-transaction-statistics**: Analyze overall transaction performance metrics
- **diagnose-slow-queries**: Identify and optimize slow SQL statements
- **optimize-table-schema-for-performance**: Design schemas to minimize contention
- **configure-transaction-retry-settings**: Set up application retry logic
- **monitor-range-hotspots**: Identify and resolve range-level performance issues
- **analyze-statement-execution-plans**: Understand query behavior and locking patterns
- **troubleshoot-performance-degradation**: Systematic approach to performance issues
- **configure-sql-stats-collection**: Control statistics collection and retention
