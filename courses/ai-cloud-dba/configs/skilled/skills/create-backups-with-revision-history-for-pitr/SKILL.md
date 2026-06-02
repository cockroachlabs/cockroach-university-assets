---
name: create-backups-with-revision-history-for-pitr
description: Create backups with revision history to enable point-in-time recovery (PITR) in CockroachDB. Captures all MVCC versions between backup start and end times, allowing restore to any timestamp within backup window. Use when user asks to "enable PITR", "backup with revision history", "point-in-time recovery", "backup all versions", or needs ability to restore to arbitrary timestamps.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Create Backups with Revision History for PITR

Create backups that capture all row versions (MVCC revisions) to enable point-in-time recovery to any timestamp within the backup window. This is essential for recovering from logical errors, accidental deletes, or data corruption at precise moments in time.

## What This Skill Teaches

This skill shows you how to:
- Create backups with the `revision_history` option
- Understand what MVCC versions are captured
- Configure gc.ttlseconds for revision history requirements
- Restore to arbitrary timestamps using PITR backups
- Manage storage implications of revision history
- Design PITR backup strategies for different use cases

**Use this skill when**:
- Need to recover from accidental data deletion
- Must restore to precise timestamp after logical error
- Compliance requires auditable version history
- Testing requires exact historical state reconstruction
- Want to undo specific transactions or schema changes

## Prerequisites

**Required**:
- BACKUP privilege on target scope (cluster/database/table)
- Enterprise license (PITR requires enterprise features)
- Sufficient storage for multiple row versions

**Verify enterprise license**:
```sql
SHOW CLUSTER SETTING enterprise.license;
```

**Required**: Valid enterprise license string

**Check gc.ttlseconds**:
```sql
SHOW CLUSTER SETTING kv.gc.ttl;
```

**Default**: 25 hours (90000 seconds)

## Understanding Revision History

### What is Revision History?

**Without revision_history** (standard backup):
- Captures single snapshot at backup timestamp
- Can restore to exact backup timestamp only
- Smaller backup size (one version per row)

**With revision_history** (PITR backup):
- Captures all MVCC versions between start and end time
- Can restore to any timestamp within window
- Larger backup size (multiple versions per row)

### MVCC Version Example

**Row changes**: 10:00 INSERT (bal:1000) → 10:15 UPDATE (bal:900) → 10:30 UPDATE (bal:1200) → 10:45 DELETE

**Standard backup**: Captures only current state (deleted)
**Revision history backup**: Captures all 4 versions

**PITR capability**: Restore to any timestamp (e.g., 10:40 → balance:1200)

## Basic Syntax

### Cluster Backup with Revision History

```sql
-- Cluster-level PITR backup
BACKUP INTO 'gs://backups/pitr/cluster'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;
```

**Components**:
- `revision_history`: Captures all MVCC versions in backup window
- `AS OF SYSTEM TIME '-10s'`: Backup end timestamp
- Backup start: Previous backup timestamp (or beginning of time for first backup)

### Database Backup with Revision History

```sql
-- Database-level PITR backup
BACKUP DATABASE mydb
  INTO 'gs://backups/pitr/mydb'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;
```

### Table Backup with Revision History

```sql
-- Table-level PITR backup
BACKUP TABLE mydb.critical_table
  INTO 'gs://backups/pitr/critical'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;
```

## PITR Backup Chains

**Full backup**:
```sql
BACKUP INTO 'gs://backups/pitr/production'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;
```

**Incremental** (extends PITR window):
```sql
BACKUP INTO LATEST IN 'gs://backups/pitr/production'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;
```

**Important**: All backups in chain must use `WITH revision_history`

**Example chain**: Sun 00:00 (full) → Mon 00:00 (incr) → Tue 00:00 (incr) → Wed 00:00 (incr)
**PITR window**: Can restore to any timestamp from Sun 00:00 to Wed 00:00

## gc.ttlseconds Requirements

**Why it matters**: Garbage collection removes old MVCC versions after gc.ttl (default 25h). Backups must complete within this window.

**Check current value**:
```sql
SHOW CLUSTER SETTING kv.gc.ttl;  -- Default: 25h0m0s
```

**Adjust if needed**:
```sql
-- Cluster-wide
SET CLUSTER SETTING kv.gc.ttl = '48h';

-- Per-table
ALTER TABLE mydb.critical_table
  CONFIGURE ZONE USING gc.ttlseconds = 172800;  -- 48 hours
```

**Sizing formula**: `gc.ttl >= Backup interval + Duration + Margin`
Example: Daily backups (24h) + 2h duration + 2h margin = 28h minimum (recommend 48h)

## Step-by-Step: Creating PITR Backups

**Step 1: Verify prerequisites**:
```sql
SHOW CLUSTER SETTING enterprise.license;  -- Must have enterprise license
SHOW CLUSTER SETTING kv.gc.ttl;          -- Should be ≥ 24-48h for daily backups
```

**Step 2: Create initial full backup**:
```sql
BACKUP INTO 'gs://backups/pitr/cluster'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;
-- Output: job_id | status: succeeded | ...
```

**Step 3: Verify revision history enabled**:
```sql
SHOW BACKUP FROM LATEST IN 'gs://backups/pitr/cluster';
-- Look for: has_revision_history: true
```

**Step 4: Create incrementals** (extends PITR window):
```sql
BACKUP INTO LATEST IN 'gs://backups/pitr/cluster'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;
```

**Step 5: Verify PITR window**:
```sql
SHOW BACKUPS IN 'gs://backups/pitr/cluster';
-- Output shows revision_start_time and revision_end_time for each backup
```

## Restoring from PITR Backups

**Restore cluster to specific timestamp**:
```sql
RESTORE FROM LATEST IN 'gs://backups/pitr/cluster'
  AS OF SYSTEM TIME '2026-03-05 14:30:00';
```

**Restore specific table** (e.g., undo accidental DELETE):
```sql
RESTORE TABLE mydb.orders
  FROM LATEST IN 'gs://backups/pitr/cluster'
  AS OF SYSTEM TIME '2026-03-05 14:34:00';  -- 1 min before incident
```

CockroachDB uses MVCC versions to reconstruct exact state at requested timestamp.

## Storage Implications

**Size impact**: Standard backup = 1 version/row. Revision history = multiple versions (typically 20-50% larger).

**Formula**: `Backup size ≈ Base size × (1 + Change rate × Versions)`
Example: 100 GB base, 10% daily change, 2 versions avg = 120 GB backup

**Monitor size**:
```sql
SELECT job_id, created, pg_size_pretty(bytes_backed_up::BIGINT) AS size
FROM crdb_internal.jobs
WHERE job_type = 'BACKUP' AND description LIKE '%revision_history%'
ORDER BY created DESC LIMIT 10;
```

## Common Patterns

**Pattern 1: Daily full + hourly incrementals**:
```sql
BACKUP INTO LATEST IN 'gs://backups/pitr/daily'
  AS OF SYSTEM TIME '-10s'
  WITH revision_history;  -- 24h PITR window
```

**Pattern 2: Critical tables with extended window** (7 days):
```sql
ALTER TABLE mydb.financial_transactions CONFIGURE ZONE USING gc.ttlseconds = 604800;
BACKUP TABLE mydb.financial_transactions INTO LATEST IN 'gs://backups/pitr/critical'
  AS OF SYSTEM TIME '-10s' WITH revision_history;
```

**Pattern 3: Hybrid strategy** (weekly cluster DR + daily critical table PITR):
```sql
BACKUP INTO 'gs://backups/weekly/cluster' AS OF SYSTEM TIME '-10s';  -- No revision_history
BACKUP TABLE mydb.orders INTO LATEST IN 'gs://backups/pitr/critical'
  AS OF SYSTEM TIME '-10s' WITH revision_history;
```

## Troubleshooting

**Issue: "Revision History Requires Enterprise License"**
Solution: `SET CLUSTER SETTING enterprise.license = '<license-key>';`

**Issue: Cannot restore to desired timestamp**
Check PITR window: `SHOW BACKUPS IN 'gs://backups/pitr/cluster';` and restore within available range.

## Best Practices

1. **Use PITR for critical data**: Financial transactions, customer data, frequently deleted data
2. **Match gc.ttl to backup frequency**: Daily→48h, Hourly→12h, Weekly→7d (add safety margin)
3. **Test PITR restores monthly**: Restore to test environment, validate data, cleanup
4. **Monitor backup size trends**: Alert if size increases >20% unexpectedly
5. **Document PITR windows**: Earliest/latest timestamps, granularity, covered tables, gc.ttl
6. **Ensure chain consistency**: All backups in chain must use `WITH revision_history`

## Use Cases

**Accidental delete recovery**: Restore table to moment before incident
**Schema migration rollback**: Restore database to pre-migration state
**Audit investigation**: Restore historical snapshot for compliance review

## Related Skills

- `understand-mvcc-multi-version-concurrency-control-concepts` - How MVCC versions work
- `execute-cluster-level-full-backups` - Create full backups (foundation for PITR)
- `create-incremental-backups-with-backup-into-latest` - Extend PITR chains
- `understand-backup-chain-structure` - How full + incremental chains work
- `restore-from-backup-chains-with-as-of-system-time` - Restore to specific timestamps
- `configure-gc-ttl-for-pitr-windows` - Adjust garbage collection for PITR
- `implement-point-in-time-recovery` - Complete PITR recovery procedures
- `understand-as-of-system-time-in-backups` - Control backup consistency
- `inspect-backup-contents-with-show-backup` - Verify revision history metadata
- `validate-backup-data-integrity-with-verifybackuptabledata` - Test PITR backup integrity
