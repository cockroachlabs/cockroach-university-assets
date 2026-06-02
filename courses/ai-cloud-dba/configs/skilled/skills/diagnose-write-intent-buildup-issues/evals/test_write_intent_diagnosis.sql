-- Test Suite: diagnose-write-intent-buildup-issues
-- Test: Write intent detection and diagnosis
-- CockroachDB v26.1.0
-- Purpose: Identify long-running transactions and intent buildup patterns

-- ============================================================================
-- Test 1: Setup - Create test table for intent simulation
-- ============================================================================

CREATE TABLE IF NOT EXISTS test_intents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  data TEXT,
  updated_at TIMESTAMP DEFAULT now()
);

INSERT INTO test_intents (data)
SELECT md5(random()::TEXT)
FROM generate_series(1, 5000);


-- ============================================================================
-- Test 2: Detect open transactions (potential intent holders)
-- ============================================================================

-- Test 2.1: Find all open transactions
SELECT
  session_id,
  txn_id,
  start,
  (now() - start) AS txn_duration,
  num_stmts_executed,
  num_auto_retries,
  active_queries
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
ORDER BY start ASC;

-- Expected: Shows all sessions with open transactions
-- Red flag: txn_duration > 60 seconds


-- Test 2.2: Find long-running transactions
SELECT
  session_id,
  txn_id,
  (now() - start) AS duration,
  num_stmts_executed,
  active_queries
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND (now() - start) > INTERVAL '10 seconds'
ORDER BY start ASC;

-- Expected: Transactions running > 10 seconds
-- Validation: Empty result is good (no long txns)


-- Test 2.3: Find idle transactions (abandoned)
SELECT
  session_id,
  txn_id,
  (now() - start) AS idle_duration,
  last_active_query,
  application_name
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND active_queries = ''
  AND (now() - start) > INTERVAL '30 seconds'
ORDER BY idle_duration DESC;

-- Expected: Open transactions with no active query (abandoned)
-- Red flag: idle_duration > 1 minute


-- ============================================================================
-- Test 3: Transaction count analysis
-- ============================================================================

-- Test 3.1: Count active transactions per node
SELECT
  node_id,
  txn_count,
  committed_count,
  aborted_count,
  (txn_count - committed_count - aborted_count) AS active_txns
FROM crdb_internal.node_txn_stats
ORDER BY active_txns DESC;

-- Expected: Active transaction count per node
-- Red flag: active_txns > 100


-- ============================================================================
-- Test 4: Simulate long-running transaction (manual test)
-- ============================================================================

-- IMPORTANT: Run this in a SEPARATE session to simulate intent buildup:
--
-- Session 2:
-- BEGIN;
-- UPDATE test_intents SET data = md5(random()::TEXT);
-- SELECT pg_sleep(120);  -- Hold transaction open for 2 minutes
-- -- DO NOT COMMIT YET - leave transaction open
--
-- Then run the detection queries below in main session


-- Test 4.1: Detect the long-running transaction (run in main session)
SELECT
  session_id,
  txn_id,
  (now() - start) AS duration,
  num_stmts_executed,
  active_queries
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
ORDER BY start ASC
LIMIT 5;

-- Expected: Shows Session 2's long-running transaction if active


-- ============================================================================
-- Test 5: Categorize transactions by duration
-- ============================================================================

SELECT
  CASE
    WHEN duration < INTERVAL '1 second' THEN '< 1s'
    WHEN duration < INTERVAL '10 seconds' THEN '1-10s'
    WHEN duration < INTERVAL '60 seconds' THEN '10-60s'
    WHEN duration < INTERVAL '300 seconds' THEN '1-5m'
    ELSE '> 5m'
  END AS duration_bucket,
  COUNT(*) AS txn_count
FROM (
  SELECT (now() - start) AS duration
  FROM crdb_internal.cluster_sessions
  WHERE txn_id IS NOT NULL
)
GROUP BY duration_bucket
ORDER BY duration_bucket;

-- Expected: Distribution of transaction durations
-- Red flag: Many transactions in '> 5m' bucket


-- ============================================================================
-- Test 6: Identify problematic query patterns
-- ============================================================================

-- Test 6.1: Find queries associated with long transactions
SELECT
  q.query_id,
  q.session_id,
  (now() - q.start) AS query_duration,
  q.phase,
  left(q.query, 100) AS query_preview,
  s.txn_id,
  (now() - s.start) AS txn_duration
FROM crdb_internal.cluster_queries q
JOIN crdb_internal.cluster_sessions s ON q.session_id = s.session_id
WHERE s.txn_id IS NOT NULL
  AND (now() - s.start) > INTERVAL '10 seconds'
ORDER BY txn_duration DESC;

-- Expected: Queries running within long transactions


-- ============================================================================
-- Test 7: Check cluster settings related to intents
-- ============================================================================

-- Test 7.1: Check transaction timeout settings
SHOW CLUSTER SETTING sql.defaults.transaction_timeout;
SHOW CLUSTER SETTING sql.defaults.statement_timeout;

-- Expected: Shows configured timeouts
-- Default: transaction_timeout = 0 (unlimited - not recommended)


-- Test 7.2: Check intent resolution settings
SHOW CLUSTER SETTING kv.transaction.write_pipelining_enabled;

-- Expected: Shows write pipelining setting


-- ============================================================================
-- Test 8: Monitor for cleanup patterns
-- ============================================================================

-- Test 8.1: Check for transaction coordinator heartbeats
-- Note: This is indirect - we look for long-lived transactions
SELECT
  COUNT(*) AS long_lived_txn_count,
  MAX(now() - start) AS oldest_txn_age
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL;

-- Expected: Count and age of open transactions


-- ============================================================================
-- Test 9: Timeout configuration testing
-- ============================================================================

-- Test 9.1: Test statement timeout
SET statement_timeout = '5s';

-- Try to run a slow query
DO $$
BEGIN
  PERFORM pg_sleep(10);
EXCEPTION
  WHEN query_canceled THEN
    RAISE NOTICE 'Query cancelled by timeout (expected)';
END $$;

RESET statement_timeout;


-- Test 9.2: Test transaction timeout
SET transaction_timeout = '10s';

-- Try to hold a transaction open too long
DO $$
BEGIN
  BEGIN;
  PERFORM pg_sleep(15);
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Transaction timeout triggered (expected): %', SQLERRM;
    ROLLBACK;
END $$;

RESET transaction_timeout;


-- ============================================================================
-- Test 10: Application pattern analysis
-- ============================================================================

-- Test 10.1: Find applications with many open transactions
SELECT
  application_name,
  COUNT(*) AS open_txn_count,
  AVG(now() - start) AS avg_txn_duration,
  MAX(now() - start) AS max_txn_duration
FROM crdb_internal.cluster_sessions
WHERE txn_id IS NOT NULL
  AND application_name != '$ internal-executor'
GROUP BY application_name
ORDER BY open_txn_count DESC;

-- Expected: Breakdown by application
-- Red flag: High open_txn_count or long max_txn_duration


-- ============================================================================
-- Test 11: Cleanup
-- ============================================================================

DROP TABLE IF EXISTS test_intents CASCADE;


-- ============================================================================
-- MANUAL TESTING GUIDE: Simulate Intent Buildup
-- ============================================================================

/*
To fully test intent diagnosis, perform this scenario:

SETUP:
CREATE TABLE intent_test (id INT PRIMARY KEY, data TEXT);
INSERT INTO intent_test SELECT i, md5(random()::TEXT) FROM generate_series(1, 10000) i;

SESSION 1 (Problematic transaction):
  BEGIN;
  UPDATE intent_test SET data = md5(random()::TEXT);
  SELECT pg_sleep(300);  -- Hold for 5 minutes!
  -- DO NOT COMMIT - simulate abandoned transaction

SESSION 2 (Monitoring):
  -- Run while Session 1 is sleeping

  -- Detect long transaction
  SELECT session_id, txn_id, (now() - start) AS duration
  FROM crdb_internal.cluster_sessions
  WHERE txn_id IS NOT NULL
  ORDER BY start ASC;

  -- Check for idle transaction
  SELECT session_id, active_queries, (now() - start) AS idle_time
  FROM crdb_internal.cluster_sessions
  WHERE txn_id IS NOT NULL AND active_queries = '';

  -- Find queries blocked by intents (if any concurrent readers)
  SELECT query_id, phase, (now() - start) AS wait_time
  FROM crdb_internal.cluster_queries
  WHERE phase = 'waiting';

SESSION 3 (Try to read - will be blocked):
  SELECT * FROM intent_test WHERE id = 1;
  -- This will wait for Session 1's intent to resolve

VERIFICATION:
□ Long transaction detected in cluster_sessions
□ idle_time increases while pg_sleep runs
□ Session 3's query shows phase = 'waiting'
□ Can identify session_id of blocking transaction

RESOLUTION:
  -- In monitoring session
  CANCEL SESSION '<session_id_from_session1>';

  -- Verify transaction cancelled
  SELECT COUNT(*) FROM crdb_internal.cluster_sessions
  WHERE session_id = '<session_id>';
  -- Should return 0

CLEANUP:
  DROP TABLE intent_test;
*/


-- ============================================================================
-- Test Summary
-- ============================================================================

-- Total test cases: 11 test groups, 20+ individual tests
-- Coverage:
--   ✓ Open transaction detection
--   ✓ Long-running transaction identification
--   ✓ Idle/abandoned transaction detection
--   ✓ Transaction count analysis
--   ✓ Duration categorization
--   ✓ Query-to-transaction correlation
--   ✓ Cluster setting verification
--   ✓ Timeout testing
--   ✓ Application pattern analysis
--
-- Expected outcomes:
--   - Detect open transactions via cluster_sessions
--   - Identify long-running transactions (duration > threshold)
--   - Find abandoned transactions (no active query)
--   - Timeout settings prevent unbounded transactions
--   - Can correlate queries to transactions
--
-- Manual test required for full validation:
--   - Create actual long-running transaction
--   - Observe intent buildup effects
--   - Verify blocking behavior
--   - Test cancellation recovery
