---
name: monitor-clock-offset-across-nodes
description: Monitor clock offset across cluster nodes using crdb_internal.node_metrics clock-offset.meannanos metric. Alert when offset exceeds 250ms (warning) or 500ms (fatal crash threshold). Critical for transaction timestamp ordering and HLC correctness. Use DB Console Hardware dashboard or SQL queries. Correlate with transaction errors, serialization failures, or "timestamp in future" issues.
domain: Transactions
bloom_level: Apply
tags: transactions, monitoring, cluster-operations, hlc, time-sync
version: 1.0.0
---

# Monitor Clock Offset Across Nodes

## Overview

Clock offset monitoring is critical for ensuring correct transaction ordering in CockroachDB. The Hybrid Logical Clock (HLC) depends on synchronized physical clocks to maintain transaction causality and prevent timestamp inversions that can corrupt distributed transactions.

**Critical thresholds**:
- **Warning**: 250ms offset (recommended maximum)
- **Fatal**: 500ms offset (node crashes automatically to protect data)

## Core Concepts

**Hybrid Logical Clock (HLC)**:
- Combines physical clock time + logical counter
- Ensures monotonically increasing timestamps
- Requires bounded clock skew (<500ms)
- Enables distributed transaction ordering

**Clock Offset Monitoring**:
- Nodes measure clock offset via gossip protocol
- `clock-offset.meannanos` tracks maximum observed offset
- Exceeding `max_offset` (500ms) triggers node crash
- Protects transaction correctness over availability

**Why Monitor Clock Offset**:
- Detect NTP failures before node crashes
- Correlate with transaction timestamp errors
- Prevent serialization failure spikes
- Ensure follower read consistency

## Instructions

### Method 1: Check Current Clock Offset (SQL)

```sql
-- View cluster-wide clock offset (nanoseconds)
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
```

**Expected output**:
```
     scope     | offset_ms | status
---------------+-----------+--------
  cluster-wide |     12.50 | OK
```

**Note**: In v26.1.0, `clock-offset.meannanos` is a cluster-wide metric (not per-node). To view individual node status, use `kv_node_status`:

```sql
-- View node information separately
SELECT node_id, address, locality, started_at
FROM crdb_internal.kv_node_status
ORDER BY node_id;
```

**Interpretation**:
- < 50ms: Excellent synchronization
- 50-100ms: Good synchronization
- 100-250ms: Monitor closely, verify NTP
- 250-500ms: **WARNING** - Take immediate action
- > 500ms: Node will crash

### Method 2: Alert on High Clock Offset

```sql
-- Identify dangerous clock offset cluster-wide
SET allow_unsafe_internals = true;

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
```

### Method 3: DB Console Hardware Dashboard

1. Navigate to `https://<node-address>:8080`
2. Click **Metrics** → **Hardware**
3. View **Clock Offset** graph
4. Monitor for upward trends

**Healthy graph**: Flat line near zero (< 50ms)
**Warning**: Upward trend approaching 250ms
**Critical**: Spikes above 250ms or near 500ms

### Method 4: Continuous Monitoring Script

```bash
#!/bin/bash
# monitor-clock-offset.sh
# Alert when clock offset exceeds thresholds

CERTS_DIR="/path/to/certs"
HOST="localhost:26258"
WARN_THRESHOLD_MS=250
CRIT_THRESHOLD_MS=450  # Alert before 500ms crash threshold

while true; do
  echo "=== Clock Offset Status - $(date) ==="

  cockroach sql --certs-dir=$CERTS_DIR --host=$HOST --execute="
    SET allow_unsafe_internals = true;

    SELECT
      'cluster-wide' AS scope,
      ROUND(value / 1000000.0, 2) AS offset_ms,
      CASE
        WHEN value > 450000000 THEN 'CRITICAL'
        WHEN value > 250000000 THEN 'WARNING'
        ELSE 'OK'
      END AS status
    FROM crdb_internal.node_metrics
    WHERE name = 'clock-offset.meannanos';
  "

  # Check for alerts
  MAX_OFFSET=$(cockroach sql --certs-dir=$CERTS_DIR --host=$HOST --format=tsv --execute="
    SET allow_unsafe_internals = true;
    SELECT value FROM crdb_internal.node_metrics WHERE name = 'clock-offset.meannanos';
  " | tail -1)

  MAX_OFFSET_MS=$(echo "scale=2; $MAX_OFFSET / 1000000" | bc)

  if (( $(echo "$MAX_OFFSET_MS > $CRIT_THRESHOLD_MS" | bc -l) )); then
    echo "CRITICAL: Clock offset ${MAX_OFFSET_MS}ms exceeds ${CRIT_THRESHOLD_MS}ms!"
    # Send alert (integrate with monitoring system)
  elif (( $(echo "$MAX_OFFSET_MS > $WARN_THRESHOLD_MS" | bc -l) )); then
    echo "WARNING: Clock offset ${MAX_OFFSET_MS}ms exceeds ${WARN_THRESHOLD_MS}ms"
  fi

  echo ""
  sleep 30
done
```

## Verify NTP Synchronization

### Check NTP Service Status

```bash
# For systems using ntpd
ntpq -p

# For systems using chrony
chronyc sources

# For systems using systemd-timesyncd
timedatectl status
```

**Expected output (chrony)**:
```
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^* time.cloudflare.com           3   6   377    32   -1234us[-1500us] +/-   15ms
^+ time.google.com               3   6   377    28   +2345us[+2100us] +/-   20ms
```

**Key indicators**:
- `*` indicates selected time source
- `Reach` should be 377 (all recent polls succeeded)
- `Last sample` offset should be < 10ms

### Check System Clock Synchronization

```bash
# Check if NTP is synchronized
timedatectl

# Expected:
# System clock synchronized: yes
# NTP service: active
```

### Verify NTP Configuration

```bash
# Check NTP servers configured
cat /etc/chrony/chrony.conf | grep ^server

# Should show multiple reliable NTP servers:
# server time.cloudflare.com iburst
# server time.google.com iburst
# server ntp.ubuntu.com iburst
```

## Correlating Clock Offset with Transaction Issues

**"Timestamp in Future" Errors** (`BAD_TIMESTAMP: client sent a timestamp that is too far in the future`):
1. Check clock offset immediately using Method 1 query
2. Verify NTP on affected node
3. Restart NTP service: `systemctl restart chronyd`
4. Force time sync: `chronyc makestep`

**Transaction Serialization Failures**: Spikes in serialization failures often correlate with clock offset spikes. Check both `crdb_internal.node_transaction_statistics` and clock offset metrics.

## Alert Configuration Examples

### Prometheus Alert Rules

```yaml
groups:
  - name: cockroachdb_clock_offset
    interval: 30s
    rules:
      - alert: ClockOffsetWarning
        expr: |
          clock_offset_meannanos{job="cockroachdb"} > 250000000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Clock offset exceeds 250ms on {{ $labels.instance }}"
          description: "Node {{ $labels.node_id }} has clock offset of {{ $value | humanizeDuration }}. Verify NTP synchronization."

      - alert: ClockOffsetCritical
        expr: |
          clock_offset_meannanos{job="cockroachdb"} > 450000000
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "CRITICAL: Clock offset approaching crash threshold on {{ $labels.instance }}"
          description: "Node {{ $labels.node_id }} has clock offset of {{ $value | humanizeDuration }}. Node will crash at 500ms. IMMEDIATE ACTION REQUIRED."
```

### Alerting Thresholds

| Offset | Severity | Action | Response Time |
|--------|----------|--------|---------------|
| < 100ms | Normal | None | N/A |
| 100-250ms | Info | Monitor, verify NTP | Next business day |
| 250-400ms | Warning | Investigate NTP issues | Within 1 hour |
| 400-500ms | Critical | Immediate NTP fix | Within 15 minutes |
| > 500ms | Fatal | Node crashes | Prevention only |

## Troubleshooting Clock Offset Issues

### Problem: Clock Offset Suddenly Increases

**Diagnosis**:
```bash
systemctl status chronyd    # Check NTP service
chronyc tracking            # Check synchronization
journalctl -u chronyd --since "1 hour ago" | grep -i "step\|slew"
```

**Common causes**: NTP service stopped, NTP servers unreachable, heavy load, VM clock sync issues, hardware issues

**Solutions**:
```bash
systemctl restart chronyd
chronyc makestep              # Force immediate sync
ntpdate -q time.cloudflare.com  # Test NTP connectivity
sudo ufw allow 123/udp        # Verify firewall allows NTP
```

### Problem: Persistent Clock Drift

**Common causes**: VM time sync conflicts, hardware issues, high CPU load

**Solutions**:
```bash
# For VMs - Disable VM time sync, use chrony exclusively
# /etc/chrony/chrony.conf
server metadata.google.internal iburst  # GCP
server 169.254.169.123 iburst          # AWS
makestep 0.1 3
rtcsync
```

### Problem: Node Crashes Due to Clock Offset

**Error**: `FATAL: maximum clock offset exceeded`

**Actions**:
1. Fix NTP on crashed node
2. Restart node after clock synchronized
3. Monitor clock offset closely

**Note**: Increasing `server.clock.max_offset` reduces consistency guarantees. Only use temporarily while fixing underlying issue.

## Best Practices

### Do:

**Configure Multiple Reliable NTP Sources** (use same servers across all nodes):
```bash
# /etc/chrony/chrony.conf
server time.cloudflare.com iburst
server time.google.com iburst
server ntp1.example.com iburst
server ntp2.example.com iburst
```

**Monitor Clock Offset Continuously**: Alert at 250ms threshold, monitor trends in DB Console

**Test NTP Configuration**:
```bash
systemctl restart chronyd
chronyc sources -v
chronyc tracking
```

**Target Metrics**:
- Production target: < 50ms
- Investigation threshold: 250ms
- Alert threshold: 250ms

### Don't:

**Ignore Clock Offset Warnings**: 250ms means approaching fatal threshold - investigate immediately

**Disable NTP**: Use appropriate time sync even in VM environments

**Mix Time Sources**: Don't use different NTP servers per node or mix NTP with VM time sync

**Increase max_offset Without Reason**: Reduces consistency guarantees, doesn't fix root cause

**Rely on Single NTP Server**: Configure multiple redundant sources

## Complete Monitoring Query

```sql
-- Comprehensive clock offset health check
SET allow_unsafe_internals = true;

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
```

## Real-World Scenarios

**NTP Server Failure**: Offset gradually increases over hours. Chrony automatically falls back to secondary servers. Fix primary server and verify all nodes use redundant time sources.

**VM Clock Sync Conflict**: Offset spikes erratically (50-200ms jumps). Disable VM tools time sync, use only chrony. Offset stabilizes at < 10ms.

**High Load Clock Drift**: Offset increases during batch jobs. Configure chrony for aggressive correction (`makestep 0.1 3`), reduce batch concurrency if needed.

## Verification Checklist

Healthy clock synchronization:
- ✅ NTP service active and synchronized
- ✅ Multiple NTP servers configured
- ✅ Clock offset < 50ms for all nodes
- ✅ Clock offset trend stable (not increasing)
- ✅ NTP reachability = 377 for all servers
- ✅ No "timestamp in future" errors in logs
- ✅ Alerts configured at 250ms threshold
- ✅ DB Console Hardware dashboard shows flat offset graph

## Related Skills

- `configure-ntp-for-clock-synchronization` - Configure NTP for clock sync
- `understand-mvcc-multi-version-concurrency-control-concepts` - How HLC timestamps affect MVCC
- `handle-clock-drift-issues` - Troubleshoot clock synchronization problems
- `troubleshoot-transaction-retry-errors` - Diagnose timestamp-related transaction errors
- `monitor-transaction-performance` - Correlate clock offset with transaction metrics
- `configure-follower-reads-for-read-scalability` - Follower reads require bounded staleness

## Documentation

- Clock Synchronization: https://www.cockroachlabs.com/docs/stable/recommended-production-settings.html#clock-synchronization
- Hardware Dashboard: https://www.cockroachlabs.com/docs/stable/ui-hardware-dashboard.html
- Node Metrics: https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html#node-status-endpoint
- Transaction Retry Errors: https://www.cockroachlabs.com/docs/stable/transaction-retry-error-reference.html

