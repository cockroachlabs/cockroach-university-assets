-- Test 4: Correlate Intents with Active Sessions
-- Purpose: Demonstrate finding sessions responsible for write intents

USE intent_test;

\echo '\n=== Test 4: Correlating Intents with Sessions ===\n'

-- Create intents to correlate
BEGIN;

UPDATE accounts SET balance = balance + 50 WHERE id <= 2;
UPDATE orders SET status = 'shipped' WHERE id <= 25;

\echo '\n=== Query 1: Current session information ===\n'

SELECT
    session_id,
    user_name,
    client_address,
    application_name,
    active_queries,
    start AS session_start,
    age(now(), start) AS session_age
FROM [SHOW CLUSTER SESSIONS]
WHERE application_name = '$ cockroach sql';

\echo '\n=== Query 2: Intents in current transaction ===\n'

SELECT
    database_name,
    table_name,
    COUNT(*) AS intent_count,
    MAX(duration) AS max_age
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY database_name, table_name
ORDER BY intent_count DESC;

\echo '\n=== Query 3: Transaction statistics ===\n'

-- This query would show transaction details if multiple sessions were active
SELECT
    application_name,
    COUNT(DISTINCT session_id) AS session_count,
    SUM(COALESCE(num_txns_executed, 0)) AS total_txns
FROM [SHOW CLUSTER SESSIONS]
GROUP BY application_name;

\echo '\n=== Note: In production, you would join sessions with intents via txn_id ===\n'
\echo 'Example query from skill:\n'
\echo 'SELECT session_id, txn_id, application_name, active_queries\n'
\echo 'FROM [SHOW CLUSTER SESSIONS]\n'
\echo 'WHERE txn_id IN (\n'
\echo '  SELECT DISTINCT txn_id FROM crdb_internal.cluster_locks\n'
\echo '  WHERE lock_strength = Intent AND duration > 30s\n'
\echo ')\n'

COMMIT;

\echo '\n=== Transaction committed ===\n'
