-- Test 3: Monitor Long-Running Transaction Intents
-- Purpose: Demonstrate detection of long-running transactions via intent age

USE intent_test;

\echo '\n=== Test 3: Detecting Long-Running Transactions ===\n'

-- Create a long-running transaction (simulated)
BEGIN;

UPDATE accounts SET balance = balance + 100 WHERE id = 1;
UPDATE orders SET total = total * 1.1 WHERE id <= 50;

\echo '\n=== Query: Find long-running transaction intents ===\n'

SELECT
    database_name,
    schema_name,
    table_name,
    txn_id,
    COUNT(*) AS intent_count,
    MAX(duration) AS max_age,
    MIN(duration) AS min_age,
    AVG(duration) AS avg_age
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY database_name, schema_name, table_name, txn_id
ORDER BY max_age DESC;

\echo '\n=== Query: Intent health assessment ===\n'

WITH intent_stats AS (
    SELECT
        COUNT(*) AS total_intents,
        MAX(duration) AS max_age,
        AVG(duration) AS avg_age,
        COUNT(DISTINCT txn_id) AS active_transactions
    FROM crdb_internal.cluster_locks
    WHERE lock_strength = 'Intent'
)
SELECT
    total_intents,
    max_age,
    avg_age,
    active_transactions,
    CASE
        WHEN total_intents > 100000 THEN 'CRITICAL'
        WHEN total_intents > 50000 THEN 'WARNING'
        WHEN max_age > INTERVAL '10 seconds' THEN 'WARNING'
        ELSE 'OK'
    END AS health_status
FROM intent_stats;

\echo '\n=== Simulating wait (in real scenario, would check again after delay) ===\n'

-- In a real monitoring scenario, you would:
-- 1. Note the intent count at T0
-- 2. Wait 60 seconds
-- 3. Note the intent count at T60
-- 4. Calculate accumulation rate: (count_T60 - count_T0) / 60

SELECT
    COUNT(*) AS current_intent_count,
    now() AS sample_time
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

COMMIT;

\echo '\n=== Transaction committed ===\n'

SELECT COUNT(*) AS final_intent_count
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';
