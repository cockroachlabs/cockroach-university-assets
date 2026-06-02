---
name: analyze-incremental-backup-efficiency
description: Use SHOW BACKUP to analyze incremental backup efficiency by comparing data_size, row_count, and performance metrics across backup chains. Calculate storage savings, monitor change rates, and optimize backup frequency based on data patterns. Essential for balancing RPO requirements with storage costs.
metadata:
  domain: Backup and Restore
  bloom_level: Analyze
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Analyze Incremental Backup Efficiency

**Domain**: Backup and Restore
**Bloom's Level**: Analyze
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to analyze incremental backup efficiency using `SHOW BACKUP` metrics. You'll learn to calculate storage savings, understand data change patterns, and optimize backup strategies based on actual workload characteristics.

**When to use this skill:**
- Evaluating backup strategy effectiveness
- Optimizing storage costs while meeting RPO requirements
- Understanding data change patterns and growth trends
- Capacity planning for backup storage infrastructure
- Troubleshooting backup performance degradation

**Key metrics analyzed:**
- `data_size`: Bytes stored in each backup layer
- `row_count`: Number of rows in each backup
- `start_time` / `end_time`: Backup duration
- Storage savings percentage (incremental vs full)
- Change rate (rows/data modified between backups)

## Instructions

### Understanding Incremental Backup Metrics

`SHOW BACKUP` provides key metrics for efficiency analysis:

```sql
-- Show detailed backup metrics
SHOW BACKUP FROM LATEST IN 'gs://acme-backups/production';

-- Key columns for analysis:
--   database_name | table_name | start_time           | end_time             | data_size | rows
-- ----------------+------------+----------------------+----------------------+-----------+---------
--   production    | orders     | 2026-03-06 00:00:00 | 2026-03-06 00:45:00 | 524288000 | 1000000
```

**Metric Definitions:**
- **data_size**: Compressed size of data in this backup layer (bytes)
- **rows**: Number of rows included in this backup layer
- **start_time** / **end_time**: Backup duration window

**Important Notes:**
- Incremental backups only include changed data since last backup
- Full backups include all data regardless of changes
- Row count in incrementals = new + modified + deleted rows

### Calculating Storage Savings

Compare full vs incremental backup sizes:

```sql
-- Show backup chain with all layers
SHOW BACKUPS IN 'gs://acme-backups/production';

-- Get size of full backup
SHOW BACKUP '2026-03-01-full' IN 'gs://acme-backups/production';
-- Sum data_size across all tables: 10 GB

-- Get size of incremental backups
SHOW BACKUP '2026-03-01-full/2026-03-02T00:00:00Z' IN 'gs://acme-backups/production';
-- Sum data_size: 500 MB (5% of full)

-- Calculate cumulative storage:
-- Full backup:    10,000 MB
-- + Incremental:     500 MB
-- + Incremental:     750 MB
-- Total:          11,250 MB

-- Without incrementals (daily full backups):
-- Day 1 full:     10,000 MB
-- Day 2 full:     10,200 MB
-- Day 3 full:     10,500 MB
-- Total:          30,700 MB

-- Storage savings: (30,700 - 11,250) / 30,700 = 63% savings
```

### Analyzing Data Change Rates

Understand how much data changes between backups:

```sql
-- Compare consecutive backups to measure change rate
SHOW BACKUP '2026-03-01-full' IN 'gs://acme-backups/production';
-- Total rows: 5,000,000

SHOW BACKUP '2026-03-01-full/2026-03-02T00:00:00Z' IN 'gs://acme-backups/production';
-- Incremental rows: 250,000 (5% daily change rate)

-- Table-level change rate analysis
--   table_name | data_size | rows   | % of full
-- -------------+-----------+--------+-----------
--   orders     | 450000000 | 225000 | 22.5% (high churn)
--   customers  |  25000000 |  12500 | 5%   (low churn)
--   sessions   |  15000000 |   7500 | 75%  (very high churn)

-- Analysis insights:
-- - orders: High change rate, needs frequent backups
-- - customers: Low change rate, stable data
-- - sessions: Very high churn, consider shorter retention
```

### Evaluating Backup Performance Trends

Monitor backup performance over time:

```sql
-- Calculate backup duration and throughput from SHOW BACKUP
-- Performance trend analysis example:
-- 2026-03-01 full: 10 GB in 45 min = 3.7 MB/s
-- 2026-03-02 incr:  500 MB in 3 min = 2.8 MB/s
-- 2026-03-03 incr:  750 MB in 5 min = 2.5 MB/s (degrading)

-- Investigate performance degradation:
-- - Network bandwidth constraints
-- - Storage throttling (S3 rate limits)
-- - Cluster resource contention
```

### Optimizing Backup Frequency

Determine optimal backup schedule based on change rates:

```sql
-- Scenario: Daily incrementals for 7 days, weekly full backups

-- Week 1 storage analysis:
-- Day 0 (Sun): Full backup     = 10,000 MB
-- Day 1 (Mon): Incremental     =    500 MB (5% change)
-- Day 2 (Tue): Incremental     =    525 MB
-- Day 3 (Wed): Incremental     =    550 MB
-- Day 4 (Thu): Incremental     =    575 MB
-- Day 5 (Fri): Incremental     =    600 MB
-- Day 6 (Sat): Incremental     =    625 MB
-- Total Week 1:                = 13,375 MB

-- Alternative: Daily full backups
-- 7 days × ~10,200 MB average  = 71,400 MB
-- Savings with incrementals:     81%

-- Decision factors:
-- - RPO requirement: 24h = daily backups sufficient
-- - RTO requirement: <1h = shorter chains (more full backups)
-- - Storage cost: High = prefer incrementals
-- - Change rate: <10% daily = incrementals very effective
```

## Common Patterns

### Pattern 1: Monthly Backup Efficiency Report

Generate comprehensive backup efficiency analysis:

```sql
-- Create monthly backup efficiency report
WITH backup_metrics AS (
  SELECT
    '2026-03-01' AS backup_date,
    'full' AS backup_type,
    10000000000 AS data_size_bytes,
    5000000 AS row_count
  UNION ALL SELECT '2026-03-02', 'incremental', 500000000, 250000
  UNION ALL SELECT '2026-03-03', 'incremental', 525000000, 262500
)
SELECT
  backup_date,
  backup_type,
  ROUND(data_size_bytes / 1024.0 / 1024.0 / 1024.0, 2) AS size_gb,
  row_count,
  CASE
    WHEN backup_type = 'full' THEN 100
    ELSE ROUND(100.0 * data_size_bytes /
         LAG(data_size_bytes) FILTER (WHERE backup_type = 'full') OVER (ORDER BY backup_date), 2)
  END AS pct_of_full
FROM backup_metrics
ORDER BY backup_date;
```

### Pattern 2: Cost-Benefit Analysis for Backup Strategy

Compare storage costs across different backup strategies:

```sql
-- Strategy A: Daily full backups
-- Storage: 30 backups × 10.5 TB = 315 TB
-- Cost: 315 TB × $23.55/TB/month = $7,418/month
-- Pros: Fastest recovery
-- Cons: Highest storage cost

-- Strategy B: Weekly full + daily incrementals
-- Week 1: 10 TB + (6 × 0.5 TB) = 13 TB
-- Total 4 weeks: ~56 TB
-- Cost: 56 TB × $23.55/TB = $1,319/month
-- Savings: $6,099/month (82% reduction)

-- Recommendation: Strategy B
-- - Meets RTO requirement
-- - 82% cost savings vs daily full
-- - Daily incrementals provide granular recovery points
```

### Pattern 3: Anomaly Detection in Backup Patterns

Identify unusual data changes:

```sql
WITH incremental_sizes AS (
  SELECT
    backup_date,
    data_size_gb,
    AVG(data_size_gb) OVER (
      ORDER BY backup_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_avg_7day
  FROM (
    VALUES
      ('2026-02-24', 0.48), ('2026-02-25', 0.49),
      ('2026-02-26', 0.47), ('2026-03-03', 2.85)  -- ANOMALY
  ) AS daily_backups(backup_date, data_size_gb)
)
SELECT
  backup_date,
  ROUND(data_size_gb, 2) AS size_gb,
  ROUND(rolling_avg_7day, 2) AS avg_7day_gb,
  CASE
    WHEN data_size_gb > rolling_avg_7day * 2
    THEN 'ANOMALY: Backup size significantly above normal'
    ELSE 'Normal'
  END AS status
FROM incremental_sizes
ORDER BY backup_date DESC;

-- Investigate anomalies:
-- Check which tables contributed to size spike
SHOW BACKUP '2026-03-01-full/2026-03-03T00:00:00Z' IN 'gs://acme-backups/production';
```

### Pattern 4: Backup Strategy Optimization Workflow

```bash
#!/bin/bash
# backup-efficiency-analysis.sh

echo "=== Backup Efficiency Analysis ==="
echo "Current strategy: Weekly full + daily incremental"
echo "30-day storage: 56 TB"
echo "Monthly cost: \$1,319"
echo ""
echo "Alternative strategies:"
echo "  A. Daily full: 315 TB, \$7,418/month"
echo "  B. Weekly full + daily incr: 56 TB, \$1,319/month (CURRENT)"
echo "  C. Bi-weekly full + daily incr: 38 TB, \$896/month"
echo ""
echo "Recommendation: Keep current strategy (B)"
echo "  - Optimal balance of cost and recovery time"
echo "  - Consider C if budget constraints require further reduction"
```

## Troubleshooting

### Issue 1: Incremental Backups Growing Larger Than Expected

**Symptoms:**
- Incremental backups approaching full backup size
- Storage savings not meeting expectations

**Diagnosis:**
```sql
-- Compare incremental size to base full backup
SHOW BACKUP '2026-03-01-full' IN 'gs://acme-backups/production';
-- Full: 10 GB

SHOW BACKUP '2026-03-01-full/2026-03-07T00:00:00Z' IN 'gs://acme-backups/production';
-- Incremental: 8 GB (80% of full - TOO HIGH)

-- Check which tables have excessive changes
--   table_name | data_size | % of full
-- -------------+-----------+-----------
--   sessions   | 7500000000|       75% (PROBLEM)
```

**Solutions:**
```sql
-- Solution 1: Implement row-level TTL for high-churn tables
ALTER TABLE sessions SET (ttl_expire_after = '24 hours');

-- Solution 2: Increase full backup frequency for high-churn tables
BACKUP TABLE sessions INTO 'gs://acme-backups/sessions-daily/' WITH revision_history;

-- Solution 3: Exclude ephemeral tables from regular backups
BACKUP DATABASE production INTO 'gs://acme-backups/production/'
WITH revision_history EXCEPT (production.sessions);
```

### Issue 2: Backup Performance Degradation Over Time

**Symptoms:**
- Backup duration increasing over time
- Throughput (MB/s) decreasing

**Diagnosis:**
```sql
-- Track backup performance trend
--   Date       | Type  | Size (GB) | Duration (min) | Throughput (MB/s)
-- -------------+-------+-----------+----------------+-------------------
--   2026-02-01 | Full  |      8.50 |             38 |              3.83
--   2026-03-01 | Full  |     10.50 |             62 |              2.90
-- Trend: Performance degrading ~25% over 30 days
```

**Solutions:**
```sql
-- Solution 1: Schedule backups during low-usage periods
CREATE SCHEDULE production_backup FOR BACKUP DATABASE production
INTO 'gs://acme-backups/production/' RECURRING '@daily'
WITH revision_history, SCHEDULE OPTIONS first_run = '2026-03-07 02:00:00';

-- Solution 2: Check for storage throttling
-- Monitor cloud storage metrics (S3 CloudWatch, GCS Monitoring)

-- Solution 3: Optimize storage destination
-- Use multiple prefixes for parallelism
BACKUP DATABASE production INTO 'gs://acme-backups/production/{DATE_FORMAT}/';
```

## Best Practices

1. **Establish Baseline Metrics**
   - Document initial backup sizes and performance
   - Track weekly/monthly trends for comparison
   - Set thresholds for anomaly detection

2. **Balance Cost vs Recovery Requirements**
   - Calculate actual storage costs for different strategies
   - Test restore times for various chain lengths
   - Re-evaluate as business needs change

3. **Monitor Key Efficiency Indicators**
   - Storage savings percentage
   - Daily change rate
   - Backup throughput trends
   - Anomalies (size spikes or drops)

4. **Optimize Based on Table Characteristics**
   - High-churn tables: Separate backup strategy
   - Stable tables: Longer intervals between full backups
   - Ephemeral tables: Evaluate if backups needed

5. **Automate Analysis and Reporting**
   - Script monthly efficiency reports
   - Alert on anomalies (size spikes >2× average)
   - Dashboard for backup cost tracking

6. **Regular Strategy Reviews**
   - Monthly: Review backup costs and storage trends
   - Quarterly: Analyze efficiency and optimize schedule
   - Annually: Test disaster recovery procedures

## Related Skills

- **verify-backup-file-integrity-with-checkfiles**: Validate backup completeness
- **understand-incremental-backup-concepts**: Backup chain architecture
- **create-incremental-backups-with-backup-into-latest**: Create efficient backup chains
- **manage-backup-retention-policies**: Optimize retention based on efficiency analysis
- **inspect-backup-contents-with-show-backup**: Extract detailed backup metadata
- **create-automated-backup-schedules**: Implement optimized backup frequencies
