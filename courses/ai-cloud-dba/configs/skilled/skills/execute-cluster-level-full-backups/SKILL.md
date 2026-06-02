---
name: execute-cluster-level-full-backups
description: Create full cluster backups in CockroachDB using BACKUP INTO command. Captures all databases, tables, schemas, users, and system metadata in a single consistent snapshot. Use when user asks to "backup the cluster", "create full backup", "backup all databases", "disaster recovery backup", "pre-upgrade backup", or needs complete cluster state for DR or migration.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Execute Cluster-Level Full Backups

Create complete cluster backups that capture all databases, tables, schemas, users, roles, and system metadata in a single consistent snapshot. Cluster-level full backups are the foundation of disaster recovery strategies and enable complete cluster restoration or migration.

## What This Skill Teaches

This skill shows you how to:
- Execute full cluster backups using BACKUP INTO syntax
- Configure backup destinations (nodelocal, S3, GCS, Azure)
- Control backup consistency with AS OF SYSTEM TIME
- Verify backup completion and contents
- Understand what's included vs. excluded in cluster backups
- Apply best practices for production backup operations

**Use this skill when**:
- Creating disaster recovery backups
- Preparing for version upgrades
- Migrating clusters to new infrastructure
- Establishing baseline for incremental backup chains
- Capturing complete cluster state for compliance

## Prerequisites

**Required**:
- BACKUP privilege or admin role
- Write access to backup destination
- Sufficient storage space for full cluster data

**Verify privileges**:
```sql
SHOW GRANTS ON DATABASE system;
```

**Required output**: BACKUP privilege or admin role

## Basic Syntax

### Minimal Cluster Backup

```sql
-- Simplest form (auto-selects timestamp)
BACKUP INTO 'nodelocal://1/backups/cluster';
```

**What this does**:
- Backs up entire cluster (all databases)
- CockroachDB automatically selects consistent timestamp
- Writes to nodelocal storage on node 1
- Creates new full backup (not incremental)

### Recommended Production Syntax

```sql
-- Recommended: explicit timestamp control
BACKUP INTO 'gs://bucket/backups/production'
  AS OF SYSTEM TIME '-10s';
```

**Why this is better**:
- Explicit timestamp avoids active transaction conflicts
- Cloud storage (not nodelocal) for production durability
- 10-second offset provides safety margin from active writes

## Storage Destinations

**Nodelocal** (testing only): `nodelocal://1/backups/test` - single node, not replicated
**S3**: `s3://bucket/path?AWS_ACCESS_KEY_ID=x&AWS_SECRET_ACCESS_KEY=y` or use `implicit_auth`
**GCS**: `gs://bucket/path?AUTH=specified&CREDENTIALS=base64json` or use `implicit_auth`
**Azure**: `azure://container/path?AZURE_ACCOUNT_NAME=x&AZURE_ACCOUNT_KEY=y`

## Step-by-Step: Creating a Full Backup

### Step 1: Verify Cluster Health

**Check cluster status**:
```sql
SELECT node_id, address, is_live
FROM crdb_internal.gossip_liveness
ORDER BY node_id;
```

**Expected**: All nodes show `is_live = true`

**Check for underreplicated ranges**:
```sql
SELECT range_id, start_key, end_key, replicas
FROM crdb_internal.ranges_no_leases
WHERE array_length(replicas, 1) < 3
LIMIT 10;
```

**Expected**: No results (no underreplicated ranges)

### Step 2: Execute Backup Command

**Production cluster backup**:
```sql
BACKUP INTO 'gs://my-backups/production/cluster'
  AS OF SYSTEM TIME '-10s';
```

**Output**:
```
        job_id       |  status   | fraction_completed | ... | rows  | ...
---------------------+-----------+--------------------+-----+-------+----
  987654321001      | succeeded |                  1 | ... | 15243 | ...
```

**Key fields**:
- `job_id`: Reference for tracking backup
- `status`: "succeeded" indicates completion
- `fraction_completed`: Progress (1 = 100%)
- `rows`: Total rows backed up

### Step 3: Verify Backup Completion

**Check job status**:
```sql
SHOW JOB 987654321001;
```

**Expected fields**:
```
job_id           | 987654321001
job_type         | BACKUP
status           | succeeded
description      | BACKUP INTO 'gs://...'
started          | 2026-03-06 10:00:00
finished         | 2026-03-06 10:15:00
fraction_completed | 1
```

**Verify backup exists**:
```sql
SHOW BACKUPS IN 'gs://my-backups/production/cluster';
```

**Output shows available backups**:
```
        path
------------------------
/2026/03/06-100000.00
```

### Step 4: Inspect Backup Contents

**View backup metadata**:
```sql
SHOW BACKUP FROM LATEST IN 'gs://my-backups/production/cluster';
```

**Output includes**:
```
database_name | table_name    | start_time           | end_time             | rows  | ...
--------------+---------------+----------------------+----------------------+-------+----
system        | users         | NULL                 | 2026-03-06 10:00:00  | 12    | ...
mydb          | customers     | NULL                 | 2026-03-06 10:00:00  | 5000  | ...
mydb          | orders        | NULL                 | 2026-03-06 10:00:00  | 10231 | ...
```

**Verify key elements**:
- All databases present (system + user databases)
- Row counts match expectations
- `end_time` matches backup timestamp

## What's Included

**Included**: All user databases, tables, indexes, constraints, sequences, schemas, SQL users/roles, grants, cluster settings, zone configs, multi-region configuration

**Excluded**: Node startup flags, certificates, active transactions, changefeeds (must recreate), metrics

## Monitoring

**Track active backup**:
```sql
SELECT job_id, status, fraction_completed, running_status
FROM crdb_internal.jobs WHERE job_type = 'BACKUP' AND status = 'running';
```

## Troubleshooting

**"Destination already contains full backup"**: Use `BACKUP INTO LATEST IN` for incremental or different destination
**"Timestamp before gc.ttlseconds"**: Use `-10s` instead of older timestamp

## Best Practices

1. **Use cloud storage in production** (S3/GCS/Azure), not nodelocal
2. **Specify `AS OF SYSTEM TIME '-10s'`** for consistent, conflict-free backups
3. **Test restores monthly** to verify RTO and data integrity
4. **Use IAM roles** (implicit auth) instead of hardcoded credentials

## Related Skills

- `understand-backup-chain-structure` - How full and incremental backups relate
- `create-incremental-backups-with-backup-into-latest` - Add incrementals to chain
- `understand-full-backup-scope-and-contents` - What's in a full backup
- `execute-database-level-backups` - Backup individual databases
- `execute-table-level-backups` - Backup individual tables
- `create-backups-with-revision-history-for-pitr` - Enable point-in-time recovery
- `understand-as-of-system-time-in-backups` - Control backup consistency
- `inspect-backup-contents-with-show-backup` - Verify backup contents
- `create-scheduled-backups-for-automation` - Automate backup execution
- `restore-cluster-from-full-backup` - Restore from cluster backup
