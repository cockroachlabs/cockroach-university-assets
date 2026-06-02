---
name: monitor-storage-capacity-and-growth
description: Can track total storage used, available capacity, and growth trends using DB Console Capacity metrics or crdb_internal.kv_store_status. Forecast when additional capacity needed based on growth rate. Alert at <20% free space. Use when user says "check disk space", "storage capacity", "disk usage", "capacity planning", "storage forecast".
metadata:
  domain: Monitoring and Alerting
  tags: capacity, storage, monitoring, alerting, forecasting
  blooms_level: Apply
  version: 1.1.0
  min_crdb_version: 26.1.0
---

# Monitor Storage Capacity and Growth

Tracks disk usage across all cluster nodes and forecasts capacity needs to prevent disk-full scenarios that can cause node failures and cluster instability.

## Overview

Storage capacity monitoring prevents disk-full scenarios that cause node shutdowns and data corruption. This skill covers monitoring usage, tracking growth, forecasting capacity needs, and setting alerting thresholds.

## Storage Metrics Architecture

### Key Capacity Metrics

- **capacity.used**: Total bytes used (data + logs + temp files)
- **capacity.available**: Bytes available for use
- **capacity**: Total disk capacity allocated
- **capacity.reserved**: Reserved bytes (ballast files)
- **livebytes**: Live data (excludes MVCC versions)
- **sysbytes**: System metadata
- **intentbytes**: Uncommitted write intents
- **valbytes**: Total value bytes (including MVCC versions)

> **Note**: All metric names in v26.1+ are lowercase (e.g., `livebytes` not `liveBytes`).

### Data Sources

- **DB Console**: `http://<node-address>:8080/#/metrics/storage` - visual graphs and trends
- **crdb_internal.kv_store_status**: SQL-queryable metrics per store
- **Prometheus**: `/_status/vars` endpoint for metrics export

## Basic Storage Monitoring

### Check Current Storage Usage

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'capacity.used')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as used_gb,
  (metrics->>'capacity.available')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as available_gb,
  (metrics->>'capacity')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as total_gb,
  ROUND(
    ((metrics->>'capacity.used')::FLOAT /
     (metrics->>'capacity')::FLOAT * 100.0)::NUMERIC,
    2
  ) as used_percent
FROM crdb_internal.kv_store_status
ORDER BY used_percent DESC;
```

### Identify Nodes Approaching Capacity

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'capacity.used')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as used_gb,
  (metrics->>'capacity.available')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as available_gb,
  ROUND(
    ((metrics->>'capacity.used')::FLOAT /
     (metrics->>'capacity')::FLOAT * 100.0)::NUMERIC,
    2
  ) as used_percent,
  CASE
    WHEN ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.95 THEN 'EMERGENCY'
    WHEN ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.90 THEN 'CRITICAL'
    WHEN ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.80 THEN 'WARNING'
    ELSE 'OK'
  END as status
FROM crdb_internal.kv_store_status
WHERE ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.80
ORDER BY used_percent DESC;
```

### Detailed Capacity Breakdown

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'capacity')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as total_gb,
  (metrics->>'capacity.used')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as used_gb,
  (metrics->>'capacity.available')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as available_gb,
  (metrics->>'livebytes')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as live_data_gb,
  (metrics->>'sysbytes')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as system_gb,
  (metrics->>'valbytes')::FLOAT::BIGINT / (1024::FLOAT*1024*1024) as value_bytes_gb,
  (metrics->>'intentbytes')::FLOAT::BIGINT / (1024::FLOAT*1024) as intent_mb,
  ROUND(
    ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT * 100.0)::NUMERIC,
    2
  ) as used_percent
FROM crdb_internal.kv_store_status
ORDER BY node_id, store_id;
```

## Growth Trend Analysis

### Track Growth Over Time

Create a tracking table and schedule periodic data collection (hourly via cron):

```sql
CREATE TABLE IF NOT EXISTS capacity_tracking (
  recorded_at TIMESTAMP DEFAULT now(),
  node_id INT,
  store_id INT,
  used_bytes BIGINT,
  available_bytes BIGINT,
  total_bytes BIGINT,
  live_bytes BIGINT,
  PRIMARY KEY (recorded_at, node_id, store_id)
);

INSERT INTO capacity_tracking (node_id, store_id, used_bytes, available_bytes, total_bytes, live_bytes)
SELECT
  node_id,
  store_id,
  (metrics->>'capacity.used')::FLOAT::BIGINT,
  (metrics->>'capacity.available')::FLOAT::BIGINT,
  (metrics->>'capacity')::FLOAT::BIGINT,
  (metrics->>'livebytes')::FLOAT::BIGINT
FROM crdb_internal.kv_store_status;
```

### Calculate Average Growth Rate (30-day)

```sql
WITH date_range AS (
  SELECT
    node_id,
    store_id,
    MIN(recorded_at) as first_time,
    MAX(recorded_at) as latest_time,
    MIN(used_bytes) as first_bytes,
    MAX(used_bytes) as latest_bytes
  FROM capacity_tracking
  WHERE recorded_at > now() - INTERVAL '30 days'
  GROUP BY node_id, store_id
)
SELECT
  node_id,
  store_id,
  (latest_bytes - first_bytes)::FLOAT / (1024::FLOAT*1024*1024) as total_growth_gb,
  EXTRACT(EPOCH FROM (latest_time - first_time))::FLOAT / 86400::FLOAT as days_measured,
  ((latest_bytes - first_bytes)::FLOAT / (1024::FLOAT*1024*1024)) /
    NULLIF(EXTRACT(EPOCH FROM (latest_time - first_time))::FLOAT / 86400::FLOAT, 0) as avg_daily_growth_gb
FROM date_range
WHERE first_time < latest_time
ORDER BY avg_daily_growth_gb DESC;
```

## Capacity Forecasting

### Forecast Time to Full Disk

```sql
SET allow_unsafe_internals = true;

WITH current_capacity AS (
  SELECT
    node_id,
    store_id,
    (metrics->>'capacity.used')::FLOAT::BIGINT as used_bytes,
    (metrics->>'capacity.available')::FLOAT::BIGINT as available_bytes,
    (metrics->>'capacity')::FLOAT::BIGINT as total_bytes
  FROM crdb_internal.kv_store_status
),
growth_rate AS (
  SELECT
    node_id,
    store_id,
    AVG((max_used_bytes - prev_used_bytes)::FLOAT /
        EXTRACT(EPOCH FROM (max_time - prev_time))) as bytes_per_second
  FROM (
    SELECT
      node_id,
      store_id,
      MAX(used_bytes) as max_used_bytes,
      MAX(recorded_at) as max_time,
      LAG(MAX(used_bytes)) OVER (PARTITION BY node_id, store_id ORDER BY DATE(recorded_at)) as prev_used_bytes,
      LAG(MAX(recorded_at)) OVER (PARTITION BY node_id, store_id ORDER BY DATE(recorded_at)) as prev_time
    FROM capacity_tracking
    WHERE recorded_at > now() - INTERVAL '30 days'
    GROUP BY node_id, store_id, DATE(recorded_at)
  ) daily_stats
  WHERE prev_used_bytes IS NOT NULL
  GROUP BY node_id, store_id
)
SELECT
  c.node_id,
  c.store_id,
  c.used_bytes::FLOAT / (1024::FLOAT*1024*1024) as current_used_gb,
  c.available_bytes::FLOAT / (1024::FLOAT*1024*1024) as available_gb,
  (c.used_bytes::FLOAT / c.total_bytes::FLOAT * 100.0) as current_used_percent,
  (g.bytes_per_second * 86400::FLOAT / (1024::FLOAT*1024*1024)) as daily_growth_gb,
  (c.available_bytes::FLOAT / g.bytes_per_second / 86400::FLOAT) as days_until_full,
  (now() + ((c.available_bytes::FLOAT / g.bytes_per_second)::INT || ' seconds')::INTERVAL)::DATE as estimated_full_date
FROM current_capacity c
JOIN growth_rate g ON c.node_id = g.node_id AND c.store_id = g.store_id
WHERE g.bytes_per_second > 0
ORDER BY days_until_full NULLS LAST;
```

### Forecast When to Add Capacity (80% Threshold)

```sql
SET allow_unsafe_internals = true;

WITH current_capacity AS (
  SELECT
    node_id,
    store_id,
    (metrics->>'capacity.used')::FLOAT::BIGINT as used_bytes,
    (metrics->>'capacity')::FLOAT::BIGINT as total_bytes
  FROM crdb_internal.kv_store_status
),
growth_rate AS (
  SELECT
    node_id,
    store_id,
    AVG((max_used_bytes - prev_used_bytes)::FLOAT /
        EXTRACT(EPOCH FROM (max_time - prev_time))) as bytes_per_second
  FROM (
    SELECT
      node_id,
      store_id,
      MAX(used_bytes) as max_used_bytes,
      MAX(recorded_at) as max_time,
      LAG(MAX(used_bytes)) OVER (PARTITION BY node_id, store_id ORDER BY DATE(recorded_at)) as prev_used_bytes,
      LAG(MAX(recorded_at)) OVER (PARTITION BY node_id, store_id ORDER BY DATE(recorded_at)) as prev_time
    FROM capacity_tracking
    WHERE recorded_at > now() - INTERVAL '30 days'
    GROUP BY node_id, store_id, DATE(recorded_at)
  ) daily_stats
  WHERE prev_used_bytes IS NOT NULL
  GROUP BY node_id, store_id
)
SELECT
  c.node_id,
  c.store_id,
  (c.used_bytes::FLOAT / c.total_bytes::FLOAT * 100.0) as current_used_percent,
  (c.total_bytes::FLOAT * 0.8 - c.used_bytes::FLOAT) / (1024::FLOAT*1024*1024) as gb_until_80_percent,
  ((c.total_bytes::FLOAT * 0.8 - c.used_bytes::FLOAT) / g.bytes_per_second / 86400::FLOAT) as days_until_80_percent,
  (now() + (((c.total_bytes::FLOAT * 0.8 - c.used_bytes::FLOAT) / g.bytes_per_second)::INT || ' seconds')::INTERVAL)::DATE as estimated_80_percent_date
FROM current_capacity c
JOIN growth_rate g ON c.node_id = g.node_id AND c.store_id = g.store_id
WHERE c.used_bytes < c.total_bytes::FLOAT * 0.8
  AND g.bytes_per_second > 0
ORDER BY days_until_80_percent NULLS LAST;
```

## Alerting Thresholds

### Recommended Alert Levels

- **Warning (80%)**: Start capacity planning, schedule expansion within 2-4 weeks
- **Critical (90%)**: Immediate planning required, expand within 1 week
- **Emergency (95%)**: Urgent action, node may shut down if disk fills

### Alert Query Template

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'capacity.used')::FLOAT / (1024::FLOAT*1024*1024) as used_gb,
  (metrics->>'capacity.available')::FLOAT / (1024::FLOAT*1024*1024) as available_gb,
  (metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT * 100.0 as used_percent,
  CASE
    WHEN ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.95 THEN 'EMERGENCY: Add capacity immediately!'
    WHEN ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.90 THEN 'CRITICAL: Add capacity within 1 week'
    WHEN ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.80 THEN 'WARNING: Plan capacity expansion'
    ELSE 'OK'
  END as alert_level,
  (metrics->>'capacity.available')::FLOAT / (1024::FLOAT*1024*1024) as gb_remaining
FROM crdb_internal.kv_store_status
WHERE ((metrics->>'capacity.used')::FLOAT / (metrics->>'capacity')::FLOAT) > 0.80
ORDER BY used_percent DESC;
```

## Ballast Files and Emergency Space

Ballast files are pre-allocated empty files deleted in emergencies to free space for critical operations.

```bash
ls -lh <store-path>/ballast  # Check ballast file status
```

Recommended: 5-10 GB per store or 10% of store capacity. See `configure-and-manage-ballast-files` skill for details.

## Troubleshooting Storage Issues

### High Disk Usage Investigation

Check for excessive MVCC versions:

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  (metrics->>'livebytes')::FLOAT / (1024::FLOAT*1024*1024) as live_gb,
  (metrics->>'valbytes')::FLOAT / (1024::FLOAT*1024*1024) as total_value_gb,
  ((metrics->>'valbytes')::FLOAT - (metrics->>'livebytes')::FLOAT) / (1024::FLOAT*1024*1024) as garbage_gb,
  (((metrics->>'valbytes')::FLOAT - (metrics->>'livebytes')::FLOAT) /
   NULLIF((metrics->>'valbytes')::FLOAT, 0) * 100.0) as garbage_percent
FROM crdb_internal.kv_store_status
ORDER BY garbage_percent DESC;
```

Adjust GC TTL if needed (impacts point-in-time recovery window):

```sql
-- GC TTL is configured per zone in v26.1+, not as a cluster setting
SHOW ZONE CONFIGURATION FOR RANGE default;

-- To modify GC TTL (default is 14400 seconds = 4 hours):
ALTER RANGE default CONFIGURE ZONE USING gc.ttlseconds = 14400;
```

### Uneven Storage Distribution

```sql
SET allow_unsafe_internals = true;

WITH store_stats AS (
  SELECT
    node_id,
    store_id,
    (metrics->>'capacity.used')::FLOAT::BIGINT as used_bytes
  FROM crdb_internal.kv_store_status
),
cluster_stats AS (
  SELECT AVG(used_bytes) as avg_used FROM store_stats
)
SELECT
  s.node_id,
  s.store_id,
  s.used_bytes::FLOAT / (1024::FLOAT*1024*1024) as used_gb,
  c.avg_used::FLOAT / (1024::FLOAT*1024*1024) as cluster_avg_gb,
  ((s.used_bytes::FLOAT - c.avg_used::FLOAT) / c.avg_used::FLOAT * 100.0) as deviation_percent
FROM store_stats s
CROSS JOIN cluster_stats c
ORDER BY ABS(s.used_bytes::FLOAT - c.avg_used::FLOAT) DESC;
```

If deviation >20%, check rebalancing settings and range distribution.

## Best Practices

1. **Monitor Proactively**: Check capacity weekly, set automated alerts at 80%, 90%, 95%, track growth trends monthly

2. **Plan Capacity Early**: Add capacity at 80% utilization, maintain 20% free space, account for rebalancing overhead

3. **Track Historical Data**: Store metrics for trend analysis, review patterns quarterly, adjust forecasts based on changes

4. **Use Ballast Files**: Configure 5-10 GB per store, test deletion procedure, document emergency response

5. **Optimize Storage**: Review GC settings, implement data archival, use partitioning and zone configs for lifecycle management

6. **Consider Growth Patterns**: Account for seasonal variations, plan for business growth events, include backup storage

7. **Multi-Store Awareness**: Monitor each store independently, plan for uneven distribution during rebalancing

## Related Skills

- `configure-and-manage-ballast-files` - Emergency disk space management
- `monitor-range-distribution` - Understanding data distribution
- `configure-replication-zones` - Managing data placement
- `monitor-cluster-health` - Overall cluster health monitoring
- `troubleshoot-node-failures` - Handling disk-full scenarios

## References

- [CockroachDB Monitoring and Alerting](https://www.cockroachlabs.com/docs/v26.1/monitoring-and-alerting)
- [Storage Capacity](https://www.cockroachlabs.com/docs/v26.1/storage-dashboard)
- [Ballast Files](https://www.cockroachlabs.com/docs/v26.1/cockroach-start#ballast-file)
- [crdb_internal System Catalog](https://www.cockroachlabs.com/docs/v26.1/crdb-internal)
