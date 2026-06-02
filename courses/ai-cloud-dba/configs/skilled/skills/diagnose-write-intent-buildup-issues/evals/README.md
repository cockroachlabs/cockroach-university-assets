## Test Coverage: diagnose-write-intent-buildup-issues

**Test Environment**: CockroachDB v26.1.0 at localhost:26258

### Test Files

1. **test_write_intent_diagnosis.sql** - Detect long-running transactions and intent patterns

### Test Execution

```bash
cockroach sql --host=localhost:26258 --insecure
\i /Users/nathanzamecnik/.claude/skills/diagnose-write-intent-buildup-issues/evals/test_write_intent_diagnosis.sql
```

### Coverage Summary

**test_write_intent_diagnosis.sql** (11 test groups, 20+ tests):
- ✅ Open transaction detection
- ✅ Long-running transaction identification
- ✅ Idle/abandoned transaction detection
- ✅ Transaction count analysis
- ✅ Duration categorization
- ✅ Query-to-transaction correlation
- ✅ Cluster setting verification
- ✅ Timeout testing
- ✅ Application pattern analysis

### Understanding Write Intents

**Normal Intent Lifecycle**:
```
1. Transaction writes → Intent created (milliseconds)
2. Transaction commits → Intent resolved
3. New version visible to all readers
```

**Problematic Intent Buildup**:
```
1. Transaction starts
2. Transaction writes (intents created)
3. Transaction runs for minutes/hours ← PROBLEM
4. Intents accumulate and block readers
```

### Manual Multi-Session Testing (REQUIRED)

To simulate **intent buildup**, run this scenario:

#### Setup
```sql
CREATE TABLE intent_test (id INT PRIMARY KEY, data TEXT);
INSERT INTO intent_test SELECT i, md5(random()::TEXT) FROM generate_series(1, 10000) i;
```

#### Session 1: Create Long Transaction (Intent Holder)
```sql
BEGIN;
UPDATE intent_test SET data = md5(random()::TEXT);
SELECT pg_sleep(300);  -- Hold transaction for 5 minutes!
-- DO NOT COMMIT - simulate abandoned transaction
```

#### Session 2: Monitor Intent Buildup
```sql
-- Detect long-running transaction
SELECT session_id, txn_id, (now() - start) AS duration
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
ORDER BY start ASC;

-- Check for idle transaction (no active query)
SELECT session_id, active_queries, (now() - start) AS idle_time
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL AND active_queries = '';

-- Find queries waiting on intents
SELECT query_id, phase, (now() - start) AS wait_time
FROM crdb_internal.cluster_queries
WHERE phase = 'waiting';
```

#### Session 3: Try to Read (Will Be Blocked)
```sql
-- This will wait for Session 1's intents to resolve
SELECT * FROM intent_test WHERE id = 1;
```

### Verification Checklist

- [ ] Long transaction detected in `cluster_sessions`
- [ ] `idle_time` increases while `pg_sleep` runs
- [ ] Session 3's query shows `phase = 'waiting'`
- [ ] Can identify `session_id` of blocking transaction
- [ ] `CANCEL SESSION` resolves the block
- [ ] After cancel, Session 3's query completes

### Resolution Testing

#### Cancel the Problematic Transaction
```sql
-- In monitoring session
CANCEL SESSION '<session_id_from_session1>';

-- Verify transaction cancelled
SELECT COUNT(*) FROM crdb_internal.cluster_sessions
WHERE session_id = '<session_id>';
-- Should return 0

-- Verify blocked query completes
-- Session 3 should now finish
```

### DB Console Verification

Navigate to: `http://localhost:8080/#/metrics`

#### Storage Metrics
- [ ] Check "Write Intents" graph
- [ ] Normal: < 1000 intents, relatively flat
- [ ] Problem: Continuously rising, thousands of intents
- [ ] Intent Age graph shows increasing age

#### SQL Activity → Transactions
- [ ] Long-running transactions visible
- [ ] "Elapsed Time" column shows duration
- [ ] Can click transaction for details

### Diagnostic Queries Reference

**Find oldest transactions**:
```sql
SELECT session_id, (now() - start) AS age
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
ORDER BY start ASC
LIMIT 5;
```

**Find abandoned transactions**:
```sql
SELECT session_id, (now() - start) AS idle_duration
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND active_queries = ''
  AND (now() - start) > INTERVAL '1 minute';
```

**Count by duration bucket**:
```sql
SELECT
  CASE
    WHEN duration < INTERVAL '1s' THEN '< 1s'
    WHEN duration < INTERVAL '60s' THEN '1-60s'
    WHEN duration < INTERVAL '5m' THEN '1-5m'
    ELSE '> 5m'
  END AS bucket,
  COUNT(*)
FROM (
  SELECT (now() - start) AS duration
  FROM crdb_internal.cluster_sessions
  WHERE txn_id IS NOT NULL
)
GROUP BY bucket;
```

### Success Criteria

✅ **PASS**: Detect open transactions via cluster_sessions
✅ **PASS**: Identify long-running transactions (duration > threshold)
✅ **PASS**: Find abandoned transactions (no active query)
✅ **PASS**: Timeout settings prevent unbounded transactions
✅ **PASS**: Can correlate queries to transactions
✅ **PASS**: Multi-session test demonstrates intent blocking
✅ **PASS**: CANCEL SESSION resolves intent buildup

### Common Intent Buildup Causes

1. **Long-running transactions**: External I/O inside transactions
2. **Abandoned transactions**: Connection loss without COMMIT/ROLLBACK
3. **High write volume**: Many concurrent writers with slow commits
4. **Transaction retries**: Contention causing extended intent lifetimes
5. **Large transactions**: Bulk updates without batching
