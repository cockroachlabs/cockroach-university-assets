---
name: restore-clusters-from-backups-in-cloud
description: Restore CockroachDB Cloud clusters from managed backups using the Cloud Console, including full cluster restores and point-in-time recovery. Use when recovering from data corruption, accidental deletions, ransomware attacks, or testing disaster recovery procedures.
metadata:
  domain: Cloud Ops
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: CockroachDB Cloud
  related_skills:
    - enable-and-configure-backups-in-cloud
    - monitor-backup-jobs-in-cloud-console
    - validate-restored-data-completeness
  prerequisites:
    - Cluster Admin or Cluster Operator role (source and destination)
    - Understanding of backup retention windows
    - Empty destination cluster for full cluster restores
  estimated_time_minutes: 45
  last_updated: "2026-03-07"
---

# Restore Clusters from Backups in Cloud

## Overview

CockroachDB Cloud provides managed backup restore capabilities through the Cloud Console and API. You can restore entire clusters or individual databases to the same cluster or a different cluster, with support for point-in-time recovery (PITR) within your backup retention window.

**Critical**: Full cluster restores require a completely empty destination cluster. Any existing databases, schemas, or tables will cause the restore to fail.

## Understanding Cloud Backup Restores

### Restore Types

**Full Cluster Restore**:
- Restores all databases and schemas
- Requires empty destination cluster
- Cannot restore to source cluster with data
- Typical use: Disaster recovery, cluster migration

**Database-Level Restore**:
- Restores specific database(s)
- Can restore to source cluster or different cluster
- Destination database must not exist
- Typical use: Selective recovery, database cloning

**Point-in-Time Restore (PITR)**:
- Restore to any timestamp within retention window
- Available for both cluster and database restores
- Precision: Sub-second accuracy
- Typical use: Recover before data corruption event

### Managed Backup Locations

**Storage**:
- Backups stored in Cockroach Labs-managed cloud storage
- Region-specific storage locations (same region as cluster)
- Encrypted at rest
- No direct access to backup files (managed by Cockroach Labs)

**Retention Windows**:
```
Retention Period | Available Recovery Points
──────────────────────────────────────────────
2 days          | Last 48 hours
7 days          | Last 7 days
30 days         | Last 30 days
90 days         | Last 90 days
365 days        | Last 365 days
```

### Restore Limitations

**Cluster-Level Restrictions**:
- Destination cluster must be completely empty
- Cannot restore to cluster with any user-created objects
- Cannot restore across major CockroachDB versions
- Cannot restore from Advanced cluster to Basic/Standard cluster (size/feature limitations may apply)

**Timing Restrictions**:
- Can only restore from backups within retention window
- Cannot restore from deleted/expired backups
- Restore target timestamp must be within backup coverage

**Permission Requirements**:
- Cluster Admin or Cluster Operator role on source cluster (where backup exists)
- Cluster Admin or Cluster Operator role on destination cluster (where restoring to)
- Organization-level permissions if restoring across clusters

## Restore Prerequisites

### Verify Backup Availability

**Step 1: Check Available Backups**

```
1. Navigate to Cloud Console
2. Select source cluster (where backup exists)
3. Click "Backup and Restore" in navigation
4. Click "Backups" tab
5. View available backups:
   ┌──────────────────────────────────────────────┐
   │ Available Backups                            │
   ├──────────────────────────────────────────────┤
   │ Timestamp           Size    Status   Actions │
   │ 2026-03-07 14:00   105 GB  Complete  Restore │
   │ 2026-03-07 08:00   104 GB  Complete  Restore │
   │ 2026-03-07 02:00   104 GB  Complete  Restore │
   │ 2026-03-06 20:00   103 GB  Complete  Restore │
   └──────────────────────────────────────────────┘
```

**Step 2: Verify Backup Details**

```
Click on a backup to view details:

Backup Details:
────────────────────────────────────────
Backup ID: backup-1234567890abcdef
Timestamp: 2026-03-07 14:00:00 UTC
Type: Full cluster backup
Size: 105 GB
Status: Completed successfully
Databases: 5 databases
  - production_db (80 GB)
  - analytics_db (15 GB)
  - reporting_db (8 GB)
  - staging_db (1.5 GB)
  - test_db (0.5 GB)

Point-in-time recovery available:
  From: 2026-03-07 14:00:00 UTC
  To:   2026-03-07 14:00:00 UTC (backup time)

With previous backups:
  From: 2026-02-06 14:00:00 UTC (30 days ago)
  To:   2026-03-07 14:00:00 UTC
────────────────────────────────────────
```

### Prepare Destination Cluster

**For Full Cluster Restore** (destination must be empty):

```
Verification checklist:

1. Check for user-created databases:
   Navigate to destination cluster → Databases
   Should show ONLY:
   - defaultdb (system database)
   - postgres (system database)
   - system (system database)

2. Verify no user tables exist:
   Cloud Console → SQL Shell:
   SELECT tablename
   FROM pg_tables
   WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'crdb_internal');

   Result should be: 0 rows

3. Confirm no non-default databases:
   SHOW DATABASES;

   Should only show:
   - defaultdb
   - postgres
   - system

If destination has data:
- Option 1: Delete all user databases manually
- Option 2: Create new empty cluster for restore
- Option 3: Restore to different cluster
```

**For Database-Level Restore**:

```
Verification:

1. Ensure destination database does NOT exist:
   SHOW DATABASES;

   # Should NOT list the database you're restoring

2. Verify sufficient storage:
   - Destination cluster storage ≥ database size
   - Account for growth during restore
   - Check cluster metrics for available capacity

3. Check compatibility:
   - CockroachDB version compatible
   - Cluster tier supports database size
```

## Performing Full Cluster Restore

### Step 1: Navigate to Restore Interface

```
1. Log in to CockroachDB Cloud Console
2. Navigate to source cluster (where backup exists)
3. Click "Backup and Restore" in left navigation
4. Click "Backups" tab
5. Locate the backup you want to restore
```

### Step 2: Initiate Cluster Restore

```
1. Find desired backup in list:
   ┌──────────────────────────────────────────────┐
   │ 2026-03-07 14:00  105 GB  Complete  [Restore]│
   └──────────────────────────────────────────────┘

2. Click "Restore" button
3. Restore dialog appears:
   ┌────────────────────────────────────────────┐
   │ Restore Cluster Backup                     │
   ├────────────────────────────────────────────┤
   │ Backup timestamp: 2026-03-07 14:00 UTC     │
   │ Backup size: 105 GB                        │
   │ Backup type: Full cluster                  │
   │                                            │
   │ Restore destination:                       │
   │ ( ) This cluster (must be empty)           │
   │ (•) Different cluster                      │
   │                                            │
   │ [Next]                                     │
   └────────────────────────────────────────────┘
```

### Step 3: Select Destination Cluster

```
1. If "Different cluster" selected:
   ┌────────────────────────────────────────────┐
   │ Select Destination Cluster                 │
   ├────────────────────────────────────────────┤
   │ Organization: YourOrg                      │
   │                                            │
   │ Available clusters:                        │
   │ ( ) production-cluster-backup (Advanced)   │
   │     Status: Empty ✓                        │
   │     Region: us-west-2                      │
   │     vCPUs: 8 per node                      │
   │     Storage: 200 GB per node               │
   │                                            │
   │ ( ) dr-cluster (Advanced)                  │
   │     Status: Empty ✓                        │
   │     Region: us-east-1                      │
   │     vCPUs: 16 per node                     │
   │     Storage: 500 GB per node               │
   │                                            │
   │ [Back]  [Next]                             │
   └────────────────────────────────────────────┘

2. Select destination cluster
3. Console validates:
   - Cluster is empty
   - Sufficient storage capacity
   - Compatible CockroachDB version
   - User has required permissions
```

### Step 4: Configure Point-in-Time (Optional)

```
Point-in-Time Restore Configuration:
┌────────────────────────────────────────────┐
│ Restore Options                            │
├────────────────────────────────────────────┤
│ ( ) Latest backup (2026-03-07 14:00 UTC)   │
│ (•) Point-in-time restore                  │
│                                            │
│ Select timestamp:                          │
│ Date: [2026-03-07]  ▼                      │
│ Time: [13:45:30]    ▼  UTC                 │
│                                            │
│ ℹ Available range:                         │
│ From: 2026-02-06 14:00 UTC                 │
│ To:   2026-03-07 14:00 UTC                 │
│                                            │
│ ⚠ Restore will recover data as it existed  │
│   at 2026-03-07 13:45:30 UTC               │
│                                            │
│ [Back]  [Next]                             │
└────────────────────────────────────────────┘

Point-in-Time Use Cases:

Scenario: Accidental data deletion
- Deletion occurred: 2026-03-07 13:50 UTC
- Restore to: 2026-03-07 13:45 UTC (before deletion)
- Result: Data recovered from before deletion

Scenario: Ransomware attack detected
- Attack detected: 2026-03-07 14:30 UTC
- Last known good state: 2026-03-07 12:00 UTC
- Restore to: 2026-03-07 12:00 UTC
- Result: Cluster restored to pre-attack state
```

### Step 5: Review and Confirm

```
┌────────────────────────────────────────────┐
│ Confirm Restore                            │
├────────────────────────────────────────────┤
│ Source:                                    │
│ • Cluster: production-cluster              │
│ • Backup: 2026-03-07 14:00 UTC             │
│ • PITR: 2026-03-07 13:45:30 UTC            │
│ • Size: 105 GB                             │
│                                            │
│ Destination:                               │
│ • Cluster: dr-cluster                      │
│ • Region: us-east-1                        │
│ • Storage available: 1.5 TB                │
│                                            │
│ Estimated duration: 45-90 minutes          │
│                                            │
│ ⚠ WARNING: This will:                      │
│ • Restore all databases to destination     │
│ • Take 45-90 minutes to complete           │
│ • Destination cluster will be unavailable  │
│   during restore                           │
│ • Cannot be cancelled once started         │
│                                            │
│ [Cancel]  [Start Restore]                  │
└────────────────────────────────────────────┘

Click "Start Restore" to begin
```

### Step 6: Monitor Restore Progress

```
Restore in progress screen:
┌────────────────────────────────────────────┐
│ Cluster Restore in Progress                │
├────────────────────────────────────────────┤
│ Status: Restoring...                       │
│ Progress: ████████████░░░░░░░░ 60%         │
│                                            │
│ Current phase: Restoring production_db     │
│ Restored: 63 GB / 105 GB                   │
│ Elapsed time: 27 minutes                   │
│ Estimated remaining: 18 minutes            │
│                                            │
│ Databases restored:                        │
│ ✓ analytics_db (15 GB)                     │
│ ✓ reporting_db (8 GB)                      │
│ ⟳ production_db (60% of 80 GB)             │
│ ○ staging_db (pending)                     │
│ ○ test_db (pending)                        │
│                                            │
│ You can safely close this window.          │
│ Progress viewable in Activity tab.         │
└────────────────────────────────────────────┘
```

### Step 7: Verify Restore Completion

```
Upon completion:
┌────────────────────────────────────────────┐
│ Restore Completed Successfully            │
├────────────────────────────────────────────┤
│ ✓ Cluster restore completed                │
│   Total time: 45 minutes                   │
│   Data restored: 105 GB                    │
│   Databases: 5                             │
│                                            │
│ Destination cluster: dr-cluster            │
│ Restored to: 2026-03-07 13:45:30 UTC       │
│                                            │
│ Next steps:                                │
│ • Verify data integrity                    │
│ • Test application connectivity            │
│ • Review restored databases                │
│ • Update connection strings (if needed)    │
│                                            │
│ [View cluster]  [Close]                    │
└────────────────────────────────────────────┘

Navigate to destination cluster:
1. Check Databases tab - all databases present
2. Verify table counts match expectations
3. Test queries on critical tables
4. Verify data timestamps match restore point
```

## Performing Database-Level Restore

### Step 1: Select Database to Restore

```
1. Navigate to source cluster → Backup and Restore
2. Click "Backups" tab
3. Click on backup to view details
4. In backup details, see list of databases:
   ┌────────────────────────────────────────┐
   │ Backup Contents                        │
   ├────────────────────────────────────────┤
   │ Database         Size      Tables      │
   │ production_db    80 GB     42 tables   │
   │ analytics_db     15 GB     12 tables   │
   │ reporting_db     8 GB      8 tables    │
   │ staging_db       1.5 GB    15 tables   │
   │ test_db          0.5 GB    5 tables    │
   └────────────────────────────────────────┘
```

### Step 2: Initiate Database Restore

```
1. Click "Restore database" option
2. Select specific database(s):
   ┌────────────────────────────────────────┐
   │ Restore Specific Databases             │
   ├────────────────────────────────────────┤
   │ Select databases to restore:           │
   │                                        │
   │ ☑ production_db (80 GB)                │
   │ ☐ analytics_db (15 GB)                 │
   │ ☐ reporting_db (8 GB)                  │
   │ ☐ staging_db (1.5 GB)                  │
   │ ☐ test_db (0.5 GB)                     │
   │                                        │
   │ Total selected: 80 GB                  │
   │                                        │
   │ [Next]                                 │
   └────────────────────────────────────────┘

Can select multiple databases
Each must not exist in destination
```

### Step 3: Choose Destination

```
Database restore destination options:
┌────────────────────────────────────────┐
│ Restore Destination                    │
├────────────────────────────────────────┤
│ Restore production_db to:              │
│                                        │
│ ( ) Same cluster (source)              │
│     Database will be restored to       │
│     current cluster. Database must     │
│     not currently exist.               │
│                                        │
│ (•) Different cluster                  │
│     Select destination cluster below   │
│                                        │
│ Destination cluster:                   │
│ [production-cluster-backup]  ▼         │
│                                        │
│ Database name (optional rename):       │
│ [production_db]                        │
│                                        │
│ ℹ Leave blank to use original name     │
│                                        │
│ [Back]  [Next]                         │
└────────────────────────────────────────┘

Renaming option allows:
- Restore to same cluster with different name
- Example: production_db → production_db_restored
- Useful for comparison or testing
```

### Step 4: Configure PITR (if needed)

```
Same PITR interface as cluster restore:

┌────────────────────────────────────────┐
│ Restore Time Selection                │
├────────────────────────────────────────┤
│ ( ) Latest backup (2026-03-07 14:00)   │
│ (•) Point-in-time: [2026-03-07 10:30]  │
│                                        │
│ Database: production_db                │
│ Restore point: 2026-03-07 10:30 UTC    │
│                                        │
│ This will restore the database as it   │
│ existed at the selected timestamp.     │
│                                        │
│ [Back]  [Next]                         │
└────────────────────────────────────────┘
```

### Step 5: Execute Database Restore

```
Review and confirm:
┌────────────────────────────────────────┐
│ Confirm Database Restore               │
├────────────────────────────────────────┤
│ Source database: production_db         │
│ Source cluster: production-cluster     │
│ Backup time: 2026-03-07 14:00 UTC      │
│ Restore to: 2026-03-07 10:30 UTC       │
│ Size: 80 GB                            │
│                                        │
│ Destination database: production_db    │
│ Destination cluster: backup-cluster    │
│                                        │
│ Estimated time: 30-60 minutes          │
│                                        │
│ [Cancel]  [Start Restore]              │
└────────────────────────────────────────┘

Monitor same as cluster restore
Check Activity tab for progress
```

## Performing Restores via Cloud API

### List Available Backups

```bash
export COCKROACH_API_SECRET="your_api_key"
export CLUSTER_ID="source_cluster_id"

# GET list of backups for cluster
curl -X GET \
  "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/backups" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  -H "Cc-Version: 2024-09-16" \
  | jq '.backups[]'

# Response:
{
  "id": "backup-abc123",
  "cluster_id": "cluster-xyz789",
  "timestamp": "2026-03-07T14:00:00Z",
  "size_bytes": 112742891520,
  "status": "COMPLETED",
  "type": "FULL_CLUSTER",
  "databases": [
    {"name": "production_db", "size_bytes": 85899345920},
    {"name": "analytics_db", "size_bytes": 16106127360}
  ]
}
```

### Initiate Cluster Restore via API

```bash
export DEST_CLUSTER_ID="destination_cluster_id"
export BACKUP_ID="backup-abc123"

# POST to initiate cluster restore
curl -X POST \
  "https://cockroachlabs.cloud/api/v1/clusters/${DEST_CLUSTER_ID}/restore" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  -H "Cc-Version: 2024-09-16" \
  -H "Content-Type: application/json" \
  -d '{
    "source_cluster_id": "'${CLUSTER_ID}'",
    "backup_id": "'${BACKUP_ID}'",
    "restore_type": "CLUSTER",
    "timestamp": "2026-03-07T13:45:30Z"
  }' \
  | jq '.'

# Response:
{
  "restore_job_id": "restore-job-123",
  "status": "RUNNING",
  "started_at": "2026-03-07T15:30:00Z",
  "estimated_completion": "2026-03-07T16:15:00Z"
}
```

### Initiate Database Restore via API

```bash
# POST to restore specific database
curl -X POST \
  "https://cockroachlabs.cloud/api/v1/clusters/${DEST_CLUSTER_ID}/restore" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  -H "Cc-Version: 2024-09-16" \
  -H "Content-Type: application/json" \
  -d '{
    "source_cluster_id": "'${CLUSTER_ID}'",
    "backup_id": "'${BACKUP_ID}'",
    "restore_type": "DATABASE",
    "databases": ["production_db"],
    "timestamp": "2026-03-07T10:30:00Z",
    "rename_database": {
      "production_db": "production_db_restored"
    }
  }' \
  | jq '.'
```

### Monitor Restore Progress via API

```bash
export RESTORE_JOB_ID="restore-job-123"

# Poll restore status
curl -X GET \
  "https://cockroachlabs.cloud/api/v1/clusters/${DEST_CLUSTER_ID}/restore/${RESTORE_JOB_ID}" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  -H "Cc-Version: 2024-09-16" \
  | jq '.'

# Response (in progress):
{
  "restore_job_id": "restore-job-123",
  "status": "RUNNING",
  "progress_percent": 60,
  "started_at": "2026-03-07T15:30:00Z",
  "current_phase": "Restoring production_db",
  "bytes_restored": 67645734912,
  "total_bytes": 112742891520,
  "estimated_completion": "2026-03-07T16:15:00Z"
}

# Response (completed):
{
  "restore_job_id": "restore-job-123",
  "status": "COMPLETED",
  "progress_percent": 100,
  "started_at": "2026-03-07T15:30:00Z",
  "completed_at": "2026-03-07T16:12:00Z",
  "duration_seconds": 2520,
  "bytes_restored": 112742891520,
  "databases_restored": ["production_db", "analytics_db"]
}
```

## Post-Restore Verification

### Data Integrity Checks

```sql
-- Connect to restored cluster
-- Via Cloud Console → SQL Shell or via cockroach sql CLI

-- 1. Verify databases restored
SHOW DATABASES;

-- Expected output:
--   database_name
-- ───────────────
--   production_db
--   analytics_db
--   reporting_db
--   (... etc)

-- 2. Verify table counts per database
SELECT
  table_schema,
  count(*) as table_count
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema', 'crdb_internal')
GROUP BY table_schema
ORDER BY table_schema;

-- 3. Verify row counts for critical tables
SELECT
  'orders' as table_name,
  count(*) as row_count
FROM production_db.orders
UNION ALL
SELECT
  'customers',
  count(*)
FROM production_db.customers
UNION ALL
SELECT
  'transactions',
  count(*)
FROM production_db.transactions;

-- Compare against expected counts from before incident

-- 4. Verify data timestamps (for PITR validation)
SELECT
  max(created_at) as latest_order,
  min(created_at) as earliest_order
FROM production_db.orders;

-- For PITR restore to 2026-03-07 13:45:30:
-- latest_order should be ≤ 2026-03-07 13:45:30
-- Confirms restore to correct point in time

-- 5. Check for foreign key integrity
SELECT
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type
FROM information_schema.table_constraints tc
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'production_db'
ORDER BY tc.table_name;

-- Verify all foreign keys present
```

### Application Testing

```
Post-restore application validation:

1. Connection Test
   - Update application connection strings if needed
   - Test application can connect to restored cluster
   - Verify SSL/TLS certificates work

2. Read Operations
   - Query critical tables
   - Verify data returned correctly
   - Check for missing or corrupted data

3. Write Operations (if restoring to production)
   - Test INSERT operations
   - Test UPDATE operations
   - Test DELETE operations
   - Verify triggers and constraints work

4. Performance Baseline
   - Run key queries, measure latency
   - Compare against pre-incident baselines
   - Identify any performance degradation

5. End-to-End Test
   - Execute critical user workflows
   - Verify complete functionality
   - Test integrations with other systems
```

### Restore Validation Checklist

```
Restore Validation Checklist:

Database Structure:
☐ All expected databases present
☐ Table counts match expectations
☐ Indexes recreated correctly
☐ Foreign keys intact
☐ Sequences restored with correct values
☐ User-defined types present

Data Completeness:
☐ Row counts match pre-incident counts
☐ Critical tables have expected data
☐ No missing rows in key tables
☐ Latest timestamps match restore point (PITR)
☐ Oldest data within expected range

Data Correctness:
☐ Sample data spot-checked for accuracy
☐ Foreign key relationships valid
☐ Uniqueness constraints satisfied
☐ CHECK constraints pass
☐ NULL/NOT NULL constraints correct

Application Validation:
☐ Application connects successfully
☐ Read operations work correctly
☐ Write operations work correctly
☐ Performance within acceptable range
☐ End-to-end workflows function

Operational Readiness:
☐ Backups re-enabled and running
☐ Monitoring alerts configured
☐ Connection strings updated (if needed)
☐ DNS/load balancer updated (if needed)
☐ Team notified of restore completion
```

## Common Restore Scenarios

### Scenario 1: Accidental Data Deletion

```
Incident Timeline:
10:00 UTC - Database operating normally
10:30 UTC - Developer accidentally runs:
            DELETE FROM orders WHERE TRUE;
            (instead of WHERE order_id = 123)
10:31 UTC - Error discovered, all orders deleted
10:32 UTC - Incident declared

Recovery Steps:
1. Determine last known good state: 10:29 UTC
2. Navigate to Backup and Restore
3. Select backup covering that time period
4. Choose point-in-time restore: 10:29 UTC
5. Select database-level restore (orders only)
6. Restore to: orders_recovered (temporary name)
7. Wait for restore (15 minutes)
8. Validate data in orders_recovered
9. Copy data to production:
   INSERT INTO orders SELECT * FROM orders_recovered;
10. Drop orders_recovered
11. Verify application functionality

Total recovery time: ~30 minutes
Data loss: 2 minutes (10:29-10:31)
```

### Scenario 2: Ransomware Attack

```
Incident Timeline:
14:00 UTC - Suspicious activity detected
14:30 UTC - Ransomware confirmed, data encrypted
14:35 UTC - Cluster isolated from network
14:40 UTC - Last known clean state: 12:00 UTC

Recovery Steps:
1. Create new empty cluster (dr-cluster)
2. Navigate to original cluster backups
3. Select backup closest to 12:00 UTC
4. Configure PITR to exactly 12:00 UTC
5. Initiate full cluster restore to dr-cluster
6. Wait for restore completion (60 minutes)
7. Validate data integrity in dr-cluster
8. Update application connection strings
9. Route traffic to dr-cluster
10. Original cluster → forensic analysis
11. After analysis, delete infected cluster

Total recovery time: ~90 minutes
Data loss: 2.5 hours (12:00-14:30)
```

### Scenario 3: Cluster Migration

```
Use Case: Migrate to larger cluster

Migration Steps:
1. Create new larger cluster (empty)
   - More vCPUs per node
   - More storage capacity
   - Same region(s)
2. Trigger on-demand backup of source cluster
3. Wait for backup completion (30 min)
4. Initiate cluster restore to new cluster
   - Latest backup (no PITR needed)
   - Full cluster restore
5. Monitor restore progress (60 min)
6. Post-restore validation:
   - Verify all databases present
   - Test application connectivity
   - Run performance benchmarks
7. Gradual cutover:
   - Route read traffic to new cluster
   - Monitor for 24 hours
   - Route write traffic to new cluster
   - Monitor for 48 hours
8. Decommission old cluster

Total migration time: ~120 minutes (restore only)
Data loss: None (coordinated cutover)
```

## Troubleshooting Restore Issues

### Restore Fails: Destination Not Empty

```
Error: "Cannot restore cluster: destination contains user data"

Diagnosis:
# Check destination cluster for databases
SHOW DATABASES;

# If user databases exist, they must be removed

Resolution:
Option 1 - Delete user databases:
DROP DATABASE production_db CASCADE;
DROP DATABASE analytics_db CASCADE;
# Repeat for all user-created databases

Option 2 - Use different cluster:
- Create new empty cluster
- Use that as restore destination

Option 3 - Use database-level restore:
- Instead of cluster restore
- Restore each database individually
- Can restore to cluster with existing data
  (as long as destination database doesn't exist)
```

### Restore Fails: Insufficient Storage

```
Error: "Cannot restore: insufficient storage capacity"

Diagnosis:
Backup size: 500 GB
Destination cluster:
- 3 nodes × 150 GB = 450 GB total storage
- Insufficient for 500 GB backup

Resolution:
Option 1 - Increase destination cluster storage:
1. Navigate to destination cluster settings
2. Edit cluster → Increase storage per node
3. Change from 150 GB → 200 GB per node
4. Wait for scaling to complete
5. Retry restore

Option 2 - Use larger cluster:
1. Create new cluster with adequate storage
2. Use as restore destination

Recommendation:
- Destination storage ≥ 1.5× backup size
- Account for future growth
- Monitor storage during restore
```

### PITR Timestamp Not Available

```
Error: "Point-in-time timestamp outside backup coverage"

Cause:
Requested timestamp: 2026-02-01 10:00 UTC
Backup retention: 30 days
Current date: 2026-03-07
Oldest backup: 2026-02-06 14:00 UTC

Requested timestamp (Feb 1) is older than oldest backup (Feb 6)

Resolution:
- Can only restore within retention window
- Choose timestamp ≥ 2026-02-06 14:00 UTC
- If older restore needed:
  - Check if longer retention backups exist elsewhere
  - May need to use archived backups (if implemented)
  - Consider longer retention for future
```

### Restore Timeout or Stuck

```
Symptom: Restore running for >3 hours (expected: 60 min)

Diagnosis:
1. Check restore job status:
   Cloud Console → Activity tab
   Look for restore job progress

2. If stuck at specific phase:
   - Note which database/phase stuck
   - Check destination cluster health
   - Verify network connectivity

Resolution:
1. Wait for automatic retry (up to 24 hours)
2. If stuck >24 hours, contact support:
   - Provide cluster IDs (source and destination)
   - Provide backup ID
   - Provide restore job ID
   - Screenshot of error/status
3. Support can:
   - Investigate backend issues
   - Manually retry failed operations
   - Provide workarounds
```

## Best Practices

### Regular Restore Testing

```
Disaster Recovery Testing Schedule:

Monthly:
- Select random backup
- Restore to test cluster
- Validate data integrity
- Measure restore duration
- Document results

Quarterly:
- Full cluster restore drill
- Update runbooks based on findings
- Time all steps
- Involve all teams (dev, ops, management)
- Test failover procedures

Annually:
- Complete DR scenario test
- Include external stakeholders
- Test communication plans
- Validate RTO/RPO compliance
- Update disaster recovery plan
```

### Restore Time Optimization

```
Factors affecting restore duration:

1. Backup size
   - 100 GB: ~30 minutes
   - 500 GB: ~90 minutes
   - 1 TB: ~180 minutes

2. Destination cluster size
   - Larger clusters (more nodes) → faster restore
   - More parallelization of restore operations

3. Network bandwidth
   - Same region: optimal speed
   - Cross-region: slower (if supported)

4. Database structure
   - Many tables: longer
   - Fewer large tables: faster
   - Index recreation time

Optimization strategies:
- Size destination cluster appropriately
- Restore during low-traffic periods
- Use database-level restore if only subset needed
- Pre-create clusters for DR readiness
```

### Documentation Requirements

```
Maintain restore documentation:

Restore Runbook should include:

1. Backup Inventory
   - Current retention policy
   - Backup schedule (frequency)
   - Estimated backup sizes
   - Last successful backup timestamp

2. Restore Procedures
   - Step-by-step console instructions
   - CLI/API restore scripts
   - PITR selection guidelines
   - Validation checklist

3. Emergency Contacts
   - Cluster admins with restore permissions
   - Cockroach Labs support contacts
   - Escalation procedures
   - Communication plan (who to notify)

4. Cluster Information
   - Production cluster ID
   - DR cluster ID (if pre-created)
   - Connection strings (pre-populated templates)
   - Network configuration (IP allowlists, VPCs)

5. Recovery Time Objectives
   - RTO target (e.g., 2 hours)
   - RPO target (e.g., 6 hours)
   - Acceptable data loss window
   - Business impact thresholds

6. Test Results
   - Last restore test date
   - Test duration
   - Issues encountered
   - Lessons learned
```

## References

**Official Documentation**:
- [Backup and Restore in CockroachDB Cloud Overview](https://www.cockroachlabs.com/docs/cockroachcloud/backup-and-restore-overview)
- [Managed Backups in CockroachDB Advanced Clusters](https://www.cockroachlabs.com/docs/cockroachcloud/managed-backups-advanced)
- [Managed Backups in CockroachDB Standard Clusters](https://www.cockroachlabs.com/docs/cockroachcloud/managed-backups)
- [Take and Restore Self-Managed Backups](https://www.cockroachlabs.com/docs/cockroachcloud/take-and-restore-self-managed-backups)
- [RESTORE](https://www.cockroachlabs.com/docs/stable/restore)
- [Take Backups with Revision History and Restore from a Point-in-time](https://www.cockroachlabs.com/docs/stable/take-backups-with-revision-history-and-restore-from-a-point-in-time)

**Related Skills**:
- Enable and configure backups in cloud
- Monitor backup jobs in cloud console
- Validate restored data completeness
- Disaster recovery planning
