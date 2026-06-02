---
name: restore-individual-tables-from-backup
description: Selectively restore specific tables using RESTORE TABLE FROM LATEST IN for surgical recovery. Restore individual tables without full database restore. Supports multiple tables, restoring into different database with into_db option, and handling foreign key dependencies with skip_missing_foreign_keys.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Restore Individual Tables from Backup

Selective table restore enables surgical data recovery by restoring specific tables from backups without restoring entire databases or clusters. This skill covers using `RESTORE TABLE ... FROM LATEST IN` for targeted table recovery, handling foreign keys, and restoring into alternate databases.

## When to Use Table-Level Restore

Use selective table restore in these scenarios:

**Accidental Table Drop**: Recover single dropped table without affecting other data
**Data Corruption**: Restore corrupted table to previous good state
**Partial Recovery**: Recover subset of tables after targeted data loss
**Data Migration**: Copy specific tables between environments
**Testing**: Create test data from production table subsets
**Schema Rollback**: Restore table to previous schema version

## Prerequisites

Before restoring individual tables:

**Backup Exists**: Valid backup containing target table(s)
**Table Does Not Exist**: Target table must not exist (or use WITH skip_missing_foreign_keys)
**Foreign Key Awareness**: Understand dependencies that may prevent restore
**Database Exists**: Target database must exist (or create it first)
**Sufficient Permissions**: User must have CREATE privilege on database
**Disk Space**: Adequate space for restored table data

## Basic Table Restore

### Restore Single Table

```sql
-- Restore one table from latest backup
RESTORE TABLE production.customers
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

### Restore Multiple Tables

```sql
-- Restore multiple tables in one operation
RESTORE TABLE production.customers, production.orders, production.products
FROM LATEST IN 'gs://backups/database?AUTH=implicit';
```

### Restore with Wildcard Pattern

```sql
-- Restore all tables matching pattern
RESTORE TABLE production.*
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

## Inspecting Available Tables in Backups

Before restoring, verify table exists in backup.

### Show All Tables in Backup

```sql
-- List all tables available in latest backup
SHOW BACKUP FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

Look for `object_name` column showing table names.

### Filter to Specific Database

```sql
-- Show only tables from specific database
SELECT
  database_name,
  object_name AS table_name,
  object_type,
  rows
FROM [SHOW BACKUP FROM LATEST IN 'gs://backups/cluster?AUTH=implicit']
WHERE database_name = 'production'
  AND object_type = 'table'
ORDER BY table_name;
```

### Check Table Schema Before Restore

```sql
-- View CREATE TABLE statement from backup
SELECT create_statement
FROM [SHOW BACKUP FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}']
WHERE object_name = 'customers' AND object_type = 'table';
```

## Restoring into Different Database

### Restore into Alternate Database

```sql
-- Restore table into different database
RESTORE TABLE production.customers
FROM LATEST IN 'gs://backups/database?AUTH=implicit'
WITH into_db = 'staging';
```

Creates `staging.customers` instead of `production.customers`.

### Create Target Database First

```sql
-- Prepare target database
CREATE DATABASE IF NOT EXISTS staging;

-- Then restore tables
RESTORE TABLE production.*
FROM LATEST IN 'gs://backups/database?AUTH=implicit'
WITH into_db = 'staging';
```

## Handling Foreign Key Dependencies

Foreign keys can prevent table restore if referenced tables don't exist.

### Skip Missing Foreign Keys

```sql
-- Restore table even if foreign key targets missing
RESTORE TABLE production.orders
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH skip_missing_foreign_keys;
```

**Warning**: Table will restore but without foreign key constraints. Referential integrity not enforced.

### Restore in Dependency Order

```sql
-- Restore parent tables first
RESTORE TABLE production.customers
FROM LATEST IN 'gs://backups/database?AUTH=implicit';

-- Then restore child tables
RESTORE TABLE production.orders
FROM LATEST IN 'gs://backups/database?AUTH=implicit';
```

### Restore All Related Tables Together

```sql
-- Restore entire dependency graph in one operation
RESTORE TABLE
  production.customers,
  production.orders,
  production.order_items,
  production.products
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

## Point-in-Time Table Restore

When backups include revision history, restore tables to specific timestamp.

### Restore Table to Specific Time

```sql
-- Restore table to exact point in time
RESTORE TABLE production.customers
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
AS OF SYSTEM TIME '2026-03-05 10:30:00';
```

### Verify PITR Availability

```sql
-- Check revision history range in backup
SELECT
  object_name,
  start_time,
  end_time
FROM [SHOW BACKUP FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}']
WHERE object_type = 'table' AND object_name = 'customers';
```

## Advanced Restore Options

### Detached Table Restore

```sql
-- Run restore as background job
RESTORE TABLE production.large_table
FROM LATEST IN 'gs://backups/database?AUTH=implicit'
WITH detached;
```

Returns job ID immediately. Monitor with `SHOW JOBS`.

### Encrypted Backup Restore

```sql
-- Restore table from encrypted backup
RESTORE TABLE production.customers
FROM LATEST IN 's3://backup-bucket/encrypted?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH encryption_passphrase = 'your-passphrase-here';
```

### Combined Options

```sql
-- Restore with multiple options
RESTORE TABLE production.orders
FROM LATEST IN 'gs://backups/database?AUTH=implicit'
WITH
  into_db = 'staging',
  skip_missing_foreign_keys,
  detached;
```

## Monitoring Restore Progress

### Check Restore Job Status

```sql
-- View all table restore jobs
SELECT
  job_id,
  status,
  fraction_completed,
  ROUND(fraction_completed * 100, 2) AS percent_complete,
  description,
  created
FROM [SHOW JOBS]
WHERE job_type = 'RESTORE'
  AND description LIKE '%RESTORE TABLE%'
ORDER BY created DESC
LIMIT 5;
```

### Monitor Specific Restore Job

```sql
-- Track specific job progress
SELECT
  job_id,
  status,
  fraction_completed,
  running_status,
  error
FROM [SHOW JOBS]
WHERE job_id = 987654321098765;
```

## Verification After Table Restore

### Verify Table Exists and Row Count

```sql
-- Check restored table exists
SHOW TABLES FROM production;

-- Verify row count
SELECT count(*) AS row_count FROM production.customers;

-- Verify sample data
SELECT * FROM production.customers ORDER BY customer_id LIMIT 10;
```

### Verify Indexes and Constraints

```sql
-- List all indexes on restored table
SHOW INDEXES FROM production.customers;

-- Check constraints restored properly
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'production' AND table_name = 'customers';
```

## Common Issues and Troubleshooting

### Issue: Table Already Exists

**Error**: `pq: relation "customers" already exists`

**Solution 1**: Drop existing table first
```sql
-- CAUTION: This deletes current table
DROP TABLE production.customers;

-- Then restore
RESTORE TABLE production.customers
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

**Solution 2**: Restore to different database
```sql
-- Restore to staging instead
RESTORE TABLE production.customers
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH into_db = 'recovery';
```

### Issue: Foreign Key Constraint Violation

**Error**: `pq: cannot restore table "orders" without referenced table "customers"`

**Solution 1**: Restore parent table first
```sql
-- Restore referenced tables first
RESTORE TABLE production.customers
FROM LATEST IN 'gs://backups/database?AUTH=implicit';

-- Then restore dependent table
RESTORE TABLE production.orders
FROM LATEST IN 'gs://backups/database?AUTH=implicit';
```

**Solution 2**: Skip missing foreign keys
```sql
-- Restore without foreign key constraints
RESTORE TABLE production.orders
FROM LATEST IN 'gs://backups/database?AUTH=implicit'
WITH skip_missing_foreign_keys;

-- Recreate foreign key constraint manually later
ALTER TABLE production.orders
ADD CONSTRAINT fk_customer
FOREIGN KEY (customer_id)
REFERENCES production.customers(customer_id);
```

### Issue: Table Not in Backup

**Error**: `pq: table "production.missing_table" does not exist in backup`

**Solution**: Verify table name and backup contents
```sql
-- List all available tables
SELECT object_name
FROM [SHOW BACKUP FROM LATEST IN 'gs://backups/database?AUTH=implicit']
WHERE object_type = 'table' AND database_name = 'production'
ORDER BY object_name;
```

### Issue: Target Database Does Not Exist

**Error**: `pq: database "staging" does not exist`

**Solution**: Create database before restore
```sql
-- Create target database
CREATE DATABASE staging;

-- Then restore table
RESTORE TABLE production.customers
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH into_db = 'staging';
```

### Issue: Insufficient Permissions

**Error**: `pq: user does not have CREATE privilege on database production`

**Solution**: Grant necessary permissions
```sql
-- Grant CREATE on database
GRANT CREATE ON DATABASE production TO restore_user;
```

## Complete Table Restore Workflow

### Scenario: Restore Accidentally Dropped Table

**Step 1**: Verify backup contains table
```sql
SELECT object_name, rows, end_time
FROM [SHOW BACKUP FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}']
WHERE database_name = 'production' AND object_name = 'customers';
```

**Step 2**: Execute restore
```sql
RESTORE TABLE production.customers
FROM LATEST IN 's3://backup-bucket/database-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH detached;
```

**Step 3**: Monitor progress
```sql
SELECT status, ROUND(fraction_completed * 100, 2) AS percent_complete
FROM [SHOW JOBS]
WHERE job_id = 987654321098765;
```

**Step 4**: Verify after completion
```sql
-- Verify table exists and row count
SELECT count(*) FROM production.customers;

-- Verify indexes
SHOW INDEXES FROM production.customers;

-- Test application queries
SELECT * FROM production.customers WHERE email = 'test@example.com';
```

## Best Practices

**Verify Backups First**: Always `SHOW BACKUP` before restoring to confirm table exists
**Understand Dependencies**: Identify foreign key relationships before selective restore
**Use into_db for Testing**: Restore to alternate database to compare before replacing
**Restore Parent Tables First**: Follow dependency order to avoid foreign key errors
**Monitor Large Restores**: Use `WITH detached` for large tables and monitor with `SHOW JOBS`
**Verify After Restore**: Always check row counts, schema, and sample data
**Document Procedures**: Maintain runbooks for common restore scenarios
**Test Regularly**: Practice selective restore procedures before needed
**Handle Foreign Keys Carefully**: Understand implications of `skip_missing_foreign_keys`

## Security Considerations

**Backup Access Control**: Restrict who can restore tables from backups
**Audit Restore Operations**: Log all restore activities for compliance
**Credential Management**: Use secure credential storage, not inline parameters
**Data Sensitivity**: Be cautious restoring PII to lower environments
**Permission Validation**: Ensure restore users have appropriate database privileges

## Related Skills

- **restore-cluster-from-full-backup**: Full cluster recovery for disaster scenarios
- **restore-database-from-backup**: Database-level restore for entire database
- **list-available-backups-with-show-backups**: Discover available backup collections
- **inspect-backup-contents-with-show-backup**: Examine backup manifests before restore
- **implement-point-in-time-recovery**: Restore to exact timestamp using revision history
- **validate-restored-data-completeness**: Verify restore success systematically
- **execute-table-level-backups**: Create table-level backups for selective restore
- **monitor-all-job-types-with-show-jobs**: Track restore job progress and status
- **create-foreign-key-constraints-for-referential-integrity**: Recreate constraints after skip_missing_foreign_keys

## Additional Resources

- CockroachDB Docs: Restore a Table
- CockroachDB Docs: RESTORE Statement
- CockroachDB Docs: Foreign Keys
- CockroachDB Docs: Backup and Restore Overview
