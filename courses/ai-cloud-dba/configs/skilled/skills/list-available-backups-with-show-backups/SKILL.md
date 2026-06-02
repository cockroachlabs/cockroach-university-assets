---
name: list-available-backups-with-show-backups
description: List all available CockroachDB backups in a storage location using SHOW BACKUPS command. Use when user asks "list backups", "show all backups", "available backups", "backup history", or needs to find restore points and manage retention.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# List Available Backups with SHOW BACKUPS

Discover all backup timestamps in a storage location to identify available restore points.

## Basic Syntax

```sql
-- List all backups in location
SHOW BACKUPS IN 'nodelocal://1/backups/cluster';
```

## What SHOW BACKUPS Returns

### Output Format

Returns list of backup subdirectories (timestamp paths):

```
           path           
--------------------------
 /2026/01/14-020000.00
 /2026/01/15-020000.00
 /2026/01/16-020000.00
 /2026/01/17-020000.00
```

### Understanding Backup Paths

**Format**: `/YYYY/MM/DD-HHMMSS.ms`

**Example**: `/2026/01/15-143022.50`
- Date: January 15, 2026
- Time: 14:30:22.50 (2:30 PM)

Each path represents either:
- A full backup (starts new chain)
- Part of an incremental chain

## Step-by-Step Usage

### 1. List All Backups

```sql
SHOW BACKUPS IN 'nodelocal://1/backups/cluster';
```

### 2. Identify Restore Points

```sql
-- Each path is a potential restore point
-- To restore from specific backup:
RESTORE FROM '2026/01/15-143022.50' IN 'nodelocal://1/backups/cluster';

-- Or use latest:
RESTORE FROM LATEST IN 'nodelocal://1/backups/cluster';
```

### 3. Inspect Specific Backup

```sql
-- After listing, inspect any backup:
SHOW BACKUP FROM '2026/01/15-143022.50' IN 'nodelocal://1/backups/cluster';
```

## Common Patterns

### Pattern 1: Find Recent Backups

```sql
-- List all backups
SHOW BACKUPS IN 'nodelocal://1/backups/prod';

-- Newest backups appear last in list
-- Latest backup can be used with FROM LATEST
```

### Pattern 2: Backup Chain Identification

```sql
-- List backups to see chain structure
SHOW BACKUPS IN 'nodelocal://1/backups/weekly';

-- Example output showing weekly full + daily incrementals:
-- /2026/01/14-020000.00  (Sunday full)
-- /2026/01/15-020000.00  (Monday incremental)
-- /2026/01/16-020000.00  (Tuesday incremental)
-- /2026/01/17-020000.00  (Wednesday incremental)
-- /2026/01/18-020000.00  (Thursday incremental)
-- /2026/01/19-020000.00  (Friday incremental)
-- /2026/01/20-020000.00  (Saturday incremental)
-- /2026/01/21-020000.00  (Sunday full - new chain)
```

### Pattern 3: Retention Management

```sql
-- List backups to identify old backups for deletion
SHOW BACKUPS IN 'nodelocal://1/backups/prod';

-- Identify backups older than 30 days
-- (Manual cleanup or use cloud storage lifecycle policies)
```

## Multiple Storage Locations

### Check Different Destinations

```sql
-- Production backups
SHOW BACKUPS IN 'nodelocal://1/backups/prod';

-- Development backups
SHOW BACKUPS IN 'nodelocal://1/backups/dev';

-- Historical archives
SHOW BACKUPS IN 'nodelocal://1/backups/archive';
```

### Cloud Storage Locations

```sql
-- S3
SHOW BACKUPS IN 's3://bucket/backups/prod?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=yyy';

-- GCS
SHOW BACKUPS IN 'gs://bucket/backups/prod?AUTH=specified&CREDENTIALS=xxx';

-- Azure
SHOW BACKUPS IN 'azure://container/backups?AZURE_ACCOUNT_NAME=xxx&AZURE_ACCOUNT_KEY=yyy';
```

## Understanding Backup Chains

### Identifying Chain Boundaries

**Full backup** starts new chain:
- First backup in location
- After `BACKUP INTO` (without LATEST)
- First backup each week in scheduled backup

**Incremental backups** extend chain:
- Created with `BACKUP INTO LATEST`
- Timestamp newer than previous backup

**Example chain structure**:
```
Chain 1:
  /2026/01/14-020000.00  (Full)
  /2026/01/15-020000.00  (Incr)
  /2026/01/16-020000.00  (Incr)
  
Chain 2:
  /2026/01/21-020000.00  (Full - new chain)
  /2026/01/22-020000.00  (Incr)
```

## Combining with Inspection

### Workflow: List then Inspect

```sql
-- Step 1: List available backups
SHOW BACKUPS IN 'nodelocal://1/backups/prod';

-- Step 2: Inspect specific backup of interest
SHOW BACKUP FROM '2026/01/15-143022.50' IN 'nodelocal://1/backups/prod';

-- Step 3: Restore if contents valid
RESTORE FROM '2026/01/15-143022.50' IN 'nodelocal://1/backups/prod';
```

## Use Cases

### Disaster Recovery Planning

**Find most recent full backup**:
```sql
SHOW BACKUPS IN 'nodelocal://1/backups/dr';

-- Identify newest full backup (largest time gap before)
-- Document for runbook
```

### Point-in-Time Recovery

**Find backup closest to target time**:
```sql
-- List all backups
SHOW BACKUPS IN 'nodelocal://1/backups/pitr';

-- Identify backup closest to incident time
-- E.g., incident at 2026-01-15 15:00
-- Use backup from 2026-01-15 14:30
```

### Compliance Auditing

**Verify retention policy compliance**:
```sql
-- List backups to prove retention
SHOW BACKUPS IN 'nodelocal://1/backups/compliance';

-- Verify:
-- - Daily backups for last 30 days exist
-- - Weekly backups for last 90 days exist  
-- - Monthly backups for last year exist
```

## Empty Location

If no backups exist:

```sql
SHOW BACKUPS IN 'nodelocal://1/backups/empty';

-- Returns:
-- (no rows)
```

**This is expected** for new backup locations.

## Troubleshooting

### Error: "backup not found" or "directory does not exist"

**Cause**: Storage location doesn't exist or inaccessible

**Solution**:
```sql
-- Verify path is correct
-- Check permissions on storage
-- Ensure storage is mounted (for nodelocal)
```

### No Backups Listed

**Possible causes**:
- No backups created yet (expected)
- Wrong storage location
- Backups deleted
- Permission issues

**Verify**:
```sql
-- Try creating a test backup first
BACKUP DATABASE defaultdb INTO 'nodelocal://1/backups/test';

-- Then list again
SHOW BACKUPS IN 'nodelocal://1/backups/test';
```

### Cannot Access Cloud Storage

**Error**: Authentication or permission error

**Solution**:
- Verify credentials in URI
- Check IAM permissions
- Test connectivity to cloud provider

## Best Practices

1. **Document backup locations** for disaster recovery runbooks
2. **Regularly list backups** to verify scheduled backups running
3. **Monitor backup count** to detect missed backups
4. **Use consistent locations** for easier management
5. **Implement retention policies** based on backup listings

## Automation Example

**Monitor backup freshness**:
```sql
-- Script to alert if no backup in last 24 hours
SHOW BACKUPS IN 'nodelocal://1/backups/prod';

-- Parse latest timestamp
-- Compare to current time
-- Alert if > 24 hours old
```

## Related Skills

- `inspect-backup-contents-with-show-backup` - Inspect specific backup contents
- `execute-cluster-level-full-backups` - Create backups to list
- `create-incremental-backups-with-backup-into-latest` - Add to backup chain
- `restore-database-from-backup` - Restore from listed backups
