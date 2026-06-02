# Execute Evaluation Tests - monitor-write-intent-accumulation

## Overview
This directory contains evaluation tests for the `monitor-write-intent-accumulation` skill. These tests demonstrate practical intent monitoring techniques using system tables and DB Console.

## Test Environment
- **Cluster**: localhost:26258
- **Connection**: `/Users/nathanzamecnik/bin/cockroach sql --host=localhost:26258 --certs-dir=/Users/nathanzamecnik/certs`
- **DB Console**: http://localhost:8080
- **CockroachDB Version**: v26.1.0+

## Test Files

### Test 1: Query cluster_locks (`test-01-query-cluster-locks.sql`)
**Purpose**: Demonstrate monitoring queries from the skill

**What it tests**:
- Basic `crdb_internal.cluster_locks` queries
- Counting intents per table
- Intent duration analysis
- Health status assessment

**Expected Results**:
- Multiple monitoring queries execute successfully
- Intent health status categorization (HEALTHY/NORMAL/WARNING/CRITICAL)
- Intent count aggregations by table

### Test 2: Intent Accumulation (`test-02-intent-accumulation.sql`)
**Purpose**: Create multiple intents and monitor accumulation patterns

**What it tests**:
- Bulk write operations creating many intents
- Intent accumulation metrics (count, age, distribution)
- Transaction intent distribution
- Cleanup verification

**Expected Results**:
- Baseline: 0 or low intent count
- During transaction: 100+ intents visible
- After commit: 0 or very low intent count
- Demonstrates accumulation → resolution cycle

### Test 3: Long-Running Transaction Detection (`test-03-long-running-transaction.sql`)
**Purpose**: Demonstrate detection of long-running transactions via intent age

**What it tests**:
- Creating intents across multiple tables
- Grouping intents by transaction ID
- Intent health assessment query
- Accumulation rate measurement

**Expected Results**:
- Intents grouped by txn_id
- Health status based on thresholds (OK/WARNING/CRITICAL)
- Timestamp-based sampling for rate calculation

### Test 4: Session Intent Correlation (`test-04-session-intent-correlation.sql`)
**Purpose**: Demonstrate finding sessions responsible for write intents

**What it tests**:
- Querying active sessions with `SHOW CLUSTER SESSIONS`
- Correlating session information with intents
- Transaction statistics by application

**Expected Results**:
- Current session information displayed
- Intent counts by table
- Example query for joining sessions with intents via txn_id

### Test 5: Intent Resolution Rate (`test-05-intent-resolution-rate.sql`)
**Purpose**: Measure intent creation and cleanup effectiveness

**What it tests**:
- Baseline intent measurements
- Quick transaction commits (rapid resolution)
- Batch intent creation
- Resolution effectiveness analysis

**Expected Results**:
- Demonstrates fast resolution (0 intents after quick commits)
- Shows temporary accumulation during active transaction
- Cleanup verification after commit

## Running the Tests

### Option 1: Run Individual Tests
```bash
/Users/nathanzamecnik/bin/cockroach sql \
  --host=localhost:26258 \
  --certs-dir=/Users/nathanzamecnik/certs \
  < test-01-query-cluster-locks.sql
```

### Option 2: Run All Tests
```bash
./run-all-tests.sh
```

### Option 3: DB Console Verification
1. Open http://localhost:8080 in browser
2. Navigate to Metrics → Storage
3. Look for "Write Intents" chart
4. Run tests and observe intent count changes in real-time

## Key Monitoring Queries

### View All Active Intents
```sql
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

### Count Intents Per Table
```sql
SELECT
    table_name,
    COUNT(*) AS intent_count,
    MAX(duration) AS max_intent_age
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY table_name
ORDER BY intent_count DESC;
```

### Intent Health Assessment
```sql
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

### Find Long-Running Transactions
```sql
SELECT
    txn_id,
    COUNT(*) AS intent_count,
    MAX(duration) AS max_duration
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY txn_id
ORDER BY intent_count DESC
LIMIT 5;
```

## DB Console Metrics to Monitor

### Storage Dashboard
Navigate to: http://localhost:8080/#/metrics/storage/cluster

**Key Charts**:
1. **Write Intents** - Current number of intents
2. **Write Intent Bytes** - Storage consumed by intents
3. **Write Intent Age** - Distribution of intent ages

**During Tests**:
- Run a test in terminal
- Watch Storage dashboard for intent spikes
- Verify intents return to baseline after commit

### Expected Patterns
- **Normal**: Intent count fluctuates 0-10K
- **During bulk write**: Spike to 100+ intents
- **After commit**: Return to 0 or baseline within seconds

## Test Execution Timeline

1. **Baseline Measurement** (5 min)
   - Check current intent count
   - Note DB Console metrics
   - Document normal state

2. **Run Tests** (20 min)
   - Execute test-01 through test-05
   - Capture output
   - Take DB Console screenshots

3. **Verification** (10 min)
   - Verify cleanup (0 intents)
   - Check for any stuck intents
   - Review DB Console for anomalies

## Documenting Results

Create `TEST-RESULTS.md` with:
- Test execution timestamp
- Each test outcome (PASS/FAIL)
- Sample query outputs
- DB Console screenshots
- Intent count graphs
- Any observations or issues

## Troubleshooting

### No Intents Detected
- Check timing: intents are short-lived
- Query within active transaction
- Use bulk operations to create measurable intent count

### High Baseline Intent Count
- Other workloads may be running
- Check `SHOW CLUSTER SESSIONS` for active transactions
- Consider testing on isolated cluster

### DB Console Not Accessible
- Verify cluster is running
- Check http://localhost:8080 in browser
- Firewall or network restrictions?

## Advanced Testing

### Multi-Session Test (Optional)
Open two terminal windows:

**Session 1**:
```sql
BEGIN;
UPDATE orders SET status = 'processing' WHERE id <= 100;
-- Leave transaction open
```

**Session 2**:
```sql
-- Query intents from Session 1
SELECT txn_id, COUNT(*)
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY txn_id;
```

**Session 1**:
```sql
COMMIT;
```

**Session 2**:
```sql
-- Verify intents cleared
SELECT COUNT(*) FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';
```

## Success Criteria

Tests are successful if:
- ✅ All queries execute without errors
- ✅ Intents visible during active transactions
- ✅ Intents cleared after COMMIT
- ✅ Health assessment queries categorize correctly
- ✅ DB Console shows intent metrics
- ✅ No stuck/orphaned intents after tests

## Next Steps

After completing these tests:
1. Compare results with skill documentation
2. Validate monitoring thresholds (50K warning, 100K critical)
3. Test alert queries against observed metrics
4. Document any skill improvements needed
