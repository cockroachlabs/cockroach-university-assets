---
name: diagnose-write-intent-buildup-issues
description: Diagnose write intent buildup issues by monitoring intent metrics, identifying problematic long-running transactions, analyzing root causes, and implementing resolution strategies to restore performance.
metadata:
  domain: Workload Management and Performance
  bloom_level: Analyze
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: active
---

# Diagnose Write Intent Buildup Issues

**Domain**: Workload Management and Performance
**Bloom's Level**: Analyze

## What This Skill Teaches

This skill teaches you how to **diagnose and resolve write intent buildup issues**—a critical performance problem caused by uncommitted transactions accumulating provisional writes:

- **What write intents are**: Provisional MVCC versions from uncommitted transactions
- **Normal vs. abnormal intent accumulation**: Expected patterns vs. problematic buildup
- **Root causes**: Long-running transactions, abandoned transactions, high write volume
- **Performance impact**: Blocking reads, memory pressure, GC backlog, query slowdowns
- **Diagnostic techniques**: Monitoring intent metrics, identifying problematic transactions
- **Resolution strategies**: Canceling transactions, tuning timeouts, fixing application code
- **Prevention**: Best practices to avoid intent buildup before it occurs

You'll learn:
- How to detect intent buildup using DB Console metrics and system tables
- How to identify which transactions are creating excessive intents
- How to analyze transaction patterns to determine root causes
- How to resolve active intent issues quickly
- How to prevent future occurrences through configuration and code changes

---

## Understanding Write Intent Buildup

### What Are Write Intents?

A **write intent** is a **provisional MVCC version** created when a transaction writes data **before committing**. Intents serve as placeholders marking "this data is being modified by transaction X."

**Normal lifecycle**:
```
1. Transaction writes → Intent created
2. Transaction commits → Intent becomes committed version (milliseconds)
3. Intent resolved → New version visible to all
```

**Storage representation**:
```
Key: /users/42
├── Intent @ Txn ABC123: {email: "new@example.com"}  ← Uncommitted
└── Committed @ T=1000: {email: "old@example.com"}   ← Previous version
```

### Normal Intent Accumulation

In a healthy cluster, intents:
- Exist for **milliseconds to seconds**
- Are **quickly resolved** when transactions commit
- Number of active intents scales with **concurrent write transactions**
- Typical workload: 10-100 active intents per node

**Example**: E-commerce checkout
```sql
BEGIN;
  UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 42;
  INSERT INTO orders (user_id, product_id, amount) VALUES (99, 42, 29.99);
COMMIT;
-- Intents exist for ~50ms, immediately resolved
```

### Abnormal Intent Buildup

**Intent buildup** occurs when intents accumulate faster than they're resolved:

**Symptoms**:
- Intent count grows continuously (hundreds to thousands per node)
- Intent age increases (seconds to minutes or hours)
- Queries slow down or time out
- Storage growth without corresponding data changes
- Memory pressure on nodes

**Example**: Problematic long-running transaction
```sql
BEGIN;
  -- Transaction starts at 10:00 AM
  UPDATE users SET status = 'processing' WHERE id = 42;
  -- Application performs slow external API call (5 minutes)
  -- ... complex calculations ...
  UPDATE users SET status = 'complete' WHERE id = 42;
COMMIT;
-- Intents exist for 5+ minutes, blocking other queries
```

---

## Causes of Write Intent Buildup

### 1. Long-Running Transactions (Most Common)

**Cause**: Transactions that remain open for extended periods without committing.

**Common patterns**:
```sql
-- ❌ PROBLEMATIC: Long transaction with external I/O
BEGIN;
  UPDATE orders SET status = 'processing' WHERE id = 100;
  -- Call external payment API (takes 30 seconds)
  -- Call shipping API (takes 20 seconds)
  UPDATE orders SET status = 'shipped' WHERE id = 100;
COMMIT;
-- Intents held for 50+ seconds
```

**Why it happens**:
- Network I/O inside transactions (API calls, file uploads)
- Complex computations between writes
- Interactive transactions in CLI sessions
- Missing `COMMIT` statements in application code
- Waiting for user input within transaction

**Impact**:
- Each write creates an intent that blocks concurrent reads
- Other transactions must wait for intents to resolve
- Cascade effect: one slow transaction blocks many readers

### 2. Abandoned Transactions

**Cause**: Transactions that never commit or rollback due to crashes or connection loss.

**How it happens**:
```sql
BEGIN;
  UPDATE products SET price = 99.99 WHERE id = 5;
  -- Client crashes here
  -- Connection drops
  -- No COMMIT or ROLLBACK issued
-- Intent remains until timeout cleanup (default: 4 hours)
```

**Common scenarios**:
- Application crash mid-transaction
- Network connection timeout
- Database connection pool reclaimed connections
- Developer exits psql without committing

**Impact**:
- Intents remain until transaction timeout (default `txn_timeout` = 4 hours)
- Blocks reads on affected keys
- Accumulates if crashes happen frequently

### 3. High Write Volume with Slow Commits

**Cause**: Many concurrent transactions writing simultaneously faster than commit rate.

**Scenario**:
```sql
-- 1000 concurrent connections all running:
BEGIN;
  INSERT INTO events (user_id, event_type, timestamp) VALUES (...);
  -- Each insert creates intent
  -- If commits are delayed, intents accumulate
COMMIT;
```

**Why it happens**:
- Bulk data loading without proper batching
- High-frequency sensor data ingestion
- Log aggregation pipelines
- ETL processes with large transaction scopes

**Impact**:
- Total intent count = concurrent writes × average transaction duration
- Example: 500 writes/sec × 2s average duration = 1000 active intents

### 4. Transaction Contention and Retries

**Cause**: Conflicting transactions causing retries that hold intents longer.

**Example**:
```sql
-- Transaction A
BEGIN;
  UPDATE accounts SET balance = balance - 100 WHERE id = 1;
  -- Conflict with Transaction B
  -- CockroachDB retries with new timestamp
  -- Original intents remain during retry
COMMIT;
```

**Why it happens**:
- Hot key contention (many transactions updating same row)
- Incorrect transaction isolation usage
- Schema design forcing updates to shared counters

**Impact**:
- Retries extend intent lifetime
- Multiple retry attempts multiply intent accumulation
- Exponential backoff delays resolution

### 5. Very Large Transactions

**Cause**: Single transaction modifying thousands or millions of rows.

**Example**:
```sql
-- ❌ PROBLEMATIC: Bulk update in single transaction
BEGIN;
  UPDATE users SET notification_enabled = true WHERE region = 'US';
  -- Updates 10 million rows
  -- Creates 10 million write intents
COMMIT;
-- May run for minutes, holding all intents
```

**Why it happens**:
- Bulk updates without batching
- Schema migrations in transactions
- Mass data corrections

**Impact**:
- Massive intent count (proportional to modified rows)
- Memory pressure on coordinator node
- Blocks concurrent operations on affected table

---

## Performance Impact of Intent Buildup

### 1. Blocking Reads

**How intents block reads**:

When a reader encounters an intent:
```
Key: /orders/100
├── Intent @ Txn T1: {status: "shipped"}  ← Uncommitted
└── Committed @ T=1000: {status: "pending"}
```

**Reader's actions**:
1. Check transaction record: "Is T1 committed, aborted, or running?"
2. **If running**: Reader **waits** for T1 to complete
3. **If committed/aborted**: Reader resolves intent and continues

**Result**: Unresolved intents from active transactions cause query latency.

**Example symptom**:
```sql
-- Normal query: 5ms
SELECT * FROM orders WHERE id = 100;

-- With long-running transaction holding intent: 30+ seconds
SELECT * FROM orders WHERE id = 100;  -- Waits for intent
```

### 2. Memory Pressure

**Intent metadata consumes memory**:
- Each intent stores: transaction ID, timestamp, provisional value
- Thousands of intents = significant memory usage
- Memory held on leaseholder node for affected ranges

**Memory calculation**:
```
Memory per intent ≈ 100-500 bytes (metadata + provisional value)
10,000 intents ≈ 1-5 MB memory
1,000,000 intents ≈ 100-500 MB memory
```

**Impact**:
- Memory pressure on storage layer
- Potential OOM (Out of Memory) on nodes
- Reduced cache efficiency

### 3. Garbage Collection Backlog

**Intents interfere with GC**:
- GC cannot remove old MVCC versions until intents are resolved
- Intent buildup prevents compaction
- Storage accumulates obsolete versions

**Result**:
- Disk space growth
- Slower range scans (must skip unremoved versions)
- Increased read amplification

### 4. Query Slowdowns

**Cascading performance degradation**:

```
Long transaction holds intents
    ↓
Readers encounter intents
    ↓
Readers wait (blocking)
    ↓
Connection pool exhaustion
    ↓
New queries queue
    ↓
Application timeouts
```

**Measured impact**:
- P50 latency: 10ms → 500ms
- P99 latency: 50ms → 10s+
- Query timeout rate increases
- User-facing errors

---

## Identifying Write Intent Buildup

### 1. DB Console: Storage Metrics

**Navigate to**: DB Console → Metrics → Storage

**Key metrics to watch**:

**Write Intents Graph**:
- Shows total intent count across cluster
- **Normal**: Relatively flat, < 1000 intents
- **Problem**: Continuously rising, thousands of intents

**Intent Age Graph**:
- Shows how long intents have existed
- **Normal**: < 1 second average age
- **Problem**: Growing age, multiple seconds or minutes

**Example interpretation**:
```
Time      Intent Count    Avg Intent Age
10:00     150            0.2s           ← Normal
10:15     300            0.5s           ← Slight increase
10:30     1,200          5.0s           ← Problem developing
10:45     5,000          45s            ← Severe buildup
```

**Red flags**:
- Intent count doubling every 5-10 minutes
- Intent age > 5 seconds
- Sudden spike in intent count

### 2. DB Console: SQL Activity Page

**Navigate to**: DB Console → SQL Activity → Transactions

**Look for**:

**Long-Running Transactions**:
- Filter: Status = "Executing"
- Sort by: "Elapsed Time" (descending)
- **Red flag**: Transactions running > 1 minute

**High Write Count**:
- Check "Rows Written" column
- **Red flag**: Transactions writing > 100,000 rows

**Transaction Details**:
- Click transaction to see full SQL statements
- Identify problematic queries

### 3. System Table: crdb_internal.node_txn_stats

**Monitor transaction statistics**:

```sql
SELECT
  node_id,
  txn_count,
  committed_count,
  aborted_count,
  (txn_count - committed_count - aborted_count) AS active_txns
FROM crdb_internal.node_txn_stats
ORDER BY active_txns DESC;
```

**Interpretation**:
```
node_id  txn_count  committed_count  aborted_count  active_txns
1        1000       980              15             5          ← Normal
2        5000       4800             50             150        ← Problem: 150 active
```

**Red flags**:
- High active transaction count (> 50 per node)
- Growing active count over time

### 4. Identify Long-Running Transactions

**Find transactions holding intents**:

```sql
SELECT
  node_id,
  session_id,
  txn_id,
  start,
  age(now(), start) AS duration,
  num_stmts_executed,
  num_auto_retries,
  active_queries
FROM crdb_internal.cluster_sessions
WHERE active_queries != ''
  AND txn_id IS NOT NULL
ORDER BY start ASC  -- Oldest first
LIMIT 20;
```

**Example output**:
```
session_id           txn_id              duration    active_queries
abc123...            def456...           00:05:30    UPDATE users SET ...
xyz789...            uvw012...           00:12:15    INSERT INTO logs ...
```

**Red flags**:
- Transactions running > 60 seconds
- Transactions with many retries (`num_auto_retries > 5`)
- Idle transactions (`active_queries` is empty but transaction open)

### 5. Check for Abandoned Transactions

**Find idle transactions (no active query)**:

```sql
SELECT
  session_id,
  txn_id,
  start,
  age(now(), start) AS idle_duration,
  last_active_query
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND active_queries = ''  -- No active query
  AND age(now(), start) > interval '1 minute'
ORDER BY start ASC;
```

**Interpretation**:
- These are transactions that began but haven't committed/rolled back
- Likely abandoned due to connection loss or application crash
- Should be investigated and potentially canceled

### 6. Log Analysis

**Search for intent-related warnings**:

```bash
grep -i "write intent" /var/log/cockroach/cockroach.log | tail -50
```

**Common log patterns**:

**Intent resolution warnings**:
```
W: waiting for write intent on key /Table/52/1/42 (transaction abc123-...)
I: resolving write intent for key /Table/52/1/42
I: cleaning up abandoned write intents from transaction def456-...
```

**Transaction timeout logs**:
```
W: transaction abc123 exceeded timeout (4h0m0s), aborting
I: aborting transaction abc123 due to client disconnect
```

**Interpretation**:
- Frequent "waiting for write intent" = active contention
- "Cleaning up abandoned" = crashes/disconnects
- Many timeout messages = `txn_timeout` may be too long

---

## Diagnosis Workflow

### Step 1: Detect Intent Buildup

**Check DB Console metrics**:
1. Navigate to DB Console → Metrics → Storage
2. Observe "Write Intents" graph
3. Check if intent count is growing
4. Check "Intent Age" graph for increasing average age

**Threshold for investigation**:
- Intent count > 1,000 and rising
- Intent age > 5 seconds

### Step 2: Identify Problematic Transactions

**Query active sessions**:

```sql
-- Find long-running transactions
SELECT
  session_id,
  txn_id,
  start,
  age(now(), start) AS duration,
  num_stmts_executed,
  active_queries
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND age(now(), start) > interval '10 seconds'
ORDER BY start ASC
LIMIT 10;
```

**Look for**:
- Oldest transactions (likely culprits)
- Transactions with empty `active_queries` (abandoned)
- Transactions with long duration but few statements

### Step 3: Analyze Transaction Operations

**Get full transaction details**:

```sql
-- Get query history for specific session
SELECT
  start,
  query,
  phase,
  status
FROM crdb_internal.cluster_queries
WHERE session_id = '<session_id_from_step2>'
ORDER BY start DESC;
```

**Determine transaction pattern**:
- What operations is it performing?
- Is it waiting on external resources?
- Is it a bulk operation?
- Is it stuck in a retry loop?

### Step 4: Determine Root Cause

**Classify the problem**:

**Long-running transaction**:
- Duration > 1 minute
- Active query visible
- Likely: complex logic inside transaction

**Abandoned transaction**:
- Duration > 5 minutes
- No active query
- Likely: connection lost or crash

**High write volume**:
- Many transactions with moderate duration
- High total intent count
- Likely: insufficient batching or commit rate

**Contention**:
- High `num_auto_retries`
- Multiple transactions on same table
- Likely: hot key contention

### Step 5: Implement Resolution

**See "Resolution Strategies" section below**

---

## Resolution Strategies

### 1. Cancel Long-Running Transactions

**Immediate action for active problematic transactions**:

```sql
-- Cancel specific session
CANCEL SESSION '<session_id>';

-- Cancel specific query (if session should continue)
CANCEL QUERY '<query_id>';
```

**When to cancel**:
- Transaction running > 5 minutes with no progress
- Abandoned transactions (idle with no active query)
- Transactions blocking critical operations

**Example**:
```sql
-- Find session to cancel
SELECT session_id, duration, active_queries
FROM (
  SELECT
    session_id,
    age(now(), start) AS duration,
    active_queries
  FROM crdb_internal.cluster_sessions
  WHERE txn_id IS NOT NULL
) WHERE duration > interval '5 minutes';

-- Cancel it
CANCEL SESSION '16b31fe7c2f43f5c0000000000000001';
```

**After canceling**:
- Intents are asynchronously cleaned up
- Monitor DB Console: intent count should decrease
- May take 1-2 minutes for full cleanup

### 2. Configure Transaction Timeouts

**Prevent future abandoned transactions**:

**Session-level timeout**:
```sql
-- Set timeout for current session
SET transaction_timeout = '60s';
SET statement_timeout = '30s';
```

**Database-level defaults**:
```sql
-- Set default for all new sessions
ALTER DATABASE mydb SET transaction_timeout = '60s';
ALTER DATABASE mydb SET statement_timeout = '30s';
```

**Cluster-wide defaults**:
```sql
-- Set cluster-wide defaults
SET CLUSTER SETTING sql.defaults.transaction_timeout = '60s';
SET CLUSTER SETTING sql.defaults.statement_timeout = '30s';
```

**Recommended values**:
- `statement_timeout`: 30-60 seconds (single query max)
- `transaction_timeout`: 60-300 seconds (entire transaction max)
- Adjust based on application requirements

**Trade-offs**:
- **Shorter timeouts**: Prevent long-running issues, may abort legitimate slow queries
- **Longer timeouts**: Allow complex operations, risk intent buildup

### 3. Fix Application Code

**Reduce transaction scope**:

**Before** (problematic):
```python
# ❌ Long transaction with external I/O
conn.execute("BEGIN")
conn.execute("UPDATE orders SET status = 'processing' WHERE id = 100")

# External API call (30 seconds)
payment_result = call_payment_api(order_id=100)

# More external I/O
shipping_label = generate_shipping_label(order_id=100)

conn.execute("UPDATE orders SET status = 'shipped' WHERE id = 100")
conn.execute("COMMIT")
# Transaction held open for 30+ seconds
```

**After** (fixed):
```python
# ✅ External I/O outside transaction
payment_result = call_payment_api(order_id=100)
shipping_label = generate_shipping_label(order_id=100)

# Short transaction for database updates only
conn.execute("BEGIN")
conn.execute("""
  UPDATE orders
  SET status = 'shipped',
      payment_id = %s,
      tracking_number = %s
  WHERE id = 100
""", (payment_result.id, shipping_label.tracking))
conn.execute("COMMIT")
# Transaction held open for ~50ms
```

**Key principle**: **Only database operations inside transactions**

### 4. Batch Large Operations

**Split large transactions into smaller chunks**:

**Before** (problematic):
```sql
-- ❌ Single transaction updating millions of rows
BEGIN;
  UPDATE users SET notification_enabled = true WHERE region = 'US';
  -- 10 million rows, holds intents for minutes
COMMIT;
```

**After** (fixed):
```sql
-- ✅ Batch updates in smaller transactions
DO $$
DECLARE
  batch_size INT := 10000;
  rows_affected INT;
BEGIN
  LOOP
    WITH to_update AS (
      SELECT id FROM users
      WHERE region = 'US' AND notification_enabled = false
      LIMIT batch_size
    )
    UPDATE users
    SET notification_enabled = true
    WHERE id IN (SELECT id FROM to_update);

    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    EXIT WHEN rows_affected = 0;

    COMMIT;  -- Commit each batch
    -- Small delay to avoid overloading cluster
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;
```

**Benefits**:
- Each batch commits quickly (intents resolved)
- Smaller memory footprint
- Interleaves with other transactions
- Can be paused/resumed if needed

### 5. Implement Automatic Retry Logic

**Handle retries outside transaction**:

**Problematic pattern**:
```python
# ❌ Retry logic keeps transaction open
conn.execute("BEGIN")
for retry in range(5):
    try:
        conn.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
        break
    except TransactionRetryError:
        time.sleep(2 ** retry)  # Exponential backoff
        # Transaction still open during sleep!
conn.execute("COMMIT")
```

**Better pattern**:
```python
# ✅ Close and retry entire transaction
for retry in range(5):
    try:
        conn.execute("BEGIN")
        conn.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
        conn.execute("COMMIT")
        break  # Success
    except TransactionRetryError:
        conn.execute("ROLLBACK")  # Explicit rollback
        time.sleep(2 ** retry)
```

### 6. Monitor for Repeat Occurrences

**Set up alerts**:

**Intent count alert**:
```sql
-- Alert if intent count > 5000
SELECT sum(intent_count) AS total_intents
FROM crdb_internal.kv_store_status;
```

**Long transaction alert**:
```sql
-- Alert if any transaction > 2 minutes
SELECT count(*) AS long_txns
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND age(now(), start) > interval '2 minutes';
```

**Configure Prometheus alerts** (if using monitoring):
```yaml
- alert: HighIntentCount
  expr: sum(sys_intents) > 5000
  for: 5m
  annotations:
    summary: "High write intent count detected"

- alert: LongRunningTransaction
  expr: max(sql_txn_latency_seconds) > 120
  for: 2m
  annotations:
    summary: "Long-running transaction detected"
```

---

## Prevention Best Practices

### 1. Design Short Transactions

**Principle**: Transactions should complete in < 1 second ideally, < 10 seconds maximum.

**Guidelines**:
- Perform reads and computation **before** `BEGIN`
- Only include writes in transaction
- Avoid external I/O (API calls, file operations)
- Use autocommit for single statements

**Example**:
```python
# ✅ GOOD: Short transaction pattern
data = fetch_and_compute_data()  # Outside transaction
validate_business_rules(data)    # Outside transaction

with db.transaction():           # Transaction starts here
    db.execute("INSERT INTO orders VALUES (...)", data)
    db.execute("UPDATE inventory SET quantity = quantity - 1 WHERE ...")
# Transaction commits here (~50ms total)
```

### 2. Use Statement and Transaction Timeouts

**Always configure timeouts**:

```sql
-- Application startup
SET CLUSTER SETTING sql.defaults.transaction_timeout = '60s';
SET CLUSTER SETTING sql.defaults.statement_timeout = '30s';
```

**Per-application tuning**:
```sql
-- Fast OLTP application
ALTER DATABASE oltp_db SET transaction_timeout = '10s';

-- Analytics/reporting application
ALTER DATABASE analytics_db SET transaction_timeout = '300s';
```

### 3. Implement Connection Pooling Correctly

**Ensure transactions close on connection return**:

**Problematic**:
```python
# ❌ Connection returned to pool with open transaction
conn = pool.get_connection()
conn.execute("BEGIN")
conn.execute("UPDATE ...")
pool.return_connection(conn)  # Transaction still open!
```

**Correct**:
```python
# ✅ Explicit transaction management
conn = pool.get_connection()
try:
    conn.execute("BEGIN")
    conn.execute("UPDATE ...")
    conn.execute("COMMIT")
except:
    conn.execute("ROLLBACK")
    raise
finally:
    pool.return_connection(conn)
```

**Use transaction context managers**:
```python
# ✅ Context manager ensures cleanup
with pool.get_connection() as conn:
    with conn.transaction():  # Auto COMMIT or ROLLBACK
        conn.execute("UPDATE ...")
```

### 4. Monitor Intent Metrics Regularly

**Establish baseline**:
- Track normal intent count (e.g., 50-200 during peak hours)
- Track normal intent age (e.g., < 0.5 seconds)
- Set alerts for 3x baseline

**Weekly review**:
- Check DB Console → Metrics → Storage → Write Intents
- Review long-running transaction patterns
- Identify slow queries that should be optimized

### 5. Educate Development Teams

**Common pitfalls to avoid**:
- Opening transactions in interactive CLI sessions and forgetting to commit
- Performing network I/O inside transactions
- Not handling connection failures (leading to abandoned transactions)
- Using transactions for read-only operations unnecessarily

**Code review checklist**:
- [ ] Are transactions as short as possible?
- [ ] Is external I/O outside transaction scope?
- [ ] Are timeouts configured?
- [ ] Is retry logic implemented correctly?
- [ ] Are large operations batched?

---

## Case Study: Diagnosing Real-World Intent Buildup

### Scenario

**Symptoms reported**:
- Users reporting slow page loads (5-10 seconds)
- Database queries timing out intermittently
- DB Console showing 15,000 write intents (normally ~200)

### Step 1: Confirm Intent Buildup

**Check DB Console**:
```
Metrics → Storage → Write Intents
  Current: 15,342 intents
  Trend: Increasing 1000 intents per minute
  Intent Age: Average 45 seconds (normally < 1 second)
```

**Diagnosis**: Severe intent buildup confirmed.

### Step 2: Identify Problematic Transactions

**Query active sessions**:
```sql
SELECT
  session_id,
  start,
  age(now(), start) AS duration,
  active_queries
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
ORDER BY start ASC
LIMIT 5;
```

**Output**:
```
session_id           start               duration   active_queries
abc123...           10:15:23            00:25:17   UPDATE user_sessions SET ...
def456...           10:20:45            00:19:55   INSERT INTO analytics_events ...
ghi789...           10:35:12            00:05:03   UPDATE orders SET ...
```

**Finding**: Two transactions running > 15 minutes!

### Step 3: Analyze Transaction Details

**Investigate longest transaction**:
```sql
SELECT query, phase, status
FROM crdb_internal.cluster_queries
WHERE session_id = 'abc123...'
ORDER BY start DESC;
```

**Output**:
```sql
UPDATE user_sessions SET last_active = now() WHERE user_id IN (
  -- Subquery selecting millions of rows
  SELECT id FROM users WHERE last_login < '2024-01-01'
);
```

**Root cause**: Bulk update attempting to modify millions of rows in single transaction.

### Step 4: Immediate Resolution

**Cancel the problematic transactions**:
```sql
CANCEL SESSION 'abc123...';
CANCEL SESSION 'def456...';
```

**Result**:
- Intents start declining: 15,342 → 12,000 → 8,000 → 500 (over 2 minutes)
- Query latency returns to normal
- Page load times recover

### Step 5: Long-Term Fix

**Rewrite problematic query with batching**:
```sql
-- New approach: Batch updates
DO $$
DECLARE
  batch_size INT := 1000;
BEGIN
  LOOP
    WITH to_update AS (
      SELECT id FROM users
      WHERE last_login < '2024-01-01'
        AND id NOT IN (
          SELECT user_id FROM user_sessions WHERE last_active > now() - interval '5 minutes'
        )
      LIMIT batch_size
    )
    UPDATE user_sessions
    SET last_active = now()
    WHERE user_id IN (SELECT id FROM to_update);

    EXIT WHEN NOT FOUND;
    COMMIT;
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;
```

**Configure timeout**:
```sql
SET CLUSTER SETTING sql.defaults.transaction_timeout = '60s';
```

**Outcome**:
- No more intent buildup from this operation
- Query runs in batches over 10 minutes instead of single 25-minute transaction
- No impact on concurrent transactions

---

## Monitoring Queries Reference

### Check Current Intent Count

```sql
SELECT
  node_id,
  sum((metrics->>'intentcount')::INT) AS intent_count
FROM crdb_internal.kv_node_status
GROUP BY node_id
ORDER BY intent_count DESC;
```

### Find Oldest Active Transactions

```sql
SELECT
  session_id,
  txn_id,
  start,
  age(now(), start) AS age,
  active_queries
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
ORDER BY start ASC
LIMIT 10;
```

### Identify Idle Transactions (Abandoned)

```sql
SELECT
  session_id,
  start,
  age(now(), start) AS idle_duration,
  last_active_query
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND active_queries = ''
  AND age(now(), start) > interval '1 minute'
ORDER BY idle_duration DESC;
```

### Count Transactions by Duration

```sql
SELECT
  CASE
    WHEN duration < interval '1 second' THEN '< 1s'
    WHEN duration < interval '10 seconds' THEN '1-10s'
    WHEN duration < interval '60 seconds' THEN '10-60s'
    WHEN duration < interval '300 seconds' THEN '1-5m'
    ELSE '> 5m'
  END AS duration_bucket,
  count(*) AS txn_count
FROM (
  SELECT age(now(), start) AS duration
  FROM crdb_internal.cluster_sessions
  WHERE txn_id IS NOT NULL
)
GROUP BY duration_bucket
ORDER BY duration_bucket;
```

### Monitor Intent Resolution Rate

```sql
-- Run periodically to see intent count trend
SELECT
  now() AS timestamp,
  sum((metrics->>'intentcount')::INT) AS total_intents
FROM crdb_internal.kv_node_status;
```

---

## Troubleshooting Common Issues

### Issue: Intent Count Not Decreasing After Canceling Transactions

**Symptom**: Canceled transactions but intent count remains high.

**Cause**: Intent cleanup is asynchronous and may take time.

**Solution**:
1. Wait 2-5 minutes for cleanup to complete
2. Check if other transactions are still creating intents
3. Monitor logs for cleanup activity:
   ```bash
   grep "cleaning up.*intent" /var/log/cockroach/cockroach.log
   ```

### Issue: Cannot Identify Transaction Causing Intents

**Symptom**: High intent count but no long-running transactions visible.

**Cause**: Many short-lived transactions with high write volume.

**Solution**:
```sql
-- Check transaction throughput
SELECT
  node_id,
  txn_count,
  committed_count,
  aborted_count
FROM crdb_internal.node_txn_stats
ORDER BY txn_count DESC;
```

**Action**:
- High `txn_count` indicates volume issue, not long transactions
- Solution: Reduce write rate or increase cluster capacity
- Consider batching writes at application level

### Issue: Intents Reappear After Cleanup

**Symptom**: Intents decrease but quickly build up again.

**Cause**: Application continuously creating long transactions.

**Solution**:
1. Identify application source:
   ```sql
   SELECT application_name, count(*)
   FROM crdb_internal.cluster_sessions
   WHERE txn_id IS NOT NULL
   GROUP BY application_name;
   ```
2. Review application code for transaction patterns
3. Deploy code fix with shorter transactions
4. Configure timeouts as safety net

---

## Key Concepts Summary

| Concept | Description |
|---------|-------------|
| **Write Intent** | Provisional MVCC version from uncommitted transaction |
| **Intent Buildup** | Accumulation of unresolved intents faster than resolution |
| **Normal Intent Count** | 10-100 per node in healthy cluster |
| **Problematic Intent Count** | 1,000+ and growing |
| **Long-Running Transaction** | Transaction open > 1 minute (problematic > 5 minutes) |
| **Abandoned Transaction** | Transaction never committed/rolled back due to crash |
| **Intent Age** | Time since intent was created |
| **Intent Resolution** | Converting intent to committed version or removing on abort |
| **Blocking Reads** | Queries waiting for intents to resolve |

---

## Related Skills

**Data Management**:
- `understand-mvcc-multi-version-concurrency-control-concepts` - MVCC foundation (intent context)
- `understand-write-intent-cleanup-and-transaction-resolution` - Intent lifecycle fundamentals
- `understand-how-mvcc-and-garbage-collection-affect-storage` - Storage impact

**Transactions**:
- `minimize-transaction-duration-to-reduce-contention` - Prevention strategies
- `implement-transaction-retry-logic-in-applications` - Correct retry patterns
- `configure-transaction-isolation-levels` - Isolation and intent visibility

**Monitoring**:
- `identify-long-running-transactions` - Finding problematic transactions
- `monitor-transaction-contention-metrics` - Related contention issues
- `monitor-write-intent-accumulation` - Proactive monitoring (Transactions domain)

**Troubleshooting**:
- `cancel-long-running-or-problematic-queries` - Resolution techniques
- `diagnose-slow-query-performance` - Related performance issues
- `troubleshoot-transaction-retry-errors` - Retry and contention diagnosis

**Workload Management**:
- `optimize-bulk-insert-operations` - Batching best practices
- `configure-statement-and-transaction-timeouts` - Timeout configuration

---

## References

- [CockroachDB Docs: Transaction Layer Architecture](https://www.cockroachlabs.com/docs/stable/architecture/transaction-layer.html#write-intents)
- [CockroachDB Docs: Transactions](https://www.cockroachlabs.com/docs/stable/transactions.html)
- [CockroachDB Docs: SET transaction_timeout](https://www.cockroachlabs.com/docs/stable/set-vars.html#supported-variables)
- [Blog: Life of a Distributed Transaction](https://www.cockroachlabs.com/blog/life-of-a-distributed-transaction/)
- [Blog: Transaction Retry Best Practices](https://www.cockroachlabs.com/docs/stable/transaction-retry-error-reference.html)

---

**Version**: 1.0.0
**Last Updated**: March 7, 2026
**Tested Against**: CockroachDB v26.1.0
