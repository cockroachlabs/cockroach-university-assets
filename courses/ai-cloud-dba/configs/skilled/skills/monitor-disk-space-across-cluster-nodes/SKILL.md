---
name: monitor-disk-space-across-cluster-nodes
description: Check disk utilization across nodes using df command, DB Console Capacity metrics, or crdb_internal.kv_store_status to prevent out-of-disk failures
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: stable
---

# Monitor Disk Space Across Cluster Nodes

**Domain**: Monitoring and Alerting
**Bloom's Level**: Apply
**Version**: 1.1.0
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you to **monitor disk space across cluster nodes** to prevent out-of-disk failures. When a node exhausts disk space, it crashes immediately to prevent data corruption. You'll learn to query disk metrics, use DB Console, check OS-level utilization, set alerting thresholds, and understand ballast files for emergency recovery.

**Important for CockroachDB v26.1+**: Queries accessing `crdb_internal` tables require setting the session variable:

```sql
SET allow_unsafe_internals = true;
```

This must be run before any query accessing `crdb_internal.kv_store_status`, `crdb_internal.gossip_nodes`, or `crdb_internal.cluster_transactions`. All SQL examples in this skill assume this has been set.

## Instructions

### 1. Monitor Disk Space Using crdb_internal.kv_store_status

**Query current disk usage for all stores:**

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  used / (1024.0 * 1024.0 * 1024.0) AS used_gb,
  available / (1024.0 * 1024.0 * 1024.0) AS available_gb,
  capacity / (1024.0 * 1024.0 * 1024.0) AS capacity_gb,
  ROUND((used::FLOAT / capacity::FLOAT) * 100, 2) AS used_percent
FROM crdb_internal.kv_store_status
ORDER BY used_percent DESC;
```

**Identify nodes exceeding 80% capacity:**

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  ROUND((used::FLOAT / capacity::FLOAT) * 100, 2) AS used_percent,
  available / (1024.0 * 1024.0 * 1024.0) AS available_gb
FROM crdb_internal.kv_store_status
WHERE (used::FLOAT / capacity::FLOAT) > 0.80
ORDER BY used_percent DESC;
```

### 2. Monitor Disk Space in DB Console

Navigate to `http://<node-address>:8080` → **Metrics → Hardware → Capacity** to view:
- Total capacity per node
- Used space per node
- Available space per node
- Percentage used per node

Watch for nodes approaching 80-90% utilization and monitor capacity growth rate to predict exhaustion.

### 3. Check Disk Space at OS Level with df Command

**SSH to each node:**

```bash
# Basic disk usage
df -h /var/lib/cockroach

# Check inode usage
df -i /var/lib/cockroach
```

**Automated multi-node check:**

```bash
#!/bin/bash
NODES="node1 node2 node3"
for node in $NODES; do
  echo "=== $node ==="
  ssh $node "df -h /var/lib/cockroach | tail -1"
done
```

### 4. Monitor Per-Store and Per-Node Capacity

**Aggregate capacity by node:**

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  COUNT(store_id) AS store_count,
  SUM(used) / (1024.0 * 1024.0 * 1024.0) AS total_used_gb,
  SUM(capacity) / (1024.0 * 1024.0 * 1024.0) AS total_capacity_gb,
  ROUND((SUM(used)::FLOAT / SUM(capacity)::FLOAT) * 100, 2) AS avg_used_percent
FROM crdb_internal.kv_store_status
GROUP BY node_id
ORDER BY avg_used_percent DESC;
```

### 5. Monitor Disk Growth Trends

**Create monitoring table (optional):**

```sql
CREATE TABLE disk_usage_history (
  collected_at TIMESTAMPTZ DEFAULT now(),
  node_id INT,
  store_id INT,
  used_bytes INT8,
  capacity_bytes INT8,
  used_percent DECIMAL(5,2),
  PRIMARY KEY (collected_at, node_id, store_id)
);
```

**Collect periodic snapshots:**

```sql
SET allow_unsafe_internals = true;

INSERT INTO disk_usage_history (node_id, store_id, used_bytes, capacity_bytes, used_percent)
SELECT
  node_id,
  store_id,
  used,
  capacity,
  ROUND((used::FLOAT / capacity::FLOAT) * 100, 2)
FROM crdb_internal.kv_store_status;
```

### 6. Set Up Alerting Thresholds

**Recommended thresholds:**
- **Warning**: 80% capacity
- **Critical**: 90% capacity
- **Emergency**: 95% capacity

**Query for alert conditions:**

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  ROUND((used::FLOAT / capacity::FLOAT) * 100, 2) AS used_percent,
  available / (1024.0 * 1024.0 * 1024.0) AS available_gb,
  CASE
    WHEN (used::FLOAT / capacity::FLOAT) >= 0.95 THEN 'EMERGENCY'
    WHEN (used::FLOAT / capacity::FLOAT) >= 0.90 THEN 'CRITICAL'
    WHEN (used::FLOAT / capacity::FLOAT) >= 0.80 THEN 'WARNING'
    ELSE 'OK'
  END AS severity
FROM crdb_internal.kv_store_status
WHERE (used::FLOAT / capacity::FLOAT) >= 0.80
ORDER BY severity DESC, used_percent DESC;
```

**Prometheus alerting rule:**

```yaml
groups:
  - name: cockroachdb_disk_space
    rules:
      - alert: CockroachDBDiskSpaceWarning
        expr: capacity:used:ratio > 0.80
        for: 5m
        labels:
          severity: warning
      - alert: CockroachDBDiskSpaceCritical
        expr: capacity:used:ratio >= 0.90
        for: 2m
        labels:
          severity: critical
```

### 7. Understand Ballast Files

Ballast files are large, empty files (default 1% of disk or 1GB) that reserve emergency space.

**Check for ballast file:**

```bash
ls -lh /var/lib/cockroach/ballast.txt
```

**When disk is full:**
- Delete ballast file to free emergency space
- Use freed space to delete data or add capacity
- Recreate ballast file after recovery

See **create-ballast-files-for-disk-management** and **handle-disk-space-emergencies-with-ballast-files** skills.

### 8. Prevent Out-of-Disk Failures

**Prevention strategies:**

1. Monitor proactively (daily or continuously)
2. Set alerts at 80%, 90%, 95%
3. Maintain ballast files
4. Add capacity before reaching 75%
5. Ensure GC reclaims old versions
6. Archive or delete historical data

**Emergency checklist:**
- [ ] Identify nodes with critical disk usage
- [ ] Check ballast file availability
- [ ] Stop non-critical writes
- [ ] Delete ballast file if necessary
- [ ] Add storage capacity immediately
- [ ] Recreate ballast file after recovery

## Common Patterns

### Pattern 1: Daily Disk Usage Report

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  ROUND((used::FLOAT / capacity::FLOAT) * 100, 2) AS used_percent,
  capacity / (1024.0 * 1024.0 * 1024.0) AS capacity_gb,
  available / (1024.0 * 1024.0 * 1024.0) AS available_gb,
  CASE
    WHEN (used::FLOAT / capacity::FLOAT) >= 0.90 THEN 'CRITICAL'
    WHEN (used::FLOAT / capacity::FLOAT) >= 0.80 THEN 'WARNING'
    ELSE 'OK'
  END AS status
FROM crdb_internal.kv_store_status
ORDER BY used_percent DESC;
```

### Pattern 2: Combined Metrics Dashboard

```sql
SET allow_unsafe_internals = true;

SELECT
  n.node_id,
  n.address,
  s.store_id,
  ROUND((s.used::FLOAT / s.capacity::FLOAT) * 100, 2) AS used_percent,
  s.available / (1024.0 * 1024.0 * 1024.0) AS available_gb,
  s.range_count,
  CASE
    WHEN (s.used::FLOAT / s.capacity::FLOAT) >= 0.95 THEN 'EMERGENCY'
    WHEN (s.used::FLOAT / s.capacity::FLOAT) >= 0.90 THEN 'CRITICAL'
    WHEN (s.used::FLOAT / s.capacity::FLOAT) >= 0.80 THEN 'WARNING'
    ELSE 'OK'
  END AS status
FROM crdb_internal.kv_store_status s
JOIN crdb_internal.gossip_nodes n ON s.node_id = n.node_id
ORDER BY used_percent DESC;
```

## Troubleshooting

### Issue 1: Node Shows 100% Disk Usage

**Symptoms:**
- Node crashed with "no space left on device"
- `df` shows 100% utilization

**Resolution:**

1. Delete ballast file:
   ```bash
   rm /var/lib/cockroach/ballast.txt
   ```

2. Restart node:
   ```bash
   systemctl start cockroach
   ```

3. Reduce data (drop unused tables, delete old data, reduce GC TTL)

4. Add storage capacity (expand disk, add nodes, or replace with larger storage)

5. Recreate ballast file:
   ```bash
   cockroach debug ballast /var/lib/cockroach/ballast.txt --size=1GB
   ```

### Issue 2: Disk Usage Higher in df Than crdb_internal

**Diagnosis:**

```bash
# Check log file sizes
du -sh /var/lib/cockroach/logs

# Check for core dumps
find /var/lib/cockroach -type f -name "core.*" -o -name "*.tmp"
```

**Causes:**
- Large log files
- Core dumps
- Temporary files
- Ballast file (counted by OS, not CockroachDB)

**Resolution:**

```bash
# Rotate logs
logrotate /etc/logrotate.d/cockroachdb

# Remove old logs
find /var/lib/cockroach/logs -name "*.log" -mtime +30 -delete

# Remove core dumps
rm /var/lib/cockroach/core.*
```

### Issue 3: Rapid Disk Growth from Write Amplification

**Diagnosis:**

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  store_id,
  logical_bytes / (1024.0 * 1024.0 * 1024.0) AS logical_gb,
  used / (1024.0 * 1024.0 * 1024.0) AS used_gb,
  ROUND((used::FLOAT / logical_bytes::FLOAT), 2) AS amplification_ratio
FROM crdb_internal.kv_store_status
WHERE logical_bytes > 0
ORDER BY amplification_ratio DESC;
```

**Resolution:**

1. Check GC settings:
   ```sql
   -- GC TTL is a zone configuration parameter, not a cluster setting
   SELECT target, raw_config_sql
   FROM [SHOW ZONE CONFIGURATION FOR RANGE default]
   WHERE raw_config_sql LIKE '%gc.ttlseconds%';
   ```

2. Identify long-running transactions:
   ```sql
   SET allow_unsafe_internals = true;

   SELECT id, application_name, start,
          now() - start AS transaction_age
   FROM crdb_internal.cluster_transactions
   WHERE start < (now() - INTERVAL '1 hour');
   ```

3. Reduce write rate (pause imports, rate-limit writes)

### Issue 4: Disk Usage Imbalanced Across Nodes

**Diagnosis:**

```sql
SET allow_unsafe_internals = true;

SELECT
  node_id,
  range_count,
  used / (1024.0 * 1024.0 * 1024.0) AS used_gb,
  ROUND((used::FLOAT / capacity::FLOAT) * 100, 2) AS used_percent
FROM crdb_internal.kv_store_status
ORDER BY range_count DESC;
```

**Resolution:**

1. Check rebalancing status:
   ```sql
   -- Check load-based rebalancing setting
   SHOW CLUSTER SETTING kv.allocator.load_based_rebalancing;

   -- Possible values:
   -- 'off' - rebalancing disabled
   -- 'leases' - only lease rebalancing enabled
   -- 'leases and replicas' - full rebalancing enabled (default)
   ```

2. Adjust rebalancing rate if slow:
   ```sql
   SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '64 MiB';
   ```

## Best Practices

### 1. Establish Continuous Monitoring

Use Prometheus and Grafana:
- Export CockroachDB metrics
- Create dashboards for disk usage
- Set up alerts for 80%, 90%, 95%
- Monitor growth trends

Key Prometheus metrics: `capacity_used`, `capacity_available`, `capacity`, `capacity:used:ratio`

### 2. Set Conservative Alerting Thresholds

| Threshold | Action | Response Time |
|-----------|--------|---------------|
| 75% | Monitor | Plan capacity expansion |
| 80% | Warning | Investigate growth causes |
| 90% | Critical | Add capacity immediately |
| 95% | Emergency | Emergency procedures |

### 3. Maintain Ballast Files on All Nodes

```bash
# Verify ballast files
for node in node1 node2 node3; do
  ssh $node "test -f /var/lib/cockroach/ballast.txt && echo 'OK' || echo 'MISSING'"
done
```

### 4. Plan Capacity Proactively

Add capacity before reaching 75%:
- Add nodes to distribute data
- Expand disk volumes
- Archive or delete old data

Calculate runway: `Runway (days) = Available GB / Daily Growth GB`

### 5. Configure Aggressive Log Rotation

```yaml
# logrotate configuration
/var/lib/cockroach/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
```

### 6. Monitor Both Disk Space and Inodes

```bash
# Check inode usage
df -i /var/lib/cockroach
```

Inode exhaustion can occur even with available disk space.

### 7. Document Emergency Procedures

Create runbooks for:
1. Ballast file deletion
2. Emergency data deletion
3. Node replacement
4. Escalation contacts
5. Post-incident ballast recreation

### 8. Test Recovery Procedures

Regularly test:
- Simulate disk full scenarios
- Verify ballast file deletion/recreation
- Practice emergency capacity expansion
- Validate monitoring pipelines

### 9. Coordinate with Garbage Collection

```sql
-- Check current GC TTL
SELECT * FROM [SHOW ZONE CONFIGURATION FOR RANGE default];

-- Lower GC TTL to reclaim space faster (e.g., 4 hours = 14400 seconds)
ALTER RANGE default CONFIGURE ZONE USING gc.ttlseconds = 14400;
```

## Related Skills

- **create-ballast-files-for-disk-management**: Create emergency recovery space
- **handle-disk-space-emergencies-with-ballast-files**: Recover from out-of-disk failures
- **prevent-out-of-disk-failures**: Proactive prevention strategies
- **monitor-storage-capacity-and-growth**: Comprehensive storage monitoring
- **configure-garbage-collection-ttl-settings**: Optimize space reclamation
- **set-up-alerting-rules-for-critical-conditions**: Configure automated alerts
- **configure-prometheus-metrics-export**: Export metrics for monitoring
- **access-and-navigate-db-console**: Use DB Console for visualization
- **decommission-nodes-safely**: Remove nodes when replacing with larger storage
