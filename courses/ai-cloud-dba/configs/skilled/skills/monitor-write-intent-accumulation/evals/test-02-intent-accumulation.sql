-- Test 2: Simulate Intent Accumulation
-- Purpose: Create multiple intents and monitor accumulation patterns

USE intent_test;

\echo '\n=== Test 2: Intent Accumulation Monitoring ===\n'

-- Create additional test table for accumulation test
CREATE TABLE IF NOT EXISTS orders (
    id INT PRIMARY KEY,
    customer_id INT,
    total DECIMAL(10, 2),
    status TEXT,
    created_at TIMESTAMP DEFAULT now()
);

-- Insert test data
INSERT INTO orders (id, customer_id, total, status)
SELECT
    i,
    (i % 100) + 1,
    (random() * 1000)::DECIMAL(10, 2),
    'pending'
FROM generate_series(1, 1000) AS i;

\echo '\n=== Baseline: Check current intent count ===\n'

SELECT COUNT(*) AS baseline_intent_count
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

\echo '\n=== Creating bulk write intents ===\n'

BEGIN;

-- Update many rows to create multiple intents
UPDATE orders SET status = 'processing' WHERE id <= 100;

\echo '\n=== Query: Intent accumulation metrics ===\n'

SELECT
    COUNT(*) AS total_intents,
    COUNT(DISTINCT txn_id) AS unique_transactions,
    MAX(duration) AS max_intent_age,
    MIN(duration) AS min_intent_age
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

\echo '\n=== Query: Intents by table ===\n'

SELECT
    database_name,
    table_name,
    COUNT(*) AS intent_count,
    MAX(duration) AS oldest_intent
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY database_name, table_name
ORDER BY intent_count DESC;

\echo '\n=== Query: Transaction intent distribution ===\n'

SELECT
    txn_id,
    COUNT(*) AS intent_count,
    MAX(duration) AS max_duration
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent'
GROUP BY txn_id
ORDER BY intent_count DESC
LIMIT 5;

COMMIT;

\echo '\n=== After commit: Verify intent cleanup ===\n'

SELECT COUNT(*) AS remaining_intents
FROM crdb_internal.cluster_locks
WHERE lock_strength = 'Intent';

\echo '\n=== Expected: 0 or very low intent count ===\n'
