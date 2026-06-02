# Monitor Write Intent Accumulation - Evaluation Test Suite

## Overview

This directory contains comprehensive evaluation tests for the **monitor-write-intent-accumulation** skill. These tests validate monitoring techniques, queries, and diagnostic procedures against a live CockroachDB v26.1+ cluster.

## Quick Start

```bash
# Verify cluster is running
/Users/nathanzamecnik/bin/cockroach node status \
  --host=localhost:26258 \
  --certs-dir=/Users/nathanzamecnik/certs

# Run all tests (quick mode)
cd /Users/nathanzamecnik/.claude/skills/monitor-write-intent-accumulation/evals
./quick-test.sh

# Or run interactive mode with pauses
./run-all-tests.sh
```

## Test Suite Contents

### SQL Test Files

| File | Purpose | Validates |
|------|---------|-----------|
| `test-01-query-cluster-locks.sql` | Basic monitoring queries | crdb_internal.cluster_locks access, grouping, health checks |
| `test-02-intent-accumulation.sql` | Bulk intent creation | Accumulation patterns, cleanup verification |
| `test-03-long-running-transaction.sql` | Long txn detection | Intent age tracking, health assessment |
| `test-04-session-intent-correlation.sql` | Session → intent mapping | SHOW CLUSTER SESSIONS, txn_id correlation |
| `test-05-intent-resolution-rate.sql` | Resolution effectiveness | Creation vs cleanup rate, transient vs persistent |

### Supporting Files

- **`run-all-tests.sh`** - Interactive test runner with pauses
- **`quick-test.sh`** - Fast batch execution
- **`EXECUTE-TESTS.md`** - Detailed execution instructions
- **`TEST-RESULTS.md`** - Results documentation template
- **`README.md`** - This file

## Test Architecture

```
evals/
├── test-*.sql              # Monitoring test scenarios
├── run-all-tests.sh        # Full suite with interaction
├── quick-test.sh           # Quick batch run
├── EXECUTE-TESTS.md        # Execution guide
├── TEST-RESULTS.md         # Results template
└── README.md               # This file
```

## Key Monitoring Queries Tested

### 1. View All Active Intents
```sql
SELECT
    database_name,
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

### 2. Count Intents Per Table
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

### 3. Intent Health Assessment
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

### 4. Find Transactions Holding Intents
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

## Expected Test Outcomes

### Test 1: Query cluster_locks
- ✅ All queries execute successfully
- ✅ Intents visible during active transaction
- ✅ Health status categorization works
- ✅ Grouping and aggregation correct

### Test 2: Intent Accumulation
- ✅ Baseline: 0 or low intent count
- ✅ During bulk update: 100+ intents visible
- ✅ After commit: Return to baseline
- ✅ Metrics captured (total, max age, avg age)

### Test 3: Long-Running Transaction
- ✅ Intent age tracking functional
- ✅ Health assessment thresholds work
- ✅ Multiple tables tracked
- ✅ Transaction grouping correct

### Test 4: Session Correlation
- ✅ SHOW CLUSTER SESSIONS works
- ✅ Session metadata captured
- ✅ Example correlation query provided
- ✅ Application name visible

### Test 5: Intent Resolution Rate
- ✅ Quick commits resolve immediately
- ✅ Batch operations create measurable intents
- ✅ Cleanup verification successful
- ✅ Timing measurements feasible

## Threshold Validation

The skill defines these thresholds - tests should validate:

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| **Intent Count** | 0-10K | 10K-50K | >100K |
| **Intent Age P95** | <1s | 1-10s | >10s |
| **Intent Bytes %** | <1% | 1-5% | >5% |

**Validation Method**: Run tests and compare observed metrics to thresholds.

## DB Console Integration

### Before Running Tests

1. Open DB Console: http://localhost:8080
2. Navigate to: Metrics → Storage
3. Note baseline metrics:
   - Write Intents chart value
   - Write Intent Bytes value

### During Test Execution

4. Watch for intent spikes during bulk operations
5. Observe return to baseline after commits
6. Capture screenshots for documentation

### After Tests

7. Verify all metrics returned to baseline
8. Check for any anomalies or stuck intents

## Test Execution Workflow

### Step 1: Pre-Test Verification (5 min)
```bash
# Check cluster status
/Users/nathanzamecnik/bin/cockroach node status \
  --host=localhost:26258 \
  --certs-dir=/Users/nathanzamecnik/certs

# Verify DB Console accessible
open http://localhost:8080

# Check baseline intent count
/Users/nathanzamecnik/bin/cockroach sql \
  --host=localhost:26258 \
  --certs-dir=/Users/nathanzamecnik/certs \
  -e "SELECT COUNT(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';"
```

### Step 2: Run Tests (20 min)
```bash
cd /Users/nathanzamecnik/.claude/skills/monitor-write-intent-accumulation/evals
./run-all-tests.sh
```

### Step 3: Verify Cleanup (5 min)
```sql
-- Check for lingering intents
SELECT COUNT(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';

-- Check test databases
SHOW DATABASES;

-- Clean up if needed
DROP DATABASE intent_test CASCADE;
```

## Common Monitoring Scenarios

### Scenario 1: Detect Steadily Growing Intents

**Simulated by**: test-02 (bulk update without commit)

**Detection Query**:
```sql
-- Measure at T0
SELECT COUNT(*) AS intents_t0 FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';

-- Wait 60 seconds

-- Measure at T60
SELECT COUNT(*) AS intents_t60 FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';

-- Calculate accumulation rate
-- If (intents_t60 - intents_t0) > 0 → Problem
```

### Scenario 2: Find Long-Running Transactions

**Simulated by**: test-03

**Detection Query**:
```sql
SELECT
    session_id,
    active_queries,
    age(now(), start) AS duration
FROM [SHOW CLUSTER SESSIONS]
WHERE start < now() - INTERVAL '5 minutes'
ORDER BY start;
```

### Scenario 3: Identify Hot Tables

**Simulated by**: test-02 (multiple tables)

**Detection Query**:
```sql
SELECT
    table_name,
    COUNT(*) AS intent_count
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY table_name
ORDER BY intent_count DESC
LIMIT 10;
```

## Troubleshooting

### Issue: No Intents Visible During Tests

**Possible Causes**:
- Intents resolving too quickly (good!)
- Query timing issues
- Transaction not active

**Debug Steps**:
```sql
-- Check if transaction is active
BEGIN;
UPDATE accounts SET balance = 999;

-- Immediately query (in same session)
SELECT COUNT(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';

-- Should show > 0
COMMIT;
```

### Issue: Stuck Intents After Tests

**Possible Causes**:
- Uncommitted transaction
- Crashed connection
- Test didn't complete

**Fix**:
```sql
-- Find sessions with open transactions
SELECT session_id, active_queries
FROM [SHOW CLUSTER SESSIONS]
WHERE active_queries != '';

-- Cancel problematic session
CANCEL SESSION 'session_id_here';

-- Force cleanup
DROP DATABASE intent_test CASCADE;
```

### Issue: Permission Denied on crdb_internal

**Fix**:
```sql
-- Grant necessary permissions
GRANT SELECT ON crdb_internal.cluster_locks TO your_user;
```

## Performance Considerations

### Query Overhead

Monitoring queries impact:
- **Minimal** for intent counts (<10ms typical)
- **Low** for grouped queries (<50ms)
- **Moderate** for complex CTEs (<200ms)

**Recommended Polling**:
- Production: Every 30-60 seconds
- Testing: Every 5-10 seconds
- Emergency: Every 1-2 seconds (brief)

### Test Impact on Cluster

These tests create:
- ~1000 rows in test tables
- ~100-200 temporary intents during bulk operations
- Negligible long-term storage impact
- No impact on production data (separate database)

## Validation Checklist

After running tests, verify:

- [ ] All queries executed successfully
- [ ] Intent counts matched expectations
- [ ] Health assessment thresholds work correctly
- [ ] Session correlation possible
- [ ] DB Console metrics visible
- [ ] Cleanup successful (0 lingering intents)
- [ ] Skill content matches observed behavior
- [ ] TEST-RESULTS.md filled out

## Documentation

Required documentation after test execution:

1. **Fill out TEST-RESULTS.md**:
   - Test outcomes (PASS/FAIL)
   - Sample query outputs
   - DB Console screenshots
   - Observations and findings

2. **Note any discrepancies**:
   - Skill claims not validated
   - Unexpected behaviors
   - Threshold accuracy

3. **Capture screenshots**:
   - DB Console Storage dashboard
   - Intent count graphs
   - Session listings

## Related Skills

These tests support:
- `understand-write-intents-and-mvcc` - Foundation concepts
- `diagnose-write-intent-buildup-issues` - Advanced troubleshooting
- `identify-long-running-transactions` - Session analysis
- `use-db-console-sql-activity-page` - UI-based monitoring

## Advanced Testing (Optional)

### Simulate Critical Alert (>100K intents)

**Warning**: Only attempt on test cluster!

```sql
-- Create many intents (may impact cluster)
BEGIN;
UPDATE large_table SET status = 'processing'
WHERE id <= 150000;

-- Query health
SELECT COUNT(*) FROM crdb_internal.cluster_locks WHERE lock_strength = 'Intent';
-- Should exceed 100K → CRITICAL

ROLLBACK; -- Clean up immediately
```

### Multi-Session Correlation Test

**Terminal 1**:
```sql
BEGIN;
UPDATE accounts SET balance = 999 WHERE id = 1;
SELECT pg_backend_pid(); -- Note session ID
-- Keep open
```

**Terminal 2**:
```sql
SELECT
    s.session_id,
    s.application_name,
    i.txn_id,
    COUNT(*) AS intent_count
FROM [SHOW CLUSTER SESSIONS] s
JOIN crdb_internal.cluster_locks i ON true
WHERE i.lock_strength = 'Intent'
GROUP BY s.session_id, s.application_name, i.txn_id;
```

**Terminal 1**:
```sql
COMMIT;
```

## Success Criteria

Tests are successful if:
- ✅ All 5 test files execute without errors
- ✅ Monitoring queries return expected results
- ✅ Health thresholds categorize correctly
- ✅ Intent accumulation → cleanup cycle works
- ✅ DB Console metrics correlate with queries
- ✅ Skill content validated against reality
- ✅ No stuck intents or sessions after tests

## Next Steps

After completing these tests:

1. Run complementary tests for `understand-write-intents-and-mvcc`
2. Compare results between both skills
3. Document any skill improvements needed
4. Test alert configurations (if applicable)
5. Share findings with skill maintainers
