---
name: monitor-cpu-usage-per-node
description: Can monitor per-node CPU usage using DB Console Hardware metrics or query crdb_internal.kv_node_status for sys.cpu.combined.percent-normalized. Set alerts for sustained CPU >80% indicating capacity constraints or query performance issues. Use when user says "check CPU", "monitor CPU usage", "CPU performance".
metadata:
  domain: Monitoring and Alerting
  tags: [monitoring, performance, cpu, hardware, alerting, capacity-planning]
  blooms_level: Apply
  version: 1.1.0
  crdb_version: v26.1.0+
  status: complete
---

# Monitor CPU Usage Per Node

## Overview

CPU monitoring is critical for maintaining optimal CockroachDB cluster performance and identifying capacity constraints before they impact application workloads. CockroachDB provides multiple methods to track CPU utilization across cluster nodes through the DB Console Hardware dashboard and the `crdb_internal.kv_node_status` system catalog.

The primary CPU metric is `sys.cpu.combined.percent-normalized`, which reports aggregate CPU usage normalized to a 0-100 scale regardless of core count. Sustained high CPU usage (>80%) typically indicates capacity constraints, inefficient queries, or workload spikes requiring investigation.

> **IMPORTANT for v26.1.0+**: All queries accessing `crdb_internal` tables require the session variable `SET allow_unsafe_internals = true;` to be set before execution. This is a security enhancement in v26.1+.

**When to use this skill:**
- Regular capacity planning and performance reviews
- Investigating slow query performance or timeouts
- Diagnosing node-level performance degradation
- Setting up alerting for production clusters
- Troubleshooting cluster-wide performance issues

## Key CPU Metrics in CockroachDB

### Primary Metrics

**sys.cpu.combined.percent-normalized**
- Combined user + system CPU usage normalized to 0-100%
- Accounts for all CPU cores (divided by core count)
- Primary metric for capacity monitoring
- Values above 80% sustained indicate capacity constraints

**sys.cpu.user.percent**
- User-space CPU usage (application processes)
- CockroachDB query processing, transaction handling
- High user CPU indicates query or transaction load

**sys.cpu.sys.percent**
- System/kernel CPU usage (OS operations)
- I/O operations, network handling, context switching
- High system CPU may indicate I/O bottlenecks

**sys.cpu.now.percent-normalized**
- Instantaneous CPU usage snapshot
- Useful for real-time monitoring
- More volatile than combined metric

### Understanding Normalization

CPU metrics are normalized by core count to provide comparable values across different hardware:

- 8-core node at 400% raw usage = 50% normalized
- 16-core node at 400% raw usage = 25% normalized
- Normalized values make cross-node comparison meaningful
- Easier to set universal alerting thresholds

## Monitoring Methods

### Method 1: DB Console Hardware Dashboard

**Access:** `http://<node-address>:8080/#/metrics/hardware/cluster`

**Features:**
- Visual graphs of CPU usage over time
- Per-node breakdown with color-coded indicators
- Configurable time ranges (10m, 1h, 6h, 1d, 1w)
- Exportable data for external analysis
- Real-time updates every 10 seconds

**Navigation:**
1. Open DB Console in browser
2. Click "Metrics" in left navigation
3. Select "Hardware" tab
4. View "CPU Percent" graph

**Interpretation:**
- Green zone (0-50%): Healthy headroom
- Yellow zone (50-70%): Moderate load
- Orange zone (70-85%): High utilization, monitor closely
- Red zone (85-100%): Critical, investigate immediately

### Method 2: SQL Queries via crdb_internal.kv_node_status

> **Session Variable Required**: All queries below require `SET allow_unsafe_internals = true;` to be executed first in your session.

**Basic CPU Check:**

```sql
-- Check current CPU usage across all nodes
SET allow_unsafe_internals = true;

SELECT
  node_id,
  (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT AS cpu_percent
FROM crdb_internal.kv_node_status
ORDER BY cpu_percent DESC;
```

**Sample Output:**
```
  node_id | cpu_percent
----------+--------------
        3 |       78.45
        1 |       65.23
        2 |       62.87
```

**Detailed CPU Metrics:**

```sql
-- Get all CPU-related metrics for a specific node
SET allow_unsafe_internals = true;

SELECT
  node_id,
  metric_key AS metric_name,
  metric_value::FLOAT AS value,
  CASE
    WHEN metric_value::FLOAT > 85 THEN 'CRITICAL'
    WHEN metric_value::FLOAT > 70 THEN 'WARNING'
    WHEN metric_value::FLOAT > 50 THEN 'MODERATE'
    ELSE 'HEALTHY'
  END AS status
FROM crdb_internal.kv_node_status,
  LATERAL jsonb_each_text(metrics) AS m(metric_key, metric_value)
WHERE metric_key LIKE 'sys.cpu%'
  AND node_id = 3
ORDER BY value DESC;
```

**Cross-Node Comparison:**

```sql
-- Compare user vs system CPU across nodes
SET allow_unsafe_internals = true;

SELECT
  node_id,
  (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT AS total_cpu,
  (metrics->>'sys.cpu.user.percent')::FLOAT AS user_cpu,
  (metrics->>'sys.cpu.sys.percent')::FLOAT AS system_cpu,
  (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT -
  (metrics->>'sys.cpu.user.percent')::FLOAT -
  (metrics->>'sys.cpu.sys.percent')::FLOAT AS iowait_estimate
FROM crdb_internal.kv_node_status
ORDER BY total_cpu DESC;
```

**High CPU Node Detection:**

```sql
-- Find nodes with sustained high CPU
SET allow_unsafe_internals = true;

SELECT
  node_id,
  (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT AS cpu_percent,
  ((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 80) AS exceeds_threshold
FROM crdb_internal.kv_node_status
WHERE (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 70
ORDER BY cpu_percent DESC;
```

### Method 3: Command-Line Monitoring

**Using cockroach node status:**

```bash
cockroach node status \
  --format=table \
  --url="postgresql://root@localhost:26257?sslmode=disable"
```

**Output includes:**
- Node ID and address
- Build version
- Uptime
- Replicas count
- CPU usage not directly shown (use SQL method)

**Continuous Monitoring Script:**

```bash
#!/bin/bash
# monitor-cpu.sh - Monitor CPU across all nodes

while true; do
  echo "=== CPU Check $(date) ==="
  cockroach sql --certs-dir=/path/to/certs --host=localhost:26258 \
    --execute="
    SET allow_unsafe_internals = true;
    SELECT
      node_id,
      ROUND((metrics->>'sys.cpu.combined.percent-normalized')::FLOAT, 2) AS cpu_percent,
      CASE
        WHEN (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 85 THEN 'CRITICAL'
        WHEN (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 70 THEN 'WARNING'
        ELSE 'OK'
      END AS status
    FROM crdb_internal.kv_node_status
    ORDER BY cpu_percent DESC;"
  sleep 60
done
```

## Alerting Configuration

### Recommended Alert Thresholds

**Warning Level (70-80%):**
- Trigger: CPU > 70% for 10+ minutes
- Action: Review query performance, check for workload spikes
- Response time: Within 1 hour
- May indicate approaching capacity limits

**Critical Level (80%+):**
- Trigger: CPU > 80% for 5+ minutes
- Action: Immediate investigation, consider scaling
- Response time: Within 15 minutes
- High risk of query slowdowns and timeouts

**Severe Level (90%+):**
- Trigger: CPU > 90% for 2+ minutes
- Action: Emergency response, possible node drain
- Response time: Immediate
- Service degradation likely occurring

### Prometheus Alerting Rules

```yaml
groups:
  - name: cockroachdb_cpu_alerts
    interval: 30s
    rules:
      - alert: CockroachDBHighCPU
        expr: sys_cpu_combined_percent_normalized > 80
        for: 5m
        labels:
          severity: critical
          component: hardware
        annotations:
          summary: "Node {{ $labels.node_id }} CPU usage critical"
          description: "CPU usage is {{ $value }}% on node {{ $labels.node_id }}"

      - alert: CockroachDBWarningCPU
        expr: sys_cpu_combined_percent_normalized > 70
        for: 10m
        labels:
          severity: warning
          component: hardware
        annotations:
          summary: "Node {{ $labels.node_id }} CPU usage elevated"
          description: "CPU usage is {{ $value }}% on node {{ $labels.node_id }}"

      - alert: CockroachDBCPUImbalance
        expr: |
          (max(sys_cpu_combined_percent_normalized) -
           min(sys_cpu_combined_percent_normalized)) > 30
        for: 15m
        labels:
          severity: warning
          component: capacity
        annotations:
          summary: "CPU usage imbalanced across cluster"
          description: "CPU variance exceeds 30% across nodes"
```

### Datadog Monitoring

```yaml
# monitors/cockroachdb_cpu.yaml
name: "CockroachDB High CPU Usage"
type: metric alert
query: |
  avg(last_10m):avg:cockroachdb.sys.cpu.combined.percent_normalized{*}
  by {node_id} > 80
message: |
  CPU usage on {{node_id.name}} is {{value}}%.

  Investigation steps:
  1. Check active queries via SHOW STATEMENTS
  2. Review recent query patterns
  3. Check for concurrent bulk operations
  4. Verify cluster capacity planning

  @pagerduty-critical @slack-ops-alerts
thresholds:
  critical: 80
  warning: 70
  recovery: 65
```

## Troubleshooting High CPU Usage

### Step 1: Identify High CPU Nodes

```sql
-- Get current CPU hotspots
SET allow_unsafe_internals = true;

SELECT
  node_id,
  (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT AS cpu_percent
FROM crdb_internal.kv_node_status
WHERE (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 70
ORDER BY cpu_percent DESC;
```

### Step 2: Check Active Queries

```sql
-- Find long-running or expensive queries on high-CPU nodes
SET allow_unsafe_internals = true;

SELECT
  node_id,
  application_name,
  query,
  start,
  NOW() - start AS duration
FROM crdb_internal.cluster_queries
WHERE node_id IN (
  SELECT node_id FROM crdb_internal.kv_node_status
  WHERE (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 80
)
ORDER BY duration DESC
LIMIT 20;
```

### Step 3: Analyze Query Execution

```sql
-- Get execution statistics for high-CPU queries
SET allow_unsafe_internals = true;

SELECT
  fingerprint_id,
  metadata->>'query' AS query_text,
  (statistics->'execution_statistics'->>'cnt')::INT AS exec_count,
  (statistics->'execution_statistics'->>'mean')::FLOAT AS mean_latency_ms
FROM crdb_internal.statement_statistics
ORDER BY
  ((statistics->'execution_statistics'->>'cnt')::INT::FLOAT *
   (statistics->'execution_statistics'->>'mean')::FLOAT) DESC
LIMIT 10;
```

### Step 4: Check for Hot Ranges

```sql
-- Identify ranges on high-CPU nodes (by size as proxy for activity)
SET allow_unsafe_internals = true;

SELECT
  range_id,
  start_pretty,
  lease_holder,
  range_size
FROM crdb_internal.ranges
WHERE lease_holder IN (
  SELECT node_id FROM crdb_internal.kv_node_status
  WHERE (metrics->>'sys.cpu.combined.percent-normalized')::FLOAT > 80
)
ORDER BY range_size DESC
LIMIT 20;
```

**Note:** QPS (queries per second) and writes_per_second metrics are not available via SQL in v26.1.0. These metrics can be viewed in:
- DB Console Hardware dashboard
- Prometheus metrics endpoint (`_status/vars`)
- Time-series database (internal access only)

### Common CPU Bottleneck Causes

**1. Expensive Queries**
- Full table scans without indexes
- Complex joins or aggregations
- Missing or outdated statistics
- Solution: Add indexes, optimize queries, run ANALYZE

**2. High Transaction Volume**
- Burst workloads exceeding capacity
- Inefficient transaction patterns
- Solution: Implement connection pooling, batch operations

**3. Hot Ranges**
- Sequential key writes causing leaseholder hotspots
- Concentrated read traffic
- Solution: Use HASH-sharded indexes, redesign schema

**4. Background Jobs**
- Bulk imports or backups
- Schema changes on large tables
- Solution: Schedule during off-peak hours, use lower priority

**5. Insufficient Hardware**
- Undersized nodes for workload
- Shared hardware resources
- Solution: Scale vertically (larger nodes) or horizontally (more nodes)

## Best Practices

### Capacity Planning

**Maintain Headroom:**
- Target 50-60% average CPU for production workloads
- Allows headroom for bursts and node failures
- Enables rolling upgrades without performance impact

**Monitor Trends:**
- Track CPU growth rate over weeks/months
- Project when thresholds will be exceeded
- Plan capacity additions proactively

**Test Peak Loads:**
- Simulate expected peak traffic
- Verify CPU stays below 80% during peaks
- Validate failover scenarios (n-1 capacity)

### Performance Optimization

**Query Optimization:**
- Review and optimize top CPU-consuming queries
- Ensure appropriate indexes exist
- Use EXPLAIN ANALYZE to understand query plans
- Keep table statistics up-to-date

**Connection Management:**
- Implement connection pooling (pgBouncer, HikariCP)
- Limit max connections per node
- Avoid connection thrashing

**Workload Isolation:**
- Use separate node pools for different workloads
- Isolate batch jobs from OLTP traffic
- Consider multi-region deployment patterns

### Monitoring Hygiene

**Regular Reviews:**
- Weekly review of CPU trends
- Monthly capacity planning sessions
- Quarterly hardware assessment

**Alert Tuning:**
- Adjust thresholds based on baseline behavior
- Reduce alert fatigue through proper thresholds
- Implement escalation policies

**Documentation:**
- Document normal CPU baselines per application
- Record seasonal patterns (month-end, year-end)
- Maintain runbooks for high-CPU scenarios

## Important Considerations

**Metric Lag:**
- `crdb_internal.kv_node_status` updates every 10 seconds
- Use for trend analysis, not real-time emergency response
- DB Console provides near-real-time visualization

**Multi-Tenant Environments:**
- CPU metrics reflect all processes on the node
- Other applications may contribute to CPU usage
- Use OS-level tools (top, htop) for process-level detail

**Cloud Environments:**
- Burstable instances (T-series AWS) have CPU credits
- Monitor credit balance alongside CPU usage
- Consider dedicated instances for production

**Version Compatibility:**
- `sys.cpu.combined.percent-normalized` available in v21.1+
- Older versions use `sys.cpu.combined.percent` (non-normalized)
- Always verify metric availability for your version

## Common Issues in v26.1.0+

**"column does not exist" error:**
- All queries accessing `crdb_internal` tables require the session variable:
  ```sql
  SET allow_unsafe_internals = true;
  ```
- This must be set at the start of each session or before each query

**"cannot cast type" errors:**
- JSONB metrics may return scientific notation
- Use two-step cast for safety: `(metrics->>'metric.name')::FLOAT::BIGINT`
- Always cast to FLOAT first, then to other numeric types if needed

**Arithmetic type errors:**
- v26.1.0 enforces strict type checking in arithmetic operations
- Ensure at least one operand is explicitly cast to FLOAT:
  ```sql
  -- BAD:  1024 * 1024
  -- GOOD: 1024::FLOAT * 1024
  ```

**Metric name case sensitivity:**
- All metric names are lowercase in v26.1.0
- Use exact casing: `sys.cpu.combined.percent-normalized` (not `sys.CPU.Combined.Percent-Normalized`)

## Related Skills

- `monitor-memory-usage-and-pressure` - Memory metrics and pressure monitoring
- `monitor-node-liveness-and-health` - Overall node health checks
- `monitor-disk-iops-and-throughput` - I/O performance monitoring
- `identify-slow-queries-and-resource-intensive-statements` - Query performance analysis
- `configure-prometheus-for-cockroachdb-monitoring` - External monitoring setup
- `analyze-hot-ranges-and-leaseholder-distribution` - Range-level performance analysis

## References

- [CockroachDB Monitoring Documentation](https://www.cockroachlabs.com/docs/v26.1/monitoring-and-alerting)
- [Hardware Metrics Dashboard](https://www.cockroachlabs.com/docs/v26.1/ui-hardware-dashboard)
- [Essential Metrics for Production](https://www.cockroachlabs.com/docs/v26.1/essential-metrics)
- [Capacity Planning Guide](https://www.cockroachlabs.com/docs/v26.1/recommended-production-settings#capacity-planning)
