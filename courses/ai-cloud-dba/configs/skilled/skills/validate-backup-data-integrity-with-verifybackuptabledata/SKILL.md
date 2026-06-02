---
name: validate-backup-data-integrity-with-verifybackuptabledata
description: Use RESTORE with verify_backup_table_data to validate row-level data integrity without performing a full restore. Reads and checksums all row data in backup files to detect corruption. Combine with schema_only to avoid writing data. Essential for production backup validation and compliance audits.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Validate Backup Data Integrity with verify_backup_table_data

**Domain**: Backup and Restore
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to validate backup data integrity at the row level using the `verify_backup_table_data` option with `RESTORE`. Unlike file-level validation (`check_files`), this performs deep validation by reading and checksumming every row in the backup.

**When to use this skill:**
- Before critical production restores requiring high confidence
- Compliance audits requiring proof of backup recoverability
- After storage system failures or corruption events
- Quarterly or annual backup validation procedures
- Before decommissioning source clusters after migration

**What this validates:**
- Row-level data integrity (checksums on all rows)
- SST file internal consistency
- Data can be successfully read and decoded

**What this does NOT validate:**
- Application-level data correctness
- File existence (use `check_files` first)
- Backup performance or restore speed

**Trade-offs:**
- Much slower than `check_files` (reads all data)
- I/O intensive (downloads and processes all SST files)
- Network bandwidth for cloud storage reads

## Instructions

### Understanding verify_backup_table_data

The `verify_backup_table_data` option performs comprehensive data validation:

**Validation Process:**
1. Reads backup manifest and schema definitions
2. Opens every SST file in backup
3. Reads every row from every table
4. Computes checksums on row data
5. Reports any corrupted or unreadable rows

**Performance Impact:**
- Operation time scales with backup data size
- Network I/O for cloud storage (downloads all SSTs)
- CPU for checksum computation

### Basic Data Integrity Validation

Validate backup data integrity without writing to cluster:

```sql
-- Create temporary validation database
CREATE DATABASE backup_validation;

-- Validate backup data without persisting to cluster
RESTORE DATABASE production
FROM 'gs://acme-backups/production/2026-03-06-full'
WITH verify_backup_table_data,
     schema_only,
     into_db = 'backup_validation';

-- If successful, all data validated without writing rows
DROP DATABASE backup_validation CASCADE;
```

**Important:** Using `schema_only` with `verify_backup_table_data` reads and validates all row data but does not write it to the cluster.

### Validating Specific Tables

Validate only critical tables for faster validation:

```sql
-- Validate specific high-priority tables
CREATE DATABASE backup_validation;

RESTORE TABLE production.orders, production.customers
FROM 'gs://acme-backups/production/2026-03-06-full'
WITH verify_backup_table_data,
     schema_only,
     into_db = 'backup_validation';

DROP DATABASE backup_validation CASCADE;
```

### Incremental Backup Chain Validation

Validate entire backup chain (full + incrementals):

```sql
-- Validate base full backup
CREATE DATABASE backup_validation;

RESTORE DATABASE production
FROM 'gs://acme-backups/production/2026-03-01-full'
WITH verify_backup_table_data,
     schema_only,
     into_db = 'backup_validation';

-- Validate latest incremental (full chain validation)
RESTORE DATABASE production
FROM LATEST IN 'gs://acme-backups/production/2026-03-01-full'
WITH verify_backup_table_data,
     schema_only,
     into_db = 'backup_validation';

DROP DATABASE backup_validation CASCADE;
```

### Validation with Progress Monitoring

Monitor long-running validation operations:

```sql
-- Start validation in background
RESTORE DATABASE production
FROM 'gs://acme-backups/production/2026-03-06-full'
WITH verify_backup_table_data,
     schema_only,
     into_db = 'backup_validation',
     detached;

-- Monitor job progress
SHOW JOBS;

-- Detailed job status
SELECT
  job_id,
  job_type,
  status,
  fraction_completed,
  running_status
FROM [SHOW JOBS]
WHERE job_type = 'RESTORE' AND status = 'running';

-- Cancel validation if needed
CANCEL JOB <job_id>;
```

### Point-in-Time Backup Validation

Validate backups created with revision history:

```sql
-- Show available restore points
SHOW BACKUP 'gs://acme-backups/production/pitr-backup'
WITH revision_history;

-- Validate backup at specific point in time
CREATE DATABASE backup_validation;

RESTORE DATABASE production
FROM 'gs://acme-backups/production/pitr-backup'
AS OF SYSTEM TIME '2026-03-06 10:30:00'
WITH verify_backup_table_data,
     schema_only,
     into_db = 'backup_validation';

DROP DATABASE backup_validation CASCADE;
```

## Common Patterns

### Pattern 1: Quarterly Compliance Audit Workflow

Complete validation procedure for compliance requirements:

```sql
-- Step 1: Verify file integrity first (fast check)
SHOW BACKUP 'gs://acme-backups/production/2026-q1-archive'
WITH check_files;

-- Step 2: Perform data integrity validation
CREATE DATABASE backup_validation;

RESTORE DATABASE production
FROM 'gs://acme-backups/production/2026-q1-archive'
WITH verify_backup_table_data,
     schema_only,
     into_db = 'backup_validation';

-- Step 3: Record audit results
INSERT INTO audit.backup_validations (
  backup_location, validation_type, status, notes
) VALUES (
  'gs://acme-backups/production/2026-q1-archive',
  'verify_backup_table_data',
  'SUCCESS',
  'Q1 2026 compliance audit - all data validated'
);

DROP DATABASE backup_validation CASCADE;
```

### Pattern 2: Pre-Migration Final Validation

Validate source cluster backup before decommissioning:

```sql
-- Step 1: File integrity
SHOW BACKUP 'gs://migration/source-final-backup' WITH check_files;

-- Step 2: Validate critical business tables
CREATE DATABASE migration_validation;

RESTORE TABLE production.orders, production.customers
FROM 'gs://migration/source-final-backup'
WITH verify_backup_table_data, schema_only, into_db = 'migration_validation';

-- Step 3: Validate all remaining tables
RESTORE DATABASE production
FROM 'gs://migration/source-final-backup'
WITH verify_backup_table_data, schema_only, into_db = 'migration_validation';

DROP DATABASE migration_validation CASCADE;
```

### Pattern 3: Automated Weekly Validation Script

Monitor backup health with regular validation:

```bash
#!/bin/bash
# weekly-backup-validation.sh
BACKUP_BASE="gs://acme-backups/daily"
DB_URL="postgresql://root@localhost:26257/defaultdb?sslmode=disable"

for day in {0..6}; do
  BACKUP_DATE=$(date -d "$day days ago" +%Y-%m-%d)

  cockroach sql --url "$DB_URL" << EOF
    CREATE DATABASE IF NOT EXISTS backup_validation;
    RESTORE DATABASE production
    FROM '$BACKUP_BASE/$BACKUP_DATE-000000.00'
    WITH verify_backup_table_data, schema_only, into_db = 'backup_validation';
    DROP DATABASE backup_validation CASCADE;
EOF

  if [ $? -eq 0 ]; then
    echo "SUCCESS: $BACKUP_DATE validated"
  else
    echo "ERROR: $BACKUP_DATE validation failed"
    ./send-alert.sh "Backup validation failed for $BACKUP_DATE"
  fi
done
```

## Troubleshooting

### Issue 1: Checksum Validation Failures

**Symptoms:**
- `verify_backup_table_data` fails with checksum errors
- Error indicates specific table or SST file

**Diagnosis:**
```sql
CREATE DATABASE corruption_check;

RESTORE TABLE production.failing_table
FROM 'gs://acme-backups/production/backup'
WITH verify_backup_table_data, schema_only, into_db = 'corruption_check';

-- Error output example:
-- ERROR: checksum mismatch in SST file: data/735840.sst
```

**Solutions:**
```sql
-- Option 1: Try previous backup
RESTORE TABLE production.failing_table
FROM 'gs://acme-backups/production/previous-backup'
WITH verify_backup_table_data, schema_only, into_db = 'corruption_check';

-- Option 2: If incremental backup corrupt, try base full
RESTORE TABLE production.failing_table
FROM 'gs://acme-backups/production/base-full-backup'
WITH verify_backup_table_data, schema_only, into_db = 'corruption_check';

DROP DATABASE corruption_check CASCADE;
```

### Issue 2: Validation Timeout or Performance Issues

**Symptoms:**
- Validation takes excessive time (hours for GB-size backups)
- Timeouts on large backups

**Diagnosis:**
```sql
-- Monitor validation job progress
SELECT job_id, fraction_completed, running_status
FROM [SHOW JOBS]
WHERE job_type = 'RESTORE' AND status = 'running';
```

**Solutions:**
```sql
-- Option 1: Validate subset of critical tables first
CREATE DATABASE backup_validation;

RESTORE TABLE production.orders, production.customers
FROM 'gs://acme-backups/production/backup'
WITH verify_backup_table_data, schema_only, into_db = 'backup_validation';

-- Option 2: Use detached mode for long validations
RESTORE DATABASE production
FROM 'gs://acme-backups/production/backup'
WITH verify_backup_table_data, schema_only, into_db = 'backup_validation', detached;

DROP DATABASE backup_validation CASCADE;
```

### Issue 3: Out of Memory During Validation

**Symptoms:**
- Validation job fails with OOM errors
- Node memory pressure during restore

**Diagnosis:**
```sql
-- Check job failure details
SELECT job_id, description, status, error
FROM [SHOW JOBS]
WHERE job_type = 'RESTORE'
ORDER BY created DESC LIMIT 5;
```

**Solutions:**
```sql
-- Option 1: Validate tables in batches
CREATE DATABASE backup_validation;

RESTORE TABLE production.orders
FROM 'gs://acme-backups/production/backup'
WITH verify_backup_table_data, schema_only, into_db = 'backup_validation';

DROP TABLE backup_validation.orders;

RESTORE TABLE production.customers
FROM 'gs://acme-backups/production/backup'
WITH verify_backup_table_data, schema_only, into_db = 'backup_validation';

DROP DATABASE backup_validation CASCADE;

-- Option 2: Use dedicated validation cluster
-- Prevents impact to production workloads
```

## Best Practices

1. **Two-Stage Validation Strategy**
   - Always run `check_files` first (fast, cheap)
   - Run `verify_backup_table_data` for compliance or after critical changes
   - Schedule deep validation quarterly
   - Use file checks for routine monitoring

2. **Always Use schema_only for Validation**
   - Combines `verify_backup_table_data` with `schema_only`
   - Reads and validates all row data without persisting
   - Faster cleanup (just drop validation database)

3. **Validation Scheduling**
   - Validate critical tables weekly
   - Full database validation monthly
   - Complete cluster validation quarterly
   - Schedule during maintenance windows

4. **Resource Management**
   - Use detached mode for long-running validations
   - Consider dedicated validation cluster for large backups
   - Monitor memory and CPU during validation

5. **Compliance and Auditing**
   - Document validation procedures in runbooks
   - Log all validation operations with timestamps
   - Maintain audit trail of validation results
   - Test restoration procedures, not just validation

6. **Error Handling**
   - Always validate previous backup if current fails
   - Investigate corruption patterns
   - Maintain backup redundancy across storage locations

## Related Skills

- **verify-backup-file-integrity-with-checkfiles**: Fast file-level validation
- **inspect-backup-contents-with-show-backup**: Examine backup metadata and structure
- **restore-database-from-backup**: Restore validated backups to production
- **create-incremental-backups-with-backup-into-latest**: Create validated backup chains
- **manage-backup-retention-policies**: Design retention strategies preserving backup integrity
- **understand-backup-chain-structure**: Backup chain dependencies
