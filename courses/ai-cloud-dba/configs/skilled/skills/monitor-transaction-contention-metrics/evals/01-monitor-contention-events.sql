-- Eval Test 1: Monitor Transaction Contention Events
-- Skill: monitor-transaction-contention-metrics
-- Purpose: Demonstrate querying crdb_internal.cluster_contention_events

\echo "=== Test 1: Monitor Contention Events ==="
\echo ""

USE contention_test;

-- Generate some contention
\echo "Generating contention events..."

-- Update popular item to create contention
BEGIN;
UPDATE inventory SET quantity = quantity - 1
WHERE product_id = '11111111-1111-1111-1111-111111111111';
SELECT pg_sleep(0.5);
COMMIT;

BEGIN;
UPDATE inventory SET quantity = quantity - 1
WHERE product_id = '11111111-1111-1111-1111-111111111111';
SELECT pg_sleep(0.5);
COMMIT;

\echo "✓ Contention generated"
\echo ""

-- Query 1: Recent contention events with duration
\echo "1. Recent contention events (last 20):"
SELECT
    collection_ts,
    contention_duration / 1000000 AS contention_ms,
    blocking_txn_id,
    waiting_txn_id,
    database_name,
    schema_name,
    table_name,
    index_name,
    num_contention_events
FROM crdb_internal.cluster_contention_events
ORDER BY contention_duration DESC
LIMIT 20;

\echo ""
\echo "Expected: Should see events with:"
\echo "  - database_name: contention_test"
\echo "  - table_name: various tables from tests"
\echo "  - contention_ms: milliseconds of blocking time"
\echo "  - num_contention_events: count of conflicts"
\echo ""

-- Query 2: Hot table analysis
\echo "2. Hot tables by cumulative contention:"
SELECT
    table_name,
    COUNT(*) AS contention_events,
    SUM(contention_duration) / 1000000 AS total_contention_ms,
    AVG(contention_duration) / 1000000 AS avg_contention_ms,
    MAX(contention_duration) / 1000000 AS max_contention_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
    AND table_name IS NOT NULL
GROUP BY table_name
ORDER BY total_contention_ms DESC
LIMIT 10;

\echo ""
\echo "Expected: Ranked list of tables by total contention time"
\echo "  - inventory and metrics tables should show up (from our tests)"
\echo "  - total_contention_ms shows cumulative blocking time"
\echo ""

-- Query 3: Specific key contention
\echo "3. Contention by specific keys:"
SELECT
    table_name,
    index_name,
    key,
    num_contention_events,
    contention_duration / 1000000 AS contention_ms
FROM crdb_internal.cluster_contention_events
WHERE table_name = 'inventory'
ORDER BY contention_duration DESC
LIMIT 20;

\echo ""
\echo "Expected: Shows which exact keys (rows) are causing contention"
\echo "  - Hot key (popular-item) should show high contention"
\echo ""

-- Query 4: Transaction fingerprint analysis
\echo "4. Transaction fingerprint conflicts:"
SELECT
    blocking_txn_fingerprint_id,
    waiting_txn_fingerprint_id,
    table_name,
    COUNT(*) AS conflict_count,
    SUM(contention_duration) / 1000000 AS total_wait_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '30 minutes'
    AND blocking_txn_fingerprint_id IS NOT NULL
GROUP BY blocking_txn_fingerprint_id, waiting_txn_fingerprint_id, table_name
ORDER BY total_wait_ms DESC
LIMIT 15;

\echo ""
\echo "Expected: Shows which transaction patterns conflict with each other"
\echo ""

-- Query 5: Time-series analysis
\echo "5. Contention trends over time:"
SELECT
    date_trunc('minute', collection_ts) AS minute,
    COUNT(*) AS events,
    SUM(contention_duration) / 1000000 AS total_contention_ms,
    AVG(contention_duration) / 1000000 AS avg_contention_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
GROUP BY minute
ORDER BY minute DESC
LIMIT 20;

\echo ""
\echo "Expected: Time-series view showing when contention occurred"
\echo "  - Should see spikes when we ran concurrent tests"
\echo ""

\echo "=== Monitoring Best Practices ==="
\echo "✓ Use crdb_internal.cluster_contention_events for detailed analysis"
\echo "✓ Look for tables with >10% contention time"
\echo "✓ Identify hot keys using key column"
\echo "✓ Track trends over time to spot regressions"
\echo "✓ Set up alerts for contention >50ms average"
\echo ""
\echo "✓ Test 1 completed"
