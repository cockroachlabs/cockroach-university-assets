-- Test Suite: Monitor Transaction Contention Metrics
-- Skill: monitor-transaction-contention-metrics
-- Level: Apply (test contention monitoring)
-- CockroachDB Version: v26.1.0

-- =============================================================================
-- TEST 1: Setup Test Environment with Contention
-- =============================================================================

DROP TABLE IF EXISTS monitoring_test CASCADE;
CREATE TABLE monitoring_test (
    id INT PRIMARY KEY,
    counter INT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Insert test data
INSERT INTO monitoring_test
SELECT generate_series(1, 1000), 0, now();

-- Create index to monitor index contention
CREATE INDEX idx_counter ON monitoring_test(counter);

-- =============================================================================
-- TEST 2: Monitor Transaction Contention Events
-- =============================================================================

-- Test Case 2A: Query recent contention events
SELECT
    collection_ts,
    blocking_txn_id,
    blocking_txn_fingerprint_id,
    waiting_txn_id,
    waiting_txn_fingerprint_id,
    contention_duration,
    contention_type,
    database_name,
    schema_name,
    table_name,
    index_name,
    key
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
ORDER BY contention_duration DESC
LIMIT 20;

-- Expected: List of recent contention events with durations

-- Test Case 2B: Aggregate contention by table
SELECT
    database_name,
    schema_name,
    table_name,
    count(*) as contention_count,
    sum(contention_duration) as total_duration_ns,
    avg(contention_duration) as avg_duration_ns,
    max(contention_duration) as max_duration_ns,
    sum(contention_duration) / 1000000000.0 as total_duration_seconds
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
GROUP BY database_name, schema_name, table_name
ORDER BY total_duration_ns DESC;

-- Expected: Tables ranked by total contention time

-- =============================================================================
-- TEST 3: Monitor Cluster-Wide Contention Events
-- =============================================================================

-- Test Case 3A: Cluster contention events
SELECT
    collection_ts,
    blocking_txn_id,
    blocking_txn_fingerprint_id,
    waiting_txn_id,
    waiting_txn_fingerprint_id,
    contention_duration,
    database_name,
    schema_name,
    table_name,
    index_name
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
ORDER BY contention_duration DESC
LIMIT 20;

-- Expected: Cluster-wide contention events

-- Test Case 3B: Contention by index
SELECT
    database_name,
    schema_name,
    table_name,
    index_name,
    count(*) as contention_count,
    sum(contention_duration) / 1000000000.0 as total_seconds,
    avg(contention_duration) / 1000000.0 as avg_milliseconds
FROM crdb_internal.cluster_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
    AND index_name IS NOT NULL
GROUP BY database_name, schema_name, table_name, index_name
ORDER BY total_seconds DESC;

-- Expected: Indexes with most contention

-- =============================================================================
-- TEST 4: Generate Contention for Monitoring
-- =============================================================================

-- Generate some contention to monitor
-- Run these in parallel sessions to create contention:

-- Session 1:
BEGIN;
UPDATE monitoring_test SET counter = counter + 1 WHERE id BETWEEN 1 AND 100;
SELECT pg_sleep(2);
COMMIT;

-- Session 2 (run while Session 1 is sleeping):
-- BEGIN;
-- UPDATE monitoring_test SET counter = counter + 1 WHERE id BETWEEN 50 AND 150;
-- COMMIT;

-- Wait for metrics to be collected (15 second interval)
SELECT pg_sleep(20);

-- =============================================================================
-- TEST 5: Query Statement Statistics for Contention
-- =============================================================================

-- Test Case 5A: Statements with highest contention time
SELECT
    metadata ->> 'query' as query_text,
    metadata ->> 'db' as database,
    statistics -> 'statistics' ->> 'cnt' as execution_count,
    (statistics -> 'statistics' -> 'contentionTime' ->> 'mean')::FLOAT as avg_contention_seconds,
    (statistics -> 'statistics' -> 'contentionTime' ->> 'sqDiff')::FLOAT as contention_variance,
    statistics -> 'statistics' ->> 'maxRetries' as max_retries
FROM crdb_internal.statement_statistics
WHERE (statistics -> 'statistics' -> 'contentionTime' ->> 'mean')::FLOAT > 0
ORDER BY avg_contention_seconds DESC
LIMIT 20;

-- Expected: Queries ranked by average contention time

-- Test Case 5B: Statements with retry errors due to contention
SELECT
    metadata ->> 'query' as query_text,
    statistics -> 'statistics' ->> 'cnt' as execution_count,
    (statistics -> 'statistics' -> 'numRows' ->> 'mean')::FLOAT as avg_rows,
    statistics -> 'statistics' ->> 'maxRetries' as max_retries,
    (statistics -> 'statistics' -> 'contentionTime' ->> 'mean')::FLOAT as avg_contention_seconds
FROM crdb_internal.statement_statistics
WHERE (statistics -> 'statistics' ->> 'maxRetries')::INT > 0
ORDER BY max_retries DESC
LIMIT 20;

-- Expected: Statements that experienced retries

-- =============================================================================
-- TEST 6: Monitor Transaction Statistics
-- =============================================================================

-- Test Case 6A: Transaction-level contention metrics
SELECT
    metadata ->> 'query' as transaction_fingerprint,
    statistics -> 'statistics' ->> 'cnt' as execution_count,
    (statistics -> 'statistics' -> 'contentionTime' ->> 'mean')::FLOAT as avg_contention_seconds,
    (statistics -> 'statistics' -> 'maxRetries')::INT as max_retries,
    (statistics -> 'statistics' -> 'commitLat' ->> 'mean')::FLOAT as avg_commit_latency
FROM crdb_internal.transaction_statistics
WHERE (statistics -> 'statistics' -> 'contentionTime' ->> 'mean')::FLOAT > 0
ORDER BY avg_contention_seconds DESC
LIMIT 20;

-- Expected: Transactions with contention issues

-- =============================================================================
-- TEST 7: Real-time Contention Monitoring
-- =============================================================================

-- Test Case 7A: Active transactions and their locks
SELECT
    txn_id,
    node_id,
    session_id,
    start,
    num_statements_executed,
    num_retries,
    num_auto_retries
FROM crdb_internal.node_transactions
WHERE num_retries > 0 OR num_auto_retries > 0;

-- Expected: Transactions that have experienced retries

-- Test Case 7B: Currently running statements
SELECT
    query_id,
    txn_id,
    node_id,
    session_id,
    start,
    query,
    phase
FROM crdb_internal.node_queries
WHERE phase != 'preparing';

-- Expected: Active queries in execution

-- =============================================================================
-- TEST 8: Contention Rate Calculation
-- =============================================================================

-- Test Case 8A: Calculate contention rate per table
WITH contention_metrics AS (
    SELECT
        table_name,
        count(*) as contention_events,
        sum(contention_duration) / 1000000000.0 as total_contention_seconds,
        min(collection_ts) as first_event,
        max(collection_ts) as last_event,
        EXTRACT(EPOCH FROM (max(collection_ts) - min(collection_ts))) as time_window_seconds
    FROM crdb_internal.transaction_contention_events
    WHERE collection_ts > now() - INTERVAL '1 hour'
        AND table_name IS NOT NULL
    GROUP BY table_name
)
SELECT
    table_name,
    contention_events,
    total_contention_seconds,
    CASE
        WHEN time_window_seconds > 0
        THEN contention_events / time_window_seconds
        ELSE 0
    END as contention_events_per_second,
    CASE
        WHEN time_window_seconds > 0
        THEN total_contention_seconds / time_window_seconds * 100
        ELSE 0
    END as contention_time_percentage
FROM contention_metrics
ORDER BY total_contention_seconds DESC;

-- Expected: Contention rate metrics per table

-- =============================================================================
-- TEST 9: Identify High-Contention Keys
-- =============================================================================

-- Test Case 9A: Most contended keys
SELECT
    database_name,
    schema_name,
    table_name,
    index_name,
    encode(key, 'escape') as key_value,
    count(*) as contention_count,
    sum(contention_duration) / 1000000.0 as total_milliseconds,
    avg(contention_duration) / 1000000.0 as avg_milliseconds
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
    AND key IS NOT NULL
GROUP BY database_name, schema_name, table_name, index_name, key
HAVING count(*) > 1
ORDER BY total_milliseconds DESC
LIMIT 20;

-- Expected: Specific keys experiencing contention (hot spots)

-- =============================================================================
-- TEST 10: Contention Timeline Analysis
-- =============================================================================

-- Test Case 10A: Contention over time (5-minute buckets)
SELECT
    date_trunc('minute', collection_ts - INTERVAL '0 seconds' * (EXTRACT(SECOND FROM collection_ts)::INT % 300)) as time_bucket,
    count(*) as event_count,
    count(DISTINCT table_name) as affected_tables,
    sum(contention_duration) / 1000000000.0 as total_seconds,
    avg(contention_duration) / 1000000.0 as avg_milliseconds,
    max(contention_duration) / 1000000.0 as max_milliseconds
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
GROUP BY time_bucket
ORDER BY time_bucket DESC;

-- Expected: Time-series view of contention patterns

-- =============================================================================
-- TEST 11: Blocking Transaction Analysis
-- =============================================================================

-- Test Case 11A: Transactions that block others most frequently
SELECT
    blocking_txn_fingerprint_id,
    count(DISTINCT waiting_txn_id) as transactions_blocked,
    count(*) as blocking_events,
    sum(contention_duration) / 1000000000.0 as total_blocking_seconds,
    avg(contention_duration) / 1000000.0 as avg_blocking_milliseconds
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
    AND blocking_txn_fingerprint_id IS NOT NULL
GROUP BY blocking_txn_fingerprint_id
ORDER BY total_blocking_seconds DESC
LIMIT 10;

-- Expected: Transaction patterns that cause most blocking

-- =============================================================================
-- TEST 12: Contention Type Distribution
-- =============================================================================

-- Test Case 12A: Distribution by contention type
SELECT
    contention_type,
    count(*) as event_count,
    count(DISTINCT table_name) as affected_tables,
    sum(contention_duration) / 1000000000.0 as total_seconds,
    avg(contention_duration) / 1000000.0 as avg_milliseconds
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
GROUP BY contention_type
ORDER BY total_seconds DESC;

-- Expected: Breakdown by contention type (write-write, read-write, etc.)

-- =============================================================================
-- TEST 13: Cross-Node Contention Monitoring
-- =============================================================================

-- Test Case 13A: Contention distribution across nodes
SELECT
    node_id,
    count(*) as local_events,
    sum(contention_duration) / 1000000000.0 as total_seconds
FROM crdb_internal.transaction_contention_events
WHERE collection_ts > now() - INTERVAL '1 hour'
GROUP BY node_id
ORDER BY total_seconds DESC;

-- Expected: Contention distribution by node (if multi-node cluster)

-- =============================================================================
-- TEST 14: Alert Threshold Monitoring
-- =============================================================================

-- Test Case 14A: Tables exceeding contention threshold (100ms average)
WITH table_contention AS (
    SELECT
        database_name,
        schema_name,
        table_name,
        count(*) as event_count,
        avg(contention_duration) / 1000000.0 as avg_milliseconds,
        sum(contention_duration) / 1000000000.0 as total_seconds
    FROM crdb_internal.transaction_contention_events
    WHERE collection_ts > now() - INTERVAL '1 hour'
    GROUP BY database_name, schema_name, table_name
)
SELECT
    database_name,
    schema_name,
    table_name,
    event_count,
    round(avg_milliseconds::NUMERIC, 2) as avg_contention_ms,
    round(total_seconds::NUMERIC, 2) as total_contention_seconds,
    CASE
        WHEN avg_milliseconds > 100 THEN 'CRITICAL'
        WHEN avg_milliseconds > 50 THEN 'WARNING'
        ELSE 'OK'
    END as alert_level
FROM table_contention
WHERE avg_milliseconds > 50
ORDER BY avg_milliseconds DESC;

-- Expected: Tables requiring attention based on thresholds

-- =============================================================================
-- TEST 15: Cleanup
-- =============================================================================

DROP TABLE IF EXISTS monitoring_test CASCADE;

-- =============================================================================
-- VALIDATION SUMMARY
-- =============================================================================

-- This test suite validates monitoring capabilities for:
-- ✓ Transaction contention events tracking
-- ✓ Cluster-wide contention aggregation
-- ✓ Statement-level contention statistics
-- ✓ Transaction-level contention metrics
-- ✓ Real-time active transaction monitoring
-- ✓ Contention rate calculations
-- ✓ Hot key identification
-- ✓ Time-series contention analysis
-- ✓ Blocking transaction patterns
-- ✓ Contention type distribution
-- ✓ Cross-node contention tracking
-- ✓ Alert threshold detection

-- MONITORING METRICS COVERED:
-- - crdb_internal.transaction_contention_events
-- - crdb_internal.cluster_contention_events
-- - crdb_internal.statement_statistics
-- - crdb_internal.transaction_statistics
-- - crdb_internal.node_transactions
-- - crdb_internal.node_queries

-- SUCCESS CRITERIA:
-- All queries execute successfully and return relevant metrics
-- Contention events are captured and queryable
-- Statistics provide actionable insights
-- Thresholds identify problematic patterns
