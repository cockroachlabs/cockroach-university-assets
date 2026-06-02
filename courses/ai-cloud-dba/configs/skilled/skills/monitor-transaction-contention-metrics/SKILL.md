---
name: monitor-transaction-contention-metrics
description: Monitor transaction contention using DB Console Transactions page, crdb_internal.cluster_contention_events, and statement statistics. Track contention time, blocking transactions, and hot keys. Use when investigating performance issues or setting up alerts.
metadata:
  domain: Transactions
  bloom_level: Apply
  tags: transactions, performance, contention, monitoring
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Monitor Transaction Contention Metrics

Transaction contention monitoring helps identify performance bottlenecks caused by concurrent access to shared data. CockroachDB provides multiple tools to track contention events, measure their impact, and pinpoint specific tables and keys causing conflicts.

## What This Skill Teaches

This skill covers practical methods for monitoring contention:

- **DB Console Transactions Page**: Visual contention metrics per query
- **crdb_internal.cluster_contention_events**: Detailed contention event logs
- **Statement Statistics**: Contention time as percentage of execution time
- **Alert Thresholds**: When contention indicates optimization need (>10% rule)
- **Hot Key Identification**: Finding specific rows/tables causing bottlenecks
- **Retry Error Tracking**: Monitoring 40001/40003 errors in application logs

## Monitoring Methods

### Method 1: DB Console Transactions Page

**Access**: Navigate to `http://<cluster-address>:8080/transactions`

**Key Metrics Available**:
- **Contention Time**: Total time spent waiting for locks
- **Contention Percentage**: Contention time / Total execution time
- **Transaction Count**: Number of executions
- **Rows Read/Written**: Transaction breadth indicators
- **Retry Rate**: Percentage of transactions that retried

**Interpreting Results**:
```
Transaction: UPDATE inventory SET quantity = ...
Execution Time: 150ms
Contention Time: 75ms
Contention %: 50%  ⚠️  HIGH - needs optimization

Transaction: SELECT * FROM products WHERE ...
Execution Time: 10ms
Contention Time: 0.5ms
Contention %: 5%  ✓  ACCEPTABLE
```

**When to Investigate**:
- Contention >10% of execution time
- Sudden increases in contention percentage
- Contention time growing under load

### Method 2: Query crdb_internal.cluster_contention_events

This internal table logs recent contention events with rich context.

**Basic Contention Overview**:
```sql
-- Recent contention events with duration
SELECT
    collection_ts,
    contention_duration,
    blocking_txn_id,
    waiting_txn_id,
    database_name,
    schema_name,
    table_name,
    index_name,
    num_contention_events
FROM crdb_internal.cluster_contention_events
ORDER BY contention_duration DESC
LIMIT 20;
```

**Expected Output**:
```
  collection_ts           | contention_duration | database_name | table_name | num_contention_events
--------------------------+---------------------+---------------+------------+----------------------
  2026-03-07 14:23:15.123 |          1250000000 | myapp         | inventory  |                   45
  2026-03-07 14:23:14.891 |           890000000 | myapp         | orders     |                   23
  2026-03-07 14:23:13.456 |           450000000 | myapp         | accounts   |                   12
```

Note: `contention_duration` is in nanoseconds (divide by 1,000,000 for milliseconds)

**Hot Table Analysis**:
```sql
-- Tables with most cumulative contention
SELECT
    table_name,
    COUNT(*) AS contention_events,
    SUM(contention_duration) / 1000000 AS total_contention_ms,
    AVG(contention_duration) / 1000000 AS avg_contention_ms,
    MAX(contention_duration) / 1000000 AS max_contention_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
    AND table_name IS NOT NULL
GROUP BY table_name
ORDER BY total_contention_ms DESC
LIMIT 10;
```

**Expected Output**:
```
  table_name | contention_events | total_contention_ms | avg_contention_ms | max_contention_ms
-------------+-------------------+---------------------+-------------------+------------------
  inventory  |               450 |             12450.5 |              27.7 |            1250.0
  orders     |               230 |              5670.2 |              24.7 |             890.0
  accounts   |               120 |              2340.8 |              19.5 |             450.0
```

**Specific Key Contention**:
```sql
-- Find which exact keys are contending
SELECT
    table_name,
    index_name,
    key,
    num_contention_events,
    contention_duration / 1000000 AS contention_ms
FROM crdb_internal.cluster_contention_events
WHERE table_name = 'inventory'
ORDER BY contention_duration DESC
LIMIT 20;
```

**Transaction Fingerprint Analysis**:
```sql
-- Identify which transaction patterns are contending
SELECT
    blocking_txn_fingerprint_id,
    waiting_txn_fingerprint_id,
    table_name,
    COUNT(*) AS conflict_count,
    SUM(contention_duration) / 1000000 AS total_wait_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '30 minutes'
GROUP BY blocking_txn_fingerprint_id, waiting_txn_fingerprint_id, table_name
ORDER BY total_wait_ms DESC
LIMIT 15;
```

**Time-Series Analysis**:
```sql
-- Track contention trends over time
SELECT
    date_trunc('minute', collection_ts) AS minute,
    COUNT(*) AS events,
    SUM(contention_duration) / 1000000 AS total_contention_ms,
    AVG(contention_duration) / 1000000 AS avg_contention_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
GROUP BY minute
ORDER BY minute DESC;
```

### Method 3: Statement Statistics with Contention Time

**Query Statement Stats**:
```sql
-- Find statements with highest contention
SELECT
    metadata ->> 'query' AS query,
    metadata ->> 'db' AS database,
    statistics -> 'statistics' -> 'cnt' AS execution_count,
    (statistics -> 'statistics' -> 'runLat' -> 'mean')::FLOAT AS avg_runtime_sec,
    (statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT AS avg_contention_sec,
    ROUND(
        (((statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT) /
         NULLIF((statistics -> 'statistics' -> 'runLat' -> 'mean')::FLOAT, 0)) * 100,
        2
    ) AS contention_pct
FROM crdb_internal.statement_statistics
WHERE (statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT > 0
ORDER BY avg_contention_sec DESC
LIMIT 20;
```

**Simplified Version**:
```sql
-- Aggregate contention by statement
SELECT
    aggregated_ts,
    fingerprint_id,
    app_name,
    (statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT AS avg_contention_sec
FROM crdb_internal.statement_statistics
WHERE app_name NOT LIKE '$ internal%'
ORDER BY avg_contention_sec DESC
LIMIT 10;
```

### Method 4: Application-Level Retry Tracking

**Monitor Error Codes**:
Track these PostgreSQL error codes in application logs:
- **40001** (`RETRY_WRITE_TOO_OLD`): Transaction timestamp too old
- **40003** (`RETRY_SERIALIZABLE`): Serialization failure

**Example Application Metric**:
```python
# Pseudocode for application monitoring
def execute_transaction():
    retry_count = 0
    while retry_count < MAX_RETRIES:
        try:
            # Execute transaction
            return success
        except psycopg2.OperationalError as e:
            if e.pgcode in ['40001', '40003']:
                retry_count += 1
                metrics.increment('transaction.retries.contention')
                continue
            raise
```

**Alert on Retry Rate**:
```
Alert: retry_rate > 5% of total transactions
```

## Monitoring Dashboards

### Essential Metrics to Track

**Real-Time Monitoring**:
1. **Contention Events per Minute**: Trend line
2. **Top 5 Hot Tables**: Bar chart of contention time
3. **Average Contention Duration**: Moving average
4. **Retry Error Rate**: Percentage of 40001/40003 errors
5. **Transactions with >10% Contention**: Count

**Historical Analysis**:
1. **Contention by Hour of Day**: Identify peak times
2. **Contention Before/After Schema Changes**: Impact analysis
3. **Per-Table Contention Trends**: Week-over-week comparison

### Sample Grafana Query (Prometheus)

```promql
# Average contention time per statement
rate(sql_contention_time_seconds_sum[5m]) /
rate(sql_contention_time_seconds_count[5m])

# Transaction retry rate
rate(txn_restarts_total{restart_type="serializable"}[5m])
```

## Alert Thresholds

### Warning Level (Investigate)
- Contention >10% of transaction execution time
- >100 contention events per minute on single table
- Average contention duration >50ms
- Retry rate >5% of transactions

### Critical Level (Immediate Action)
- Contention >25% of transaction execution time
- >500 contention events per minute
- Average contention duration >200ms
- Retry rate >15% of transactions
- Specific table showing >1 second cumulative contention per minute

## Practical Monitoring Workflow

### Step 1: Establish Baseline
```sql
-- Capture baseline during normal operations
SELECT
    table_name,
    AVG(contention_duration) / 1000000 AS baseline_avg_ms,
    MAX(contention_duration) / 1000000 AS baseline_max_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 day'
    AND table_name IS NOT NULL
GROUP BY table_name;
```

### Step 2: Monitor Deviations
```sql
-- Compare current contention to baseline
WITH baseline AS (
    SELECT
        table_name,
        AVG(contention_duration) AS baseline_avg
    FROM crdb_internal.cluster_contention_events
    WHERE collection_ts BETWEEN now() - INTERVAL '7 days' AND now() - INTERVAL '1 day'
    GROUP BY table_name
),
current AS (
    SELECT
        table_name,
        AVG(contention_duration) AS current_avg
    FROM crdb_internal.cluster_contention_events
    WHERE collection_ts > now() - INTERVAL '1 hour'
    GROUP BY table_name
)
SELECT
    c.table_name,
    b.baseline_avg / 1000000 AS baseline_ms,
    c.current_avg / 1000000 AS current_ms,
    ROUND(((c.current_avg - b.baseline_avg) / NULLIF(b.baseline_avg, 0)) * 100, 2) AS pct_increase
FROM current c
JOIN baseline b ON c.table_name = b.table_name
WHERE c.current_avg > b.baseline_avg * 1.5  -- 50% increase threshold
ORDER BY pct_increase DESC;
```

### Step 3: Drill Down to Root Cause
```sql
-- For identified hot table, find specific keys
SELECT
    key,
    num_contention_events,
    contention_duration / 1000000 AS contention_ms
FROM crdb_internal.cluster_contention_events
WHERE table_name = '<hot_table_from_step2>'
    AND collection_ts > now() - INTERVAL '1 hour'
ORDER BY contention_duration DESC
LIMIT 20;
```

### Step 4: Correlate with Workload
```sql
-- Check if contention correlates with query volume
SELECT
    date_trunc('minute', collection_ts) AS minute,
    COUNT(*) AS contention_events,
    SUM(contention_duration) / 1000000 AS total_contention_ms
FROM crdb_internal.cluster_contention_events
WHERE table_name = '<hot_table>'
    AND collection_ts > now() - INTERVAL '2 hours'
GROUP BY minute
ORDER BY minute;

-- Compare against query rate from statement stats
```

## Common Patterns and Interpretations

### Pattern 1: Sudden Spike
```
Normal:     [===] 10 events/min, 50ms avg
Spike:      [=================] 500 events/min, 50ms avg
```
**Interpretation**: Increased concurrency (more users), not slower transactions
**Action**: Check application traffic, consider scaling

### Pattern 2: Growing Duration
```
Hour 1:     [===] 50 events/min, 20ms avg
Hour 2:     [===] 50 events/min, 80ms avg
```
**Interpretation**: Transactions taking longer to resolve conflicts
**Action**: Check for long-running transactions, slow queries

### Pattern 3: Single Hot Key
```
Table:      inventory
Events:     90% on product_id='popular-item'
```
**Interpretation**: Hot key bottleneck
**Action**: Schema redesign, sharding, or application-level batching

### Pattern 4: Range Boundary Contention
```
Contention on keys near range split:
Range 1 end:   'key_m_999'
Range 2 start: 'key_n_000'
High contention at boundary
```
**Interpretation**: Cross-range transaction coordination
**Action**: Adjust range sizes or schema to reduce cross-range txns

## Monitoring Best Practices

1. **Set Up Automated Alerts**: Don't rely on manual checks
2. **Monitor Trends, Not Snapshots**: Contention varies with workload
3. **Correlate with Business Events**: Deployments, marketing campaigns, peak hours
4. **Track Per-Table Metrics**: Aggregate stats hide specific bottlenecks
5. **Retain Historical Data**: Enable before/after optimization comparisons
6. **Test Monitoring Under Load**: Ensure alerts fire appropriately

## Troubleshooting Monitoring Queries

**Issue**: `crdb_internal.cluster_contention_events` returns no rows
```sql
-- Check if contention tracking is enabled (default: on)
SHOW CLUSTER SETTING sql.contention.event_store.capacity;
-- Should be non-zero (default: 64MB)

-- Check if there's actually contention
SELECT COUNT(*) FROM crdb_internal.cluster_contention_events;
-- May be zero if no recent contention occurred
```

**Issue**: Permission denied
```sql
-- Grant necessary permissions
GRANT SELECT ON crdb_internal.cluster_contention_events TO monitoring_user;
```

**Issue**: High memory usage from contention event store
```sql
-- Reduce retention capacity if needed
SET CLUSTER SETTING sql.contention.event_store.capacity = '32MB';
```

## Related Skills

**Understanding Contention**:
- `understand-transaction-contention-causes` - Root causes of contention
- `explain-transaction-layer-functionality` - How transactions work in CockroachDB

**Optimization Techniques**:
- `minimize-transaction-duration-to-reduce-contention` - Reduce lock hold time
- `minimize-transaction-breadth-to-reduce-contention` - Reduce keys locked
- `design-schemas-to-minimize-transaction-contention` - Schema-level solutions

**Application-Level**:
- `handle-transaction-retry-errors-in-applications` - Handle 40001/40003 errors
- `implement-transaction-retry-logic-in-applications` - Client-side retry loops

**Advanced Monitoring**:
- `identify-long-running-transactions` - Find transactions holding locks too long
- `use-db-console-sql-activity-page` - Visual query performance analysis

## When to Use This Skill

Trigger this skill when:
- User says "check contention", "monitor transaction performance"
- Application experiencing retry errors or slow transactions
- Setting up performance monitoring dashboards
- Investigating specific performance regression
- Validating impact of optimization changes

## Example Monitoring Session

```sql
-- 1. Quick health check
SELECT COUNT(*) AS recent_events,
       AVG(contention_duration) / 1000000 AS avg_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '5 minutes';

-- 2. Identify worst offender
SELECT table_name, SUM(contention_duration) / 1000000 AS total_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '5 minutes'
GROUP BY table_name
ORDER BY total_ms DESC
LIMIT 3;

-- 3. Drill into specific table
SELECT key, num_contention_events, contention_duration / 1000000 AS ms
FROM crdb_internal.cluster_contention_events
WHERE table_name = '<worst_table>'
ORDER BY contention_duration DESC
LIMIT 10;

-- 4. Check transaction patterns
SELECT blocking_txn_fingerprint_id, COUNT(*) AS conflicts
FROM crdb_internal.cluster_contention_events
WHERE table_name = '<worst_table>'
GROUP BY blocking_txn_fingerprint_id
ORDER BY conflicts DESC;
```

## Further Reading

- [CockroachDB Docs: Contention Dashboard](https://www.cockroachlabs.com/docs/stable/ui-sql-dashboard#contention)
- [CockroachDB Docs: crdb_internal Tables](https://www.cockroachlabs.com/docs/stable/crdb-internal)
- [CockroachDB Docs: Transaction Retry Errors](https://www.cockroachlabs.com/docs/stable/transaction-retry-error-reference)
