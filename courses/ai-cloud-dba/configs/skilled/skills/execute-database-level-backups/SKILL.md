---
name: execute-database-level-backups
description: Create database-level backups in CockroachDB using BACKUP DATABASE command. Use when user asks to "backup a database", "backup specific database", "application backup", or needs targeted recovery for single database without full cluster restore.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Execute Database-Level Backups

Create backups of specific databases for targeted recovery strategies.

## Basic Syntax

```sql
-- Backup single database
BACKUP DATABASE mydb INTO 'nodelocal://1/backups/mydb';

-- Recommended: with timestamp
BACKUP DATABASE mydb INTO 'nodelocal://1/backups/mydb'
  AS OF SYSTEM TIME '-10s';

-- Backup multiple databases
BACKUP DATABASE db1, db2, db3 INTO 'nodelocal://1/backups/multiple';
```

## When to Use Database Backups

**Use database-level backups for**:
- Single application recovery
- Tenant-specific backup strategies
- Testing/development database cloning
- Partial cluster backups

**Don't use for**:
- Complete disaster recovery (use cluster backup)
- Cross-database transactions (use cluster backup)

## Step-by-Step

### 1. Identify Database to Backup

```sql
-- List all databases
SHOW DATABASES;

-- Check database size
SELECT *  FROM [SHOW DATABASES] WHERE database_name = 'mydb';
```

### 2. Execute Backup

```sql
BACKUP DATABASE mydb INTO 'nodelocal://1/backups/mydb-prod'
  AS OF SYSTEM TIME '-10s';
```

### 3. Verify Backup

```sql
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/mydb-prod';
```

**Check**:
- Database name correct
- Table count matches expectations
- Row counts reasonable

## Common Patterns

**Application-specific daily backup**:
```sql
CREATE SCHEDULE app_db_daily
  FOR BACKUP DATABASE application_db INTO 'nodelocal://1/backups/app'
  RECURRING '@daily'
  FULL BACKUP '@weekly';
```

**Multi-tenant backup strategy**:
```sql
-- Tenant A database
BACKUP DATABASE tenant_a INTO 'nodelocal://1/backups/tenant-a';

-- Tenant B database  
BACKUP DATABASE tenant_b INTO 'nodelocal://1/backups/tenant-b';
```

**Dev/test cloning**:
```sql
-- Backup production database
BACKUP DATABASE prod_db INTO 'nodelocal://1/backups/prod-clone';

-- Restore to different name for testing
RESTORE DATABASE prod_db FROM LATEST IN 'nodelocal://1/backups/prod-clone'
  WITH new_db_name = 'test_db';
```

## Advanced Options

**Backup with PITR**:
```sql
BACKUP DATABASE mydb INTO 'nodelocal://1/backups/mydb-pitr'
  WITH revision_history;
```

**Backup to cloud storage**:
```sql
BACKUP DATABASE mydb INTO 's3://bucket/backups/mydb?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=yyy'
  AS OF SYSTEM TIME '-10s';
```

## What's Included

**Included in database backup**:
- All tables in the database
- All data rows
- Table schemas and constraints
- Indexes (primary and secondary)
- Sequences
- Views
- User-defined types

**Not included**:
- Other databases
- System tables (use cluster backup)
- Users and roles (use cluster backup)
- Cluster settings

## Troubleshooting

**Error: "database does not exist"**
```sql
-- List available databases
SHOW DATABASES;

-- Check spelling matches exactly
BACKUP DATABASE "MyDatabase" INTO 'nodelocal://1/backups/db';
```

**Error: "cannot backup system database"**
- System databases cannot be backed up individually
- Use cluster backup to include system tables

**Multiple databases backup fails**
```sql
-- Ensure all databases exist
BACKUP DATABASE db1, db2 INTO 'nodelocal://1/backups/multi';
-- If db2 doesn't exist, entire backup fails
```

## Comparison: Database vs Cluster Backup

| Aspect | Database Backup | Cluster Backup |
|--------|----------------|----------------|
| Scope | Single database | All databases |
| Size | Smaller | Larger |
| Recovery | Targeted | Complete |
| Users/Roles | Not included | Included |
| System tables | Not included | Included |
| Best for | App recovery | DR |

## Best Practices

1. Use database backups for application-specific recovery
2. Combine with cluster backups for complete DR strategy
3. Test restore to verify backup includes all needed data
4. Use cloud storage for production backups
5. Schedule database backups more frequently than cluster backups

## Related Skills

- `execute-cluster-level-full-backups` - Backup entire cluster
- `create-incremental-backups-with-backup-into-latest` - Add incremental backups
- `restore-database-from-backup` - Restore databases
