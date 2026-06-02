---
name: create-incremental-backups-with-backup-into-latest
description: Create incremental backups using BACKUP INTO LATEST command to capture only data changed since last backup. Use when user asks for "incremental backup", "backup changes only", "reduce backup size", "hourly backups", or wants storage-efficient frequent backups.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  tested: false
---

# Create Incremental Backups with BACKUP INTO LATEST

**Domain**: Backup and Restore
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to create storage-efficient incremental backups using the `BACKUP INTO LATEST` command. You'll learn to capture only changed data since the last backup, build backup chains, and optimize storage costs while maintaining comprehensive backup coverage.

**When to use this skill:**
- Implementing hourly or frequent backup schedules
- Reducing backup storage costs by 70-90%
- Meeting tight RPO requirements without excessive storage
- Building automated backup strategies with schedules
- Managing backup chains for point-in-time recovery

**Key concepts covered:**
- Automatic chain detection and extension
- Full vs incremental backup creation
- Backup chain structure and dependencies
- Storage savings calculation
- Chain management and validation

## Basic Syntax

```sql
-- Create incremental backup (extends existing chain)
BACKUP INTO LATEST IN 'nodelocal://1/backups/cluster';

-- Recommended: with timestamp
BACKUP INTO LATEST IN 'nodelocal://1/backups/cluster'
  AS OF SYSTEM TIME '-10s';
```

## How It Works

### First Backup Creates Full

If destination is empty, `BACKUP INTO LATEST` creates a full backup:

```sql
-- First run: Creates full backup automatically
BACKUP INTO LATEST IN 'nodelocal://1/backups/new-location';
```

### Subsequent Backups Create Incrementals

Once full backup exists, creates incrementals:

```sql
-- Second run: Creates incremental (changes since full)
BACKUP INTO LATEST IN 'nodelocal://1/backups/new-location';

-- Third run: Creates incremental (changes since last incremental)  
BACKUP INTO LATEST IN 'nodelocal://1/backups/new-location';
```

### Automatic Chain Detection

CockroachDB automatically:
1. Checks destination for existing backups
2. Finds most recent backup timestamp
3. Captures changes since that timestamp
4. Maintains backup chain integrity

## Step-by-Step

```sql
-- Step 1: Create initial full backup (runs automatically)
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod' AS OF SYSTEM TIME '-10s';
-- Result: Full backup created

-- Step 2: Create incremental (captures changes since full)
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod' AS OF SYSTEM TIME '-10s';
-- Result: Incremental with only changed data

-- Step 3: Continue creating incrementals (hourly/daily)
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod' AS OF SYSTEM TIME '-10s';
-- Result: Each incremental captures changes since last backup

-- Step 4: Verify backup chain
SHOW BACKUPS IN 'nodelocal://1/backups/prod';
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/prod';
```

## Common Patterns

### Pattern 1: Hourly Incrementals

```sql
-- Automated hourly incremental backups
CREATE SCHEDULE hourly_incremental
  FOR BACKUP INTO 'nodelocal://1/backups/prod'
  RECURRING '@hourly';
```

### Pattern 2: Weekly Full + Daily Incrementals

```sql
-- Full backup weekly, incrementals daily
CREATE SCHEDULE prod_backup
  FOR BACKUP INTO 'nodelocal://1/backups/prod'
  RECURRING '@daily'
  FULL BACKUP '@weekly';
```

**Result**:
- Sunday: Full backup (new chain)
- Mon-Sat: Daily incrementals
- Next Sunday: New full backup (new chain)

### Pattern 3: Manual Incremental After Changes

```sql
-- After major data load or migration
BACKUP INTO LATEST IN 'nodelocal://1/backups/post-migration' AS OF SYSTEM TIME '-10s';
```

## Storage Savings Example

**1 TB database, 2% daily change rate**:
- Daily full backups: 7 TB/week
- Weekly full + daily incrementals: 1.12 TB/week (1 TB + 6×20 GB)
- **Savings: 84%**

## Advanced Options

### Database-Level Incrementals

```sql
-- Incremental backup of specific database
BACKUP DATABASE mydb INTO LATEST IN 'nodelocal://1/backups/mydb'
  AS OF SYSTEM TIME '-10s';
```

### Incremental with Revision History

```sql
-- Incremental with PITR support
BACKUP INTO LATEST IN 'nodelocal://1/backups/pitr'
  WITH revision_history;
```

## Cloud Storage Examples

### S3 Backup Chain

```sql
-- Initial full backup (first run)
BACKUP INTO LATEST IN 's3://my-company-backups/production?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=yyy'
  AS OF SYSTEM TIME '-10s';

-- Subsequent incrementals (hourly runs)
BACKUP INTO LATEST IN 's3://my-company-backups/production?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=yyy'
  AS OF SYSTEM TIME '-10s';
```

### GCS Backup Chain

```sql
-- Using specified credentials
BACKUP INTO LATEST IN 'gs://acme-backups/prod-cluster?AUTH=specified&CREDENTIALS=base64-encoded-key'
  AS OF SYSTEM TIME '-10s';
```

**Best practice**: Store credentials in environment variables or use implicit auth (IAM roles)

### Azure Blob Storage

```sql
BACKUP INTO LATEST IN 'azure://backups-container/prod?AZURE_ACCOUNT_NAME=myaccount&AZURE_ACCOUNT_KEY=xxx'
  AS OF SYSTEM TIME '-10s';
```

## Troubleshooting

### Issue 1: Error "no full backup found"

**Symptoms:**
```
ERROR: no full backup found in destination
```

**Cause**: Attempting `BACKUP INTO LATEST` when no full backup exists at the destination

**Diagnosis:**
```sql
-- Check for existing backups
SHOW BACKUPS IN 'nodelocal://1/backups/new';
-- Returns empty or error
```

**Solutions:**
```sql
-- Solution 1: Create initial full backup
BACKUP INTO 'nodelocal://1/backups/new' AS OF SYSTEM TIME '-10s';

-- Now LATEST works
BACKUP INTO LATEST IN 'nodelocal://1/backups/new' AS OF SYSTEM TIME '-10s';

-- Solution 2: Use BACKUP INTO on first run (creates full automatically)
-- Then BACKUP INTO LATEST for subsequent runs
```

**Prevention**: Always verify backup destination exists or use `BACKUP INTO LATEST` consistently (it auto-creates full on first run)

### Issue 2: Incremental Unexpectedly Large

**Symptoms:**
- Incremental backup size approaching full backup size (>50%)
- Storage savings not meeting expectations (should be 5-15% typically)
- Backup duration similar to full backups

**Diagnosis:**
```sql
-- List backup chain with sizes
SHOW BACKUPS IN 'nodelocal://1/backups/prod';

-- Compare full vs incremental sizes
SHOW BACKUP FROM '2026/03/01-000000.00' IN 'nodelocal://1/backups/prod';  -- Full: 10 GB
SHOW BACKUP FROM '2026/03/02-000000.00' IN 'nodelocal://1/backups/prod';  -- Incr: 8 GB (TOO HIGH)

-- Identify high-churn tables
SELECT table_name, rows, size_bytes/1024/1024/1024 AS size_gb
FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/prod']
ORDER BY size_bytes DESC;
```

**Common Causes:**
1. **High data change rate** (20%+ daily) - Expected in write-heavy workloads
2. **Schema changes** - ALTER TABLE operations cause table to be fully backed up
3. **Bulk operations** - Large INSERT/UPDATE/DELETE between backups
4. **Compaction changes** - RocksDB compaction reshuffling SSTables

**Solutions:**
```sql
-- Solution 1: Increase full backup frequency for high-churn tables
CREATE SCHEDULE high_churn_tables
  FOR BACKUP TABLE mydb.sessions INTO 'nodelocal://1/backups/sessions'
  RECURRING '@daily'
  FULL BACKUP '@daily';  -- Full every day due to high churn

-- Solution 2: Implement row-level TTL to reduce dataset size
ALTER TABLE sessions SET (ttl_expire_after = '24 hours');

-- Solution 3: Separate backup strategies by change rate
-- Low-churn tables: Weekly full + daily incremental
-- High-churn tables: Daily full backups

-- Solution 4: Start new backup chain (creates fresh full)
BACKUP INTO 'nodelocal://1/backups/prod' AS OF SYSTEM TIME '-10s';
```

### Issue 3: Chain Broken - Cannot Restore

**Symptoms:**
```
ERROR: backup layer missing in chain
ERROR: unable to find full backup
```

**Cause**: Deleted backup in the middle of chain, breaking dependency path

**Example of broken chain:**
```
Timeline:
  [Full Sun] -> [Incr Mon] -> [DELETED Tue] -> [Incr Wed]

Trying to restore Wed fails because it depends on Tue
```

**Diagnosis:**
```sql
-- List all backups in chain
SHOW BACKUPS IN 'nodelocal://1/backups/prod';

-- Attempt to show backup that should exist
SHOW BACKUP FROM '2026/03/05-000000.00' IN 'nodelocal://1/backups/prod';
-- ERROR: backup not found
```

**Solutions:**
```sql
-- Solution 1: Restore from last valid backup before deletion
RESTORE FROM '2026/03/04-000000.00' IN 'nodelocal://1/backups/prod';

-- Solution 2: Start new backup chain (if recent backup lost)
BACKUP INTO 'nodelocal://1/backups/prod-new' AS OF SYSTEM TIME '-10s';

-- Solution 3: If partial data acceptable, restore from earlier full backup
SHOW BACKUPS IN 'nodelocal://1/backups/prod';
-- Find most recent valid full backup
RESTORE FROM '2026/03/01-000000.00' IN 'nodelocal://1/backups/prod';
```

**Prevention Best Practices:**
```sql
-- Never delete individual backups in a chain
-- Instead, delete entire chains at once

-- BAD: Delete single incremental
-- rm -rf /cockroach-data/extern/backups/prod/2026/03/04-000000.00

-- GOOD: Delete entire old chain
-- rm -rf /cockroach-data/extern/backups/prod-week-of-feb-24/

-- Implement retention policies with GC (garbage collection) options
CREATE SCHEDULE prod_backup
  FOR BACKUP INTO 'gs://backups/prod'
  RECURRING '@hourly'
  FULL BACKUP '@weekly'
  WITH SCHEDULE OPTIONS gc_protect_expires_after = '30 days';
```

### Issue 4: AS OF SYSTEM TIME Too Old

**Symptoms:**
```
ERROR: AS OF SYSTEM TIME is too far in the past
```

**Cause**: Trying to backup data older than GC window (default 25 hours)

**Solution:**
```sql
-- Check cluster GC settings
SHOW CLUSTER SETTING kv.gc.ttl;
-- Default: 25h0m0s

-- Use recent timestamp
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod'
  AS OF SYSTEM TIME '-10s';  -- Recent timestamp

-- If you need older data, increase GC window (use with caution)
SET CLUSTER SETTING kv.gc.ttl = '48h';  -- Increases storage usage
```

## Backup Chain Structure

```
Timeline:
Week 1:
  [Full Sun] -> [Incr Mon] -> [Incr Tue] -> ... -> [Incr Sat]
  
Week 2:
  [Full Sun] -> [Incr Mon] -> [Incr Tue] -> ... -> [Incr Sat]
```

**Restore from Tuesday Week 1**:
1. Restore Full (Sunday)
2. Apply Incr Mon
3. Apply Incr Tue
= Data as of Tuesday

## Monitoring Incremental Backups

**Check backup sizes**:
```sql
SHOW BACKUPS IN 'nodelocal://1/backups/prod';
```

**Look for**:
- First backup (largest = full)
- Subsequent backups (smaller = incrementals)
- Trend in incremental sizes (should be consistent)

**Monitor job history**:
```sql
SELECT job_id, status, created, description
FROM [SHOW JOBS]  
WHERE job_type = 'BACKUP'
ORDER BY created DESC
LIMIT 20;
```

## Best Practices

1. **Always use same destination** for chain integrity
2. **Start new chain weekly/monthly** to limit restore chain length
3. **Monitor incremental sizes** for unexpected growth
4. **Test restore from chain** to verify backup validity
5. **Automate with schedules** for consistency
6. **Use cloud storage** for production incrementals

## Best Practices

1. **Use Consistent Destinations**
   - Always use the same storage path for a backup chain
   - Never mix backups from different sources in same destination
   - Document backup destinations in runbooks

2. **Start New Chains Periodically**
   - Weekly or monthly full backups create new chains
   - Limits restore chain length (faster recovery)
   - Reduces risk of chain corruption affecting long history

3. **Monitor Incremental Sizes**
   - Alert on incrementals >30% of full backup size
   - Investigate sudden size increases (schema changes, bulk operations)
   - Track storage usage trends for capacity planning

4. **Automate with Schedules**
   - Use `CREATE SCHEDULE` for consistency
   - Avoid manual backup runs (prone to human error)
   - Set up monitoring for schedule failures

5. **Test Restore Regularly**
   - Monthly: Restore from incremental chain to validate
   - Verify restore completes successfully
   - Measure restore time for RTO planning

6. **Use Cloud Storage for Production**
   - S3/GCS/Azure Blob for durability and availability
   - Nodelocal only for development/testing
   - Enable versioning on cloud buckets for protection

7. **Implement Retention Policies**
   - Define retention based on compliance requirements
   - Use garbage collection options to auto-delete old backups
   - Keep at least 2 full backup chains for safety

## Performance Considerations

**Incremental backup performance factors:**

1. **Data change rate**: Higher churn = larger incrementals = longer backup time
2. **Network bandwidth**: Cloud storage backups limited by network throughput
3. **Cluster load**: Backups consume CPU/IO; schedule during low-usage periods
4. **Storage destination**: S3/GCS performance varies by region and tier

**Optimization strategies:**
```sql
-- Schedule during low-usage hours (2-4 AM)
CREATE SCHEDULE off_hours_backup
  FOR BACKUP INTO 's3://backups/prod'
  RECURRING '0 2 * * *'  -- 2 AM daily
  FULL BACKUP '0 2 * * 0';  -- 2 AM Sunday

-- Use execution locality to reduce cross-region traffic
BACKUP INTO LATEST IN 's3://backups/prod'
  WITH execution_locality = 'region=us-east1';

-- For large incrementals, increase resources temporarily
-- (adjust cluster settings before backup if needed)
```

## Comparison: BACKUP INTO vs BACKUP INTO LATEST

| Aspect | BACKUP INTO | BACKUP INTO LATEST |
|--------|-------------|-------------------|
| **Behavior** | Always creates full backup | Creates full if empty, else incremental |
| **Use case** | Starting new chain | Extending existing chain |
| **Storage** | ~10 GB per backup | ~500 MB per incremental |
| **Automation** | Requires logic to switch | Automatic detection |
| **Best for** | Weekly/monthly baseline | Hourly/daily backups |

**Example workflow:**
```sql
-- Week 1: Start new chain with full backup
BACKUP INTO 'gs://backups/prod-week-10' AS OF SYSTEM TIME '-10s';

-- Week 1: Add incrementals
BACKUP INTO LATEST IN 'gs://backups/prod-week-10' AS OF SYSTEM TIME '-10s';  -- Mon
BACKUP INTO LATEST IN 'gs://backups/prod-week-10' AS OF SYSTEM TIME '-10s';  -- Tue
-- ... continue daily

-- Week 2: Start NEW chain (new destination)
BACKUP INTO 'gs://backups/prod-week-11' AS OF SYSTEM TIME '-10s';

-- Week 2: Add incrementals to new chain
BACKUP INTO LATEST IN 'gs://backups/prod-week-11' AS OF SYSTEM TIME '-10s';
```

## Related Skills

- **understand-incremental-backup-concepts**: Learn how incrementals work architecturally
- **execute-cluster-level-full-backups**: Create initial full backup to start chain
- **inspect-backup-contents-with-show-backup**: Verify backup chain integrity
- **list-available-backups-with-show-backups**: List all backups in chain
- **create-automated-backup-schedules**: Automate LATEST backups with schedules
- **analyze-incremental-backup-efficiency**: Calculate storage savings and optimize strategy
- **manage-backup-retention-policies**: Implement retention and garbage collection
- **restore-cluster-from-full-backup**: Restore using incremental chains
