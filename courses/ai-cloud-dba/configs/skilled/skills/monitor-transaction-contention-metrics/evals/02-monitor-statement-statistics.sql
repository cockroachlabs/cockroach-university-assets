-- Eval Test 2: Monitor Statement Statistics with Contention Time
-- Skill: monitor-transaction-contention-metrics
-- Purpose: Query crdb_internal.statement_statistics for contention metrics

\echo "=== Test 2: Statement Statistics Contention Monitoring ==="
\echo ""

USE contention_test;

-- Generate some statements with measurable contention
\echo "Executing statements to generate statistics..."

UPDATE inventory SET quantity = quantity - 1
WHERE product_id = '11111111-1111-1111-1111-111111111111';

UPDATE inventory SET quantity = quantity - 1
WHERE product_id = '22222222-2222-2222-2222-222222222222';

UPDATE metrics SET value = value + 1 WHERE metric_name = 'page_views';

\echo "✓ Statements executed"
\echo ""

-- Query 1: Statements with highest contention
\echo "1. Statements with contention time:"
SELECT
    metadata ->> 'query' AS query,
    metadata ->> 'db' AS database,
    (statistics -> 'statistics' -> 'cnt')::INT AS execution_count,
    ROUND((statistics -> 'statistics' -> 'runLat' -> 'mean')::FLOAT * 1000, 2) AS avg_runtime_ms,
    ROUND((statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT * 1000, 2) AS avg_contention_ms,
    ROUND(
        ((statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT /
         NULLIF((statistics -> 'statistics' -> 'runLat' -> 'mean')::FLOAT, 0)) * 100,
        2
    ) AS contention_pct
FROM crdb_internal.statement_statistics
WHERE (statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT > 0
    AND metadata ->> 'db' = 'contention_test'
ORDER BY avg_contention_ms DESC
LIMIT 20;

\echo ""
\echo "Expected columns:"
\echo "  - query: The SQL statement"
\echo "  - execution_count: How many times executed"
\echo "  - avg_runtime_ms: Average total execution time"
\echo "  - avg_contention_ms: Average time spent waiting for locks"
\echo "  - contention_pct: Percentage of time spent contending"
\echo ""
\echo "Warning threshold: contention_pct > 10% indicates optimization needed"
\echo "Critical threshold: contention_pct > 25% requires immediate action"
\echo ""

-- Query 2: Simplified aggregate view
\echo "2. Aggregate contention by application:"
SELECT
    aggregated_ts,
    app_name,
    COUNT(*) AS statement_types,
    ROUND(AVG((statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT) * 1000, 2) AS avg_contention_ms
FROM crdb_internal.statement_statistics
WHERE app_name NOT LIKE '$ internal%'
    AND (statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT > 0
GROUP BY aggregated_ts, app_name
ORDER BY avg_contention_ms DESC
LIMIT 10;

\echo ""
\echo "Expected: Contention aggregated by application name"
\echo ""

-- Query 3: Compare contention to total runtime
\echo "3. Statements ranked by contention percentage:"
SELECT
    metadata ->> 'query' AS query,
    (statistics -> 'statistics' -> 'cnt')::INT AS executions,
    ROUND(((statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT /
           NULLIF((statistics -> 'statistics' -> 'runLat' -> 'mean')::FLOAT, 0)) * 100, 2) AS contention_pct,
    CASE
        WHEN ((statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT /
              NULLIF((statistics -> 'statistics' -> 'runLat' -> 'mean')::FLOAT, 0)) > 0.25 THEN '🔴 CRITICAL'
        WHEN ((statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT /
              NULLIF((statistics -> 'statistics' -> 'runLat' -> 'mean')::FLOAT, 0)) > 0.10 THEN '🟡 WARNING'
        ELSE '🟢 OK'
    END AS status
FROM crdb_internal.statement_statistics
WHERE (statistics -> 'statistics' -> 'contentionTime' -> 'mean')::FLOAT > 0
    AND metadata ->> 'db' = 'contention_test'
ORDER BY contention_pct DESC
LIMIT 15;

\echo ""
\echo "Status indicators:"
\echo "  🟢 OK: <10% contention (acceptable)"
\echo "  🟡 WARNING: 10-25% contention (investigate)"
\echo "  🔴 CRITICAL: >25% contention (optimize immediately)"
\echo ""

\echo "=== Statement Statistics Monitoring ==="
\echo "✓ Statement stats provide per-query contention metrics"
\echo "✓ Use contention_pct to prioritize optimizations"
\echo "✓ Compare contention time to total runtime"
\echo "✓ Monitor trends over aggregated_ts windows"
\echo ""
\echo "✓ Test 2 completed"
