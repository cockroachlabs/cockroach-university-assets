---
name: restore-cluster-from-full-backup
description: Restore entire cluster from full backup using RESTORE FROM LATEST IN for disaster recovery. Recovers all databases, tables, users, roles, and cluster settings. Target cluster must be empty (no user databases). Used for catastrophic failure recovery and cluster migration to new infrastructure.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Restore Cluster from Full Backup

Full cluster restore is a critical disaster recovery operation that recovers your entire CockroachDB cluster from a backup. This skill covers using `RESTORE FROM LATEST IN` to restore all databases, tables, users, roles, and cluster settings in a single operation.

## When to Use Full Cluster Restore

Use full cluster restore in these scenarios:

**Disaster Recovery**: Complete cluster failure requiring full rebuild from backups
**Infrastructure Migration**: Moving cluster to new hardware or cloud provider
**Catastrophic Data Loss**: Accidental data deletion across multiple databases
**Testing**: Creating production-like environments for testing
**Compliance**: Restoring to specific point in time for audit purposes

## Prerequisites

Before performing a full cluster restore:

**Empty Target Cluster**: Cluster must have NO user databases (only system databases)
**Cluster Version**: Target cluster version must match or be newer than backup
**Enterprise License**: Full cluster restore requires enterprise license
**Backup Access**: Valid credentials for backup storage location
**Sufficient Resources**: Adequate disk space, memory, and CPU for restored data
**Network Connectivity**: Access to backup storage (S3, GCS, Azure, etc.)

## Basic Full Cluster Restore

### Restore from Latest Backup

```sql
-- Restore entire cluster from most recent full backup
RESTORE FROM LATEST IN 's3://backup-bucket/cluster-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

### Restore from Specific Backup Location

```sql
-- Restore from specific backup collection
RESTORE FROM LATEST IN 'gs://production-backups/daily-full?AUTH=implicit';
```

### Restore with Azure Storage

```sql
-- Restore from Azure Blob Storage
RESTORE FROM LATEST IN 'azure://backups/cluster?AZURE_ACCOUNT_NAME={account}&AZURE_ACCOUNT_KEY={key}';
```

## Inspecting Available Backups

Before restoring, inspect backup contents and available timestamps.

### List All Backups in Collection

```sql
-- Show all backups in collection
SHOW BACKUPS IN 's3://backup-bucket/cluster-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

Output shows:
- Backup paths
- Start and end times
- Backup types (full or incremental)
- Size information

### Inspect Specific Backup Contents

```sql
-- Show detailed contents of latest backup
SHOW BACKUP FROM LATEST IN 's3://backup-bucket/cluster-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

This displays:
- All databases included
- Table schemas
- User and role definitions
- Cluster settings
- Row counts per table

### Inspect Specific Backup Timestamp

```sql
-- Show contents of backup at specific time
SHOW BACKUP FROM '2026-03-01 00:00:00' IN 's3://backup-bucket/cluster-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}';
```

## Point-in-Time Recovery (PITR)

When backups include revision history, restore to exact point in time.

### Restore to Specific Timestamp

```sql
-- Restore cluster to exact point in time
RESTORE FROM LATEST IN 's3://backup-bucket/cluster-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
AS OF SYSTEM TIME '2026-03-05 14:30:00';
```

### Restore to Before Incident

```sql
-- Restore to 5 minutes before data corruption occurred
RESTORE FROM LATEST IN 'gs://backups/cluster?AUTH=implicit'
AS OF SYSTEM TIME '2026-03-05 09:25:00';
```

### Verify Revision History Availability

```sql
-- Check if backup supports PITR
SHOW BACKUP FROM LATEST IN 's3://backup-bucket/cluster-backups?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH revision_history;
```

Look for `revision_history` column showing time range for PITR.

## Advanced Restore Options

### Restore with Encryption

If backup was created encrypted, provide encryption passphrase.

```sql
-- Restore encrypted backup
RESTORE FROM LATEST IN 's3://backup-bucket/encrypted?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH encryption_passphrase = 'your-strong-passphrase-here';
```

### Restore with Custom Options

```sql
-- Restore with multiple options
RESTORE FROM LATEST IN 'gs://backups/cluster?AUTH=implicit'
WITH
  detached,
  encryption_passphrase = 'passphrase',
  skip_localities_check;
```

**Options explained**:
- `detached`: Run restore as background job, return immediately
- `encryption_passphrase`: Decrypt encrypted backups
- `skip_localities_check`: Skip validation of node locality matching backup

### Detached Restore for Large Clusters

```sql
-- Start restore as background job
RESTORE FROM LATEST IN 's3://backup-bucket/large-cluster?AWS_ACCESS_KEY_ID={access_key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH detached;
```

Returns job ID immediately. Monitor with `SHOW JOBS`.

## Monitoring Restore Progress

### Check Restore Job Status

```sql
-- View all restore jobs
SELECT job_id, status, fraction_completed, running_status, description
FROM [SHOW JOBS]
WHERE job_type = 'RESTORE'
ORDER BY created DESC
LIMIT 10;
```

### Monitor Specific Restore Job

```sql
-- Monitor specific job by ID
SELECT
  job_id,
  status,
  fraction_completed,
  ROUND(fraction_completed * 100, 2) AS percent_complete,
  running_status,
  created,
  started,
  finished,
  error
FROM [SHOW JOBS]
WHERE job_id = 123456789012345;
```

### Watch Restore Progress in Real-Time

```sql
-- View active restore with detailed progress
SHOW JOBS
WHEN COMPLETE (SELECT * FROM [SHOW JOBS] WHERE job_id = 123456789012345);
```

## Verification After Restore

After restore completes, verify cluster integrity.

### Verify Database Count

```sql
-- Count restored databases
SELECT count(*) AS database_count
FROM [SHOW DATABASES];
```

Compare with expected count from backup manifest.

### Verify Table Count

```sql
-- Count restored tables per database
SELECT
  table_schema AS database,
  count(*) AS table_count
FROM information_schema.tables
WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'crdb_internal', 'pg_extension')
GROUP BY table_schema
ORDER BY table_schema;
```

### Verify Users and Roles

```sql
-- List restored users
SHOW USERS;

-- List restored roles
SHOW ROLES;
```

### Verify Critical Tables

```sql
-- Check row count for critical tables
SELECT
  'orders' AS table_name,
  count(*) AS row_count
FROM production.orders
UNION ALL
SELECT 'customers', count(*) FROM production.customers
UNION ALL
SELECT 'products', count(*) FROM production.products;
```

Compare counts with pre-disaster baseline or backup manifest.

### Verify Cluster Settings

```sql
-- Check critical cluster settings restored
SHOW CLUSTER SETTING cluster.organization;
SHOW CLUSTER SETTING enterprise.license;
SHOW CLUSTER SETTING kv.range_merge.queue_enabled;
```

## Common Issues and Troubleshooting

### Issue: Target Cluster Not Empty

**Error**: `pq: cluster restore can only be run on a cluster with no user databases`

**Solution**:
```sql
-- Drop all user databases (CAUTION!)
SELECT 'DROP DATABASE ' || database_name || ' CASCADE;'
FROM [SHOW DATABASES]
WHERE database_name NOT IN ('system', 'postgres', 'defaultdb');

-- Execute each DROP DATABASE statement
```

### Issue: Version Mismatch

**Error**: `pq: backup was created on version X, but cluster is running version Y`

**Solution**: Upgrade target cluster to version matching or newer than backup:
```bash
# Upgrade cluster to compatible version
cockroach version  # Check current version
# Perform rolling upgrade if needed
```

### Issue: Insufficient Disk Space

**Error**: `pq: store ... out of disk space`

**Solution**:
```sql
-- Check disk usage before restore
SELECT
  node_id,
  store_id,
  capacity,
  available,
  used,
  ROUND(used / capacity * 100, 2) AS percent_used
FROM crdb_internal.kv_store_status;

-- Add more nodes or increase disk capacity
```

### Issue: Missing Encryption Passphrase

**Error**: `pq: file appears encrypted -- ENCRYPTION_PASSPHRASE param is required`

**Solution**:
```sql
-- Provide correct passphrase
RESTORE FROM LATEST IN 's3://bucket/backups?AWS_ACCESS_KEY_ID={key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH encryption_passphrase = 'correct-passphrase';
```

### Issue: Storage Credentials Invalid

**Error**: `pq: AccessDenied: Access Denied`

**Solution**:
```sql
-- Verify credentials with SHOW BACKUPS first
SHOW BACKUPS IN 's3://bucket/backups?AWS_ACCESS_KEY_ID={correct_key}&AWS_SECRET_ACCESS_KEY={correct_secret}';

-- Use correct credentials in RESTORE
```

### Issue: Restore Job Stuck or Slow

**Symptom**: `fraction_completed` not increasing

**Troubleshooting**:
```sql
-- Check for node issues
SELECT node_id, address, is_live
FROM crdb_internal.gossip_nodes;

-- Check disk I/O performance
SELECT
  store_id,
  node_id,
  capacity,
  available,
  used
FROM crdb_internal.kv_store_status;

-- Consider canceling and restarting
CANCEL JOB 123456789012345;
```

## Complete Disaster Recovery Workflow

### Step 1: Provision New Cluster

```bash
# Start fresh cluster (same or newer version)
cockroach start --insecure --store=/data/node1 --listen-addr=localhost:26257 --http-addr=localhost:8080 --background
cockroach start --insecure --store=/data/node2 --listen-addr=localhost:26258 --http-addr=localhost:8081 --join=localhost:26257 --background
cockroach start --insecure --store=/data/node3 --listen-addr=localhost:26259 --http-addr=localhost:8082 --join=localhost:26257 --background

cockroach init --insecure --host=localhost:26257
```

### Step 2: Verify Cluster Empty

```sql
-- Connect to new cluster
cockroach sql --insecure --host=localhost:26257

-- Verify no user databases exist
SHOW DATABASES;
```

Should only show: `system`, `postgres`, `defaultdb`

### Step 3: Inspect Available Backups

```sql
-- List backup collection
SHOW BACKUPS IN 's3://production-backups/cluster?AWS_ACCESS_KEY_ID={key}&AWS_SECRET_ACCESS_KEY={secret}';

-- Examine latest backup contents
SHOW BACKUP FROM LATEST IN 's3://production-backups/cluster?AWS_ACCESS_KEY_ID={key}&AWS_SECRET_ACCESS_KEY={secret}';
```

### Step 4: Execute Restore

```sql
-- Start restore as background job
RESTORE FROM LATEST IN 's3://production-backups/cluster?AWS_ACCESS_KEY_ID={key}&AWS_SECRET_ACCESS_KEY={secret}'
WITH detached;
```

Note job ID returned.

### Step 5: Monitor Progress

```sql
-- Check every few minutes
SELECT
  job_id,
  fraction_completed,
  ROUND(fraction_completed * 100, 2) AS percent,
  running_status
FROM [SHOW JOBS]
WHERE job_id = 123456789012345;
```

### Step 6: Verify After Completion

```sql
-- Verify databases
SHOW DATABASES;

-- Verify critical tables
SELECT count(*) FROM production.orders;
SELECT count(*) FROM production.customers;

-- Verify users
SHOW USERS;

-- Test application queries
SELECT * FROM production.products WHERE product_id = 'TEST123';
```

### Step 7: Update Application Connection Strings

```bash
# Point application to new cluster
export DATABASE_URL="postgresql://user@new-cluster:26257/production?sslmode=require"

# Restart application services
systemctl restart app-server
```

## Best Practices

**Test Restores Regularly**: Perform test restores quarterly to verify backup integrity
**Document Recovery Time**: Measure restore duration to validate RTO targets
**Verify Backup Contents**: Always `SHOW BACKUP` before executing restore
**Use Detached Mode**: For large clusters, use `WITH detached` to avoid connection timeouts
**Monitor Cluster Health**: Watch node liveness and disk space during restore
**Validate Data After Restore**: Run row counts and application smoke tests
**Keep Credentials Secure**: Use credential files or environment variables, not inline
**Plan for Downtime**: Communicate maintenance window for restore operations
**Archive Old Backups**: Implement retention policies to manage storage costs
**Test PITR Capability**: Verify revision history works before disaster strikes

## Security Considerations

**Backup Encryption**: Always encrypt backups containing sensitive data
**Access Control**: Restrict backup storage access to authorized personnel only
**Credential Rotation**: Rotate storage credentials regularly
**Audit Logging**: Log all restore operations for compliance
**Network Security**: Use VPC endpoints or private links for cloud storage access
**License Management**: Ensure valid enterprise license before restore

## Related Skills

- **restore-individual-tables-from-backup**: Selective table recovery without full cluster restore
- **restore-database-from-backup**: Database-level restore for single database recovery
- **list-available-backups-with-show-backups**: Inspect backup collections before restore
- **inspect-backup-contents-with-show-backup**: Examine backup manifests and metadata
- **implement-point-in-time-recovery**: Restore to exact timestamp using revision history
- **validate-restored-data-completeness**: Systematically verify restore success
- **conduct-disaster-recovery-testing**: Execute complete DR drills in test environments
- **execute-cluster-level-full-backups**: Create full cluster backups for restore
- **create-backups-with-revision-history-for-pitr**: Enable PITR capability in backups
- **monitor-scheduled-backups-with-show-schedules**: Verify backup schedules producing restorable backups

## Additional Resources

- CockroachDB Docs: Restore a Cluster
- CockroachDB Docs: Full Cluster Restore
- CockroachDB Docs: Disaster Recovery Planning
- CockroachDB Docs: Backup and Restore Overview
