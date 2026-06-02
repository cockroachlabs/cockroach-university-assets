---
name: verify-backup-file-integrity-with-checkfiles
description: Use RESTORE with check_files option to verify all files referenced in the backup manifest exist in storage. Essential for validating backups after storage migration, retention cleanup, or before critical restore operations. Detects missing or deleted backup files without performing a full data restore.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Verify Backup File Integrity with check_files

**Domain**: Backup and Restore
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to verify backup file integrity using the `check_files` option with `RESTORE`. Unlike data integrity validation (which reads and checksums row data), file integrity validation confirms that all files referenced in the backup manifest physically exist in storage without actually restoring data.

**When to use this skill:**
- After storage migration or backup relocation
- Following retention policy cleanup or manual file deletion
- Before critical restore operations requiring high confidence
- During compliance audits requiring backup validation
- After storage system maintenance or recovery
- When diagnosing backup-related errors or failures

**What this validates:**
- All SST files referenced in manifest exist
- Manifest file itself is accessible and readable
- Backup chain continuity (full + incrementals)
- External storage connectivity and permissions

**What this does NOT validate:**
- Row-level data integrity (use `verify_backup_table_data` instead)
- Backup restorability or schema correctness
- Data corruption within existing files
- Performance or restore speed

## Instructions

### Understanding check_files Validation

The `check_files` option performs manifest-based file validation:

**Validation Process:**
1. Reads backup manifest (BACKUP_MANIFEST file)
2. Extracts list of all SST files required for restore
3. Verifies each file exists at expected storage location
4. Reports any missing files with specific paths
5. Validates incremental backup chain references

**Performance Characteristics:**
- Fast operation (metadata-only, no data reading)
- Minimal storage I/O (existence checks only)
- Network overhead for cloud storage (HEAD requests)
- Scales with number of files, not data size

### Basic File Integrity Validation

Verify a full backup's file integrity:

```sql
-- First, inspect the backup to see what it contains
SHOW BACKUP FROM LATEST IN 'gs://acme-backups/production';

-- Verify all files exist using RESTORE with check_files option
-- This validates file existence without actually restoring data
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/production'
WITH check_files;

-- Expected output when all files present:
-- (0 rows) - validation succeeds silently

-- Output when files are missing:
-- ERROR: backup validation failed: missing files:
--   gs://acme-backups/production/2026-03-06-000000.00/data/735840.sst
--   gs://acme-backups/production/2026-03-06-000000.00/data/735841.sst
```

### Validating Incremental Backup Chains

Verify an entire backup chain (full + all incrementals):

```sql
-- Show all backups in collection
SHOW BACKUPS IN 'gs://acme-backups/production';

-- Inspect latest backup details
SHOW BACKUP FROM LATEST IN 'gs://acme-backups/production';

-- Verify latest backup chain file integrity
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/production'
WITH check_files;

-- Verify specific backup by subdirectory name
SHOW BACKUP '2026-03-06-000000.00' IN 'gs://acme-backups/production';

RESTORE DATABASE production
FROM '2026-03-06-000000.00' IN 'gs://acme-backups/production'
WITH check_files;
```

### Validating Scheduled Backups

Check file integrity for scheduled backup collections:

```sql
-- List all backups in scheduled collection
SHOW BACKUPS IN 'gs://acme-backups/scheduled/production';

-- Output:
--          path
-- ----------------------
--   2026-03-01-000000.00
--   2026-03-02-000000.00
--   2026-03-03-000000.00
--   2026-03-06-000000.00

-- Inspect specific backups
SHOW BACKUP '2026-03-01-000000.00' IN 'gs://acme-backups/scheduled/production';

-- Verify each backup's file integrity
RESTORE DATABASE production
FROM '2026-03-01-000000.00' IN 'gs://acme-backups/scheduled/production'
WITH check_files;

RESTORE DATABASE production
FROM '2026-03-02-000000.00' IN 'gs://acme-backups/scheduled/production'
WITH check_files;

-- Verify latest backup in collection
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/scheduled/production'
WITH check_files;
```

### Cross-Storage Validation Patterns

Verify backups after storage migration or replication:

```sql
-- Inspect source backup before migration
SHOW BACKUP FROM LATEST IN 'gs://source-bucket/backups';

-- Validate source backup file integrity
RESTORE DATABASE production
FROM LATEST IN 'gs://source-bucket/backups'
WITH check_files;

-- Perform storage migration (external process)
-- gsutil -m rsync -r gs://source-bucket/backups/ gs://dest-bucket/backups/

-- Inspect destination backup after migration
SHOW BACKUP FROM LATEST IN 'gs://dest-bucket/backups';

-- Validate destination backup file integrity
RESTORE DATABASE production
FROM LATEST IN 'gs://dest-bucket/backups'
WITH check_files;

-- Verify both locations have identical metadata
-- Compare row counts and size_bytes values from SHOW BACKUP output
```

### Validating After Retention Policy Cleanup

Verify backup integrity after applying retention policies:

```sql
-- Before cleanup: Show all backups
SHOW BACKUPS IN 'gs://acme-backups/scheduled/production';

-- Apply retention policy (external process)
-- Delete backups older than 30 days

-- After cleanup: Verify remaining backups
SHOW BACKUPS IN 'gs://acme-backups/scheduled/production';

-- Inspect remaining backups
SHOW BACKUP '2026-03-01-000000.00' IN 'gs://acme-backups/scheduled/production';

-- Verify each remaining backup's file integrity
RESTORE DATABASE production
FROM '2026-03-01-000000.00' IN 'gs://acme-backups/scheduled/production'
WITH check_files;

-- Ensure backup chain continuity
-- If incremental backups exist, verify base full backup is present
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/scheduled/production'
WITH check_files;
```

## Common Patterns

### Pattern 1: Pre-Restore Validation Workflow

Before performing critical restores, validate backup completeness:

```sql
-- Step 1: Identify target backup for restore
SHOW BACKUPS IN 'gs://acme-backups/production';

-- Step 2: Inspect backup contents
SHOW BACKUP '2026-03-06-000000.00' IN 'gs://acme-backups/production';

-- Step 3: Validate file integrity using check_files
RESTORE DATABASE production
FROM '2026-03-06-000000.00' IN 'gs://acme-backups/production'
WITH check_files;

-- Step 4: If validation passes (no error), proceed with actual restore
RESTORE DATABASE production
FROM '2026-03-06-000000.00' IN 'gs://acme-backups/production';
```

### Pattern 2: Automated Backup Validation Script

Create monitoring script to validate recent backups:

```bash
#!/bin/bash
# Daily validation script for monitoring systems

# Validate latest backup file integrity
cockroach sql --url "postgresql://root@localhost:26257/defaultdb" <<EOF
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/production'
WITH check_files;
EOF

# Exit code 0 = validation success
# Exit code 1 = missing files detected or other error
```

### Pattern 3: Multi-Location Backup Validation

Validate backup redundancy across multiple storage locations:

```sql
-- Primary storage location
RESTORE DATABASE production
FROM LATEST IN 'gs://us-backups/production'
WITH check_files;

-- Secondary storage location (disaster recovery)
RESTORE DATABASE production
FROM LATEST IN 'gs://eu-backups/production'
WITH check_files;

-- Archive storage location (long-term retention)
RESTORE DATABASE production
FROM '2026-03-01-000000.00' IN 's3://archive-backups/production'
WITH check_files;

-- All three should succeed for complete redundancy
```

### Pattern 4: Incremental Chain Validation

Validate entire incremental backup chain integrity:

```sql
-- List all backups in collection
SHOW BACKUPS IN 'gs://acme-backups/production';

-- Inspect chain structure
SHOW BACKUP FROM LATEST IN 'gs://acme-backups/production';

-- Validate base full backup
RESTORE DATABASE production
FROM '2026-03-01-000000.00' IN 'gs://acme-backups/production'
WITH check_files;

-- Validate subsequent incremental backups
RESTORE DATABASE production
FROM '2026-03-02-000000.00' IN 'gs://acme-backups/production'
WITH check_files;

RESTORE DATABASE production
FROM '2026-03-03-000000.00' IN 'gs://acme-backups/production'
WITH check_files;

-- Failure in any layer breaks chain recoverability
```

## Troubleshooting

### Issue 1: Missing Files After Storage Migration

**Symptoms:**
- `check_files` reports missing SST files
- Files were recently migrated between storage locations
- Some files present, others missing

**Diagnosis:**
```sql
-- Check which specific files are missing
RESTORE DATABASE production
FROM LATEST IN 'gs://dest-bucket/backups'
WITH check_files;
-- Error message lists exact missing file paths

-- Verify source location still has files
RESTORE DATABASE production
FROM LATEST IN 'gs://source-bucket/backups'
WITH check_files;

-- Compare file counts and metadata
SHOW BACKUP FROM LATEST IN 'gs://source-bucket/backups';
SHOW BACKUP FROM LATEST IN 'gs://dest-bucket/backups';
```

**Solutions:**
```sql
-- Option 1: Re-migrate missing files only
-- Extract missing paths from error message
-- gsutil cp gs://source-bucket/.../missing-file.sst gs://dest-bucket/.../

-- Option 2: Re-migrate entire backup
-- gsutil -m rsync -r -d gs://source/backups/ gs://dest/backups/

-- Option 3: Verify with recursive sync (delete extra files)
-- gsutil -m rsync -r -d -c gs://source/backups/ gs://dest/backups/

-- Re-validate after migration
RESTORE DATABASE production
FROM LATEST IN 'gs://dest-bucket/backups'
WITH check_files;
```

### Issue 2: Incremental Chain Broken by Retention Policy

**Symptoms:**
- Base full backup deleted by retention policy
- Incremental backups reference missing full backup
- Restore attempts fail with "base backup not found"

**Diagnosis:**
```sql
-- Show remaining backups after cleanup
SHOW BACKUPS IN 'gs://acme-backups/scheduled/production';

-- Try to validate incremental backup
RESTORE DATABASE production
FROM '2026-03-05-000000.00' IN 'gs://acme-backups/scheduled/production'
WITH check_files;
-- ERROR: base backup not found: 2026-03-01-000000.00

-- Check backup metadata
SHOW BACKUP '2026-03-05-000000.00' IN 'gs://acme-backups/scheduled/production';
-- Look for start_time showing base backup timestamp
```

**Solutions:**
```sql
-- Solution 1: Restore from earlier full backup before deletion
-- If base backup still exists elsewhere, restore from archive

-- Solution 2: Use next available full backup
SHOW BACKUPS IN 'gs://acme-backups/scheduled/production';
-- Find next full backup (is_full_cluster = true)
RESTORE DATABASE production
FROM '2026-03-07-000000.00' IN 'gs://acme-backups/scheduled/production'
WITH check_files;

-- Solution 3: Adjust retention policy to preserve full backups longer
-- Ensure retention: incrementals < full backups < long-term archive
-- Example: keep incrementals 7 days, full backups 30 days, monthly 1 year

-- Prevention: Always validate retention policy preserves full backups
-- Delete incrementals first, then older full backups
```

### Issue 3: Storage Permission or Connectivity Errors

**Symptoms:**
- Timeout errors during file validation
- Permission denied errors for specific files
- Intermittent validation failures

**Diagnosis:**
```sql
-- Test basic storage connectivity
SHOW BACKUP FROM LATEST IN 'gs://acme-backups/production';
-- If this fails, check storage permissions

-- Verify credentials have list/read permissions
-- gsutil ls gs://acme-backups/production/
-- gsutil cat gs://acme-backups/production/latest/BACKUP_MANIFEST

-- Check cloud provider IAM permissions
-- GCS: storage.objects.get, storage.objects.list
-- S3: s3:GetObject, s3:ListBucket
```

**Solutions:**
```sql
-- Option 1: Update storage credentials
-- Ensure CockroachDB cluster has valid credentials
SET CLUSTER SETTING cloudstorage.gs.default.key = '...';

-- Option 2: Test with explicit credentials
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/production?AUTH=specified'
WITH check_files, credentials = '...';

-- Option 3: Verify network connectivity
-- Check firewall rules allow HTTPS to storage endpoints
-- Ensure DNS resolution works for storage.googleapis.com

-- Option 4: Increase timeout for slow storage
SET CLUSTER SETTING cloudstorage.timeout = '5m';
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/production'
WITH check_files;
```

## Best Practices

1. **Regular Validation Schedule**
   - Run `check_files` validation weekly for production backups
   - Validate immediately after storage migration or maintenance
   - Automate validation in monitoring/alerting systems
   - Check recent backups (last 24h) daily

2. **Pre-Restore Validation**
   - Always validate with `check_files` before critical restores
   - Verify entire backup chain if using incrementals
   - Test restore in non-production environment first
   - Document validation results for audit trails

3. **Storage Migration Workflow**
   - Validate source backup before migration
   - Validate destination backup after migration
   - Compare file counts and total sizes
   - Keep source backup until destination validated

4. **Retention Policy Safety**
   - Validate oldest retained backup still has complete file set
   - Ensure incremental backups don't outlive base full backup
   - Test retention policy in non-production first
   - Document which backups are safe to delete

5. **Performance Optimization**
   - Run `check_files` during off-peak hours (network-intensive)
   - Validate scheduled backups after completion window
   - Use parallel validation for multiple backup locations
   - Monitor validation duration for degradation trends

6. **Combine with Data Validation**
   - Use `check_files` for routine quick checks
   - Use `verify_backup_table_data` for deeper validation
   - Perform data validation quarterly or before major changes
   - Document validation strategy in runbooks

## Related Skills

- **validate-backup-data-integrity-with-verifybackuptabledata**: Deep row-level integrity validation
- **inspect-backup-contents-with-show-backup**: Examine backup metadata and structure
- **understand-incremental-backup-concepts**: Backup chain dependencies
- **manage-backup-retention-policies**: Design retention strategies preserving backup integrity
- **create-incremental-backups-with-backup-into-latest**: Create incremental backup chains
- **restore-database-from-backup**: Restore validated backups
- **list-available-backups-with-show-backups**: Discover backups in storage locations
- **understand-backup-chain-structure**: Backup chain architecture and dependencies
