---
name: execute-table-level-backups
description: Create backups of individual tables or groups of tables in CockroachDB using BACKUP TABLE syntax. Enables surgical backup strategies for specific datasets with independent schedules and retention policies. Use when user asks to "backup a table", "backup specific tables", "backup schema", "surgical backup", or needs granular control over backup scope.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Execute Table-Level Backups

Create targeted backups of individual tables or groups of tables instead of entire databases or clusters. Table-level backups enable flexible backup strategies with granular control over scope, schedule, and retention.

## What This Skill Teaches

This skill shows you how to:
- Backup individual tables with BACKUP TABLE syntax
- Backup multiple tables in a single command
- Backup entire schemas using wildcard patterns
- Design surgical backup strategies for specific datasets
- Manage independent retention policies per table
- Restore individual tables from table-level backups

**Use this skill when**:
- Large tables need separate backup schedules
- Critical tables need more frequent backups
- Compliance requires isolated table backups
- Testing requires specific table snapshots
- Reducing backup scope for performance

## Prerequisites

**Required**:
- BACKUP privilege on target tables
- SELECT privilege on target tables
- Write access to backup destination

**Verify privileges**:
```sql
SHOW GRANTS ON TABLE mydb.customers;
```

**Required output**: BACKUP and SELECT privileges

## Basic Syntax

### Single Table Backup

```sql
-- Backup one table
BACKUP TABLE mydb.customers
  INTO 'gs://backups/tables/customers'
  AS OF SYSTEM TIME '-10s';
```

**Format**: `BACKUP TABLE <database>.<table> INTO '<destination>'`

**Components**:
- `<database>`: Database containing table
- `<table>`: Table name to backup
- `<destination>`: Storage location (same as cluster backups)
- `AS OF SYSTEM TIME`: Consistency timestamp (recommended)

### Multiple Tables Backup

```sql
-- Backup multiple tables (comma-separated)
BACKUP TABLE mydb.customers, mydb.orders, mydb.payments
  INTO 'gs://backups/tables/customer-data'
  AS OF SYSTEM TIME '-10s';
```

**All tables backed up in single consistent snapshot**.

### Schema Wildcard Backup

```sql
-- Backup all tables in schema
BACKUP TABLE mydb.public.*
  INTO 'gs://backups/schemas/public'
  AS OF SYSTEM TIME '-10s';
```

**Pattern**: `<database>.<schema>.*`
- Backs up all tables in specified schema
- Includes future tables added to schema (if restoring schema definition)

## Storage Destinations

Same as cluster backups: nodelocal (testing), S3, GCS, Azure

## Step-by-Step: Creating Table Backups

### Step 1: Identify Tables to Backup

**List tables in database**:
```sql
SHOW TABLES FROM mydb;
```

**Check table sizes**:
```sql
SELECT
  table_name,
  pg_size_pretty(pg_total_relation_size(table_schema || '.' || table_name)) AS size
FROM information_schema.tables
WHERE table_schema = 'mydb'
ORDER BY pg_total_relation_size(table_schema || '.' || table_name) DESC;
```

**Identify backup candidates**:
- Large tables needing separate schedules
- Critical tables needing frequent backups
- Tables with specific retention requirements

### Step 2: Execute Table Backup

**Single critical table**:
```sql
BACKUP TABLE mydb.customer_payments
  INTO 'gs://backups/critical/payments'
  AS OF SYSTEM TIME '-10s';
```

**Output**:
```
        job_id       |  status   | fraction_completed | rows  | ...
---------------------+-----------+--------------------+-------+----
  123456789001      | succeeded |                  1 | 8452  | ...
```

### Step 3: Verify Backup Completion

**Check job status**:
```sql
SHOW JOB 123456789001;
```

**Expected**:
- `status`: "succeeded"
- `fraction_completed`: 1
- `finished`: Timestamp of completion

**Verify backup contents**:
```sql
SHOW BACKUP FROM LATEST IN 'gs://backups/critical/payments';
```

**Output shows table metadata**:
```
database_name | table_name        | start_time | end_time            | rows  | ...
--------------+-------------------+------------+---------------------+-------+----
mydb          | customer_payments | NULL       | 2026-03-06 10:00:00 | 8452  | ...
```

## Backup Strategies

**Related tables**: Backup together for referential integrity
**Size-based**: Large tables on separate schedules
**Compliance**: Isolate sensitive tables with encryption

## Backup Options

**PITR**: Add `WITH revision_history` for point-in-time recovery
**Incremental**: Use `INTO LATEST IN` for subsequent backups
**Encryption**: Add `WITH encryption_passphrase = 'xxx'` for sensitive data

## What's Included

**Included**: Table rows, schema, indexes, constraints, sequences, column families
**Excluded**: Other tables, database-level config, system tables

## Troubleshooting

**"Table not found"**: Verify table name with `SHOW TABLES`
**"Permission denied"**: `GRANT BACKUP ON TABLE...`
**Foreign key errors**: Backup all related tables together

## Restoring Table-Level Backups

### Restore Single Table

**Basic restore syntax**:
```sql
RESTORE TABLE mydb.customers
  FROM LATEST IN 'gs://backups/tables/customers';
```

**Restore to different table name**:
```sql
RESTORE TABLE mydb.customers
  FROM LATEST IN 'gs://backups/tables/customers'
  WITH into_db = 'testdb', table_name = 'customers_backup';
```

### Restore Multiple Tables

**Restore all tables from backup**:
```sql
RESTORE TABLE mydb.orders, mydb.order_items
  FROM LATEST IN 'gs://backups/order-system';
```

**Restore to point in time** (requires revision_history):
```sql
RESTORE TABLE mydb.transactions
  FROM LATEST IN 'gs://backups/pitr/transactions'
  AS OF SYSTEM TIME '2026-03-06 10:00:00';
```

## Best Practices

1. **Backup related tables together** to maintain foreign key integrity
2. **Use descriptive paths** (`gs://backups/critical/payments`)
3. **Test monthly restores** to test database
4. **Hybrid strategy**: Daily cluster backup + hourly critical table backups
5. **Use incrementals for large tables** (82% storage savings: weekly full + daily incremental vs daily full)

## Related Skills

- `execute-cluster-level-full-backups` - Backup entire cluster instead of tables
- `execute-database-level-backups` - Backup entire database
- `create-incremental-backups-with-backup-into-latest` - Add incrementals to table backups
- `create-backups-with-revision-history-for-pitr` - Enable point-in-time recovery for tables
- `restore-individual-tables-from-backup` - Restore table-level backups
- `understand-backup-chain-structure` - Manage full + incremental chains
- `inspect-backup-contents-with-show-backup` - Verify table backup contents
- `create-scheduled-backups-for-automation` - Automate table-level backups
