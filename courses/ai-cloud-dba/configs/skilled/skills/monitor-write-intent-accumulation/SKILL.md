---
name: monitor-write-intent-accumulation
description: Monitor write intent metrics in DB Console and system tables to detect long-running transactions, diagnose performance issues, and troubleshoot excessive intent accumulation.
metadata:
  domain: Transactions
  bloom_level: Apply
  tags: write-intents, monitoring, performance, transactions, troubleshooting
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Monitor Write Intent Accumulation

**Domain**: Transactions
**Bloom's Level**: Apply

## What This Skill Teaches

This skill provides **hands-on techniques** for monitoring and diagnosing write intent accumulation:

- **Using DB Console Storage dashboard** to track intent metrics
- **Querying crdb_internal.cluster_locks** to inspect active intents
- **Identifying long-running transactions** causing intent buildup
- **Diagnosing performance degradation** from excessive intents
- **Setting up alerts** for unhealthy intent levels
- **Troubleshooting and remediation** when intents exceed thresholds
- **Understanding intent cleanup processes** and their effectiveness

You'll learn:
- How to read and interpret write intent metrics
- When to consider intent levels problematic (>100K threshold)
- How to find transactions responsible for intent accumulation
- How to use system tables and logs for intent investigation
- How to implement monitoring and alerting for intent health
- Practical remediation strategies for intent-related issues

---

## Understanding Write Intent Metrics

### What Normal Looks Like

**Healthy cluster**:
- **Intent count**: 0 - 10,000 intents (fluctuates with transaction load)
- **Intent age**: < 1 second for 95th percentile
- **Intent bytes**: < 1% of total storage
- **Intent resolution rate**: Matches transaction commit/abort rate

**Why these ranges?**
- Typical transactions commit in milliseconds to low seconds
- Intents exist briefly between write and commit
- Short-lived intents don't accumulate
- Cleanup processes keep pace with creation

### What Problematic Looks Like

**Unhealthy cluster**:
- **Intent count**: > 100,000 intents (especially if growing)
- **Intent age**: > 5-10 seconds consistently
- **Intent bytes**: > 5% of storage or rapidly growing
- **Intent resolution rate**: Lags behind creation rate

**Why this is bad**:
- **Read performance degrades**: Readers must resolve or wait for intents
- **Storage bloat**: Unresolved intents consume disk space
- **Transaction conflicts increase**: More chances of encountering blocking intents
- **System instability**: Extreme cases (>1M intents) can cause severe slowdowns

---

## Monitoring Write Intents in DB Console

### Storage Dashboard Overview

**Navigate to**: DB Console → Metrics → Storage

**Key charts**:

#### 1. Live Bytes vs Intent Bytes

**Chart**: "Live Bytes" and "Write Intent Bytes"

**Interpretation**:
```
Live Bytes: 10 GB (actual committed data)
Intent Bytes: 50 MB (0.5% of live bytes) → ✅ Healthy
Intent Bytes: 1 GB (10% of live bytes) → ⚠️ Concerning
Intent Bytes: 5 GB (50% of live bytes) → ❌ Critical
```

**What to look for**:
- Intent bytes should be small fraction of live bytes
- Steady growth indicates accumulation problem
- Spikes during bulk operations are normal

#### 2. Write Intent Count

**Chart**: "Write Intents"

**Interpretation**:
```
Count: 0-10K    → ✅ Normal for low-medium load
Count: 10K-50K  → ⚠️ Monitor closely, check for long transactions
Count: 50K-100K → ⚠️ Investigate actively
Count: >100K    → ❌ Action required
```

**What to look for**:
- Stable fluctuation vs. steady growth
- Correlation with transaction rate
- Sudden spikes (may indicate stalled transaction)

#### 3. Write Intent Age

**Chart**: "Write Intent Age" (if available in your version)

**Interpretation**:
```
P50: <100ms  → ✅ Excellent
P95: <1s     → ✅ Good
P95: 1-5s    → ⚠️ Some slow transactions
P95: >10s    → ❌ Long-running transactions causing problems
P99: >60s    → ❌ Critical issue
```

**What to look for**:
- Most intents should resolve quickly (sub-second)
- High P99 indicates stragglers (long transactions or abandoned intents)

### Step-by-Step: Checking Intent Health in DB Console

**1. Open Storage Dashboard**
```
http://localhost:8080/#/metrics/storage/cluster
```

**2. Check Intent Count**
- Locate "Write Intents" chart
- Note current value and trend (increasing/stable/decreasing)
- If > 50K, proceed to investigation

**3. Check Intent Bytes**
- Locate "Write Intent Bytes" chart
- Calculate percentage of live bytes: `(Intent Bytes / Live Bytes) * 100`
- If > 5%, investigate

**4. Check Time Range**
- Use time selector to view last hour, day, or week
- Identify patterns (time-of-day spikes, steady growth, sudden jumps)

**5. Correlate with Transaction Activity**
- Open SQL Activity → Transactions tab
- Look for long-running transactions matching intent spike timing

---

## Querying System Tables for Intent Details

### Using crdb_internal.cluster_locks

**Primary table** for inspecting active locks and intents:

```sql
-- View all current locks (includes write intents)
SELECT
  database_name,
  schema_name,
  table_name,
  lock_key_pretty,
  txn_id,
  duration,
  granted
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
ORDER BY duration DESC
LIMIT 20;
```

**Sample output**:
```
 database_name | schema_name | table_name | lock_key_pretty | txn_id                               | duration  | granted
---------------+-------------+------------+-----------------+--------------------------------------+-----------+---------
 mydb          | public      | orders     | /100            | e8a5b123-4567-89ab-cdef-0123456789ab | 00:02:15  | true
 mydb          | public      | users      | /42             | f9b6c234-5678-90bc-def0-1234567890cd | 00:00:45  | true
 mydb          | public      | inventory  | /5              | a1c7d345-6789-01cd-ef01-2345678901de | 00:00:12  | true
```

**Interpretation**:
- `duration`: How long intent has existed
- `txn_id`: Transaction holding the intent
- `lock_key_pretty`: Row key (often shows primary key value like /100)
- `granted = true`: Intent is actively held

**Red flags**:
- Duration > 60 seconds: Long-running transaction
- Many rows with same txn_id: Transaction writing to many keys
- Thousands of rows: Excessive intent accumulation

### Finding Transactions Holding Intents

```sql
-- Identify sessions with long-running transactions holding intents
SELECT
  session_id,
  txn_id,
  application_name,
  client_address,
  active_queries,
  start,
  age(now(), start) AS txn_duration
FROM [SHOW CLUSTER SESSIONS]
WHERE txn_id IN (
  SELECT DISTINCT txn_id
  FROM crdb_internal.cluster_locks
  WHERE lock_strength = 'Intent'
    AND duration > INTERVAL '30s'
)
ORDER BY start;
```

**Sample output**:
```
 session_id | txn_id  | application_name | client_address | active_queries      | start               | txn_duration
------------+---------+------------------+----------------+---------------------+---------------------+--------------
 171a2...   | e8a5... | my_app           | 10.0.1.5:54321 | UPDATE orders ...   | 2026-03-07 10:05:00 | 00:05:23
 182b3...   | f9b6... | data_loader      | 10.0.1.8:44567 | <IDLE in txn>       | 2026-03-07 10:08:15 | 00:02:08
```

**Action**:
- Contact application owners for long transactions
- Kill problematic sessions if necessary: `CANCEL SESSION 'session_id'`

### Counting Intents Per Table

```sql
-- Estimate intent distribution across tables
SELECT
  table_name,
  COUNT(*) AS intent_count,
  MAX(duration) AS max_intent_age
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY table_name
ORDER BY intent_count DESC
LIMIT 10;
```

**Sample output**:
```
 table_name | intent_count | max_intent_age
------------+--------------+----------------
 orders     | 45678        | 00:03:45
 inventory  | 12345        | 00:01:20
 users      | 3456         | 00:00:15
```

**Interpretation**:
- Identifies hot tables with many concurrent writes
- High intent count + high max age = problem table
- Use to prioritize investigation efforts

---

## Monitoring Intent Cleanup Effectiveness

### Checking Intent Resolution Rate

**Concept**: Intents should be resolved (committed or aborted) at roughly the same rate they're created.

**Metrics to compare**:
```
Intent Creation Rate ≈ Transaction Write Rate
Intent Resolution Rate ≈ Transaction Commit + Abort Rate

If Creation > Resolution → Intents accumulate
```

**DB Console approach**:
1. Note current intent count: e.g., 50K
2. Wait 1 minute
3. Note new intent count: e.g., 75K
4. Accumulation rate: +25K/minute → ❌ Problem

**SQL approach**:
```sql
-- Capture intent count at two points in time
SELECT count(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';
-- Note: 45,678 at T=0

-- Wait 60 seconds

SELECT count(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';
-- Note: 67,890 at T=60

-- Calculation:
-- Accumulation: (67890 - 45678) / 60 = 370 intents/second
-- If this is sustained, investigate why resolution is lagging
```

### Checking GC Intent Cleanup Logs

**Search logs** for intent cleanup activity:

```bash
grep "cleaning up abandoned" /var/log/cockroach/cockroach.log | tail -20
```

**Sample output**:
```
I: cleaning up abandoned write intents from transaction abc123 (age: 4h15m)
I: cleaning up abandoned write intents from transaction def456 (age: 6h22m)
W: intent resolution took 15s for transaction ghi789 (high intent count)
```

**Interpretation**:
- Regular cleanup messages: GC is working
- Very old ages (>4 hours): Abandoned intents from crashed clients
- Slow resolution times: High intent count per transaction

---

## Setting Alert Thresholds

### Recommended Alert Rules

**Critical Alert** (page on-call):
```
Alert: WriteIntentAccumulationCritical
Condition: write_intent_count > 100,000
Duration: 5 minutes
Action: Immediate investigation required
```

**Warning Alert** (notify team):
```
Alert: WriteIntentAccumulationWarning
Condition: write_intent_count > 50,000
Duration: 10 minutes
Action: Review long-running transactions
```

**Intent Age Alert**:
```
Alert: OldWriteIntents
Condition: write_intent_age_p95 > 10s
Duration: 5 minutes
Action: Check for stuck transactions
```

**Intent Bytes Alert**:
```
Alert: WriteIntentStorageHigh
Condition: (write_intent_bytes / live_bytes) > 0.05
Duration: 5 minutes
Action: Investigate storage consumption
```

### Prometheus Query Examples

**For Prometheus/Grafana monitoring**:

```promql
# Intent count
sum(intentcount) by (cluster)

# Intent age P95
histogram_quantile(0.95, rate(intentage_bucket[5m]))

# Intent bytes percentage
(sum(intentbytes) / sum(livebytes)) * 100
```

---

## Diagnostic Scenarios

### Scenario 1: Steady Intent Growth

**Symptoms**:
- Intent count increases steadily over hours
- DB Console shows linear upward trend
- Performance slowly degrading

**Diagnosis**:

**Step 1**: Check for long-running transactions
```sql
SELECT
  session_id,
  active_queries,
  age(now(), start) AS duration
FROM [SHOW CLUSTER SESSIONS]
WHERE start < now() - INTERVAL '5 minutes'
ORDER BY start;
```

**Step 2**: Check for "IDLE in transaction" sessions
```sql
SELECT session_id, application_name, start
FROM [SHOW CLUSTER SESSIONS]
WHERE active_queries = '<IDLE in transaction>'
  AND age(now(), start) > INTERVAL '1 minute';
```

**Step 3**: Review application code
- Look for BEGIN without COMMIT
- Check connection pool settings (idle transaction timeout)
- Review error handling (transactions not rolled back on error)

**Remediation**:
```sql
-- Kill stuck sessions
CANCEL SESSION 'session_id';

-- Configure timeouts to prevent future occurrences
SET CLUSTER SETTING sql.defaults.idle_in_transaction_session_timeout = '5m';
```

### Scenario 2: Sudden Intent Spike

**Symptoms**:
- Intent count jumps from 5K to 150K in minutes
- Correlated with specific time/event
- May return to normal or remain elevated

**Diagnosis**:

**Step 1**: Check transaction activity
```sql
-- Look for bulk operations
SELECT
  application_name,
  COUNT(*) AS txn_count,
  SUM(num_writes) AS total_writes
FROM [SHOW CLUSTER SESSIONS]
GROUP BY application_name
ORDER BY total_writes DESC;
```

**Step 2**: Identify bulk write transaction
```sql
-- Find transaction with many writes
SELECT txn_id, COUNT(*) AS intent_count
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY txn_id
ORDER BY intent_count DESC
LIMIT 5;
```

**Step 3**: Check if it's a legitimate bulk operation
- Data migration job?
- Large batch insert?
- Schema change writing to many rows?

**Remediation**:
```sql
-- If problematic, cancel the transaction
CANCEL SESSION (
  SELECT session_id FROM [SHOW CLUSTER SESSIONS]
  WHERE txn_id = 'problematic_txn_id'
);

-- Or wait for completion if legitimate
-- Monitor intent resolution after completion
```

### Scenario 3: Persistent High Intent Count

**Symptoms**:
- Intent count stays high (>100K) continuously
- No single long transaction found
- Many small transactions but intents not resolving

**Diagnosis**:

**Step 1**: Check intent cleanup rate
```sql
-- Count intents now
SELECT count(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';
-- Wait 60 seconds, count again
-- Calculate accumulation rate
```

**Step 2**: Check for GC issues
```bash
# Check logs for GC failures
grep -i "intent resolution.*failed" /var/log/cockroach/cockroach.log
```

**Step 3**: Review transaction throughput
- High write throughput might legitimately create many intents
- Check if intent count is proportional to transaction rate

**Remediation**:
```sql
-- If throughput-related, consider:
-- 1. Scaling cluster (add nodes)
-- 2. Optimizing transactions (batch smaller, reduce contention)
-- 3. Sharding hot keys
```

---

## Troubleshooting Excessive Intents (>100K)

### Immediate Actions

**1. Identify and stop the source**
```sql
-- Find sessions creating most writes
SELECT
  session_id,
  application_name,
  active_queries,
  num_writes
FROM [SHOW CLUSTER SESSIONS]
ORDER BY num_writes DESC
LIMIT 10;

-- Cancel problematic sessions
CANCEL SESSION 'session_id';
```

**2. Check cluster health**
```
http://localhost:8080/#/overview/list
```
- Are nodes healthy?
- Any nodes recently crashed? (may leave orphaned intents)

**3. Monitor intent resolution**
```sql
-- Watch intent count decrease
SELECT count(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';
-- Re-run every minute to confirm cleanup is happening
```

### Root Cause Investigation

**Common causes**:

**1. Application bugs**
- BEGIN without COMMIT/ROLLBACK
- Exception handling doesn't rollback
- Connection pool leaks (connections with open transactions)

**2. Long-running analytics queries**
```sql
-- Find queries running > 5 minutes
SELECT active_queries, age(now(), start)
FROM [SHOW CLUSTER SESSIONS]
WHERE age(now(), start) > INTERVAL '5 minutes';
```

**3. Bulk operations without batching**
```sql
-- Example: Updating 1M rows in single transaction
BEGIN;
  UPDATE large_table SET status = 'processed' WHERE status = 'pending';
  -- Creates 1M intents!
COMMIT;

-- Better: Batch in smaller transactions
DO $$
BEGIN
  FOR i IN 1..100 LOOP
    UPDATE large_table SET status = 'processed'
    WHERE id IN (
      SELECT id FROM large_table WHERE status = 'pending' LIMIT 10000
    );
    COMMIT;  -- Commits 10K intents at a time
  END LOOP;
END $$;
```

**4. Schema changes on large tables**
```sql
-- Check for running schema changes
SHOW JOBS WHERE job_type = 'SCHEMA CHANGE' AND status = 'running';
```

### Prevention Strategies

**1. Configure transaction timeouts**
```sql
-- Cluster-wide defaults
SET CLUSTER SETTING sql.defaults.transaction_timeout = '60s';
SET CLUSTER SETTING sql.defaults.statement_timeout = '30s';
SET CLUSTER SETTING sql.defaults.idle_in_transaction_session_timeout = '5m';
```

**2. Application-side transaction management**
```python
# Good pattern: Explicit transaction management
def update_order(order_id, status):
    with conn.begin():  # Auto-commits on success, rolls back on error
        conn.execute("UPDATE orders SET status = %s WHERE id = %s", (status, order_id))
    # Transaction automatically closed

# Bad pattern: Forgotten transaction
def update_order_bad(order_id, status):
    conn.execute("BEGIN")
    conn.execute("UPDATE orders SET status = %s WHERE id = %s", (status, order_id))
    # Oops, forgot to COMMIT! Intent left open until connection timeout
```

**3. Monitor application transaction patterns**
```sql
-- Review transaction statistics
SELECT
  application_name,
  AVG(num_writes) AS avg_writes,
  MAX(num_writes) AS max_writes
FROM [SHOW CLUSTER SESSIONS]
GROUP BY application_name;
```

---

## Best Practices for Intent Monitoring

### 1. Establish Baseline Metrics

**Measure normal operation**:
```
Week 1 baseline:
- Average intent count: 2,500
- P95 intent age: 0.5s
- Intent bytes: 15 MB (0.2% of live bytes)

Set alerts above baseline:
- Warning: 10,000 intents (4x baseline)
- Critical: 50,000 intents (20x baseline)
```

### 2. Regular Health Checks

**Daily dashboard review**:
- Check Storage dashboard for intent trends
- Review Transactions page for long-running queries
- Scan logs for intent cleanup warnings

**Weekly deep dive**:
```sql
-- Generate intent health report
WITH intent_stats AS (
  SELECT
    COUNT(*) AS total_intents,
    MAX(duration) AS max_age,
    AVG(duration) AS avg_age
  FROM crdb_internal.cluster_locks
  WHERE lock_strength = 'Intent'
)
SELECT
  total_intents,
  max_age,
  avg_age,
  CASE
    WHEN total_intents > 100000 THEN 'CRITICAL'
    WHEN total_intents > 50000 THEN 'WARNING'
    ELSE 'OK'
  END AS health_status
FROM intent_stats;
```

### 3. Correlate with Application Deployments

- Track intent metrics before/after deployments
- New code may introduce transaction leaks
- Compare metrics to previous version

### 4. Monitor Resolution Lag

```sql
-- Calculate intent backlog growth rate
-- Run at T=0:
SELECT count(*) AS intents_t0 FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';

-- Run at T=300 (5 minutes later):
SELECT count(*) AS intents_t5 FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';

-- If (intents_t5 - intents_t0) > 0 and growing: Resolution lagging
```

### 5. Use DB Console Insights

**Navigate to**: DB Console → Insights

- Look for "Long-running transaction" insights
- Review transaction fingerprints with high intent counts
- Use recommendations to optimize transaction patterns

---

## Key Metrics Summary

| Metric | Healthy | Warning | Critical | Action |
|--------|---------|---------|----------|--------|
| **Intent Count** | 0-10K | 10K-50K | >100K | Investigate long transactions |
| **Intent Age P95** | <1s | 1-10s | >10s | Find stuck transactions |
| **Intent Bytes %** | <1% | 1-5% | >5% | Check storage consumption |
| **Resolution Lag** | 0 | Growing slowly | Rapidly growing | Stop source, scale cluster |

---

## Related Skills

**Transactions**:
- `understand-write-intents-and-mvcc` - Conceptual foundation for intents
- `understand-write-intent-cleanup-and-transaction-resolution` - Intent lifecycle details
- `identify-long-running-transactions` - Finding problematic transactions
- `diagnose-write-intent-buildup-issues` - Advanced troubleshooting

**Monitoring**:
- `monitor-transaction-contention-metrics` - Contention from intent conflicts
- `access-and-navigate-db-console` - Using DB Console effectively
- `use-db-console-sql-activity-page` - Analyzing transaction patterns

**Performance**:
- `cancel-long-running-or-problematic-queries` - Stopping intent-holding transactions
- `implement-transaction-retry-logic-in-applications` - Handling intent conflicts
- `minimize-transaction-scope-and-duration` - Reducing intent lifetime

**Troubleshooting**:
- `generate-debug-zip-for-support` - Collecting diagnostic data including intent info
- `monitor-cluster-health-during-maintenance` - Overall cluster health checks

---

## References

- [CockroachDB Docs: Transactions](https://www.cockroachlabs.com/docs/stable/transactions.html)
- [CockroachDB Docs: Transaction Layer Architecture](https://www.cockroachlabs.com/docs/stable/architecture/transaction-layer.html)
- [CockroachDB Docs: DB Console Overview](https://www.cockroachlabs.com/docs/stable/ui-overview.html)
- [Blog: Understanding Transaction Contention](https://www.cockroachlabs.com/blog/transaction-contention/)
- [Docs: crdb_internal Tables](https://www.cockroachlabs.com/docs/stable/crdb-internal.html)

---

**Version**: 1.0.0
**Last Updated**: March 7, 2026
**Tested Against**: CockroachDB v26.1.0
