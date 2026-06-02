---
name: create-automated-backup-schedules
description: Create automated recurring backup schedules in CockroachDB using CREATE SCHEDULE FOR BACKUP command. Use when user asks to "automate backups", "schedule backups", "recurring backups", "automatic backups", or wants backups to run without manual intervention.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  tested: false
---

# Create Automated Backup Schedules

**Domain**: Backup and Restore
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to create automated, recurring backup schedules using `CREATE SCHEDULE FOR BACKUP`. You'll learn to define backup frequencies using CRON expressions, implement full+incremental strategies, and maintain hands-off backup coverage for production environments.

**When to use this skill:**
- Setting up production backup automation
- Meeting compliance requirements for regular backups
- Implementing consistent RPO/RTO targets
- Eliminating manual backup processes
- Creating backup strategies with full and incremental patterns

**Key concepts covered:**
- CRON expression syntax for backup timing
- Full vs incremental backup scheduling
- Schedule lifecycle management (create, pause, resume, drop)
- Monitoring schedule execution and failures
- Cloud storage integration for automated backups

## Basic Syntax

```sql
-- Daily incremental backups, weekly full backups
CREATE SCHEDULE daily_backup
  FOR BACKUP INTO 'nodelocal://1/backups/scheduled'
  RECURRING '@daily'
  FULL BACKUP '@weekly';
```

**Returns**: Schedule ID for management

## When to Use Scheduled Backups

**Use schedules for**:
- Production environments needing continuous backup coverage
- Consistent RPO targets (1 hour, 4 hours, daily, etc.)
- Hands-off backup operations
- Compliance requirements for regular backups

**Don't use for**:
- One-time backups (use BACKUP INTO directly)
- Ad-hoc testing backups
- Pre-migration snapshots

## CRON Shortcuts

**Common shortcuts**:
- `@hourly` - Every hour (top of the hour)
- `@daily` - Every day at midnight UTC
- `@weekly` - Every Sunday at midnight UTC
- `@monthly` - First day of month at midnight UTC

## Step-by-Step

### 1. Basic Daily Backup Schedule

```sql
-- Daily backups at midnight UTC
CREATE SCHEDULE prod_daily_backup
  FOR BACKUP INTO 'nodelocal://1/backups/prod'
  RECURRING '@daily';
```

**Result**: Runs full backup daily at 00:00 UTC

### 2. Incremental + Full Backup Strategy

```sql
-- Hourly incrementals, weekly full backups
CREATE SCHEDULE prod_backup
  FOR BACKUP INTO 'nodelocal://1/backups/prod'
  RECURRING '@hourly'          -- Incremental backups hourly
  FULL BACKUP '@weekly';       -- Full backup every Sunday
```

**Result**:
- Hourly: Incremental backups (changes only)
- Sunday 00:00 UTC: Full backup (new chain starts)

### 3. Database-Specific Schedule

```sql
-- Schedule for specific database
CREATE SCHEDULE app_db_backup
  FOR BACKUP DATABASE application_db INTO 'nodelocal://1/backups/app'
  RECURRING '@daily'
  FULL BACKUP '@weekly';
```

## Common Patterns

### Pattern 1: Production Standard (Hourly Incrementals)

```sql
CREATE SCHEDULE 'Production Hourly Backups'
  FOR BACKUP INTO 'nodelocal://1/backups/prod'
  RECURRING '@hourly'
  FULL BACKUP '@weekly';
```

**RPO**: 1 hour (max data loss)
**Storage**: Efficient (incrementals small)

### Pattern 2: High-Frequency (15-Minute RPO)

```sql
CREATE SCHEDULE 'Critical 15min RPO'
  FOR BACKUP DATABASE critical_db INTO 'nodelocal://1/backups/critical'
  RECURRING '*/15 * * * *'      -- Every 15 minutes
  FULL BACKUP '0 2 * * 0';      -- Sunday 2 AM
```

**RPO**: 15 minutes
**Use case**: Financial, healthcare systems

### Pattern 3: Development (Daily Only)

```sql
CREATE SCHEDULE 'Dev Daily Backup'
  FOR BACKUP INTO 'nodelocal://1/backups/dev'
  RECURRING '@daily';
```

**No FULL BACKUP clause**: Creates full backup every run

## Custom CRON Expressions

### Specific Times

```sql
-- Every day at 2:30 AM
CREATE SCHEDULE nightly_backup
  FOR BACKUP INTO 'nodelocal://1/backups/nightly'
  RECURRING '30 2 * * *';

-- Weekdays at 6 PM
CREATE SCHEDULE weekday_evening
  FOR BACKUP INTO 'nodelocal://1/backups/weekday'
  RECURRING '0 18 * * 1-5';

-- First day of month at 3 AM
CREATE SCHEDULE monthly_backup
  FOR BACKUP INTO 'nodelocal://1/backups/monthly'
  RECURRING '0 3 1 * *';
```

## Schedule Options

### WITH EXPERIMENTAL SCHEDULE OPTIONS

```sql
-- Set first run time
CREATE SCHEDULE 'Production Daily Backup'
  FOR BACKUP INTO 'nodelocal://1/backups/detailed'
  RECURRING '@daily'
  WITH EXPERIMENTAL SCHEDULE OPTIONS first_run = '2026-03-06 02:00:00';
```

**Available Options** (require EXPERIMENTAL prefix):
- `first_run`: When to execute first backup (timestamp, defaults to now)
- `on_execution_failure`: How to handle failures ('retry', 'reschedule', 'pause')
- `on_previous_running`: What to do if previous backup still running ('start', 'skip', 'wait')
- `ignore_existing_backups`: Start fresh backup chain (boolean)

## Verify Schedule Created

```sql
-- List all schedules
SHOW SCHEDULES;

-- Find specific schedule by name
SELECT * FROM [SHOW SCHEDULES]
WHERE schedule_name LIKE '%Production%';
```

**Check**:
- `schedule_status`: Should be 'ACTIVE'
- `next_run`: Shows next execution time
- `recurrence`: Confirms CRON expression

## Cloud Storage Destinations

### S3

```sql
CREATE SCHEDULE s3_backup
  FOR BACKUP INTO 's3://my-bucket/backups?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=yyy'
  RECURRING '@daily'
  FULL BACKUP '@weekly';
```

### GCS

```sql
CREATE SCHEDULE gcs_backup
  FOR BACKUP INTO 'gs://my-bucket/backups?AUTH=specified&CREDENTIALS=xxx'
  RECURRING '@daily'
  FULL BACKUP '@weekly';
```

## What Happens After Creation

**Immediately**:
1. Schedule created with ACTIVE status
2. First backup scheduled (first_run or immediately)
3. Schedule ID returned

**Ongoing**:
1. Incremental backups run per RECURRING schedule
2. Full backups run per FULL BACKUP schedule
3. Backup jobs tracked in SHOW JOBS
4. Schedules persist across cluster restarts

## Monitoring

### Check Schedule Status

```sql
SHOW SCHEDULES WHERE schedule_name = 'Production Hourly Backups';
```

### Check Recent Backup Jobs

```sql
SELECT job_id, status, created, description
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
ORDER BY created DESC
LIMIT 10;
```

## Retention and Garbage Collection

**Note**: Automatic backup retention is managed through the `gc.ttlseconds` zone configuration on the backup storage destination, not through schedule options. To implement retention policies, see the related skill **manage-backup-retention-policies**.

Manual cleanup example:

```sql
-- List backups to identify old ones
SHOW BACKUPS IN 's3://backups/prod';

-- Manually delete old backup subdirectories as needed
-- (requires external tools or storage management)
```

## Troubleshooting

### Issue 1: Schedule Created but No Backups Running

**Symptoms:**
- Schedule shows in `SHOW SCHEDULES` but no backup jobs executing
- `next_run` timestamp not updating

**Diagnosis:**
```sql
-- Check schedule details
SHOW SCHEDULES;

-- Look for:
-- schedule_status column
-- next_run timestamp
-- jobsrunning count
```

**Common Causes and Solutions:**

**Cause 1: Schedule paused**
```sql
-- Check status
SELECT id, label, schedule_status FROM [SHOW SCHEDULES] WHERE label = 'prod_backup';
-- schedule_status = 'PAUSED'

-- Solution: Resume schedule
RESUME SCHEDULES <schedule_id>;
```

**Cause 2: first_run set in future**
```sql
-- Schedule won't run until first_run time
SELECT id, label, next_run FROM [SHOW SCHEDULES];
-- next_run = '2026-04-01 00:00:00' (future date)

-- Solution: Wait for scheduled time, or drop and recreate with earlier first_run
```

**Cause 3: CRON expression never matches (invalid)**
```sql
-- Invalid CRON like '70 25 * * *' (invalid hour/minute)
-- Solution: Fix CRON expression
DROP SCHEDULES <bad_schedule_id>;
CREATE SCHEDULE prod_backup
  FOR BACKUP INTO 's3://backups/prod'
  RECURRING '0 2 * * *';  -- Valid: 2 AM daily
```

### Issue 2: Backup Jobs Consistently Failing

**Symptoms:**
- Schedule active and running, but all backup jobs fail
- `SHOW JOBS` shows repeated failures

**Diagnosis:**
```sql
-- Check recent backup job failures
SELECT job_id, created, description, error
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP' AND status = 'failed'
ORDER BY created DESC
LIMIT 10;
```

**Common Errors:**

**Error: "permission denied" or "access denied"**
```
Cause: Invalid or expired cloud storage credentials
```

**Solutions:**
```sql
-- Option 1: Update credentials in schedule
DROP SCHEDULES <old_schedule_id>;
CREATE SCHEDULE prod_backup
  FOR BACKUP INTO 's3://backups/prod?AWS_ACCESS_KEY_ID=new-key&AWS_SECRET_ACCESS_KEY=new-secret'
  RECURRING '@daily';

-- Option 2: Use IAM roles (recommended for production)
-- Configure cluster nodes with IAM role, then:
CREATE SCHEDULE prod_backup
  FOR BACKUP INTO 's3://backups/prod?AUTH=implicit'
  RECURRING '@daily';
```

**Error: "no space left on device"**
```
Cause: Insufficient disk space for backup operation
```

**Solutions:**
```sql
-- Check disk usage
SELECT node_id, store_id, capacity, available
FROM crdb_internal.kv_store_status;

-- If local storage full:
-- 1. Use cloud storage instead of nodelocal
-- 2. Increase disk capacity
-- 3. Delete old backups to free space
```

**Error: "backup location already in use"**
```
Cause: Multiple schedules writing to same destination
```

**Solutions:**
```sql
-- Use unique destination per schedule
CREATE SCHEDULE schedule_a
  FOR BACKUP INTO 's3://backups/prod-schedule-a'  -- Unique path
  RECURRING '@hourly';

CREATE SCHEDULE schedule_b
  FOR BACKUP INTO 's3://backups/prod-schedule-b'  -- Different path
  RECURRING '@daily';
```

### Issue 3: Schedule Running but Incrementals Not Created

**Symptoms:**
- Every backup is full size (no incrementals)
- Storage usage growing faster than expected

**Diagnosis:**
```sql
-- Check if FULL BACKUP clause missing or set to same frequency
SHOW SCHEDULES;

-- Look at backup chain
SHOW BACKUPS IN 's3://backups/prod';
-- All backups similar size (all fulls, no incrementals)
```

**Cause**: FULL BACKUP not specified, or equals RECURRING frequency

**Solution:**
```sql
-- BAD: Creates full backup every hour
CREATE SCHEDULE bad_schedule
  FOR BACKUP INTO 's3://backups/prod'
  RECURRING '@hourly'
  FULL BACKUP '@hourly';  -- Same frequency = all fulls

-- GOOD: Creates incrementals hourly, full weekly
CREATE SCHEDULE good_schedule
  FOR BACKUP INTO 's3://backups/prod'
  RECURRING '@hourly'
  FULL BACKUP '@weekly';  -- Full less frequent than incremental
```

## Schedule Lifecycle

**Create** → **Monitor** → **Modify/Pause** → **Drop**

```sql
-- Create
CREATE SCHEDULE ...

-- Monitor  
SHOW SCHEDULES;

-- Pause for maintenance
PAUSE SCHEDULES <id>;

-- Resume
RESUME SCHEDULES <id>;

-- Remove permanently
DROP SCHEDULES <id>;
```

## Best Practices

1. **Use Descriptive Names** - Create schedules with clear names like 'Production Hourly Backups'
2. **Start Conservative** - Begin with daily backups, increase frequency based on RPO
3. **Monitor First Runs** - Ensure backups succeed before trusting automation
4. **Match FULL BACKUP to Retention** - Weekly full = 1 week max chain length
5. **Cloud Storage for Production** - Use S3/GCS/Azure (not nodelocal)
6. **Set Alerts** - Monitor backup job failures and schedule health
7. **Test Restore Regularly** - Monthly restore tests from scheduled backups
8. **Implement Retention** - Manually manage old backups or use external lifecycle policies

## CRON Expression Reference

```
@hourly   = 0 * * * *    | @daily    = 0 0 * * *   | @weekly   = 0 0 * * 0
@monthly  = 0 0 1 * *    | 0 2 * * * = Daily 2 AM  | */30 * * * * = Every 30min
```

**Format**: `minute hour day_of_month month day_of_week`

## Quick Reference Commands

```sql
-- Create schedule
CREATE SCHEDULE <name> FOR BACKUP INTO '<dest>' RECURRING '<cron>' FULL BACKUP '<cron>';

-- List all schedules
SHOW SCHEDULES;

-- Pause schedule (stops future backups)
PAUSE SCHEDULES <id>;

-- Resume paused schedule
RESUME SCHEDULES <id>;

-- Delete schedule permanently
DROP SCHEDULES <id>;

-- Check recent backup jobs
SELECT job_id, status, created, description
FROM [SHOW JOBS] WHERE job_type = 'BACKUP' ORDER BY created DESC LIMIT 10;
```

## Related Skills

- **configure-cron-expressions-for-backup-schedules**: Deep dive into CRON syntax
- **monitor-scheduled-backups-with-show-schedules**: Monitor schedule execution and health
- **manage-backup-schedule-lifecycle**: Pause, resume, and drop schedules
- **configure-schedule-options-for-first-run-and-retention**: Advanced schedule options
- **create-incremental-backups-with-backup-into-latest**: Understand incremental strategy
- **manage-backup-retention-policies**: Implement retention and GC policies
- **execute-cluster-level-full-backups**: Manual backup alternative to schedules
- **inspect-backup-contents-with-show-backup**: Verify scheduled backup contents
