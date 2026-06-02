-- Test 5: Monitor Intent Resolution Rate
-- Purpose: Measure intent creation and cleanup effectiveness

USE intent_test;

\echo '\n=== Test 5: Intent Resolution Rate Monitoring ===\n'

\echo '\n=== Baseline measurement ===\n'

SELECT
    COUNT(*) AS intent_count_t0,
    now() AS measurement_time
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

\echo '\n=== Create transient intents (quick transactions) ===\n'

-- Transaction 1
BEGIN;
UPDATE accounts SET balance = balance + 1 WHERE id = 1;
COMMIT;

-- Transaction 2
BEGIN;
UPDATE accounts SET balance = balance + 1 WHERE id = 2;
COMMIT;

-- Transaction 3
BEGIN;
UPDATE accounts SET balance = balance + 1 WHERE id = 3;
COMMIT;

\echo '\n=== Second measurement (after quick commits) ===\n'

SELECT
    COUNT(*) AS intent_count_t1,
    now() AS measurement_time
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

\echo '\n=== Expected: Low or zero intent count (rapid resolution) ===\n'

\echo '\n=== Create batch of intents ===\n'

BEGIN;

UPDATE orders SET total = total + 1 WHERE id <= 100;

\echo '\n=== Measurement during active transaction ===\n'

SELECT
    COUNT(*) AS intent_count_active,
    COUNT(DISTINCT txn_id) AS active_txn_count,
    MAX(duration) AS max_age,
    now() AS measurement_time
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

COMMIT;

\echo '\n=== Final measurement (post-commit) ===\n'

SELECT
    COUNT(*) AS intent_count_final,
    now() AS measurement_time
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

\echo '\n=== Analysis: Resolution Effectiveness ===\n'
\echo 'In production monitoring:\n'
\echo '1. Sample intent count at T=0\n'
\echo '2. Wait 60 seconds\n'
\echo '3. Sample intent count at T=60\n'
\echo '4. Calculate accumulation rate: (count_t60 - count_t0) / 60\n'
\echo '5. Alert if rate > threshold (e.g., 100 intents/second sustained)\n'
