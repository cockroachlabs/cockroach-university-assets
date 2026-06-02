-- Eval Test 3: Baseline and Deviation Monitoring
-- Skill: monitor-transaction-contention-metrics
-- Purpose: Establish baselines and detect deviations

\echo "=== Test 3: Baseline and Deviation Monitoring ==="
\echo ""

USE contention_test;

-- Step 1: Establish baseline (simulate historical data)
\echo "Step 1: Establishing baseline contention metrics..."

CREATE TEMPORARY TABLE IF NOT EXISTS baseline_metrics AS
SELECT
    table_name,
    AVG(contention_duration) AS baseline_avg_duration,
    MAX(contention_duration) AS baseline_max_duration,
    COUNT(*) AS baseline_event_count
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
    AND table_name IS NOT NULL
GROUP BY table_name;

\echo "Baseline captured:"
SELECT
    table_name,
    baseline_avg_duration / 1000000 AS baseline_avg_ms,
    baseline_max_duration / 1000000 AS baseline_max_ms,
    baseline_event_count
FROM baseline_metrics
ORDER BY baseline_avg_ms DESC;

\echo ""
\echo "Step 2: Generate new contention (simulate increased load)..."

-- Simulate increased contention
UPDATE inventory SET quantity = quantity - 1
WHERE product_id = '11111111-1111-1111-1111-111111111111';

UPDATE metrics SET value = value + 1 WHERE metric_name = 'page_views';
UPDATE metrics SET value = value + 1 WHERE metric_name = 'active_users';

\echo "✓ Additional load generated"
\echo ""

-- Step 3: Compare current to baseline
\echo "Step 3: Detecting deviations from baseline..."

WITH current_metrics AS (
    SELECT
        table_name,
        AVG(contention_duration) AS current_avg_duration,
        MAX(contention_duration) AS current_max_duration,
        COUNT(*) AS current_event_count
    FROM crdb_internal.cluster_contention_events
    WHERE collection_ts > now() - INTERVAL '5 minutes'
        AND table_name IS NOT NULL
    GROUP BY table_name
)
SELECT
    c.table_name,
    b.baseline_avg_duration / 1000000 AS baseline_avg_ms,
    c.current_avg_duration / 1000000 AS current_avg_ms,
    ROUND(((c.current_avg_duration - b.baseline_avg_duration) /
           NULLIF(b.baseline_avg_duration, 0)) * 100, 2) AS pct_change,
    CASE
        WHEN c.current_avg_duration > b.baseline_avg_duration * 2 THEN '🔴 ALERT: 2x increase'
        WHEN c.current_avg_duration > b.baseline_avg_duration * 1.5 THEN '🟡 WARNING: 50% increase'
        WHEN c.current_avg_duration < b.baseline_avg_duration * 0.5 THEN '🟢 IMPROVED: 50% decrease'
        ELSE '✓ Normal variance'
    END AS status
FROM current_metrics c
LEFT JOIN baseline_metrics b ON c.table_name = b.table_name
WHERE b.baseline_avg_duration IS NOT NULL
ORDER BY pct_change DESC NULLS LAST;

\echo ""
\echo "Alert thresholds:"
\echo "  🔴 ALERT: >100% increase (2x baseline)"
\echo "  🟡 WARNING: >50% increase from baseline"
\echo "  ✓ Normal: Within 50% of baseline"
\echo "  🟢 IMPROVED: >50% decrease from baseline"
\echo ""

-- Step 4: Time-series comparison
\echo "Step 4: Contention trend analysis (last hour):"

SELECT
    date_trunc('minute', collection_ts) AS minute,
    COUNT(*) AS events_per_minute,
    AVG(contention_duration) / 1000000 AS avg_contention_ms,
    MAX(contention_duration) / 1000000 AS max_contention_ms
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
GROUP BY minute
ORDER BY minute DESC
LIMIT 15;

\echo ""
\echo "Look for patterns:"
\echo "  - Sudden spikes in events_per_minute"
\echo "  - Increasing avg_contention_ms trend"
\echo "  - High max_contention_ms values"
\echo ""

\echo "=== Monitoring Workflow Summary ==="
\echo "1. Establish baseline during normal operations"
\echo "2. Continuously monitor current metrics"
\echo "3. Compare current to baseline (detect >50% increase)"
\echo "4. Alert on anomalies (>2x baseline = critical)"
\echo "5. Track trends over time for proactive optimization"
\echo ""
\echo "✓ Test 3 completed"
