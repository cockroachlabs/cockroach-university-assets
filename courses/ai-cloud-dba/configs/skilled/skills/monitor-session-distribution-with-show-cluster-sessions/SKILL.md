---
name: monitor-session-distribution-with-show-cluster-sessions
description: Can use SHOW CLUSTER SESSIONS to view all active SQL connections, their distribution across nodes, active queries, and session duration. Identify long-running sessions or connection pool imbalances across nodes. Use when user says "check sessions", "monitor connections", "session distribution".
metadata:
  domain: Monitoring and Alerting
  tags: cluster-operations, connection-management, monitoring
  blooms_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
---

# Monitor Session Distribution with SHOW CLUSTER SESSIONS

Monitors active SQL connections across all cluster nodes to identify connection pool imbalances, long-running sessions, idle connections, and node-level load distribution. Essential for capacity planning, troubleshooting connection issues, and ensuring balanced application load.

## Why Monitor Session Distribution

Provides insights into connection pool health, load balancer effectiveness, application connection patterns, and capacity planning. Detects uneven node distribution, long-running sessions, idle connections, and connection leaks.

## SHOW CLUSTER SESSIONS Syntax

### Basic Usage

```sql
-- View all active sessions across cluster
SHOW CLUSTER SESSIONS;
```

Returns columns:
- `node_id`: Node hosting the session
- `session_id`: Unique session identifier (hex string)
- `user_name`: SQL user for the session
- `client_address`: IP address and port of client
- `application_name`: Application identifier from connection string
- `active_queries`: Currently executing SQL statements
- `last_active_query`: Last query executed (if session is idle)
- `session_start`: Timestamp when session was created
- `active_query_start`: Start time of currently executing query
- `num_txns_executed`: Number of transactions executed in session
- `trace_id`: Trace ID for distributed tracing
- `goroutine_id`: Internal goroutine ID
- `isolation_level`: Transaction isolation level (SERIALIZABLE)

**Note**: Memory tracking columns (`alloc_bytes`, `max_alloc_bytes`) and transaction ID (`kv_txn`) are NOT available in v26.1.0. Use `crdb_internal.cluster_transactions` for transaction details and `crdb_internal.node_memory_monitors` for memory tracking.

**Common filters**:
```sql
-- Specific node
SHOW CLUSTER SESSIONS WHERE node_id = 1;

-- Specific application
SHOW CLUSTER SESSIONS WHERE application_name = 'myapp';

-- Active queries only
SHOW CLUSTER SESSIONS WHERE active_queries != '';
```

## Analyzing Session Distribution

### Method 1: Distribution Across Nodes

**Check connection balance**:

```sql
-- Count sessions per node
SELECT
  node_id,
  count(*) as session_count
FROM [SHOW CLUSTER SESSIONS]
GROUP BY node_id
ORDER BY session_count DESC;
```

**Expected results (3-node cluster with balanced load balancer)**:
```
 node_id | session_count
---------+---------------
       1 |            45
       2 |            47
       3 |            43
```

**Unhealthy imbalance**:
```
 node_id | session_count
---------+---------------
       1 |           120
       2 |             8
       3 |             5
```

**Causes of imbalance**:
- Load balancer misconfiguration (not round-robin)
- Direct connections bypassing load balancer
- Node recently added (connections haven't redistributed)
- Application pinning to specific node
- Connection pooling issues

### Method 2: Sessions by Application

**Identify per-application connection counts**:

```sql
-- Connection distribution by application
SELECT
  application_name,
  count(*) as session_count,
  count(DISTINCT node_id) as nodes_used
FROM [SHOW CLUSTER SESSIONS]
GROUP BY application_name
ORDER BY session_count DESC;
```

**Interpretation**:
```
 application_name | session_count | nodes_used
------------------+---------------+------------
 webapp           |           120 |          3   -- Good: distributed
 batch_job        |            50 |          1   -- Warning: single node
 admin_tool       |             3 |          2   -- Normal
```

**Analysis**:
- `webapp` with 120 sessions across 3 nodes = healthy distribution
- `batch_job` with 50 sessions on 1 node = potential bottleneck
- `admin_tool` with 3 sessions = normal for interactive tool

### Method 3: Active vs Idle Sessions

```sql
-- Sessions with no active queries
SELECT
  node_id,
  application_name,
  session_id,
  session_start
FROM [SHOW CLUSTER SESSIONS]
WHERE active_queries = ''
ORDER BY session_start ASC;
```

**Idle session concerns**: Over-provisioned connection pools, connection leaks (very old idle sessions), resource waste.

### Method 4: Long-Running Sessions

```sql
-- Sessions with long-running queries (> 5 minutes)
SELECT
  node_id,
  application_name,
  active_query_start,
  now() - active_query_start as duration,
  left(active_queries, 80) as query_preview
FROM [SHOW CLUSTER SESSIONS]
WHERE active_query_start IS NOT NULL
  AND now() - active_query_start > INTERVAL '5 minutes'
ORDER BY duration DESC;
```

**Common causes**: Missing indexes, large batch operations, transactions holding locks, application bugs.


## Connection Pool Imbalance Detection

### Scenario: Load Balancer Verification

**Check if connections are evenly distributed** (indicates proper load balancing):

```sql
-- Calculate distribution statistics
WITH node_counts AS (
  SELECT
    node_id,
    count(*) as session_count
  FROM [SHOW CLUSTER SESSIONS]
  GROUP BY node_id
),
stats AS (
  SELECT
    avg(session_count) as avg_sessions,
    max(session_count) as max_sessions,
    min(session_count) as min_sessions
  FROM node_counts
)
SELECT
  n.node_id,
  n.session_count,
  s.avg_sessions,
  ROUND(n.session_count / s.avg_sessions, 2) as ratio_to_avg
FROM node_counts n, stats s
ORDER BY n.node_id;
```

**Healthy distribution**:
```
 node_id | session_count | avg_sessions | ratio_to_avg
---------+---------------+--------------+--------------
       1 |            45 |        45.0  |         1.00
       2 |            47 |        45.0  |         1.04
       3 |            43 |        45.0  |         0.96
```

**Unhealthy distribution**:
```
 node_id | session_count | avg_sessions | ratio_to_avg
---------+---------------+--------------+--------------
       1 |           120 |        44.3  |         2.71   -- Alert!
       2 |             8 |        44.3  |         0.18
       3 |             5 |        44.3  |         0.11
```

**Alert threshold**: `ratio_to_avg > 1.5` or `ratio_to_avg < 0.5`

### Load Balancer Configuration Issues

Check if applications bypass load balancer or pin to specific nodes:

```sql
-- Applications using only one node
SELECT
  application_name,
  count(DISTINCT node_id) as nodes_used,
  count(*) as total_sessions
FROM [SHOW CLUSTER SESSIONS]
GROUP BY application_name
HAVING count(DISTINCT node_id) = 1 AND count(*) > 10;
```

### Connection Pool Sizing Analysis

**Detect over-provisioned pools**:

```sql
-- Compare active vs idle sessions per application
SELECT
  application_name,
  count(*) as total_sessions,
  count(*) FILTER (WHERE active_queries != '') as active_sessions,
  count(*) FILTER (WHERE active_queries = '') as idle_sessions,
  ROUND(100.0 * count(*) FILTER (WHERE active_queries = '') / count(*), 1) as idle_percent
FROM [SHOW CLUSTER SESSIONS]
GROUP BY application_name
HAVING count(*) > 10
ORDER BY idle_percent DESC;
```

**Interpretation**:
```
 application_name | total | active | idle | idle_percent
------------------+-------+--------+------+--------------
 webapp_prod      |   100 |     12 |   88 |        88.0%  -- Over-provisioned!
 api_service      |    50 |     35 |   15 |        30.0%  -- Healthy
 batch_worker     |    20 |     18 |    2 |        10.0%  -- Optimal
```

**Recommendations**:
- **> 80% idle**: Reduce connection pool size
- **30-50% idle**: Healthy buffer for burst traffic
- **< 10% idle**: Consider increasing pool size (if performance issues)

## Common Session Issues

### Stuck Queries (> 10 minutes)

```sql
SELECT
  node_id,
  active_query_start,
  now() - active_query_start as duration,
  left(active_queries, 80) as query_preview
FROM [SHOW CLUSTER SESSIONS]
WHERE active_query_start IS NOT NULL
  AND now() - active_query_start > INTERVAL '10 minutes'
ORDER BY duration DESC;
```

**Resolution**: Use `EXPLAIN` to check query plan, cancel with `CANCEL QUERY`, add missing indexes.

### Abandoned Sessions (> 1 hour idle)

```sql
SELECT
  session_id,
  session_start,
  now() - session_start as age
FROM [SHOW CLUSTER SESSIONS]
WHERE now() - session_start > INTERVAL '1 hour'
  AND active_queries = ''
ORDER BY age DESC;
```

**Resolution**: Cancel with `CANCEL SESSION`, configure `sql.defaults.idle_in_session_timeout`, fix application connection handling.


## Best Practices

### Key Cluster Settings

```sql
-- Close idle sessions after 2 hours
SET CLUSTER SETTING sql.defaults.idle_in_session_timeout = '2h';

-- Limit connections per node
SET CLUSTER SETTING server.max_connections_per_gateway = 1000;

-- Close idle transactions after 10 minutes
SET CLUSTER SETTING sql.defaults.idle_in_transaction_session_timeout = '10m';
```

### Connection Pool Configuration

- **Min connections**: 5-10
- **Max connections**: 20-50 per instance
- **Max lifetime**: 30 minutes
- **Idle timeout**: 5 minutes
- **Always set application_name** in connection string

## Key Alert Queries

```sql
-- Alert 1: Connection imbalance (node > 2x average)
WITH stats AS (
  SELECT node_id, count(*) as cnt,
         avg(count(*)) OVER () as avg_cnt
  FROM [SHOW CLUSTER SESSIONS]
  GROUP BY node_id
)
SELECT node_id FROM stats WHERE cnt > 2 * avg_cnt;

-- Alert 2: Long-running queries (> 30 min)
SELECT count(*) FROM [SHOW CLUSTER SESSIONS]
WHERE now() - active_query_start > INTERVAL '30 minutes';

-- Alert 3: Connection pool exhaustion (> 80%)
SELECT node_id, count(*) as sessions
FROM [SHOW CLUSTER SESSIONS]
GROUP BY node_id
HAVING count(*) > 800;  -- If max = 1000

-- Alert 4: Abandoned sessions (idle > 4 hours)
SELECT count(*) FROM [SHOW CLUSTER SESSIONS]
WHERE active_queries = ''
  AND now() - session_start > INTERVAL '4 hours';
```

## Troubleshooting Scenarios

### All Connections on One Node

**Diagnosis**: Check load balancer config, verify application connection string points to load balancer, check node reachability.

**Resolution**: Fix load balancer, update connection string, restart application.

### Excessive Idle Connections (> 80%)

**Diagnosis**: Check connection pool size in application config, identify applications with highest idle percentage.

**Resolution**: Reduce pool max size, configure idle timeout, enable pool shrinking.

### Long-Running Queries Blocking Drain

**Diagnosis**: Identify long-running queries, determine if safe to cancel.

**Resolution**:
```sql
-- Cancel specific query or session
CANCEL QUERY '<session_id>';
CANCEL SESSION '<session_id>';

-- Or increase drain-wait time
cockroach node drain 1 --drain-wait=30m
```

## Related Skills

- `manage-active-connections-and-sessions` - Session management and cancellation
- `verify-connection-draining-completion` - Validate drain completed
- `configure-connection-limits` - Set connection limits
- `cancel-long-running-queries-and-sessions` - Cancel problematic sessions
- `inspect-active-sessions-and-connections` - Deep session inspection

## Documentation

- Session Management: https://www.cockroachlabs.com/docs/stable/show-sessions.html
- Connection Pooling: https://www.cockroachlabs.com/docs/stable/connection-pooling.html
- Node Drain: https://www.cockroachlabs.com/docs/stable/node-shutdown.html
- Cluster Settings: https://www.cockroachlabs.com/docs/stable/cluster-settings.html
