---
name: enable-and-collect-query-diagnostics-bundles
description: Enable automatic diagnostics collection for slow queries and download bundles containing EXPLAIN ANALYZE output, trace data, and execution metadata for deep troubleshooting
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Enable and Collect Query Diagnostics Bundles

**Domain**: Monitoring and Alerting
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

You will learn to enable automatic diagnostics collection for queries exceeding latency thresholds and download diagnostic bundles containing detailed execution information. This skill covers using both the `crdb_internal.request_statement_bundle()` function and the DB Console UI to collect comprehensive diagnostics including EXPLAIN ANALYZE output, distributed trace data, and execution metadata for troubleshooting slow or problematic queries.

**Key Capabilities**:
- Request automatic diagnostics bundle collection for specific queries
- Configure latency thresholds and expiration intervals
- Collect bundles via SQL and DB Console interfaces
- Download and extract bundle contents
- Analyze EXPLAIN plans, trace data, and execution statistics
- Understand bundle lifecycle and storage management

## Overview

Query diagnostics bundles are comprehensive diagnostic packages automatically collected when a query exceeds specified latency thresholds. Each bundle contains EXPLAIN ANALYZE output, distributed traces, query metadata, environment context, and table statistics snapshots.

**When to Use**:
- Intermittent slow queries that are hard to reproduce manually
- Capturing execution details at the moment of performance degradation
- Analyzing distributed execution patterns across nodes
- Collecting evidence for performance investigations without disrupting workloads

**Bundle Contents**: EXPLAIN ANALYZE output, distributed trace data, statement fingerprint, session variables, cluster settings, and table statistics at execution time.

### v26.1.0 Compatibility Notes

**Session Requirement**: All queries accessing diagnostics system tables require setting `allow_unsafe_internals = true` at the session level.

**Table Locations**:
- Diagnostics requests: `system.statement_diagnostics_requests` (NOT `crdb_internal`)
- Collected bundles: `system.statement_diagnostics` (NOT `crdb_internal`)

**Schema Changes**:
- `system.statement_diagnostics_requests` uses `completed` (BOOL) and `statement_diagnostics_id` instead of `collected_at`
- Statement statistics use `statistics->'statistics'->'runLat'->>'mean'` for latency (not top-level `mean`)

## Requesting Diagnostics Bundles via SQL

### Basic Bundle Request

Use `crdb_internal.request_statement_bundle()` to request automatic collection:

```sql
-- Request bundle for queries matching fingerprint with 500ms latency threshold
SELECT crdb_internal.request_statement_bundle(
  'SELECT * FROM users WHERE email = $1',
  0.5,
  '1h'::INTERVAL
);
```

**Parameters**:
1. **Statement Fingerprint**: Query pattern with parameters replaced by `$1`, `$2`, etc.
2. **Latency Threshold**: Minimum execution time in seconds (e.g., `0.5` = 500ms)
3. **Expiration Interval**: How long to collect bundles before auto-expiring

**Return Value**:
```
request_statement_bundle
--------------------------
true
```

### Finding Statement Fingerprints

Query fingerprints normalize parameters and literals. Find them in statement statistics:

```sql
-- Find fingerprints for slow queries
SET allow_unsafe_internals = true;

SELECT
  fingerprint_id,
  metadata->>'query' AS query_fingerprint,
  (statistics->'statistics'->'runLat'->>'mean')::FLOAT AS mean_latency_sec
FROM crdb_internal.statement_statistics
WHERE (statistics->'statistics'->'runLat'->>'mean')::FLOAT > 1.0
ORDER BY (statistics->'statistics'->'runLat'->>'mean')::FLOAT DESC
LIMIT 10;
```

**Example Output**:
```
  fingerprint_id          |           query_fingerprint           | mean_latency_sec
--------------------------+---------------------------------------+------------------
  12345678901234567890    | SELECT * FROM orders WHERE user_id = $1 | 2.456
  09876543210987654321    | UPDATE inventory SET qty = $1 WHERE id = $2 | 1.823
```

### Setting Latency Thresholds and Expiration

Choose thresholds based on query expectations:

```sql
-- OLTP queries: 100-500ms threshold
SELECT crdb_internal.request_statement_bundle(
  'SELECT id FROM products WHERE sku = $1', 0.1, '30m'::INTERVAL);

-- Analytical queries: 5-30 second threshold
SELECT crdb_internal.request_statement_bundle(
  'SELECT * FROM orders WHERE user_id = $1', 5.0, '2h'::INTERVAL);

-- Debug mode: capture first execution (0 threshold)
SELECT crdb_internal.request_statement_bundle(
  'SELECT * FROM problematic_view', 0, '15m'::INTERVAL);
```

**Expiration Guidelines**: Use 15m-1h for immediate issues, 2-24h for rare intermittent problems.

### Viewing Active Bundle Requests

Check currently active bundle collection requests:

```sql
-- View all active diagnostics requests
SET allow_unsafe_internals = true;

SELECT
  id,
  statement_fingerprint,
  min_execution_latency,
  expires_at,
  completed,
  statement_diagnostics_id,
  requested_at
FROM system.statement_diagnostics_requests
ORDER BY requested_at DESC;
```

**Example Output**:
```
  id | statement_fingerprint              | min_execution_latency |        expires_at         | completed | statement_diagnostics_id |      requested_at
-----+------------------------------------+-----------------------+---------------------------+-----------+--------------------------+---------------------------
  42 | SELECT * FROM orders WHERE id = $1 | 00:00:00.5           | 2026-03-06 15:30:00+00:00 | false     | NULL                     | 2026-03-06 14:00:00+00:00
  41 | UPDATE users SET name = $1         | 00:00:01             | 2026-03-06 14:15:00+00:00 | true      | 12345                    | 2026-03-06 13:00:00+00:00
```

**Key Columns**:
- **id**: Unique request identifier
- **min_execution_latency**: Configured latency threshold
- **expires_at**: When the request will automatically expire
- **completed**: Boolean indicating if bundle was collected
- **statement_diagnostics_id**: ID of collected bundle (NULL if not yet collected)

### Canceling Bundle Requests

Remove a bundle request before it expires:

```sql
-- Cancel a specific diagnostics request by ID
SELECT crdb_internal.cancel_statement_diagnostics_request(42);
```

**When to Cancel**:
- Investigation is complete and bundle was already collected
- Request was created with incorrect fingerprint or threshold
- Need to replace with updated configuration
- Storage or performance concerns

**Check Collection Status**:
```sql
SET allow_unsafe_internals = true;

-- Find requests still waiting for collection
SELECT id, statement_fingerprint, min_execution_latency, expires_at
FROM system.statement_diagnostics_requests
WHERE NOT completed
ORDER BY requested_at DESC;
```

## Collecting Bundles via DB Console

### UI-Based Bundle Collection

1. Navigate to DB Console at `http://<node-address>:8080` → SQL Activity → Statements
2. Locate target statement (sort by latency or search)
3. Click statement row → Diagnostics tab
4. Click "Activate Diagnostics" → configure threshold and expiration → Activate
5. Monitor "Waiting for query" status until bundle collected
6. Click "Download" to get `.zip` file: `statement-bundle-<id>-<timestamp>.zip`

**List Bundles via SQL**:
```sql
SET allow_unsafe_internals = true;

SELECT id, statement_fingerprint, collected_at, error
FROM system.statement_diagnostics
ORDER BY collected_at DESC LIMIT 10;
```

## Understanding Bundle Contents

### Extracting the Bundle

Unzip the downloaded bundle file:

```bash
# Extract bundle contents
unzip statement-bundle-12345-20260306.zip -d diagnostics-analysis/

# View extracted files
ls -la diagnostics-analysis/
```

**Typical Bundle Structure**:
```
diagnostics-analysis/
├── statement.txt           # Original SQL statement
├── plan.txt               # EXPLAIN ANALYZE output
├── trace.json             # Distributed trace data
├── trace.txt              # Human-readable trace
├── env.sql                # Environment settings and schema
└── stats-*.sql            # Table statistics snapshots
```

### Analyzing Bundle Contents

**EXPLAIN ANALYZE Output** (`plan.txt`):
- Compare actual vs estimated row counts (large gaps indicate stale statistics)
- Review KV time and network time for performance bottlenecks
- Check execution mode (vectorized vs row-by-row)
- Identify scanned key ranges and access patterns

**Trace Data** (`trace.json`):
- Extract slow operations using jq: `jq '.spans[] | select(.duration > 100000)'`
- Review operation names: `sql.exec`, `kv.get`, `distsql.flow`
- Identify nodes involved in distributed execution
- Analyze duration in microseconds for each span

**Environment Context** (`env.sql`):
- Session settings affecting execution (timeouts, application name)
- Table and index schemas at execution time
- Constraints and foreign keys

**Table Statistics** (`stats-*.sql`):
- Verify statistics freshness (check `created_at` timestamp)
- Review row counts and distinct counts for selectivity
- Compare to current statistics for staleness detection

## Bundle Storage and Cleanup

**Monitor Storage**:
```sql
SET allow_unsafe_internals = true;

SELECT id, statement_fingerprint, collected_at,
  array_length(bundle_chunks, 1) AS num_chunks,
  error
FROM system.statement_diagnostics
ORDER BY collected_at DESC;
```

**Cleanup Bundles**:
```sql
SET allow_unsafe_internals = true;

-- Delete bundles older than 30 days
DELETE FROM system.statement_diagnostics
WHERE collected_at < (now() - '30 days'::INTERVAL);

-- Delete specific bundle
DELETE FROM system.statement_diagnostics WHERE id = 42;
```

**Storage Considerations**: Average bundle size is 100KB-5MB. Bundles persist until manually deleted. Establish retention policies and download important bundles before cleanup.

## Automatic vs Manual Collection

**Automatic Collection** (via `request_statement_bundle()`):
- Captures real production conditions without manual reproduction
- Collects data at the exact moment of slowness
- Minimal disruption to operations

**Manual Collection** (via `EXPLAIN ANALYZE`):
```sql
EXPLAIN ANALYZE (VERBOSE, DISTSQL)
SELECT * FROM orders WHERE user_id = 'abc123';
```
- Immediate results for reproducible issues
- Full control and iteration during development

## Best Practices

**Request Configuration**:
- Use specific fingerprints targeting exact queries, not broad patterns
- Set realistic thresholds based on query SLOs (OLTP: 100-500ms, analytical: 5-30s)
- Limit expiration windows to 1-2 hours unless tracking rare issues
- Cancel requests after bundle collection completes

**Storage Management**:
- Establish retention policies (e.g., 30-90 days) and automate cleanup
- Download important bundles externally before deletion
- Monitor total storage consumption regularly

**Analysis Workflow**:
- Start with EXPLAIN output (actual vs estimated rows, KV time)
- Check trace data for slow operations and node distribution
- Verify statistics freshness and accuracy
- Compare to known-good baseline execution patterns

**Performance Considerations**:
- Bundle collection has minimal runtime overhead
- Each request captures only the first matching execution
- Avoid overly aggressive thresholds to prevent excessive collection

## Troubleshooting

**Bundle Request Not Collecting**:
- Verify fingerprint exactly matches (including parameter placeholders `$1`, `$2`)
- Lower latency threshold if query never exceeds current setting
- Confirm query is executing during expiration window
- Check if bundle already collected (`completed = true`)

```sql
-- Verify fingerprint and check threshold
SET allow_unsafe_internals = true;

SELECT fingerprint_id, metadata->>'query' AS fingerprint
FROM crdb_internal.statement_statistics
WHERE metadata->>'query' LIKE '%orders%';
```

**Cannot Download Bundle**:
```sql
SET allow_unsafe_internals = true;

-- Verify bundle exists
SELECT id, statement_fingerprint, collected_at, error
FROM system.statement_diagnostics
WHERE id = 42;
```

- Try accessing console through different cluster nodes
- Check browser download blocking and network connectivity
- Check if error column contains diagnostic collection failures

**Bundle Contains Incomplete Data**:
- Query may have failed during execution (check statement.txt for errors)
- Distributed execution may have timed out on some nodes
- Check failed execution counts in statement statistics

**Excessive Storage Consumption**:
```sql
SET allow_unsafe_internals = true;

-- Audit bundles by number of chunks (large bundles have many chunks)
SELECT id, statement_fingerprint, collected_at,
  array_length(bundle_chunks, 1) AS num_chunks
FROM system.statement_diagnostics
ORDER BY array_length(bundle_chunks, 1) DESC NULLS LAST
LIMIT 20;

-- Delete old bundles to free space
DELETE FROM system.statement_diagnostics
WHERE collected_at < (now() - '7 days'::INTERVAL);
```

## Related Skills

- **analyze-query-plans-with-explain**: Understanding EXPLAIN output and execution plans
- **identify-slow-queries-using-statement-statistics**: Finding problematic queries in statement stats
- **troubleshoot-query-performance-issues**: General query performance troubleshooting approach
- **monitor-distributed-sql-execution**: Monitoring DistSQL and distributed query execution
- **configure-statement-timeout-settings**: Setting query timeout protections
- **use-db-console-for-performance-monitoring**: Navigating DB Console for performance analysis

## Summary

Query diagnostics bundles provide automated, comprehensive diagnostic data collection for troubleshooting slow or problematic queries. By configuring latency thresholds and expiration windows using `crdb_internal.request_statement_bundle()` or the DB Console UI, you can capture detailed execution information including EXPLAIN ANALYZE output, distributed traces, and execution metadata exactly when performance issues occur. This enables deep analysis of intermittent problems without manual reproduction, supporting effective performance troubleshooting and optimization efforts.

## Appendix: v26.1.0 Table Schemas

### system.statement_diagnostics_requests

Stores active and completed diagnostics bundle requests.

```
Column Name              | Type        | Description
-------------------------|-------------|------------------------------------------
id                       | INT8        | Unique request identifier
completed                | BOOL        | Whether bundle was collected (default: false)
statement_fingerprint    | STRING      | Query pattern with parameter placeholders
statement_diagnostics_id | INT8        | ID of collected bundle (NULL if not collected)
requested_at             | TIMESTAMPTZ | When request was created
min_execution_latency    | INTERVAL    | Latency threshold for collection
expires_at               | TIMESTAMPTZ | When request auto-expires
sampling_probability     | FLOAT8      | Probability of collection (NULL = 100%)
plan_gist                | STRING      | Plan gist filter (advanced)
anti_plan_gist           | BOOL        | Anti-plan gist flag (advanced)
redacted                 | BOOL        | Whether to redact sensitive data
username                 | STRING      | User who created request
```

**Key Queries**:
```sql
-- Find active requests
SELECT * FROM system.statement_diagnostics_requests WHERE NOT completed;

-- Find completed requests
SELECT * FROM system.statement_diagnostics_requests
WHERE completed AND statement_diagnostics_id IS NOT NULL;
```

### system.statement_diagnostics

Stores collected diagnostics bundles.

```
Column Name               | Type        | Description
--------------------------|-------------|------------------------------------------
id                        | INT8        | Unique bundle identifier
statement_fingerprint     | STRING      | Query pattern for this bundle
statement                 | STRING      | Full statement text
collected_at              | TIMESTAMPTZ | When bundle was collected
trace                     | JSONB       | Distributed trace data
bundle_chunks             | INT8[]      | Array of chunk IDs for bundle data
error                     | STRING      | Error message if collection failed
transaction_diagnostics_id| INT8        | Transaction bundle ID (if applicable)
```

**Key Queries**:
```sql
-- List all bundles
SELECT id, statement_fingerprint, collected_at, error
FROM system.statement_diagnostics
ORDER BY collected_at DESC;

-- Check for failed collections
SELECT id, statement_fingerprint, error
FROM system.statement_diagnostics
WHERE error IS NOT NULL;
```

**Note**: Bundle data is stored in chunks referenced by `bundle_chunks` array. Use DB Console UI to download complete bundle files.
