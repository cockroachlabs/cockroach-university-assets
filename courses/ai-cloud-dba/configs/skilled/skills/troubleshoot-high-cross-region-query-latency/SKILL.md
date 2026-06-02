---
name: troubleshoot-high-cross-region-query-latency
description: Systematically diagnose and resolve cross-region query latency issues by analyzing statement statistics, table locality, leaseholder placement, network latency, and query execution plans
metadata:
  domain: Multi-Region
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: ready
  author: CockroachDB University
  tags:
    - multi-region
    - performance
    - latency
    - troubleshooting
    - query-optimization
    - locality
  testing_notes: |
    v26.1.0 compatibility updates:
    - Replaced crdb_internal.ranges_no_leases table_name filtering with SHOW RANGES
    - Updated node_metrics queries to use store_id instead of node_id
    - Added allow_unsafe_internals requirement for crdb_internal queries
    - Verified all queries against v26.1.0 cluster (localhost:26258)
    - Tested against multi-region cluster (us-east, us-west, eu-west)
---

# Troubleshoot High Cross-Region Query Latency

**Domain**: Multi-Region
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

> **Important**: Many queries in this skill require `SET allow_unsafe_internals = true;` to access `crdb_internal` tables. This setting should only be used in development/troubleshooting environments. In production, use the DB Console UI (`http://<node>:8080`) for monitoring.

## What This Skill Teaches

This skill teaches you systematic troubleshooting workflows for diagnosing and resolving high cross-region query latency in multi-region CockroachDB deployments. You'll learn to identify slow queries, determine whether latency is caused by cross-region data access, analyze table locality configurations, verify leaseholder placement, inspect network latency between regions, review query execution plans for cross-region operations, and check for transaction contention that amplifies latency issues.

## Overview: Cross-Region Latency Sources

**Network baseline costs:**
- Same region: 1-5ms | Cross-region US: 60-80ms | US-Europe: 100-150ms | US-Asia: 150-250ms

**Operations causing cross-region latency:**
- Remote leaseholder reads, cross-region writes (region survival quorum), cross-region joins, remote index lookups, distributed transaction coordination

**Common causes:**
- Locality misconfigurations (GLOBAL for region-specific data, REGIONAL BY TABLE in wrong region)
- Leaseholder preferences not aligned with application regions
- Transaction contention amplifying network latency
- Missing indexes forcing full table scans across regions

## Systematic Troubleshooting Workflow

Follow this structured approach to diagnose cross-region latency issues:

### Step 1: Identify Slow Queries

Start by identifying queries with high latency using statement statistics.

```sql
-- Find queries with high mean latency
-- Note: Requires allow_unsafe_internals in v26.1.0+
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  metadata->>'db' AS database,
  metadata->>'applicationName' AS app_name,
  (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 AS mean_latency_ms,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT / 1000 AS max_latency_ms,
  (statistics->'statistics'->>'cnt')::INT AS executions,
  -- Variance indicator
  ROUND(
    (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT /
    NULLIF((statistics->'statistics'->'runLat'->>'mean')::FLOAT, 0),
    2
  ) AS max_to_mean_ratio
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->>'cnt')::INT > 50
  AND (statistics->'statistics'->'runLat'->>'mean')::FLOAT / 1000 > 100  -- > 100ms
ORDER BY mean_latency_ms DESC
LIMIT 20;
```

**What to look for:**
- Queries with mean latency > 100ms (likely cross-region)
- High `max_to_mean_ratio` (>5) indicates inconsistent performance
- Application name helps identify which service is affected

**Next steps:**
- If mean latency is 50-150ms, likely cross-region reads
- If mean latency is 100-300ms, likely cross-region writes (region survival)
- Proceed to Step 2 to confirm cross-region access

### Step 2: Determine If Latency Is Cross-Region

```sql
-- Check leaseholder location for slow query tables
-- v26.1.0: Use SHOW RANGES for specific tables
SHOW RANGES FROM TABLE users WITH DETAILS;
SHOW RANGES FROM TABLE orders WITH DETAILS;

-- Or check table locality configuration
SET allow_unsafe_internals = true;
SELECT name AS table_name, locality
FROM crdb_internal.tables
WHERE database_name = current_database()
  AND schema_name = 'public'
  AND name IN ('users', 'orders');
```

**Cross-region indicators:** Leaseholder in different region than application, GLOBAL table for region-specific data, REGIONAL BY TABLE in wrong region

**Next step:** If leaseholders are remote, continue to Step 3. Otherwise, investigate general query optimization (indexes, execution plans).

### Step 3: Analyze Table Locality Configuration

```sql
-- View table localities
SELECT table_name, locality FROM [SHOW TABLES FROM your_database];
```

**Fix common misconfigurations:**

```sql
-- Problem: GLOBAL table for region-specific data
-- Solution: Convert to REGIONAL BY ROW
ALTER TABLE users SET LOCALITY REGIONAL BY ROW;

-- Problem: REGIONAL BY TABLE in wrong region
-- Solution: Move to correct region
ALTER TABLE users SET LOCALITY REGIONAL BY TABLE IN "us-west";

-- Problem: Multi-region workload without REGIONAL BY ROW
-- Solution: Enable row-level locality with crdb_region column
ALTER TABLE users SET LOCALITY REGIONAL BY ROW;
```

**Next step:** If locality is correct, proceed to Step 4.

### Step 4: Verify Network Latency

```sql
-- Check inter-region network latency
-- v26.1.0: Use store_id instead of node_id
SET allow_unsafe_internals = true;
SELECT store_id, value / 1000000.0 AS latency_ms
FROM crdb_internal.node_metrics
WHERE name = 'rpc.heartbeat.latency-p99'
ORDER BY store_id;
```

**Expected ranges:** Same region <10ms, US cross-region 60-80ms, transatlantic 100-150ms

**If abnormal (>2x expected):** Check cloud provider status, VPC configuration, bandwidth saturation. Otherwise proceed to Step 5.

### Step 5: Review Query Execution Plans

```sql
EXPLAIN (ANALYZE, VERBOSE) SELECT * FROM users WHERE user_id = 123;
```

**Cross-region indicators in plans:** Remote region scans, index joins with remote indexes, cross-region hash joins, distributed execution across multiple regions

**Common fixes:**

```sql
-- Remote index: Set leaseholder preference
ALTER INDEX users@idx_email CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east]]';

-- Cross-region joins: Use follower reads (if staleness acceptable)
SELECT * FROM users AS OF SYSTEM TIME follower_read_timestamp()
  JOIN orders USING (user_id);

-- Full table scans: Add covering index
CREATE INDEX ON users (user_email) STORING (user_name, created_at);
```

### Step 6: Check for Transaction Contention

```sql
-- Check retry rates (indicator of contention)
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'maxRetries')::INT AS max_retries,
  (statistics->'statistics'->>'cnt')::INT AS executions,
  ROUND((statistics->'statistics'->'maxRetries')::INT::FLOAT /
    NULLIF((statistics->'statistics'->>'cnt')::INT, 0) * 100, 2) AS retry_rate_pct
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'maxRetries')::INT > 0
ORDER BY retry_rate_pct DESC LIMIT 20;
```

**Contention indicators:** retry_rate_pct >5%, max_retries >3, high max/mean latency ratio (>10)

**Remediation:**

```sql
-- Minimize transaction scope (reduce lock duration)
BEGIN;
  UPDATE users SET last_login = now() WHERE user_id = 123;
COMMIT;

-- Use AS OF SYSTEM TIME for historical reads (avoids contention)
SELECT * FROM users AS OF SYSTEM TIME '-5s' WHERE region = 'us-east';
```

## Common Patterns and Solutions

### Pattern 1: REGIONAL BY ROW with Wrong Leaseholders

**Problem:** Table locality correct but leaseholders in wrong region
**Solution:**
```sql
ALTER TABLE users CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east], [+region=us-west]]';
```

### Pattern 2: GLOBAL Table Write Latency

**Problem:** GLOBAL tables require cross-region quorum (100-200ms writes)
**Solution:** Convert to REGIONAL BY ROW if writes are frequent and region-specific
```sql
ALTER TABLE users SET LOCALITY REGIONAL BY ROW;
```

### Pattern 3: Cross-Region Joins

**Problem:** Joining tables with leaseholders in different regions
**Solutions:**
- **Denormalize:** Add foreign key columns to avoid joins
- **Follower reads:** Use `AS OF SYSTEM TIME follower_read_timestamp()` for stale-ok queries
- **Co-locate:** Set same leaseholder preferences for both tables

### Pattern 4: Remote Index Scans

**Problem:** Index leaseholder in different region
**Solution:**
```sql
ALTER INDEX users@idx_email CONFIGURE ZONE USING
  lease_preferences = '[[+region=us-east]]';
```

### Pattern 5: Application in Wrong Region

**Problem:** App deployed in region without leaseholders
**Solutions:**
- Deploy app in same region as data
- Add database nodes in app region
- Configure leaseholder preferences for app region

## Diagnostic Checklist

**Identify:** Query slow queries from statement statistics (mean >100ms, high variance)
**Confirm:** Check leaseholder placement - are leaseholders in same region as application?
**Verify:** Measure network latency between regions - within expected ranges?
**Analyze:** Run EXPLAIN on slow queries - remote scans, cross-region joins, distributed execution?
**Contention:** Check retry rates - is contention amplifying latency?
**Fix:** Configure locality, leaseholder preferences, add indexes, denormalize, or use follower reads
**Validate:** Measure latency improvements in statement statistics

## Troubleshooting Advanced Scenarios

### Intermittent Latency Spikes (max/mean >10)

**Cause:** Leaseholder movement or network variability
**Fix:** Pin leaseholder preferences more aggressively, check for cluster rebalancing activity

### Read-Heavy Workload Latency

**Cause:** Not using follower reads
**Fix:** Use `AS OF SYSTEM TIME follower_read_timestamp()` for stale-acceptable queries (analytics, dashboards)

### Multi-Statement Transaction Latency

**Cause:** Transaction spans multiple regions (each statement incurs cross-region latency)
**Fix:** Minimize transaction scope, denormalize to keep related data in same region, or separate non-critical operations outside transaction

## Best Practices

**Diagnostic methodology:**
- Start with data: Query statement statistics before hypothesizing
- Isolate variables: Test one change at a time (locality → leaseholder → indexes)
- Use EXPLAIN ANALYZE for actual runtime behavior
- Measure baselines: Know normal network latency for your topology
- Consider application patterns: Some cross-region latency may be unavoidable

**Monitoring and alerting:**
- Alert on mean latency >100ms, max/mean >10, retry rate >5%, network latency >2x expected
- Monitor latency trends by application and database
- Use DB Console (`http://localhost:8080/#/sql-activity`) for p50/p90/p99 percentile graphs

**Validation workflow:**
1. Capture baseline latency
2. Apply configuration change
3. Wait for rebalancing
4. Measure new latency
5. Confirm improvement

## Instructions

When the user invokes this skill for troubleshooting:

1. **Gather context**: Ask which queries are slow, how slow, and in which region
2. **Run diagnostics**: Execute Step 1 (identify slow queries) from the workflow
3. **Systematic analysis**: Walk through Steps 2-6 based on findings
4. **Provide specific recommendations**: Show exact SQL to fix locality, leaseholder preferences, indexes
5. **Validate solutions**: Help user measure before/after latency improvements

**Key questions to ask:**
- What is the current mean/max latency for slow queries?
- Which tables are involved in slow queries?
- Where is your application deployed (which region)?
- What is your database's multi-region configuration (regions, primary region, survival goals)?
- Is the workload read-heavy, write-heavy, or mixed?
- Is eventual consistency acceptable (follower reads possible)?

## Related Skills

- **analyze-query-latency-percentiles**: Analyzing mean/max/min latency metrics for identifying slow queries
- **monitor-network-latency-between-nodes**: Checking RPC heartbeat latency and network health
- **monitor-cross-region-query-traffic**: Tracking cross-region query volume and patterns
- **verify-table-locality-configuration**: Checking REGIONAL BY TABLE/ROW/GLOBAL settings
- **check-leaseholder-location-for-tables**: Identifying where leaseholders are placed
- **configure-leaseholder-preferences-with-zone-configs**: Setting leaseholder placement constraints
- **use-follower-reads-to-reduce-latency**: Implementing AS OF SYSTEM TIME for stale reads
- **optimize-multi-region-deployments-for-low-latency**: Architectural patterns for low-latency multi-region
- **identify-and-analyze-database-contention**: Diagnosing transaction contention issues
- **use-explain-analyze-for-runtime-execution-analysis**: Analyzing actual query execution behavior

## References

- **Multi-Region Performance**: https://www.cockroachlabs.com/docs/stable/performance.html
- **Table Locality**: https://www.cockroachlabs.com/docs/stable/table-localities.html
- **Leaseholder Preferences**: https://www.cockroachlabs.com/docs/stable/configure-replication-zones.html#lease_preferences
- **Follower Reads**: https://www.cockroachlabs.com/docs/stable/follower-reads.html
- **Troubleshooting Performance**: https://www.cockroachlabs.com/docs/stable/performance-best-practices-overview.html
- **Network Latency**: https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting.html#network-latency
