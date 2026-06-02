-- Test Suite: Monitor Clock Offset Across Nodes
-- Skill: monitor-clock-offset-across-nodes
-- Test Date: 2026-03-07
-- Cluster: localhost:26258
-- Version: v26.1

-- =============================================================================
-- TEST 1: Basic Clock Offset Query
-- =============================================================================
-- Description: Verify clock-offset.meannanos metric is accessible
-- Expected: Returns cluster-wide clock offset value in nanoseconds

SET allow_unsafe_internals = true;

SELECT
  'cluster-wide' AS scope,
  ROUND(value / 1000000.0, 2) AS offset_ms,
  CASE
    WHEN value > 500000000 THEN 'CRITICAL: Will crash at 500ms'
    WHEN value > 250000000 THEN 'WARNING: Too high'
    WHEN value > 100000000 THEN 'CAUTION: Monitor'
    ELSE 'OK'
  END AS status
FROM crdb_internal.node_metrics
WHERE name = 'clock-offset.meannanos';

-- Expected Result:
--     scope     | offset_ms | status
-- --------------+-----------+--------
--  cluster-wide |      X.XX | OK

-- Pass Criteria:
-- - Query executes without error
-- - Returns exactly 1 row
-- - offset_ms is a numeric value
-- - status column shows appropriate threshold classification

-- =============================================================================
-- TEST 2: Clock Offset Alert Query (Threshold Detection)
-- =============================================================================
-- Description: Verify alert query only returns results when offset > 100ms
-- Expected: Returns rows only if clock offset exceeds 100ms threshold

SELECT
  'cluster-wide' AS scope,
  ROUND(value / 1000000.0, 2) AS offset_ms,
  CASE
    WHEN value > 500000000 THEN 'CRITICAL: Will crash'
    WHEN value > 250000000 THEN 'WARNING: Too high'
    WHEN value > 100000000 THEN 'CAUTION: Monitor'
    ELSE 'OK'
  END AS status
FROM crdb_internal.node_metrics
WHERE name = 'clock-offset.meannanos'
  AND value > 100000000;  -- Alert on > 100ms

-- Expected Result (if offset < 100ms):
-- (0 rows)

-- Expected Result (if offset > 100ms):
--     scope     | offset_ms | status
-- --------------+-----------+---------
--  cluster-wide |    XXX.XX | CAUTION: Monitor

-- Pass Criteria:
-- - Query executes without error
-- - Returns 0 rows if offset < 100ms
-- - Returns 1 row if offset > 100ms
-- - Correctly classifies threshold levels

-- =============================================================================
-- TEST 3: Comprehensive Health Check Query
-- =============================================================================
-- Description: Full health check with recommendations
-- Expected: Returns comprehensive status and actionable recommendations

WITH clock_metrics AS (
  SELECT
    value AS offset_nanos,
    ROUND(value / 1000000.0, 2) AS offset_ms
  FROM crdb_internal.node_metrics
  WHERE name = 'clock-offset.meannanos'
)
SELECT
  'cluster-wide' AS scope,
  offset_ms,
  CASE
    WHEN offset_ms > 500 THEN 'FATAL: Will crash'
    WHEN offset_ms > 400 THEN 'CRITICAL: Immediate action'
    WHEN offset_ms > 250 THEN 'WARNING: Too high'
    WHEN offset_ms > 100 THEN 'CAUTION: Monitor'
    ELSE 'OK'
  END AS status,
  CASE
    WHEN offset_ms > 400 THEN 'Fix NTP immediately'
    WHEN offset_ms > 250 THEN 'Investigate NTP issues'
    WHEN offset_ms > 100 THEN 'Verify NTP configuration'
    ELSE 'No action needed'
  END AS recommendation
FROM clock_metrics;

-- Expected Result:
--     scope     | offset_ms |  status  |    recommendation
-- --------------+-----------+----------+---------------------
--  cluster-wide |      X.XX | OK       | No action needed

-- Pass Criteria:
-- - Query executes without error
-- - Returns exactly 1 row
-- - All columns populated correctly
-- - Recommendations align with status levels

-- =============================================================================
-- TEST 4: Verify Node Status Query (Context)
-- =============================================================================
-- Description: Verify we can query node information separately
-- Expected: Returns list of all nodes in cluster

SELECT node_id, address, locality, started_at
FROM crdb_internal.kv_node_status
ORDER BY node_id;

-- Expected Result (example for single-node cluster):
--  node_id |     address      | locality | started_at
-- ---------+------------------+----------+------------
--        1 | localhost:26257  |          | 2026-03-XX...

-- Pass Criteria:
-- - Query executes without error
-- - Returns at least 1 row (one per node)
-- - All columns populated
-- - Shows active nodes only

-- =============================================================================
-- TEST 5: Multiple Clock-Related Metrics
-- =============================================================================
-- Description: List all available clock-related metrics
-- Expected: Shows all clock metrics available in system

SELECT name, value
FROM crdb_internal.node_metrics
WHERE name LIKE '%clock%'
ORDER BY name;

-- Expected Result (partial):
--          name              |    value
-- ---------------------------+-------------
--  clock-offset.meannanos    |  XXXXX
--  ... (other clock metrics)

-- Pass Criteria:
-- - Query executes without error
-- - Returns clock-offset.meannanos metric
-- - May return other clock-related metrics

-- =============================================================================
-- TEST 6: Verify allow_unsafe_internals Setting
-- =============================================================================
-- Description: Test that queries work with allow_unsafe_internals
-- Expected: Setting can be enabled and queries execute

-- Test without setting (should work in most cases)
SELECT name, value
FROM crdb_internal.node_metrics
WHERE name = 'clock-offset.meannanos';

-- Test with setting explicitly enabled
SET allow_unsafe_internals = true;

SELECT name, value
FROM crdb_internal.node_metrics
WHERE name = 'clock-offset.meannanos';

-- Pass Criteria:
-- - Both queries should execute successfully
-- - Both return same result
-- - No permission errors

-- =============================================================================
-- TEST 7: Timestamp Correlation Query
-- =============================================================================
-- Description: Verify HLC timestamp function works
-- Expected: Returns current cluster timestamp

SELECT cluster_logical_timestamp();

-- Expected Result:
--  cluster_logical_timestamp
-- ---------------------------
--  1234567890123456789.0000000000

-- Pass Criteria:
-- - Query executes without error
-- - Returns valid HLC timestamp (large integer + decimal)
-- - Timestamp increases on subsequent calls

-- =============================================================================
-- VALIDATION CHECKLIST
-- =============================================================================
--
-- After running all tests, verify:
--
-- ✅ TEST 1: Basic query returns clock offset
-- ✅ TEST 2: Alert query filters correctly
-- ✅ TEST 3: Health check provides recommendations
-- ✅ TEST 4: Node status query works
-- ✅ TEST 5: Clock metrics are discoverable
-- ✅ TEST 6: allow_unsafe_internals setting works
-- ✅ TEST 7: HLC timestamp query works
--
-- Expected Outcomes:
-- - Clock offset should be < 50ms on healthy cluster
-- - All queries execute without errors
-- - Metrics available in crdb_internal.node_metrics
-- - Status classifications align with documented thresholds
--
-- Known Limitations (v26.1):
-- - clock-offset.meannanos is cluster-wide metric (not per-node)
-- - Per-node offset not directly queryable via SQL
-- - Use DB Console Hardware dashboard for per-node visualization
