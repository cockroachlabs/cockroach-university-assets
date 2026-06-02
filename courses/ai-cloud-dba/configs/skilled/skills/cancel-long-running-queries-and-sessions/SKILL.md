---
name: cancel-long-running-queries-and-sessions
description: Identify and cancel problematic queries and sessions impacting cluster performance
metadata:
  domain: Cluster Management
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  tested: true
---

# Cancel Long-Running Queries and Sessions

**Domain**: Cluster Management
**Bloom's Level**: Apply

## What This Skill Teaches

You'll learn to identify, investigate, and cancel long-running queries and sessions that impact cluster performance. This includes using SHOW QUERIES and SHOW SESSIONS to find problematic operations, filtering by various criteria (runtime, memory usage, application), and applying graceful or forced cancellation strategies.

## When to Use This Skill

- **Performance degradation**: Cluster experiencing slowdowns or high resource usage
- **Runaway queries**: Queries consuming excessive memory or CPU time
- **Stuck transactions**: Long-running transactions blocking other operations
- **Application issues**: Misbehaving applications creating connection leaks
- **Maintenance windows**: Clearing active sessions before cluster maintenance
- **Resource contention**: Identifying queries competing for resources

## Core Concepts

### Query States
- **Executing**: Currently running on a node
- **Waiting**: Queued or blocked by contention
- **Idle in transaction**: Open transaction with no active query

### Session vs Query
- **Session**: Connection from client to cluster (may have multiple queries)
- **Query**: Individual SQL statement within a session
- **Canceling query**: Stops current statement, keeps session alive
- **Canceling session**: Terminates connection, rolls back transaction

## Instructions

### 1. Identify Long-Running Queries

```sql
-- Show all active queries with runtime
SHOW QUERIES;

-- Show queries running longer than 1 minute
SELECT query_id, node_id, user_name, application_name,
       start, query, (now() - start) AS duration
FROM [SHOW CLUSTER QUERIES]
WHERE start < (now() - INTERVAL '1 minute')
ORDER BY start;

-- Find longest-running queries
SELECT query_id, node_id, application_name, query,
       (now() - start) AS duration
FROM [SHOW CLUSTER QUERIES]
WHERE (now() - start) > INTERVAL '30 seconds'
ORDER BY (now() - start) DESC
LIMIT 10;
```

### 2. Investigate Query Details

```sql
-- Get full query text and execution plan
SHOW QUERY 'query-id-here';

-- View query execution statistics
SELECT query_id, session_id, application_name,
       start, query, (now() - start) AS duration
FROM [SHOW CLUSTER QUERIES]
WHERE query_id = 'query-id-here';

-- Check query runtime status
SELECT query_id, session_id, (now() - start) AS duration,
       CASE
         WHEN (now() - start) > INTERVAL '5 minutes' THEN 'VERY_SLOW'
         WHEN (now() - start) > INTERVAL '1 minute' THEN 'SLOW_QUERY'
         ELSE 'NORMAL'
       END AS status
FROM [SHOW CLUSTER QUERIES]
WHERE query_id = 'query-id-here';
```

### 3. Filter Queries by Application or User

```sql
-- Find queries from specific application
SELECT query_id, user_name, start, (now() - start) AS duration, query
FROM [SHOW CLUSTER QUERIES]
WHERE application_name = 'myapp'
AND (now() - start) > INTERVAL '30 seconds';

-- Find all queries from specific user
SELECT query_id, application_name, start, (now() - start) AS duration
FROM [SHOW CLUSTER QUERIES]
WHERE user_name = 'reporting_user'
ORDER BY (now() - start) DESC;

-- Identify applications with most long-running queries
SELECT application_name, count(*) AS query_count,
       max(now() - start) AS longest_query
FROM [SHOW CLUSTER QUERIES]
WHERE (now() - start) > INTERVAL '10 seconds'
GROUP BY application_name
ORDER BY query_count DESC;
```

### 4. Identify Problematic Sessions

```sql
-- Show all active sessions
SHOW SESSIONS;

-- Find sessions idle in transaction
SELECT session_id, node_id, user_name, application_name,
       active_queries, last_active_query, session_start
FROM [SHOW CLUSTER SESSIONS]
WHERE active_queries = ''
AND last_active_query != ''
AND (now() - active_query_start) > INTERVAL '5 minutes';

-- Find sessions with multiple active queries
SELECT session_id, application_name, user_name,
       active_queries, session_start
FROM [SHOW CLUSTER SESSIONS]
WHERE active_queries != ''
ORDER BY session_start;

-- Sessions from specific client address
SELECT session_id, client_address, user_name,
       application_name, active_queries
FROM [SHOW CLUSTER SESSIONS]
WHERE client_address LIKE '10.0.1.%';
```

### 5. Cancel Individual Queries

```sql
-- Cancel specific query (graceful)
CANCEL QUERY 'query-id-here';

-- Cancel query on specific node
CANCEL QUERY '17d0e0c38db5cc380000000000000001' ON NODE 1;

-- Cancel multiple queries from application
-- First identify queries
SELECT query_id FROM [SHOW CLUSTER QUERIES]
WHERE application_name = 'batch_processor'
AND (now() - start) > INTERVAL '2 minutes';

-- Then cancel each query (manual or scripted)
CANCEL QUERY 'query-id-1';
CANCEL QUERY 'query-id-2';
```

### 6. Cancel Sessions

```sql
-- Cancel specific session
CANCEL SESSION 'session-id-here';

-- Cancel session on specific node
CANCEL SESSION '17d0e0c38db5cc380000000000000001' ON NODE 1;

-- Force cancel (closes connection immediately)
-- Note: Regular CANCEL SESSION is already forceful
-- Sessions terminate and roll back active transactions
```

### 7. Monitor Cancellation Impact

```sql
-- Verify query was cancelled
SELECT query_id, (now() - start) AS duration
FROM [SHOW CLUSTER QUERIES]
WHERE query_id = 'cancelled-query-id';
-- Should return no results

-- Check for remaining sessions from application
SELECT count(*) AS session_count
FROM [SHOW CLUSTER SESSIONS]
WHERE application_name = 'problematic_app';

-- Monitor cluster performance after cancellation
SELECT * FROM crdb_internal.node_runtime_info;
```

## Common Patterns

### Pattern: Cancel All Queries from Misbehaving Application

```sql
-- 1. Identify application queries
SELECT query_id, (now() - start) AS duration, query
FROM [SHOW CLUSTER QUERIES]
WHERE application_name = 'legacy_app';

-- 2. Cancel longest-running queries first
-- Export query IDs and cancel programmatically
-- Or use cockroach sql with --execute flag in a loop
```

### Pattern: Clear Idle Transactions Before Maintenance

```sql
-- 1. Find idle transactions older than threshold
SELECT session_id, user_name, application_name,
       active_query_start, last_active_query
FROM [SHOW CLUSTER SESSIONS]
WHERE active_queries = ''
AND last_active_query != ''
AND (now() - active_query_start) > INTERVAL '10 minutes';

-- 2. Cancel sessions (rolls back idle transactions)
CANCEL SESSION 'session-id-1';
CANCEL SESSION 'session-id-2';
```

### Pattern: Emergency Memory Pressure Relief

```sql
-- 1. Find queries sorted by estimated resource usage
SELECT query_id, (now() - start) AS duration, application_name,
       substring(query, 1, 100) AS query_preview
FROM [SHOW CLUSTER QUERIES]
WHERE (now() - start) > INTERVAL '30 seconds'
ORDER BY (now() - start) DESC;

-- 2. Cancel top offenders
CANCEL QUERY 'longest-running-query-id';
```

### Pattern: Identify and Cancel Distributed Queries

```sql
-- Distributed queries may show on multiple nodes
SELECT query_id, node_id, (now() - start) AS duration
FROM [SHOW CLUSTER QUERIES]
WHERE query LIKE '%FULL SCAN%'
OR query LIKE '%JOIN%'
ORDER BY (now() - start) DESC;

-- Cancel on any node (cancels entire distributed operation)
CANCEL QUERY 'distributed-query-id';
```

## Troubleshooting

### Query Won't Cancel

**Symptom**: CANCEL QUERY succeeds but query still appears in SHOW QUERIES

**Causes**:
- Query in commit/rollback phase (must complete)
- System-level query (cannot be cancelled)
- Network partition preventing cancellation signal

**Solutions**:
```sql
-- Check query phase
SELECT query_id, (now() - start) AS duration, query
FROM [SHOW CLUSTER QUERIES]
WHERE query_id = 'stuck-query-id';

-- If stuck in commit, wait for completion
-- If truly stuck, cancel entire session instead
CANCEL SESSION 'session-id-for-query';

-- Last resort: restart node (only if query is on single node)
-- Not recommended for production
```

### Cannot Identify Query Source

**Symptom**: Query visible but no clear application_name or user_name

**Investigation**:
```sql
-- Check all query metadata
SELECT * FROM [SHOW CLUSTER QUERIES]
WHERE query_id = 'unknown-query-id';

-- Look for client address patterns
SELECT session_id, client_address, application_name
FROM [SHOW CLUSTER SESSIONS]
WHERE session_id IN (
  SELECT session_id FROM [SHOW CLUSTER QUERIES]
  WHERE query_id = 'unknown-query-id'
);

-- Check if query is internal/system
-- System queries often have empty application_name
```

### Session Immediately Reconnects After Cancel

**Symptom**: Canceling session but connection pool recreates it

**Cause**: Application connection pool auto-reconnects

**Solution**:
- Fix application code or connection pool settings
- Temporarily block at firewall/load balancer level
- Use network policies to rate-limit reconnections

### Permission Denied When Canceling

**Symptom**: User cannot cancel queries from other users

**Cause**: Insufficient privileges

**Solution**:
```sql
-- Admin users can cancel any query/session
-- Non-admin users can only cancel their own

-- Grant admin privilege if needed
GRANT admin TO username;

-- Or cancel as admin user
-- cockroach sql --user=admin
-- CANCEL QUERY 'query-id';
```

## Common Mistakes

1. **Canceling without investigation**: Always identify why query is slow before canceling
2. **Ignoring idle transactions**: "Idle in transaction" sessions hold locks and resources
3. **Canceling critical operations**: Be cautious with DDL, backup/restore, changefeeds
4. **Not monitoring after cancel**: Verify queries don't restart or pile up again
5. **Confusing query_id and session_id**: These are different identifiers
6. **Not checking for retries**: Applications may automatically retry cancelled queries
7. **Canceling during commit**: Queries in commit phase cannot be cancelled

## Best Practices

1. **Set query timeouts**: Use `statement_timeout` cluster setting to auto-cancel slow queries
   ```sql
   SET statement_timeout = '5m';
   SET CLUSTER SETTING sql.defaults.statement_timeout = '10m';
   ```

2. **Monitor proactively**: Set up alerts for long-running queries before they cause issues

3. **Identify patterns**: Track which applications/queries frequently need cancellation

4. **Document thresholds**: Define SLOs for acceptable query runtime

5. **Use application_name**: Ensure applications set meaningful names for easier filtering
   ```sql
   -- In connection string
   -- postgresql://user@host/db?application_name=my_service
   ```

6. **Graceful degradation**: Cancel queries in order of severity (longest first)

7. **Communicate with users**: Notify application teams before canceling their queries

8. **Test cancellation**: Verify applications handle query cancellation gracefully

9. **Log cancellations**: Keep audit trail of what was cancelled and why

10. **Review query plans**: Use EXPLAIN to understand why queries are slow

## Performance Considerations

- `SHOW QUERIES` and `SHOW SESSIONS` are lightweight operations
- `SHOW CLUSTER QUERIES/SESSIONS` query all nodes (slightly more expensive)
- Cancellation is immediate but cleanup may take time
- Cancelled queries still consume resources until fully terminated
- Large result sets may take time to abort

## Security Considerations

- Only admin users can cancel queries from other users
- Regular users can only cancel their own queries/sessions
- Audit cancellations in security-sensitive environments
- Be cautious canceling queries that may contain sensitive data in progress

## Related Skills

- **monitor-query-performance**: Identify slow queries before they become problematic
- **configure-statement-timeout**: Set automatic query cancellation thresholds
- **analyze-query-execution-plans**: Understand why queries run slowly
- **manage-connection-pools**: Prevent session leaks and connection exhaustion
- **monitor-transaction-contention**: Identify blocking transactions
- **troubleshoot-performance-issues**: Systematic approach to cluster slowdowns
- **use-cluster-observability-tools**: Monitoring dashboards and metrics
- **manage-user-privileges**: Control who can cancel queries

## Additional Resources

- [CockroachDB Docs: SHOW QUERIES](https://www.cockroachlabs.com/docs/stable/show-queries.html)
- [CockroachDB Docs: SHOW SESSIONS](https://www.cockroachlabs.com/docs/stable/show-sessions.html)
- [CockroachDB Docs: CANCEL QUERY](https://www.cockroachlabs.com/docs/stable/cancel-query.html)
- [CockroachDB Docs: CANCEL SESSION](https://www.cockroachlabs.com/docs/stable/cancel-session.html)
- [CockroachDB Docs: Statement Timeout](https://www.cockroachlabs.com/docs/stable/set-vars.html#statement-timeout)

## Examples

### Example 1: Cancel All Queries Older Than 10 Minutes

```sql
-- Identify long-running queries
SELECT query_id, user_name, application_name,
       (now() - start) AS duration, substring(query, 1, 100)
FROM [SHOW CLUSTER QUERIES]
WHERE (now() - start) > INTERVAL '10 minutes'
ORDER BY (now() - start) DESC;

-- Cancel each query (script this for multiple queries)
CANCEL QUERY '17d0e0c38db5cc380000000000000001';
CANCEL QUERY '17d0e0c38db5cc390000000000000002';
```

### Example 2: Clear All Sessions from Decommissioned Application

```sql
-- Find sessions
SELECT session_id, client_address, session_start
FROM [SHOW CLUSTER SESSIONS]
WHERE application_name = 'old_reporting_app';

-- Cancel all sessions
CANCEL SESSION 'session-id-1';
CANCEL SESSION 'session-id-2';
CANCEL SESSION 'session-id-3';
```

### Example 3: Emergency Response to Memory Pressure

```sql
-- Find resource-intensive queries
SELECT query_id, (now() - start) AS duration,
       application_name, node_id
FROM [SHOW CLUSTER QUERIES]
ORDER BY (now() - start) DESC
LIMIT 5;

-- Cancel top 3 offenders
CANCEL QUERY 'query-id-1';
CANCEL QUERY 'query-id-2';
CANCEL QUERY 'query-id-3';

-- Verify improvement
SELECT node_id, used_bytes, available_bytes
FROM crdb_internal.node_runtime_info;
```
