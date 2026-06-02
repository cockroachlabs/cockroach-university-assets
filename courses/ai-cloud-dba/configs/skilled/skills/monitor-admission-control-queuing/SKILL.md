---
name: monitor-admission-control-queuing
description: Monitor admission control queue depths and wait times using DB Console Queues dashboard or crdb_internal.node_metrics. High queuing indicates cluster overload or insufficient capacity. Track queue length and wait duration metrics to detect performance bottlenecks.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Analyze
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - monitoring
    - performance
    - admission-control
    - capacity-planning
    - troubleshooting
---

# Monitor Admission Control Queuing

## Overview

Admission control prevents cluster overload by queuing requests when resources (disk, CPU, memory) are constrained. Monitoring queue depths and wait times helps detect capacity issues before performance degrades.

**Key insight**: Brief queuing during traffic spikes is normal. Sustained queuing over minutes indicates insufficient capacity.

## Important for v26.1.0+

**Table Access**: Admission control metrics are stored in `crdb_internal.node_metrics`, which requires:

```sql
SET allow_unsafe_internals = true;
```

This must be run at the start of every session before querying admission control metrics.

**Metric Structure**: Metrics use name-value pairs:
- **name**: Metric identifier (e.g., `admission.wait_queue_length.kv`)
- **value**: Metric value (queue depth, wait time in nanoseconds, admission counts)

**Wait Time Units**: Wait duration metrics are in **nanoseconds**. To convert to milliseconds, divide by 1,000,000.

**All SQL examples in this skill assume `SET allow_unsafe_internals = true;` has been run.**

## Use Cases

- Monitor cluster load and detect overload conditions
- Troubleshoot sudden latency increases
- Plan capacity expansion based on queue metrics
- Alert on sustained queuing
- Distinguish between healthy operation and overload

## Core Concepts

### Queue Types

**KV Queue (Storage Layer)**
- Queues write operations when disk I/O saturated
- Indicates disk bandwidth or IOPS bottleneck

**SQL Queue (Query Processing)**
- Queues SQL queries when CPU or memory saturated
- Indicates compute bottleneck

**SQL Response Queue**
- Queues when network bandwidth constrained (less common)

### How It Works

**Normal load**: Requests execute immediately, no queuing

**High load**: Requests queue until resources available
- Queue depth and wait time increase
- Requests execute when resources free up

**Critical threshold**: Queues persist for minutes (not seconds)

## Instructions

### Method 1: Current Queue Status

```sql
SET allow_unsafe_internals = true;

-- View all queues with current depth
SELECT name, value as queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND value > 0
ORDER BY value DESC;
```

**Output columns**:
- `name`: Metric name (e.g., `admission.wait_queue_length.kv`)
- `queue_depth`: Number of requests currently queued

### Method 2: KV vs SQL Queue Analysis

```sql
SET allow_unsafe_internals = true;

-- Compare queue depths by layer
SELECT
  CASE
    WHEN name LIKE '%kv-stores%' THEN 'KV Stores Layer'
    WHEN name LIKE '%kv%' THEN 'KV Layer'
    WHEN name LIKE '%sql%' THEN 'SQL Layer'
    WHEN name LIKE '%elastic%' THEN 'Elastic Layer'
    ELSE 'Other'
  END as layer,
  COUNT(*) as metric_count,
  AVG(value) as avg_queue_depth,
  MAX(value) as max_queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
GROUP BY layer
ORDER BY max_queue_depth DESC;
```

**Layers explained**:
- **KV Layer**: Write operations to the storage layer
- **KV Stores Layer**: Storage engine operations
- **SQL Layer**: SQL query processing
- **Elastic Layer**: Background/elastic workloads

### Method 3: DB Console Queues Dashboard

1. Navigate to `https://<node-address>:8080`
2. Click **Metrics** → **Queues**
3. View: KV Work Queue Length, SQL Work Queue Length, Wait Times

**Healthy**: Zero/near-zero queuing, occasional spikes
**Warning**: Sustained elevation
**Critical**: Growing queue depth

### Method 4: Queue Metrics with Wait Times

```sql
SET allow_unsafe_internals = true;

-- Queue depths with corresponding wait times
SELECT
  CASE
    WHEN name LIKE '%kv-stores%' THEN 'KV Stores'
    WHEN name LIKE '%kv%' THEN 'KV'
    WHEN name LIKE '%sql%' THEN 'SQL'
    WHEN name LIKE '%elastic%' THEN 'Elastic'
  END as layer,
  name as metric_name,
  value as queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND value > 0
ORDER BY value DESC;

-- View wait durations separately
SELECT
  CASE
    WHEN name LIKE '%kv-stores%' THEN 'KV Stores'
    WHEN name LIKE '%kv%' THEN 'KV'
    WHEN name LIKE '%sql%' THEN 'SQL'
    WHEN name LIKE '%elastic%' THEN 'Elastic'
  END as layer,
  ROUND(AVG(value) / 1000000.0, 2) as avg_wait_ms,
  ROUND(MAX(value) / 1000000.0, 2) as max_wait_ms
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_durations.%-avg'
   OR name LIKE 'admission.wait_durations.%-max'
GROUP BY layer
ORDER BY max_wait_ms DESC;
```

**Note**: Queue depths and wait times are tracked in separate metrics and may need to be queried separately or combined using JOINs.

## Key Admission Control Metrics

| Metric Pattern | Description | Healthy | Warning | Critical |
|----------------|-------------|---------|---------|----------|
| **admission.wait_queue_length.*** | Queue depth (count) | 0-5 | 5-50 | > 50 |
| **admission.wait_durations.*-avg** | Avg wait time (nanoseconds) | < 10ms (10M ns) | 10-100ms (10M-100M ns) | > 100ms (> 100M ns) |
| **admission.wait_durations.*-max** | Max wait time (nanoseconds) | < 50ms (50M ns) | 50-200ms | > 200ms |
| **admission.admitted.*** | Requests admitted (cumulative count) | Growing steadily | Plateauing | Stalled |
| **admission.errored.*** | Failed requests (count) | 0 | > 0 | Growing |

## Understanding Queue Metrics

**admission.wait_queue_length.***: Number of queued requests
- Normal: 0-5, brief spikes
- Warning: Sustained > 10
- Critical: > 50 and growing

**admission.wait_durations.*-avg**: Average queue wait time (nanoseconds)
- Normal: < 10ms (< 10,000,000 ns)
- Warning: > 50ms (> 50,000,000 ns)
- Critical: > 100ms (> 100,000,000 ns)

**admission.admitted.***: Cumulative count of admitted requests
- Normal: Growing steadily
- Warning: Growth rate decreasing while queue grows
- Critical: Stalled or near-zero growth

**Common queue types**:
- `.kv` - KV layer operations
- `.kv-stores` - Storage engine operations
- `.sql-kv-response` - SQL responses from KV layer
- `.sql-sql-response` - SQL query responses
- `.elastic-cpu` - Elastic CPU workloads
- `.elastic-stores` - Elastic storage workloads

## Example: Complete Admission Control Health Check

```sql
SET allow_unsafe_internals = true;

-- Comprehensive admission control monitoring
SELECT
  'Current Queue Status' as check_name,
  COUNT(*) as metric_count,
  SUM(value) as total_queued,
  MAX(value) as max_queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND value > 0

UNION ALL

SELECT
  'KV Layer Queuing',
  COUNT(*),
  SUM(value),
  MAX(value)
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND (name LIKE '%kv-stores%' OR name LIKE '%\.kv\.')
  AND value > 0

UNION ALL

SELECT
  'SQL Layer Queuing',
  COUNT(*),
  SUM(value),
  MAX(value)
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND name LIKE '%sql%'
  AND value > 0;
```

**Expected output when healthy**: Empty result set (no queuing)

**Expected output during load**: Shows metric counts and queue depths per layer

## Detecting Cluster Overload

| Status | Queue Depth (value) | Avg Wait (ns) | Admitted Count Growth | Duration |
|--------|---------------------|---------------|-----------------------|----------|
| **Healthy** | 0-2 | < 1M ns (< 1ms) | Steady | N/A |
| **Moderate** | 3-10 | 1M-10M ns (1-10ms) | Steady | Seconds |
| **Warning** | 10-50 | 10M-100M ns (10-100ms) | Slowing | Minutes |
| **Critical** | > 50 | > 100M ns (> 100ms) | Stalled, errors | Sustained |

## Alert Thresholds

### Warning Alert (queue_depth > 10)

```sql
SET allow_unsafe_internals = true;

SELECT
  'Warning: Admission control queuing' as alert,
  name as metric_name,
  value as queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND value > 10
ORDER BY value DESC;
```

**Action**: Monitor for 5-10 min, review workload, prepare to scale

**To check wait times**:
```sql
SET allow_unsafe_internals = true;

SELECT
  name as metric_name,
  ROUND(value / 1000000.0, 2) as avg_wait_ms
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_durations.%-avg'
  AND value > 10000000  -- > 10ms
ORDER BY value DESC;
```

### Critical Alert (queue_depth > 50 OR wait > 100ms)

```sql
SET allow_unsafe_internals = true;

-- Check for severe queue depth
SELECT
  'CRITICAL: Severe queue depth' as alert,
  name as metric_name,
  value as queue_depth,
  NULL::FLOAT as avg_wait_ms
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND value > 50

UNION ALL

-- Check for high wait times (> 100ms = 100,000,000 ns)
SELECT
  'CRITICAL: High wait time' as alert,
  name as metric_name,
  NULL::FLOAT as queue_depth,
  ROUND(value / 1000000.0, 2) as avg_wait_ms
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_durations.%-avg'
  AND value > 100000000
ORDER BY queue_depth DESC NULLS LAST;
```

**Action**: Immediate investigation, identify bottleneck, scale urgently

## Troubleshooting High Queuing

### Problem: KV Queue Depth High

**Diagnosis**:
```sql
SET allow_unsafe_internals = true;

-- Check for KV store queuing
SELECT
  name as metric_name,
  value as queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length.kv-stores%'
  AND value > 0
ORDER BY value DESC;

-- Check disk-related metrics
SELECT name, value
FROM crdb_internal.node_metrics
WHERE name LIKE '%rocksdb%'
   OR name LIKE '%storage.disk%'
ORDER BY name
LIMIT 20;
```

**Common causes**:
- Disk I/O saturated (IOPS or bandwidth)
- Write-heavy workload exceeding disk capacity
- Compaction backlog in storage engine
- Insufficient disk IOPS for workload

**Solutions**:
1. **Upgrade disk**: Move to faster SSDs or more IOPS
2. **Add nodes**: Distribute writes across more disks
3. **Reduce write amplification**: Review schema, reduce indexes
4. **Optimize queries**: Reduce unnecessary writes
5. **Check disk health**: Ensure no failing disks

### Problem: SQL Queue Depth High

**Diagnosis**:
```sql
SET allow_unsafe_internals = true;

-- Check for SQL layer queuing
SELECT
  name as metric_name,
  value as queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length.sql%'
  AND value > 0
ORDER BY value DESC;

-- Check CPU-related metrics
SELECT name, value
FROM crdb_internal.node_metrics
WHERE name LIKE '%sys.cpu%'
   OR name LIKE '%sys.goroutines%'
ORDER BY name
LIMIT 20;
```

**Common causes**:
- CPU saturated from query processing
- Complex queries consuming too much CPU
- Memory pressure causing GC pressure
- Too many concurrent queries

**Solutions**:
1. **Add nodes**: Distribute SQL processing
2. **Optimize queries**: Add indexes, rewrite inefficient queries
3. **Limit concurrency**: Reduce connection pool size
4. **Increase CPU**: Upgrade to larger instance types
5. **Review workload**: Identify expensive queries

### Problem: Sustained Queuing During Peak Hours

**Common causes**:
- Cluster sized for average load, not peak
- Insufficient capacity headroom

**Solutions**:
1. Size for peak + 30% headroom
2. Enable auto-scaling (managed service)
3. Add nodes permanently if peaks are regular
4. Optimize queries to reduce resource usage
5. Rate limit at application layer

## Capacity Planning with Queue Metrics

**Add nodes when**:
- Queue depth > 10 for > 10% of time
- Wait times regularly exceed 10ms
- Queuing occurs during normal load
- admitted_count plateaus despite growing queue

**Capacity calculation example**:
```
Current: 3 nodes, queue depth 20
Request rate: 1000/sec, Admitted: 800/sec
Shortage: 20% → Required: 3 × 1.25 = 5 nodes (with headroom)
```

**Verify after scaling**:
```sql
SET allow_unsafe_internals = true;

-- Check queue depths
SELECT name, value as queue_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND value > 0;

-- Check admission rates
SELECT name, value as admitted_count
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.admitted.%'
ORDER BY value DESC
LIMIT 10;
```

Expect: Queue depth reduced, admitted_count growing steadily

## Best Practices

**Do**:
- Monitor queue metrics in real-time dashboards
- Alert on sustained queuing (> 5 minutes)
- Distinguish KV vs SQL queuing to identify bottleneck
- Size cluster for peak load + 30% headroom
- Correlate queuing with resource utilization

**Don't**:
- Panic at brief queue spikes (seconds)
- Ignore sustained queuing (minutes/hours)
- Add capacity without identifying bottleneck
- Disable admission control (protects cluster health)

## Monitoring Script

```bash
#!/bin/bash
# monitor-admission-control.sh
# Monitor admission control queuing every 30 seconds

CERTS_DIR="/path/to/certs"
HOST="localhost:26258"
COCKROACH_BIN="/path/to/cockroach"

while true; do
  echo "=== Admission Control Status - $(date) ==="

  $COCKROACH_BIN sql --certs-dir=$CERTS_DIR --host=$HOST --execute="
    SET allow_unsafe_internals = true;

    -- Queue depths
    SELECT name, value as queue_depth
    FROM crdb_internal.node_metrics
    WHERE name LIKE 'admission.wait_queue_length%'
      AND value > 0
    ORDER BY value DESC
    LIMIT 10;

    -- Wait times (in milliseconds)
    SELECT
      CASE
        WHEN name LIKE '%kv-stores%' OR name LIKE '%kv-%' THEN 'KV Layer'
        WHEN name LIKE '%sql%' THEN 'SQL Layer'
        WHEN name LIKE '%elastic%' THEN 'Elastic Layer'
        ELSE 'Other'
      END as layer,
      ROUND(AVG(value) / 1000000.0, 2) as avg_wait_ms,
      ROUND(MAX(value) / 1000000.0, 2) as max_wait_ms
    FROM crdb_internal.node_metrics
    WHERE name LIKE 'admission.wait_durations.%-avg'
       OR name LIKE 'admission.wait_durations.%-max'
    GROUP BY layer
    ORDER BY max_wait_ms DESC;
  "

  echo ""
  sleep 30
done
```

**Usage**:
1. Set `CERTS_DIR` to your cluster certificates directory
2. Set `HOST` to your cluster address
3. Set `COCKROACH_BIN` to your cockroach binary path
4. Make executable: `chmod +x monitor-admission-control.sh`
5. Run: `./monitor-admission-control.sh`

## Real-World Scenarios

### Scenario 1: Traffic Spike
**Symptoms**: SQL queue depth spikes to 50, wait times 200ms
**Solution**: Add temporary nodes, pre-warm cluster, throttle at app layer

### Scenario 2: Batch Job Overload
**Symptoms**: KV queue depth 30 during batch window, write saturation
**Solution**: Run during off-peak, throttle batch rate, increase disk IOPS

### Scenario 3: Gradual Capacity Exhaustion
**Symptoms**: Queue depth increasing week over week
**Solution**: Proactive capacity planning, add nodes before critical, optimize queries

## Verification Checklist

Healthy admission control:
- `admission.wait_queue_length.*` is 0 or near-0 most of the time (> 95%)
- `admission.wait_durations.*-avg` < 10ms (< 10,000,000 ns)
- `admission.admitted.*` counts growing steadily
- `admission.errored.*` is zero or near-zero
- Queuing spikes last seconds, not minutes
- No correlation with user-reported latency

**Quick health check**:
```sql
SET allow_unsafe_internals = true;

-- Count metrics with active queuing
SELECT COUNT(*) as queues_with_depth
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_queue_length%'
  AND value > 0;

-- Check for high wait times
SELECT COUNT(*) as high_wait_queues
FROM crdb_internal.node_metrics
WHERE name LIKE 'admission.wait_durations.%-avg'
  AND value > 50000000;  -- > 50ms
```

Expect: Both queries return 0 for healthy cluster

## Related Skills

- `monitor-cpu-usage-per-node` - CPU bottleneck detection
- `monitor-disk-io-and-throughput` - Disk bottleneck detection
- `monitor-memory-usage-and-pressure` - Memory pressure monitoring
- `monitor-statement-statistics` - Query performance analysis
- `monitor-resource-usage-per-node` - Overall resource health
- `identify-hot-ranges` - Load distribution issues

## Documentation

- Admission Control: https://www.cockroachlabs.com/docs/stable/architecture/admission-control.html
- DB Console Queues: https://www.cockroachlabs.com/docs/stable/ui-queues-dashboard.html
- Performance Tuning: https://www.cockroachlabs.com/docs/stable/performance-best-practices-overview.html
- Capacity Planning: https://www.cockroachlabs.com/docs/stable/recommended-production-settings.html
