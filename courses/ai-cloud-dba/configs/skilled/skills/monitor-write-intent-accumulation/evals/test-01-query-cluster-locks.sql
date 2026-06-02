-- Test 1: Query crdb_internal.cluster_locks for Intent Monitoring
-- Purpose: Demonstrate monitoring queries from the skill

USE intent_test;

\echo '\n=== Test 1: Monitoring Write Intents via crdb_internal.cluster_locks ===\n'

-- Create a scenario with multiple intents
BEGIN;

UPDATE accounts SET balance = balance + 10 WHERE id = 1;
UPDATE accounts SET balance = balance + 20 WHERE id = 2;
UPDATE accounts SET balance = balance + 30 WHERE id = 3;

\echo '\n=== Query 1: View all current locks (includes write intents) ===\n'

SELECT
    database_name,
    schema_name,
    table_name,
    lock_key_pretty,
    txn_id,
    duration,
    granted,
    lock_strength
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
ORDER BY duration DESC
LIMIT 20;

\echo '\n=== Query 2: Count intents per table ===\n'

SELECT
    table_name,
    COUNT(*) AS intent_count,
    MAX(duration) AS max_intent_age
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY table_name
ORDER BY intent_count DESC
LIMIT 10;

\echo '\n=== Query 3: Intent duration analysis ===\n'

SELECT
    table_name,
    lock_key_pretty,
    duration,
    CASE
        WHEN duration < INTERVAL '1 second' THEN 'HEALTHY (<1s)'
        WHEN duration < INTERVAL '5 seconds' THEN 'NORMAL (1-5s)'
        WHEN duration < INTERVAL '10 seconds' THEN 'WARNING (5-10s)'
        ELSE 'CRITICAL (>10s)'
    END AS health_status
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
ORDER BY duration DESC;

COMMIT;

\echo '\n=== Transaction committed - intents resolved ===\n'

-- Verify cleanup
SELECT COUNT(*) AS remaining_intents
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
  AND table_name = 'accounts';
