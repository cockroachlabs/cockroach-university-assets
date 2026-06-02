---
name: inspect-backup-contents-with-show-backup
description: Inspect CockroachDB backup metadata using SHOW BACKUP command to examine databases, tables, row counts, and sizes. Use when user asks to "check backup contents", "verify backup", "what's in backup", "inspect backup", or needs to validate backup before restore.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
  tested: false
---

# Inspect Backup Contents with SHOW BACKUP

**Domain**: Backup and Restore
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to inspect backup metadata using `SHOW BACKUP` to validate backup contents before restore operations. You'll learn to examine databases, tables, row counts, sizes, timestamps, and verify backup chain integrity without actually restoring data.

**When to use this skill:**
- Validating backup contents before restore
- Verifying scheduled backups are capturing expected data
- Auditing backup chains for compliance
- Troubleshooting backup issues (missing tables, size anomalies)
- Planning restore operations and estimating time

**Key concepts covered:**
- SHOW BACKUP metadata columns and interpretation
- Inspecting full vs incremental backups
- Verifying backup chain integrity
- File integrity checking with check_files option
- Backup validation workflows

## Basic Syntax

```sql
-- Inspect latest backup in location
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster';

-- Inspect specific backup by timestamp path
SHOW BACKUP FROM '2026/03/06-140000.00' IN 'nodelocal://1/backups/cluster';

-- With file integrity check
SHOW BACKUP FROM LATEST IN 's3://backups/prod' WITH check_files;
```

**Important**: `SHOW BACKUP` is read-only - it does not modify or restore any data.

## Output Columns

### Key Metadata Fields

**database_name**: Database containing the table
**object_name**: Table name in the backup
**start_time**: Timestamp when backup started
**end_time**: Timestamp when backup completed
**size_bytes**: Total compressed data size
**rows**: Approximate row count
**is_full_cluster**: true if full cluster backup

### Example Output

```
  database_name | object_name | rows   | size_bytes  | start_time             | end_time
+---------------+-------------+--------+-------------+------------------------+-----------------------+
  production    | users       | 500000 | 52428800    | 2026-03-06 14:00:00   | 2026-03-06 14:15:00
  production    | orders      | 1200000| 104857600   | 2026-03-06 14:00:00   | 2026-03-06 14:15:00
  production    | products    | 50000  | 10485760    | 2026-03-06 14:00:00   | 2026-03-06 14:15:00
```

## Step-by-Step Validation Workflow

### 1. List Available Backups

```sql
-- See all backups in destination
SHOW BACKUPS IN 'nodelocal://1/backups/cluster';

-- Example output:
--          path
-- ----------------------
--  2026/03/01-000000.00
--  2026/03/02-000000.00
--  2026/03/03-000000.00
--  2026/03/06-140000.00
```

### 2. Inspect Latest Backup

```sql
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster';
```

### 3. Validate Expected Contents

**Checklist:**
- [ ] All expected databases present
- [ ] Table count matches production
- [ ] Row counts reasonable (within 10% of expected)
- [ ] Backup completed recently (check end_time)
- [ ] No zero-size tables (unless expected)
- [ ] No missing critical tables

### 4. Query Backup Metadata

```sql
-- Count databases in backup
SELECT COUNT(DISTINCT database_name)
FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster'];

-- Count total tables
SELECT COUNT(*)
FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster'];

-- Check specific database
SELECT object_name, rows, size_bytes/1024/1024 AS size_mb
FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster']
WHERE database_name = 'production'
ORDER BY size_bytes DESC;

-- Sum total backup size
SELECT
  SUM(size_bytes)/1024/1024/1024 AS total_size_gb,
  SUM(rows) AS total_rows
FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster'];
```

## Common Validation Patterns

### Pattern 1: Pre-Restore Validation

```sql
-- Step 1: Verify backup exists and is recent
SHOW BACKUPS IN 's3://backups/prod';

-- Step 2: Inspect contents
SHOW BACKUP FROM LATEST IN 's3://backups/prod';

-- Step 3: Verify target database exists
SELECT object_name, rows
FROM [SHOW BACKUP FROM LATEST IN 's3://backups/prod']
WHERE database_name = 'application_db';

-- Step 4: If valid, proceed with restore
RESTORE DATABASE application_db FROM LATEST IN 's3://backups/prod';
```

### Pattern 2: Backup Completeness Check

```sql
-- Compare backup to live cluster
WITH live_tables AS (
  SELECT table_schema AS database_name, table_name
  FROM information_schema.tables
  WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'crdb_internal', 'pg_extension')
),
backup_tables AS (
  SELECT database_name, object_name
  FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster']
)
SELECT
  'Missing from backup' AS status,
  database_name,
  table_name
FROM live_tables
WHERE (database_name, table_name) NOT IN (SELECT database_name, object_name FROM backup_tables);
```

### Pattern 3: Incremental Chain Inspection

```sql
-- List all backups in chain
SHOW BACKUPS IN 's3://backups/prod';

-- Inspect full backup (first in chain)
SHOW BACKUP FROM '2026/03/01-000000.00' IN 's3://backups/prod';
-- Expected: Large size_bytes (contains all data)

-- Inspect incremental backups
SHOW BACKUP FROM '2026/03/02-000000.00' IN 's3://backups/prod';
SHOW BACKUP FROM '2026/03/03-000000.00' IN 's3://backups/prod';
-- Expected: Smaller size_bytes (only changed data)

-- Compare sizes to verify incrementals working
SELECT
  '2026/03/01 full' AS backup,
  SUM(size_bytes)/1024/1024/1024 AS size_gb
FROM [SHOW BACKUP FROM '2026/03/01-000000.00' IN 's3://backups/prod']
UNION ALL
SELECT
  '2026/03/02 incr',
  SUM(size_bytes)/1024/1024/1024
FROM [SHOW BACKUP FROM '2026/03/02-000000.00' IN 's3://backups/prod'];
```

## Advanced Options

### File Integrity Checking

```sql
-- Verify all backup files exist in storage
SHOW BACKUP FROM LATEST IN 's3://backups/prod' WITH check_files;
```

**What check_files does:**
- Verifies backup manifest file exists
- Checks all referenced SST (data) files exist
- Does NOT validate data corruption (use verify_backup_table_data for that)
- Adds latency (reads file metadata from storage)

**When to use:**
- Before critical restore operations
- After storage migrations or copies
- During disaster recovery drills
- Monthly backup audits

### Verify Data Integrity

```sql
-- Expensive: Reads and checksums all data (use sparingly)
RESTORE DATABASE production
FROM LATEST IN 's3://backups/prod'
WITH verify_backup_table_data, schema_only;
```

**Note**: This validates data checksums but only restores schema (not data) - useful for testing backup integrity.

## Troubleshooting

### Issue 1: Error "backup not found"

**Symptoms:**
```
ERROR: backup not found in specified location
```

**Diagnosis:**
```sql
-- List available backups first
SHOW BACKUPS IN 'nodelocal://1/backups/cluster';

-- Verify path syntax correct (check for typos)
```

**Common Causes:**
1. Wrong storage path
2. Backup hasn't completed yet (check SHOW JOBS)
3. Credentials issue (can't access storage)

**Solutions:**
```sql
-- Verify backup job completed
SELECT job_id, status, description
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
ORDER BY created DESC
LIMIT 10;

-- Check correct path
SHOW BACKUPS IN 'nodelocal://1/backups/cluster';  -- Not /prod/backups
```

### Issue 2: Row Counts Show 0 or NULL

**Symptoms:**
- `rows` column shows 0 for tables that should have data
- Inconsistent with production table sizes

**Diagnosis:**
```sql
-- Compare to live cluster
SELECT COUNT(*) FROM production.users;  -- Returns 500,000

-- Check backup
SELECT rows
FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/cluster']
WHERE object_name = 'users';  -- Shows 0
```

**Possible Causes:**
1. Empty tables (expected for some tables)
2. Backup metadata not yet updated (rare, usually eventual consistency)
3. Corrupted backup (restore test to verify)

**Solutions:**
```sql
-- Solution 1: Check if table actually empty in cluster
SELECT COUNT(*) FROM production.users;

-- Solution 2: Test restore to temp database
RESTORE DATABASE production
FROM LATEST IN 'nodelocal://1/backups/cluster'
WITH into_db = 'production_test';

-- Verify restored data
SELECT COUNT(*) FROM production_test.users;
```

### Issue 3: check_files Fails

**Symptoms:**
```
ERROR: file not found in backup storage
ERROR: manifest file missing
```

**Diagnosis:**
```sql
-- Attempt file integrity check
SHOW BACKUP FROM LATEST IN 's3://backups/prod' WITH check_files;
-- Fails with file error
```

**Causes:**
- Backup files deleted or corrupted
- Storage bucket/path changed
- Permissions issue preventing file access

**Solutions:**
```sql
-- Solution 1: Use different backup if available
SHOW BACKUPS IN 's3://backups/prod';
-- Find earlier backup that's valid
SHOW BACKUP FROM '2026/03/05-000000.00' IN 's3://backups/prod' WITH check_files;

-- Solution 2: Start new backup chain
BACKUP INTO 's3://backups/prod-new' AS OF SYSTEM TIME '-10s';

-- Solution 3: Check storage permissions
-- Verify AWS/GCS credentials have read access to bucket
```

## Best Practices

1. **Always Inspect Before Restore**
   - Run `SHOW BACKUP` to verify contents match expectations
   - Check row counts are reasonable
   - Confirm backup timestamp is recent enough

2. **Automate Validation**
   - Script weekly backup content checks
   - Alert on missing tables or size anomalies
   - Monitor backup chain integrity

3. **Use check_files for Critical Restores**
   - Verify file integrity before disaster recovery
   - Run during monthly DR drills
   - Balance latency cost vs confidence gain

4. **Document Expected Contents**
   - Maintain list of expected databases/tables
   - Document expected row count ranges
   - Update when schema changes

5. **Monitor Backup Sizes**
   - Track size_bytes trends over time
   - Alert on unexpected 2x size increases
   - Investigate sudden drops (missing data?)

6. **Test Restore Regularly**
   - Monthly: Inspect backup contents
   - Quarterly: Full restore test to temp environment
   - Annually: Full disaster recovery drill

## Quick Reference Commands

```sql
-- List all backups in destination
SHOW BACKUPS IN '<destination>';

-- Inspect latest backup
SHOW BACKUP FROM LATEST IN '<destination>';

-- Inspect specific backup
SHOW BACKUP FROM '<timestamp-path>' IN '<destination>';

-- With file integrity check
SHOW BACKUP FROM LATEST IN '<destination>' WITH check_files;

-- Count databases
SELECT COUNT(DISTINCT database_name) FROM [SHOW BACKUP FROM LATEST IN '<dest>'];

-- Sum total size
SELECT SUM(size_bytes)/1024/1024/1024 AS size_gb FROM [SHOW BACKUP FROM LATEST IN '<dest>'];

-- Filter by database
SELECT * FROM [SHOW BACKUP FROM LATEST IN '<dest>'] WHERE database_name = 'mydb';
```

## Related Skills

- **list-available-backups-with-show-backups**: List all backups in a location
- **verify-backup-file-integrity-with-checkfiles**: Deep dive into file integrity checking
- **execute-cluster-level-full-backups**: Create backups to inspect
- **create-incremental-backups-with-backup-into-latest**: Build backup chains to inspect
- **restore-database-from-backup**: Restore after validating with SHOW BACKUP
- **validate-restored-data-completeness**: Verify data after restore operations
- **manage-backup-retention-policies**: Implement retention based on backup inspection
- **analyze-incremental-backup-efficiency**: Use SHOW BACKUP to calculate savings
