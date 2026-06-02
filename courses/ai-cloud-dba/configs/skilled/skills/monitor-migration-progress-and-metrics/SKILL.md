---
name: monitor-migration-progress-and-metrics
description: Monitor CockroachDB migration progress using data transfer rate tracking, replication lag monitoring, bottleneck identification, failure alerting, and MOLT monitoring tools. Essential for ensuring successful migration execution and early issue detection.
metadata:
  domain: Migrations
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: production
  related_skills:
    - execute-migration-cutover-procedures
    - implement-migration-rollback-procedures
    - validate-migration-completeness
    - use-molt-fetch-for-data-migration
    - use-molt-verify-for-migration-validation
    - perform-migration-dry-runs
    - configure-replication-and-failback-for-migrations
  prerequisites:
    - Understanding of MOLT migration tools
    - Familiarity with CockroachDB monitoring
    - Basic SQL query skills
    - Access to monitoring infrastructure
  estimated_time_minutes: 60
  last_updated: "2026-03-09"
---

# Monitor Migration Progress and Metrics

## Overview

Migration monitoring provides real-time visibility into data transfer progress, performance characteristics, and potential issues. Effective monitoring enables teams to detect problems early, optimize migration performance, and make informed decisions about cutover timing and rollback necessity.

**Monitoring Objectives**:
1. **Track Progress**: Measure data transfer completion percentage
2. **Measure Performance**: Monitor throughput, latency, and resource utilization
3. **Detect Issues**: Identify errors, bottlenecks, and anomalies
4. **Validate Success**: Confirm data integrity and completeness
5. **Enable Decisions**: Provide data for go/no-go and rollback decisions

This skill teaches you to implement comprehensive monitoring throughout all migration phases.

## What This Skill Teaches

You will learn to:

- **Track data transfer rates** and estimate completion times
- **Monitor replication lag** in real-time during online migrations
- **Identify performance bottlenecks** in network, CPU, and disk I/O
- **Configure migration failure alerts** for critical conditions
- **Use MOLT monitoring capabilities** for automated tracking
- **Build migration dashboards** with key metrics
- **Analyze migration logs** for troubleshooting
- **Measure migration success criteria** against SLAs

## Prerequisites

Before implementing migration monitoring:

1. **Migration Tools Installed**: MOLT Fetch, MOLT Verify, monitoring agents
2. **Monitoring Infrastructure**: Prometheus, Grafana, or equivalent
3. **Database Access**: Read permissions on source and target databases
4. **Log Aggregation**: Centralized logging system (ELK, Splunk, CloudWatch)
5. **Alert Configuration**: Alerting channels configured (Slack, PagerDuty, email)

## Key Migration Metrics

### Data Transfer Metrics

**Primary Metrics**:

```yaml
Data Volume Metrics:
  - Total rows to migrate: Baseline measurement
  - Rows migrated: Current progress
  - Rows remaining: Backlog
  - Migration progress percentage: Visual indicator
  - Bytes transferred: Network utilization
  - Tables completed: Checkpoint tracking

Performance Metrics:
  - Transfer rate (rows/second): Throughput
  - Transfer rate (MB/second): Bandwidth utilization
  - Average row size: Data characteristics
  - Estimated time remaining: Planning metric
  - Elapsed time: Duration tracking

Quality Metrics:
  - Rows failed: Error count
  - Error rate (%): Quality indicator
  - Retry count: Resilience metric
  - Data validation failures: Integrity issues
```

### Replication Lag Metrics

For online migrations with continuous replication:

```yaml
Lag Metrics:
  - Replication lag (seconds): Time delta between source and target
  - Replication lag (transactions): Transaction count delta
  - Replication lag (bytes): Data volume delta
  - Catch-up rate: How quickly lag is decreasing

Health Metrics:
  - Replication status: Running/stopped/error
  - Last applied transaction: Position tracking
  - Replication throughput: Transactions/second
  - Backlog size: Pending transactions
```

### System Resource Metrics

**Source Database**:
```yaml
Resource Utilization:
  - CPU usage: Impact on production workload
  - Memory usage: Buffer pool pressure
  - Disk I/O: Read throughput
  - Network egress: Bandwidth consumption
  - Active connections: Connection pool usage
```

**Target CockroachDB**:
```yaml
Resource Utilization:
  - CPU usage per node: Cluster balance
  - Memory usage per node: Resource constraints
  - Disk I/O per node: Write throughput
  - Network ingress: Data arrival rate
  - Range count growth: Data distribution
```

## Monitoring MOLT Fetch Migration

### Real-Time Progress Tracking

**MOLT Fetch provides built-in logging**:

```bash
# Run MOLT Fetch with detailed logging
molt fetch \
  --source 'mysql://user:password@source-db:3306/production' \
  --target 'postgresql://root@crdb-lb:26257/production?sslmode=require' \
  --direct-copy \
  --logging debug \
  --table-filter 'orders,customers,products,inventory' \
  --table-handling drop-on-target-and-recreate \
  2>&1 | tee /var/log/molt-fetch-$(date +%Y%m%d-%H%M%S).log
```

**Log output contains**:
- Table-by-table progress
- Row counts processed
- Transfer rates
- Errors and warnings
- Completion timestamps

### Parsing MOLT Fetch Logs

**Extract key metrics from logs**:

```bash
#!/bin/bash
# parse-molt-logs.sh

LOG_FILE="/var/log/molt-fetch-20260309-140000.log"

echo "=== MOLT FETCH MIGRATION METRICS ==="

# Total rows processed
TOTAL_ROWS=$(grep -oP 'processed \K\d+' $LOG_FILE | awk '{s+=$1} END {print s}')
echo "Total rows processed: $TOTAL_ROWS"

# Average transfer rate
AVG_RATE=$(grep -oP '\d+ rows/s' $LOG_FILE | grep -oP '\d+' | awk '{s+=$1; c++} END {print s/c}')
echo "Average transfer rate: $AVG_RATE rows/s"

# Tables completed
TABLES_DONE=$(grep -c "Table .* completed" $LOG_FILE)
echo "Tables completed: $TABLES_DONE"

# Errors encountered
ERROR_COUNT=$(grep -ci "error" $LOG_FILE)
echo "Errors logged: $ERROR_COUNT"

# Migration duration
START_TIME=$(head -5 $LOG_FILE | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' | head -1)
END_TIME=$(tail -5 $LOG_FILE | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' | tail -1)
echo "Start: $START_TIME"
echo "End: $END_TIME"
```

### Custom Progress Monitoring Script

**Query source and target for progress**:

```bash
#!/bin/bash
# monitor-migration-progress.sh

SOURCE_DB="mysql://user:password@source-db:3306/production"
TARGET_DB="postgresql://root@crdb-lb:26257/production?sslmode=require"

while true; do
  clear
  echo "=== MIGRATION PROGRESS DASHBOARD ==="
  echo "Timestamp: $(date)"
  echo ""

  # Table: orders
  SOURCE_ORDERS=$(mysql -h source-db -u user -ppassword production -e "SELECT COUNT(*) FROM orders;" | tail -1)
  TARGET_ORDERS=$(cockroach sql --url "$TARGET_DB" --execute "SELECT COUNT(*) FROM orders;" --format=csv | tail -1)
  ORDERS_PROGRESS=$(awk "BEGIN {printf \"%.2f\", ($TARGET_ORDERS/$SOURCE_ORDERS)*100}")

  echo "Table: orders"
  echo "  Source: $SOURCE_ORDERS rows"
  echo "  Target: $TARGET_ORDERS rows"
  echo "  Progress: $ORDERS_PROGRESS%"
  echo ""

  # Table: customers
  SOURCE_CUSTOMERS=$(mysql -h source-db -u user -ppassword production -e "SELECT COUNT(*) FROM customers;" | tail -1)
  TARGET_CUSTOMERS=$(cockroach sql --url "$TARGET_DB" --execute "SELECT COUNT(*) FROM customers;" --format=csv | tail -1)
  CUSTOMERS_PROGRESS=$(awk "BEGIN {printf \"%.2f\", ($TARGET_CUSTOMERS/$SOURCE_CUSTOMERS)*100}")

  echo "Table: customers"
  echo "  Source: $SOURCE_CUSTOMERS rows"
  echo "  Target: $TARGET_CUSTOMERS rows"
  echo "  Progress: $CUSTOMERS_PROGRESS%"
  echo ""

  # Overall progress
  TOTAL_SOURCE=$(($SOURCE_ORDERS + $SOURCE_CUSTOMERS))
  TOTAL_TARGET=$(($TARGET_ORDERS + $TARGET_CUSTOMERS))
  OVERALL_PROGRESS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_TARGET/$TOTAL_SOURCE)*100}")

  echo "Overall Progress: $OVERALL_PROGRESS%"
  echo "================================"

  sleep 30
done
```

## Monitoring Online Migration Replication

### Replication Lag Monitoring

**Track lag for CDC-based migrations**:

```sql
-- CockroachDB: Monitor changefeed (replication) lag
SELECT
  job_id,
  job_type,
  description,
  status,
  running_status,
  created,
  started,
  finished,
  modified,
  fraction_completed,
  high_water_timestamp,
  error,
  coordinator_id
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
  AND status = 'running'
ORDER BY created DESC;

-- Calculate replication lag
SELECT
  job_id,
  description,
  age(clock_timestamp(), high_water_timestamp) AS replication_lag
FROM crdb_internal.jobs
WHERE job_type = 'CHANGEFEED'
  AND status = 'running';
```

**MySQL Binlog Position Tracking**:

```sql
-- Source MySQL: Current binlog position
SHOW MASTER STATUS;

-- Output:
-- File: mysql-bin.000123
-- Position: 987654321
-- Binlog_Do_DB:
-- Binlog_Ignore_DB:
-- Executed_Gtid_Set: 3e11fa47-5371-11e9-9989-0242ac130002:1-987654
```

**PostgreSQL Replication Slot Lag**:

```sql
-- PostgreSQL: Monitor replication lag
SELECT
  slot_name,
  plugin,
  slot_type,
  database,
  active,
  active_pid,
  confirmed_flush_lsn,
  pg_current_wal_lsn(),
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
  ) AS lag_bytes
FROM pg_replication_slots
WHERE slot_name = 'crdb_migration_slot';
```

### Automated Lag Alerting

**Script to monitor and alert on lag**:

```bash
#!/bin/bash
# monitor-replication-lag.sh

TARGET_DB="postgresql://root@crdb-lb:26257/production?sslmode=require"
LAG_THRESHOLD_SECONDS=30
ALERT_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

while true; do
  # Query replication lag
  LAG_SECONDS=$(cockroach sql --url "$TARGET_DB" --execute "
    SELECT COALESCE(
      extract(epoch from age(clock_timestamp(), high_water_timestamp)),
      0
    )
    FROM crdb_internal.jobs
    WHERE job_type = 'CHANGEFEED'
      AND status = 'running'
    LIMIT 1;
  " --format=csv | tail -1)

  echo "[$(date)] Replication lag: ${LAG_SECONDS}s"

  # Alert if lag exceeds threshold
  if (( $(echo "$LAG_SECONDS > $LAG_THRESHOLD_SECONDS" | bc -l) )); then
    curl -X POST $ALERT_WEBHOOK \
      -H 'Content-Type: application/json' \
      -d "{
        \"text\": \"⚠️  Migration replication lag alert\",
        \"attachments\": [{
          \"color\": \"warning\",
          \"fields\": [
            {\"title\": \"Current Lag\", \"value\": \"${LAG_SECONDS}s\", \"short\": true},
            {\"title\": \"Threshold\", \"value\": \"${LAG_THRESHOLD_SECONDS}s\", \"short\": true}
          ]
        }]
      }"
  fi

  sleep 60
done
```

## Performance Bottleneck Identification

### Network Bottleneck Detection

**Measure network throughput**:

```bash
# Monitor network transfer rates (Linux)
# Source database server
iftop -i eth0 -f "dst port 26257"

# Or use nload for simpler view
nload -u M eth0

# Calculate sustained throughput
echo "=== Network Throughput ==="
RX_BYTES_START=$(cat /sys/class/net/eth0/statistics/rx_bytes)
sleep 10
RX_BYTES_END=$(cat /sys/class/net/eth0/statistics/rx_bytes)
THROUGHPUT=$(( ($RX_BYTES_END - $RX_BYTES_START) / 10 / 1024 / 1024 ))
echo "Sustained throughput: ${THROUGHPUT} MB/s"
```

### CPU Bottleneck Detection

**Monitor database CPU usage**:

```sql
-- CockroachDB: CPU usage per node
SELECT
  node_id,
  store_id,
  (metrics -> 'sys.cpu.user.percent')::FLOAT AS cpu_user_percent,
  (metrics -> 'sys.cpu.sys.percent')::FLOAT AS cpu_sys_percent
FROM crdb_internal.kv_store_status
ORDER BY node_id;
```

```bash
# MySQL: CPU usage
mysqladmin -h source-db -u root -p extended-status | grep Threads_running

# System CPU monitoring
top -bn1 | grep "Cpu(s)" | awk '{print "CPU Usage: " $2 + $4 "%"}'
```

### Disk I/O Bottleneck Detection

**Monitor disk throughput**:

```bash
# Linux: iostat for disk I/O
iostat -x 5 3  # 5-second intervals, 3 iterations

# Look for:
# - %util approaching 100%: Disk saturation
# - High await times: Slow disk operations
# - Low MB/s despite high %util: I/O bottleneck

# CockroachDB disk I/O metrics
cockroach sql --url "postgresql://root@crdb-lb:26257/defaultdb?sslmode=require" \
  --execute "
SELECT
  node_id,
  (metrics -> 'rocksdb.block.cache.hits')::INT AS cache_hits,
  (metrics -> 'rocksdb.block.cache.misses')::INT AS cache_misses,
  (metrics -> 'rocksdb.read.bytes.total')::BIGINT / 1024 / 1024 AS read_mb,
  (metrics -> 'rocksdb.write.bytes.total')::BIGINT / 1024 / 1024 AS write_mb
FROM crdb_internal.kv_store_status
ORDER BY node_id;
"
```

### Query-Level Bottleneck Detection

**Identify slow queries during migration**:

```sql
-- CockroachDB: Slow queries
SELECT
  fingerprint_id,
  metadata ->> 'query' AS query,
  metadata -> 'statistics' -> 'statistics' ->> 'cnt' AS exec_count,
  (metadata -> 'statistics' -> 'statistics' ->> 'runLat' ->> 'mean')::FLOAT / 1000000 AS avg_latency_ms,
  (metadata -> 'statistics' -> 'statistics' ->> 'runLat' ->> 'max')::FLOAT / 1000000 AS max_latency_ms
FROM crdb_internal.statement_statistics
WHERE aggregated_ts > now() - INTERVAL '1 hour'
  AND (metadata -> 'statistics' -> 'statistics' ->> 'runLat' ->> 'mean')::FLOAT / 1000000 > 1000
ORDER BY avg_latency_ms DESC
LIMIT 20;
```

```sql
-- MySQL: Slow query log analysis
SELECT
  DIGEST_TEXT AS query,
  COUNT_STAR AS exec_count,
  AVG_TIMER_WAIT / 1000000000000 AS avg_latency_sec,
  MAX_TIMER_WAIT / 1000000000000 AS max_latency_sec
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = 'production'
  AND AVG_TIMER_WAIT / 1000000000000 > 1
ORDER BY AVG_TIMER_WAIT DESC
LIMIT 20;
```

## Migration Failure Alerting

### Critical Failure Alerts

**Configure alerts for migration-stopping conditions**:

```yaml
# Prometheus alerting rules (prometheus-alerts.yml)
groups:
  - name: migration_alerts
    interval: 30s
    rules:
      # Alert: Migration replication stopped
      - alert: MigrationReplicationStopped
        expr: |
          (cockroachdb_jobs_running_status{job_type="CHANGEFEED"} != 1)
          or absent(cockroachdb_jobs_running_status{job_type="CHANGEFEED"})
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Migration replication has stopped"
          description: "Changefeed job for migration is not running"

      # Alert: High replication lag
      - alert: MigrationReplicationLagHigh
        expr: |
          (time() - cockroachdb_jobs_high_water_timestamp{job_type="CHANGEFEED"}) > 60
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Migration replication lag exceeds 60 seconds"
          description: "Replication lag: {{ $value }}s"

      # Alert: Migration error rate high
      - alert: MigrationErrorRateHigh
        expr: |
          rate(cockroachdb_jobs_failed_total{job_type="CHANGEFEED"}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Migration experiencing high error rate"
          description: "Error rate: {{ $value }} errors/sec"

      # Alert: CockroachDB cluster unhealthy
      - alert: MigrationTargetClusterUnhealthy
        expr: |
          cockroachdb_liveness_livenodes < 3
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "CockroachDB target cluster has insufficient live nodes"
          description: "Live nodes: {{ $value }}"

      # Alert: Disk space low on target
      - alert: MigrationTargetDiskSpaceLow
        expr: |
          (cockroachdb_capacity_available / cockroachdb_capacity) < 0.15
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "CockroachDB target cluster low on disk space"
          description: "Available capacity: {{ $value | humanizePercentage }}"
```

### Error Tracking and Analysis

**Monitor and categorize errors**:

```bash
#!/bin/bash
# analyze-migration-errors.sh

LOG_FILE="/var/log/molt-fetch.log"

echo "=== MIGRATION ERROR ANALYSIS ==="

# Connection errors
CONN_ERRORS=$(grep -ci "connection refused\|timeout\|network" $LOG_FILE)
echo "Connection errors: $CONN_ERRORS"

# Authentication errors
AUTH_ERRORS=$(grep -ci "authentication failed\|access denied" $LOG_FILE)
echo "Authentication errors: $AUTH_ERRORS"

# Data type errors
TYPE_ERRORS=$(grep -ci "type mismatch\|invalid data type" $LOG_FILE)
echo "Data type errors: $TYPE_ERRORS"

# Constraint violations
CONSTRAINT_ERRORS=$(grep -ci "foreign key\|unique constraint\|check constraint" $LOG_FILE)
echo "Constraint violation errors: $CONSTRAINT_ERRORS"

# Transaction errors
TXN_ERRORS=$(grep -ci "serialization\|deadlock\|lock timeout" $LOG_FILE)
echo "Transaction errors: $TXN_ERRORS"

# Sample recent errors
echo ""
echo "Recent error samples:"
grep -i "error" $LOG_FILE | tail -5
```

## MOLT Verify Continuous Validation

**Run MOLT Verify periodically during migration**:

```bash
#!/bin/bash
# continuous-validation.sh

SOURCE="mysql://user:password@source-db:3306/production"
TARGET="postgresql://root@crdb-lb:26257/production?sslmode=require"

while true; do
  echo "[$(date)] Running MOLT Verify validation..."

  molt verify \
    --source "$SOURCE" \
    --target "$TARGET" \
    --table-filter 'orders,customers,products' \
    --row-count \
    --logging info \
    > /var/log/molt-verify-$(date +%Y%m%d-%H%M%S).log 2>&1

  VERIFY_EXIT_CODE=$?

  if [ $VERIFY_EXIT_CODE -ne 0 ]; then
    echo "WARNING: MOLT Verify detected discrepancies!"
    # Send alert
    curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
      -H 'Content-Type: application/json' \
      -d '{"text": "⚠️  MOLT Verify detected data discrepancies during migration"}'
  fi

  # Run validation every 5 minutes
  sleep 300
done
```

## Best Practices

1. **Monitor All Phases**: Track metrics during planning, execution, and post-cutover
2. **Establish Baselines**: Measure performance before migration for comparison
3. **Automate Alerts**: Configure alerting for critical conditions
4. **Log Everything**: Capture detailed logs for troubleshooting
5. **Dashboard Visibility**: Make metrics accessible to all stakeholders
6. **Continuous Validation**: Run MOLT Verify throughout migration
7. **Resource Monitoring**: Track both source and target system resources
8. **Document Thresholds**: Define acceptable ranges for all metrics

## Related Skills

- **execute-migration-cutover-procedures**: Use monitoring to validate cutover
- **implement-migration-rollback-procedures**: Monitoring triggers rollback decisions
- **validate-migration-completeness**: Final validation uses monitoring data
- **use-molt-fetch-for-data-migration**: Understand MOLT Fetch metrics
- **use-molt-verify-for-migration-validation**: Validation monitoring
- **perform-migration-dry-runs**: Establish monitoring baselines

## Additional Resources

- [MOLT Documentation](https://www.cockroachlabs.com/docs/stable/molt.html)
- [CockroachDB Metrics](https://www.cockroachlabs.com/docs/stable/monitor-cockroachdb-with-prometheus.html)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/overview/)
