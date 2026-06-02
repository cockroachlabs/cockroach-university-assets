---
name: understand-as-of-system-time-in-backups
description: Understand how AS OF SYSTEM TIME controls backup consistency and timestamp selection in CockroachDB. Learn why backups need consistent snapshots, how to choose timestamps within the gc.ttlseconds window, and best practices for avoiding transaction locks. Use when user asks about "backup consistency", "AS OF SYSTEM TIME", "backup timestamp", or "transaction conflicts during backup".
metadata:
  domain: Backup and Restore
  bloom_level: Understand
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Understand AS OF SYSTEM TIME in Backups

Understand the purpose and mechanics of the AS OF SYSTEM TIME clause in backup operations - how it ensures transactional consistency, how to select appropriate timestamps, and how it interacts with garbage collection and active transactions.

## What This Skill Teaches

This skill explains:
- Why backups need a consistent timestamp
- How AS OF SYSTEM TIME guarantees transactional consistency
- The relationship between backup timestamps and gc.ttlseconds
- When to use relative vs. absolute timestamps
- How to avoid transaction locks and conflicts
- What happens when AS OF SYSTEM TIME is omitted

**Use this skill when**:
- Planning backup timing strategies
- Troubleshooting backup timestamp errors
- Understanding backup consistency guarantees
- Designing backup automation
- Resolving "timestamp before gc.ttlseconds" errors

## Core Concepts

### Transactional Consistency

AS OF SYSTEM TIME ensures all backup data reflects a single point in time. Without it, backups may capture partial transaction states (e.g., debit without credit). CockroachDB uses MVCC to maintain row versions tagged with timestamps, enabling consistent snapshots.

## AS OF SYSTEM TIME Syntax

### Basic Syntax

```sql
BACKUP INTO '<destination>'
  AS OF SYSTEM TIME '<timestamp>';
```

**Timestamp formats**:
1. Relative timestamps (recommended)
2. Absolute timestamps
3. Follower reads timestamps
4. Special values

### Relative Timestamps (Recommended)

**Format**: `-<duration>` (e.g., `-10s`, `-5m`, `-1h`)

```sql
BACKUP INTO 'gs://backups/prod' AS OF SYSTEM TIME '-10s';
```

**Units**: `s` (seconds), `m` (minutes), `h` (hours)

Relative timestamps stay within gc.ttlseconds, work in scripts, and avoid timezone issues.

### Absolute Timestamps

```sql
BACKUP INTO 'gs://backups/specific' AS OF SYSTEM TIME '2026-03-06T10:30:00Z';
```

**Formats**: RFC3339 (`2026-03-06T10:30:00Z`), decimal nanoseconds, or date (`2026-03-06`)

Use for coordinating multi-cluster backups or compliance. Must be within gc.ttlseconds window (default 25h).

### Omitting AS OF SYSTEM TIME

```sql
BACKUP INTO 'gs://backups/auto';
```

CockroachDB auto-selects a consistent timestamp (typically ~10s in past). Specify explicitly when coordinating multi-cluster backups or for compliance.

## The gc.ttlseconds Window

**Default**: 25 hours (90000 seconds)

CockroachDB retains MVCC versions within this window. Backup timestamps must fall within `[current_time - gc.ttlseconds, current_time]`.

**Check setting**:
```sql
SHOW CLUSTER SETTING kv.gc.ttl;  -- Output: 25h0m0s
```

**Timestamp too old error**:
```sql
BACKUP INTO 'gs://backups/old' AS OF SYSTEM TIME '-30h';
-- ERROR: cannot specify timestamp older than gc.ttlseconds (25h0m0s)
```

**Solutions**: Use `-10s` (within window) or increase `kv.gc.ttl` (increases storage).

## Avoiding Transaction Conflicts

Backups at current time may conflict with active transactions, causing delays. Use past timestamps (e.g., `-10s`) to read committed versions without locks.

**Adjust offset based on workload**:
- OLTP (fast): `-5s`
- Mixed: `-10s`
- Analytics (long): `-30s` or `-5m`

## Best Practices

1. **Use relative timestamps** (`-10s`) in scripts for automatic gc.ttlseconds compliance
2. **Adjust offset by workload**: OLTP `-5s`, mixed `-10s`, analytics `-30s`
3. **Multi-cluster coordination**: Capture timestamp via `SELECT cluster_logical_timestamp()` and use same value across clusters

## Troubleshooting

### Issue: "Timestamp Before gc.ttlseconds" Error

**Error**: `cannot specify timestamp older than gc.ttlseconds`

**Solution**:
1. Use more recent timestamp: `-10s` instead of `-30h`
2. Or increase gc.ttlseconds: `SET CLUSTER SETTING kv.gc.ttl = '48h'`

### Issue: Backup Hangs or Takes Very Long

**Symptom**: BACKUP job runs for hours without completing

**Solution**:
1. Use older timestamp: `AS OF SYSTEM TIME '-5m'`
2. Schedule backups during low-traffic windows
3. Kill blocking transactions if safe

### Issue: Timezone Confusion with Absolute Timestamps

**Symptom**: Backup captures wrong time period

**Solution**: Always specify timezone or use relative timestamps:
```sql
AS OF SYSTEM TIME '2026-03-06T02:00:00-08:00';  -- Pacific
-- OR
AS OF SYSTEM TIME '-10s';  -- Relative (recommended)
```

## Related Skills

- `understand-mvcc-multi-version-concurrency-control-concepts` - How MVCC enables consistent snapshots
- `execute-cluster-level-full-backups` - Creating backups with AS OF SYSTEM TIME
- `create-backups-with-revision-history-for-pitr` - Using AS OF SYSTEM TIME with PITR
- `restore-from-backup-chains-with-as-of-system-time` - Using AS OF SYSTEM TIME in restores
- `configure-gc-ttlseconds-for-backup-windows` - Adjusting garbage collection window
- `troubleshoot-backup-timestamp-errors` - Resolving AS OF SYSTEM TIME issues
- `understand-transaction-isolation-levels` - How timestamps affect transaction visibility
