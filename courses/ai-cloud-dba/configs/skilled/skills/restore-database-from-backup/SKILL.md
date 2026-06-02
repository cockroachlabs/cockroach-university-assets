---
name: restore-database-from-backup
description: Restore databases from CockroachDB backups using RESTORE DATABASE command. Use when user asks to "restore database", "recover database", "restore from backup", "database recovery", or needs to recover specific database from backup without full cluster restore.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Restore Database from Backup

Recover specific databases from backups for targeted recovery without full cluster restore.

## Basic Syntax

```sql
-- Restore database from latest backup
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb';

-- Restore to different name (for testing/comparison)
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb'
  WITH new_db_name = 'mydb_restored';
```

## Prerequisites

### Database Must Not Exist

```sql
-- Check if database exists
SHOW DATABASES;

-- If exists, drop it first (CAUTION!)
DROP DATABASE mydb CASCADE;

-- Then restore
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb';
```

**OR use new_db_name** to restore alongside existing database

## Step-by-Step Restore

### 1. Verify Backup Exists

```sql
-- List available backups
SHOW BACKUPS IN 'nodelocal://1/backups/mydb';

-- Inspect latest backup contents
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/mydb';

-- Verify database is in backup
SELECT * FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/mydb']
WHERE database_name = 'mydb';
```

### 2. Prepare Cluster

```sql
-- Ensure target database doesn't exist
DROP DATABASE IF EXISTS mydb CASCADE;

-- Or use different name
-- (skip DROP if using new_db_name)
```

### 3. Execute Restore

```sql
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb';
```

**Expected output**:
```
        job_id       |  status   | fraction_completed
---------------------+-----------+-------------------
  123456789012345678 | succeeded |                  1
```

### 4. Verify Restore Success

```sql
-- Check database exists
SHOW DATABASES;

-- Verify tables restored
SHOW TABLES FROM mydb;

-- Check row counts
SELECT 'users' AS table_name, COUNT(*) AS rows FROM mydb.users
UNION ALL
SELECT 'orders', COUNT(*) FROM mydb.orders;

-- Compare to backup metadata
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/mydb';
```

## Common Patterns

### Pattern 1: Production Recovery

```sql
-- Scenario: Database corruption, need to recover

-- Step 1: Drop corrupted database
DROP DATABASE mydb CASCADE;

-- Step 2: Restore from latest backup
RESTORE DATABASE mydb FROM LATEST IN 's3://backups/prod/mydb';

-- Step 3: Verify and resume application
SELECT COUNT(*) FROM mydb.users;
```

### Pattern 2: Test/Dev Cloning

```sql
-- Clone production database for testing
RESTORE DATABASE prod_db FROM LATEST IN 's3://backups/prod/db'
  WITH new_db_name = 'test_db';

-- Now have both prod_db and test_db
-- Safe to test against test_db
```

### Pattern 3: Comparison Restore

```sql
-- Restore to compare data states

-- Restore yesterday's backup with different name
RESTORE DATABASE app_db FROM '2026/01/16-020000.00' IN 'nodelocal://1/backups/app'
  WITH new_db_name = 'app_db_yesterday';

-- Compare row counts
SELECT 
  (SELECT COUNT(*) FROM app_db.users) AS current_count,
  (SELECT COUNT(*) FROM app_db_yesterday.users) AS yesterday_count;

-- Compare specific data
SELECT * FROM app_db.users WHERE id = 123
EXCEPT
SELECT * FROM app_db_yesterday.users WHERE id = 123;
```

## Advanced Options

### Restore from Specific Timestamp

```sql
-- Restore from specific backup (not latest)
RESTORE DATABASE mydb FROM '2026/01/15-143022.50' IN 'nodelocal://1/backups/mydb';
```

### Point-in-Time Recovery

```sql
-- Restore to specific time (requires revision_history in backup)
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb-pitr'
  AS OF SYSTEM TIME '2026-01-15 14:00:00';
```

**Use case**: Recover from logical error at specific time

### Schema-Only Restore

```sql
-- Restore table structures without data (for validation)
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb'
  WITH schema_only;
```

**Use case**: Quickly validate schema, check CREATE TABLE statements

## Restore from Incremental Chain

**Automatic chain resolution**:
```sql
-- CockroachDB automatically applies full + incrementals
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/chain';
```

Behind the scenes:
1. Restores full backup (base)
2. Applies incremental 1
3. Applies incremental 2
4. etc.

**No manual chain management needed** with FROM LATEST

## What Gets Restored

### Included in Database Restore

- All tables and data rows
- Primary and secondary indexes
- Table schemas and constraints
- Sequences
- Views
- User-defined types
- Table-level zone configurations

### NOT Included

- Users and roles (use cluster restore)
- Permissions on database (must re-grant)
- Other databases
- Cluster settings

## Permissions After Restore

**Recreate grants**:
```sql
-- After restore, reapply permissions
GRANT ALL ON DATABASE mydb TO app_user;
GRANT SELECT, INSERT, UPDATE ON TABLE mydb.* TO app_role;
```

**Best practice**: Document grants in runbook for faster recovery

## Troubleshooting

### Error: "database already exists"

**Cause**: Cannot restore over existing database

**Solution 1** - Drop existing:
```sql
DROP DATABASE mydb CASCADE;
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb';
```

**Solution 2** - Use different name:
```sql
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/mydb'
  WITH new_db_name = 'mydb_restored';
```

### Error: "backup does not contain database mydb"

**Cause**: Backup doesn't include the database you're trying to restore

**Solution**:
```sql
-- Check what's in the backup
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/wrong';

-- Use correct backup location
RESTORE DATABASE mydb FROM LATEST IN 'nodelocal://1/backups/correct';
```

### Restore Very Slow

**Possible causes**:
- Large database (expected)
- I/O contention
- Network latency (cloud storage)
- Long incremental chain

**Monitor progress**:
```sql
SELECT fraction_completed FROM [SHOW JOBS]
WHERE job_type = 'RESTORE' AND status = 'running';
```

**Optimization**:
- Use faster storage
- Restore during low-traffic window
- Consider shorter backup chains

### Row Counts Don't Match

**After restore**:
```sql
-- Compare restored counts to backup metadata
SELECT table_name, COUNT(*) FROM mydb.users;

-- vs

SELECT rows FROM [SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/mydb']
WHERE table_name = 'users';
```

**If mismatch**:
- Backup metadata is approximate (not exact)
- Small differences (<1%) normal
- Large differences suggest restore issue

## Validation Checklist

After restore completes:

- [ ] Database exists (`SHOW DATABASES`)
- [ ] All tables present (`SHOW TABLES`)
- [ ] Row counts match expectations
- [ ] Indexes exist (`SHOW INDEXES`)
- [ ] Constraints valid (`SHOW CONSTRAINTS`)
- [ ] Can query tables (sample SELECT)
- [ ] Can write to tables (test INSERT)
- [ ] Permissions reapplied

## Application Reconnection

After successful restore:

```sql
-- 1. Verify database healthy
SELECT COUNT(*) FROM mydb.users;

-- 2. Test key queries
SELECT * FROM mydb.users WHERE id = 1;

-- 3. Test write operations
INSERT INTO mydb.test_table VALUES (1, 'test');

-- 4. Resume application connections
```

## Best Practices

1. **Always inspect backup before restore** with SHOW BACKUP
2. **Test restores in non-production first** when possible
3. **Document permission grants** for faster recovery
4. **Verify row counts** after restore
5. **Use new_db_name for testing** to avoid dropping production data
6. **Monitor restore progress** with SHOW JOBS
7. **Have rollback plan** if restore doesn't work

## Restore Performance

**Expected times** (approximate):

| Database Size | Restore Time |
|---------------|-------------|
| 1 GB          | 1-2 minutes |
| 10 GB         | 5-15 minutes |
| 100 GB        | 30-90 minutes |
| 1 TB          | 4-12 hours |

*Times vary based on I/O, network, cluster resources*

## Related Skills

- `inspect-backup-contents-with-show-backup` - Verify backup before restore
- `list-available-backups-with-show-backups` - Find available restore points
- `execute-database-level-backups` - Create database backups
- `understand-incremental-backup-concepts` - Understanding backup chains
