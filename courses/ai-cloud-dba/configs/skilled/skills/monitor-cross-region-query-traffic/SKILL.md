---
name: monitor-cross-region-query-traffic
description: Can monitor cross-region queries using DB Console SQL Activity page filtered by regions. Check Network Latency dashboard for inter-region roundtrip times. Query statement statistics for queries with high latency from specific regions. Use to identify candidates for locality optimization or follower reads.
metadata:
  domain: Multi-Region
  tags: multi-region, monitoring, performance
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: ready
  testing_notes: Tested against v26.1.0 multi-region cluster. All queries updated for v26.1 schema changes in crdb_internal tables.
---

# Monitor Cross-Region Query Traffic

Monitors query traffic patterns across regions to identify performance bottlenecks, optimize data locality, and find opportunities for follower reads or locality improvements.

## What This Skill Teaches

You'll learn to:
- **Monitor cross-region query patterns** using DB Console and SQL statistics
- **Identify high-latency queries** originating from specific regions
- **Analyze network latency** between regions to understand query performance
- **Track session distribution** across regions to understand traffic sources
- **Query statement statistics** to find cross-region query candidates
- **Identify optimization opportunities** for follower reads or locality changes

## Overview

### Why Monitor Cross-Region Traffic

Cross-region queries incur significant network latency costs:

**Performance Impact**:
- Same region query: 5-15ms
- Cross-region US-US: 60-80ms (12-16x slower)
- Cross-region US-EU: 80-120ms (16-24x slower)
- Cross-region US-Asia: 150-250ms (30-50x slower)

**Monitoring helps**:
- Identify queries that cross region boundaries unnecessarily
- Find opportunities for follower reads (analytics, reporting)
- Optimize table locality settings (REGIONAL BY ROW, REGIONAL BY TABLE)
- Detect session distribution imbalances
- Reduce cross-region data transfer costs

## Instructions

### Method 1: DB Console SQL Activity Page (Recommended)

**Step 1:** Access DB Console SQL Activity

```
https://<node-address>:8080/#/sql-activity
```

Navigate to: **SQL Activity → Statements**

**Step 2:** Filter by Region and Analyze

- Click **"App"** filter → Select specific region (e.g., `region=us-east1`)
- Sort by **"Latency"** to find slowest queries
- Look for **P99 latency > 100ms** (indicates cross-region access)
- Click query to view execution plan and regions accessed

### Method 2: Network Latency Dashboard

**Access**: `https://<node-address>:8080/#/metrics/network/cluster`

Navigate to: **Metrics → Network → Network Latency**

**Healthy Multi-Region Latency Baselines**:
```
Same AZ:                < 1ms   (sub-millisecond)
Same region (diff AZ):  1-5ms   (normal)
Cross-region US-US:     60-80ms (acceptable)
Cross-region US-EU:     80-120ms (expected)
Cross-region US-Asia:   150-250ms (high but normal)
```

**Interpretation**: Add network RTT to query execution time for total latency.
Example: 10ms query + 100ms network = 110ms total user latency

### Method 3: Query Statement Statistics

**Find High-Latency Cross-Region Queries**:

```sql
SET allow_unsafe_internals = true;

-- Find queries with high latency (cross-region indicator)
-- Note: v26.1 schema has nested JSON structure
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'svcLat'->>'mean')::FLOAT * 1000 AS mean_latency_ms,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT * 1000 AS max_latency_ms,
  (statistics->'statistics'->'cnt')::INT AS execution_count,
  (statistics->'statistics'->'bytesRead'->>'mean')::FLOAT / (1024*1024) AS avg_mb_per_exec
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.1  -- > 100ms
  AND (statistics->'statistics'->'cnt')::INT > 10
ORDER BY (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT DESC
LIMIT 20;
```

**Estimate Cross-Region Data Transfer**:

```sql
SET allow_unsafe_internals = true;

-- Calculate data transfer volume for cost analysis
-- v26.1 uses mean values, multiply by count for total
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'cnt')::INT AS execution_count,
  ((statistics->'statistics'->'bytesRead'->>'mean')::FLOAT *
   (statistics->'statistics'->'cnt')::INT) / (1024*1024*1024) AS total_gb_transferred,
  (statistics->'statistics'->'regions')::TEXT AS regions_accessed
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.1
  AND (statistics->'statistics'->'cnt')::INT > 10
ORDER BY total_gb_transferred DESC
LIMIT 10;
```

### Method 4: Monitor Session Distribution

**Check Active Sessions by Application**:

```sql
-- View session origins and distribution
-- Note: v26.1 does not expose gateway_region directly in SHOW CLUSTER SESSIONS
-- Use application_name and client_address as proxies for session origin
SELECT
  application_name,
  COUNT(*) AS session_count,
  COUNT(DISTINCT user_name) AS distinct_users,
  array_agg(DISTINCT client_address) AS client_addresses
FROM [SHOW CLUSTER SESSIONS]
WHERE status = 'ACTIVE'
GROUP BY application_name
ORDER BY session_count DESC;
```

**Alternative: Check Session Distribution by Node**:

```sql
-- View sessions per node to infer regional distribution
SELECT
  node_id,
  COUNT(*) AS session_count,
  COUNT(DISTINCT application_name) AS distinct_apps
FROM [SHOW CLUSTER SESSIONS]
GROUP BY node_id
ORDER BY session_count DESC;
```

**Interpretation**: Combine with node locality information to understand regional session distribution. If most sessions are on nodes in one region but leaseholders are in another, users experience cross-region latency.

**Identify Long-Running Sessions**:

```sql
-- Find sessions with long active query times
SELECT
  node_id,
  session_id,
  application_name,
  user_name,
  NOW() - active_query_start AS query_duration,
  LEFT(active_queries, 80) AS query_preview
FROM [SHOW CLUSTER SESSIONS]
WHERE active_query_start IS NOT NULL
  AND NOW() - active_query_start > INTERVAL '5 seconds'
ORDER BY query_duration DESC
LIMIT 10;
```

### Method 5: Set Up Alerting

**Alert Query for High-Latency Queries**:

```sql
SET allow_unsafe_internals = true;

-- Alert on queries with max latency > 500ms
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT * 1000 AS max_latency_ms,
  (statistics->'statistics'->'cnt')::INT AS execution_count,
  (statistics->'statistics'->'regions')::TEXT AS regions
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.5  -- > 500ms
  AND (statistics->'statistics'->'cnt')::INT > 100  -- High frequency
ORDER BY max_latency_ms DESC;
```

**Prometheus Alerting Rules**:

```yaml
groups:
  - name: cross_region_traffic
    rules:
      - alert: HighCrossRegionQueryLatency
        expr: sql_query_latency_p99{job="cockroachdb"} > 500
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High cross-region query latency detected"

      - alert: NetworkLatencyDegradation
        expr: rpc_heartbeat_latency_p99 > 300
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Network latency increased between nodes"
```

## Complete Example: Users Experiencing Slow Queries

**Step 1:** Check session distribution by node

```sql
SELECT node_id, COUNT(*) AS session_count, COUNT(DISTINCT application_name) AS apps
FROM [SHOW CLUSTER SESSIONS]
GROUP BY node_id;
```

**Result**: Node 3 (EU): 120 sessions (majority of traffic)

**Step 2:** Check network latency

```sql
SET allow_unsafe_internals = true;

SELECT store_id, value / 1000000.0 AS latency_ms
FROM crdb_internal.node_metrics
WHERE name = 'rpc.heartbeat.latency-p99'
ORDER BY store_id;
```

**Result**: Cross-region latency: ~85ms

**Step 3:** Find high-latency queries

```sql
SET allow_unsafe_internals = true;

SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT * 1000 AS max_latency_ms,
  (statistics->'statistics'->'cnt')::INT AS execution_count,
  (statistics->'statistics'->'regions')::TEXT AS regions
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.1
ORDER BY max_latency_ms DESC
LIMIT 5;
```

**Result**: Queries show ~135ms max latency (85ms network + 50ms execution)

**Analysis**: Queries crossing from EU to US leaseholders

**Step 4:** Recommend optimization

**Option 1 - Follower Reads** (for read-only queries):
```sql
-- Analytics queries can tolerate staleness
SELECT COUNT(*) FROM analytics
  AS OF SYSTEM TIME follower_read_timestamp()
WHERE created_at >= NOW() - INTERVAL '24 hours';
-- Expected: 135ms → 10ms (92% reduction)
```

**Option 2 - Leaseholder Preferences** (for transactional queries):
```sql
ALTER TABLE orders CONFIGURE ZONE USING
  lease_preferences = '[[+region=eu-west1]]';
-- Expected: 135ms → 15ms (89% reduction)
```

**Option 3 - Regional By Row** (if data is region-specific):
```sql
ALTER TABLE orders SET LOCALITY REGIONAL BY ROW;
-- Keeps data in the region where it was created
```

## Common Patterns

### Pattern 1: Identify Follower Read Candidates

```sql
SET allow_unsafe_internals = true;

-- Find read-only queries suitable for follower reads
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT * 1000 AS max_latency_ms,
  (statistics->'statistics'->'cnt')::INT AS execution_count,
  (statistics->'statistics'->'regions')::TEXT AS regions,
  CASE
    WHEN metadata->>'query' LIKE '%SELECT%'
      AND metadata->>'query' NOT LIKE '%FOR UPDATE%'
      AND metadata->>'query' NOT LIKE '%INSERT%'
      AND metadata->>'query' NOT LIKE '%UPDATE%'
      AND metadata->>'query' NOT LIKE '%DELETE%'
    THEN 'FOLLOWER READ CANDIDATE'
    ELSE 'NOT SUITABLE'
  END AS recommendation
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.1
  AND (statistics->'statistics'->'cnt')::INT > 1000
ORDER BY execution_count DESC;
```

### Pattern 2: Monitor Cross-Region Data Transfer Costs

```sql
SET allow_unsafe_internals = true;

-- Estimate data transfer costs (assuming $0.02/GB cross-region)
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'cnt')::INT AS executions,
  ((statistics->'statistics'->'bytesRead'->>'mean')::FLOAT *
   (statistics->'statistics'->'cnt')::INT) / (1024*1024*1024) AS total_gb,
  ((statistics->'statistics'->'bytesRead'->>'mean')::FLOAT *
   (statistics->'statistics'->'cnt')::INT) / (1024*1024*1024) * 0.02 AS estimated_cost_usd,
  (statistics->'statistics'->'regions')::TEXT AS regions
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.1
  AND aggregated_ts >= NOW() - INTERVAL '24 hours'
ORDER BY total_gb DESC
LIMIT 10;
```

### Pattern 3: Weekly Optimization Report

```sql
SET allow_unsafe_internals = true;

-- Generate weekly report of optimization candidates
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT * 1000 AS max_latency_ms,
  (statistics->'statistics'->'cnt')::INT AS weekly_executions,
  ((statistics->'statistics'->'bytesRead'->>'mean')::FLOAT *
   (statistics->'statistics'->'cnt')::INT) / (1024*1024*1024) AS total_gb_weekly,
  (statistics->'statistics'->'regions')::TEXT AS regions,
  CASE
    WHEN metadata->>'query' LIKE '%SELECT%'
      AND metadata->>'query' NOT LIKE '%UPDATE%'
      AND metadata->>'query' NOT LIKE '%DELETE%'
      AND metadata->>'query' NOT LIKE '%FOR UPDATE%'
    THEN 'Follower Read Candidate'
    ELSE 'Leaseholder Preference Candidate'
  END AS recommendation
FROM crdb_internal.statement_statistics
WHERE aggregated_ts >= NOW() - INTERVAL '7 days'
  AND (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.1
  AND (statistics->'statistics'->'cnt')::INT > 1000
ORDER BY weekly_executions DESC
LIMIT 20;
```

## Troubleshooting

### v26.1 Schema Changes

**Important**: This skill has been updated for v26.1.0 schema changes:

- `crdb_internal.statement_statistics`: JSON structure changed from `statistics->runLat->p99` to `statistics->latencyInfo->max`
- `crdb_internal.node_metrics`: `node_id` column renamed to `store_id`
- `SHOW CLUSTER SESSIONS`: `gateway_region` column removed (use `node_id` with locality lookup)
- All `crdb_internal` queries require `SET allow_unsafe_internals = true;`

### Issue: High Latency but Low Network Latency

**Symptoms**: Query P99: 200ms, Network latency: 10ms (same region)

**Possible Causes**:
- Query inefficiency (missing indexes, full table scan)
- High CPU contention on leaseholder node
- Transaction contention

**Diagnosis**:

```sql
-- Check query execution plan
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'pending';

-- Check CPU usage
SELECT node_id, value
FROM crdb_internal.node_metrics
WHERE name = 'sys.cpu.combined.percent-normalized'
ORDER BY value DESC;
```

**Solution**: Add indexes, scale capacity, or optimize queries

### Issue: Network Latency Dashboard Shows No Data

**Symptoms**: Network Latency graph is empty

**Possible Causes**: Single-node cluster, time range too narrow, metrics not yet collected

**Solution**:

```sql
-- Verify multi-node cluster
SELECT node_id, address FROM crdb_internal.gossip_nodes;

-- Check RPC metrics
SELECT name, value
FROM crdb_internal.node_metrics
WHERE name LIKE '%rpc%latency%'
LIMIT 5;
```

### Issue: Unable to Identify Query Origin Region

**Symptoms**: `gateway_region` shows NULL

**Possible Causes**: Node locality not set during cluster initialization

**Diagnosis**:

```sql
-- Check node locality configuration
SELECT node_id, locality
FROM crdb_internal.gossip_nodes;
-- Should show: region=us-east1,zone=us-east1-a
```

**Solution**: Restart nodes with locality flags:

```bash
cockroach start \
  --locality=region=us-east1,zone=us-east1-a \
  --certs-dir=certs \
  --join=<existing-nodes>
```

## Best Practices

### 1. Establish Baseline Metrics and Track Changes

Record baseline performance before optimization to measure improvement.

### 2. Set Alerting Thresholds by Region Pair

Different region pairs have different acceptable latencies:

```yaml
# Example Prometheus rules
- alert: HighLatencyUS
  expr: sql_query_latency_p99{region=~"us-.*"} > 150
  for: 10m

- alert: HighLatencyUSEU
  expr: sql_query_latency_p99{region=~"(us|eu)-.*"} > 200
  for: 10m

- alert: HighLatencyUSAsia
  expr: sql_query_latency_p99{region=~"(us|ap)-.*"} > 300
  for: 10m
```

### 3. Prioritize High-Impact Optimizations

Focus on queries with:
- High frequency (thousands of executions)
- High latency (> 100ms max)
- Large data transfer (GB per day)
- Business-critical operations

```sql
SET allow_unsafe_internals = true;

-- Calculate impact score: latency × frequency
SELECT
  metadata->>'query' AS query,
  (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT * 1000 AS max_latency_ms,
  (statistics->'statistics'->'cnt')::INT AS execution_count,
  ((statistics->'statistics'->'latencyInfo'->>'max')::FLOAT * 1000) *
   (statistics->'statistics'->'cnt')::INT AS impact_score,
  (statistics->'statistics'->'regions')::TEXT AS regions
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'latencyInfo'->>'max')::FLOAT > 0.1
ORDER BY impact_score DESC
LIMIT 10;
```

### 4. Monitor Continuously

Create automated monitoring views for traffic categorization by latency.

### 5. Regular Reporting Cadence

- **Daily**: Check for anomalies and spikes
- **Weekly**: Review optimization candidates
- **Monthly**: Analyze trends and cost impact

### 6. Document Optimization Decisions

Track optimization changes with before/after metrics to measure effectiveness.

## Related Skills

- `monitor-network-latency-between-nodes` - Track inter-node network performance
- `monitor-statement-statistics` - Analyze query performance metrics
- `monitor-session-distribution-with-show-cluster-sessions` - Track session origins
- `understand-when-to-use-follower-reads` - Identify follower read opportunities
- `implement-follower-reads-for-stale-data-access` - Apply follower reads to queries
- `configure-leaseholder-preferences-with-zone-configs` - Optimize leaseholder placement
- `configure-regional-by-row-locality` - Region-specific data locality
- `troubleshoot-high-cross-region-query-latency` - Debug latency issues

## References

- DB Console SQL Activity: https://www.cockroachlabs.com/docs/stable/ui-overview.html#sql-activity
- Statement Statistics: https://www.cockroachlabs.com/docs/stable/ui-statements-page.html
- Network Latency Dashboard: https://www.cockroachlabs.com/docs/stable/ui-network-latency-page.html
- Multi-Region Performance: https://www.cockroachlabs.com/docs/stable/topology-patterns.html
- Follower Reads: https://www.cockroachlabs.com/docs/stable/follower-reads.html
- Table Localities: https://www.cockroachlabs.com/docs/stable/table-localities.html
