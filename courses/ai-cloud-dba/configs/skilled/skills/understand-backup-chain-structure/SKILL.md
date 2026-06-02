---
name: understand-backup-chain-structure
description: Understand how backup chains work in CockroachDB - the relationship between full backups and incremental backups, how chains enable point-in-time recovery, and strategies for managing chain length. Use when user asks about "backup chains", "full and incremental backups", "backup strategy", or "how incremental backups work".
metadata:
  domain: Backup and Restore
  bloom_level: Understand
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Understand Backup Chain Structure

Understand the architecture and mechanics of backup chains in CockroachDB - how full and incremental backups relate, how chains enable efficient storage and point-in-time recovery, and strategies for managing chain length and performance.

## What This Skill Teaches

This skill explains:
- What constitutes a backup chain (full + incrementals)
- How incremental backups build on full backups
- How chains enable point-in-time recovery (PITR)
- Why restore time increases with chain length
- When to start a new chain vs. continuing existing chain
- Trade-offs between backup frequency and restore time

**Use this skill when**:
- Planning backup strategies
- Explaining backup storage patterns
- Troubleshooting slow restores
- Designing retention policies
- Understanding why a new full backup is needed

## Core Concepts

### Backup Chain Definition

A **backup chain** consists of:

1. **One full backup** (base)
   - Complete snapshot of all data at a point in time
   - Independent and self-contained
   - Can be restored without other backups
   - Largest storage size

2. **Zero or more incremental backups** (deltas)
   - Captures only changes since previous backup in chain
   - Depends on full backup and all prior incrementals
   - Cannot be restored independently
   - Smaller storage size (only changed data)

**Critical requirement**: All backups in a chain must use the **same destination URI**.

### Chain Structure Example

```
Backup Chain at 'nodelocal://1/backups/production':

[Full Backup]           ← Base (Sunday 00:00)
     ↓
[Incremental 1]         ← Delta (Monday 00:00)
     ↓
[Incremental 2]         ← Delta (Tuesday 00:00)
     ↓
[Incremental 3]         ← Delta (Wednesday 00:00)
     ↓
[Incremental 4]         ← Delta (Thursday 00:00)
```

**Total chain length**: 5 backups (1 full + 4 incrementals)

### How Chains Are Created

**Create full backup** (starts new chain):
```sql
-- First backup to this destination
BACKUP INTO 'nodelocal://1/backups/weekly'
  AS OF SYSTEM TIME '-10s';
```

**Create incremental backup** (extends chain):
```sql
-- Subsequent backup to same destination
BACKUP INTO LATEST IN 'nodelocal://1/backups/weekly'
  AS OF SYSTEM TIME '-10s';
```

The `LATEST` keyword tells CockroachDB to:
1. Find the most recent backup in the chain
2. Calculate changes since that backup
3. Append new incremental to the chain

### Destination URI Importance

**All backups in chain must share exact destination**:

```sql
-- Chain A (valid)
BACKUP INTO 'nodelocal://1/backups/prod';               -- Full
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod';     -- Incremental (same URI)

-- Chain B (broken - different URIs)
BACKUP INTO 'nodelocal://1/backups/prod';               -- Full
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod2';    -- ERROR: different URI
```

**Result**: Each unique URI creates a separate chain.

## Point-in-Time Recovery with Chains

### How PITR Works

Backup chains enable restoring to **any timestamp** within the chain's time range:

```
Chain Timeline:

Full Backup:        Sun 2026-03-02 00:00:00  ──────┐
Incremental 1:      Mon 2026-03-03 00:00:00        │ Time range for PITR
Incremental 2:      Tue 2026-03-04 00:00:00        │ (Can restore to any
Incremental 3:      Wed 2026-03-05 00:00:00        │  timestamp in range)
Incremental 4:      Thu 2026-03-06 00:00:00  ──────┘
```

**Restore to specific timestamp**:
```sql
-- Restore to Tuesday afternoon (between Incremental 2 and 3)
RESTORE FROM LATEST IN 'nodelocal://1/backups/weekly'
  AS OF SYSTEM TIME '2026-03-04 14:30:00';
```

**What happens during restore**:
1. CockroachDB finds the full backup
2. Applies Incremental 1 (changes through Monday)
3. Applies Incremental 2 (changes through Tuesday)
4. Stops at requested timestamp (Tuesday 14:30)
5. Result: Database state as of Tuesday 14:30

### PITR Requirements

**Standard backups** (without revision_history):
- Can restore to any **backup timestamp** in chain
- Cannot restore to arbitrary time between backups

**Backups with revision_history**:
- Can restore to **any timestamp** within chain range
- Requires all backups in chain use `WITH revision_history`

```sql
-- Enable PITR for entire chain
BACKUP INTO 'nodelocal://1/backups/pitr'
  WITH revision_history;

BACKUP INTO LATEST IN 'nodelocal://1/backups/pitr'
  WITH revision_history;
```

## Restore Process and Chain Traversal

### How Restore Traverses Chains

When restoring from a chain, CockroachDB:

1. **Locates full backup** (base of chain)
2. **Identifies all incrementals** in chronological order
3. **Applies changes sequentially**:
   - Full backup data (complete snapshot)
   - + Incremental 1 changes
   - + Incremental 2 changes
   - + Incremental 3 changes
   - ... until target timestamp reached

**Performance impact**: Longer chains = more incrementals to apply = longer restore time

### Restore Time Example

```
Chain with 4 incrementals:
- Full backup restore:      30 minutes
- Incremental 1 apply:       5 minutes
- Incremental 2 apply:       5 minutes
- Incremental 3 apply:       5 minutes
- Incremental 4 apply:       5 minutes
- Total restore time:       50 minutes

Chain with 20 incrementals:
- Full backup restore:      30 minutes
- 20 incrementals apply:   100 minutes (5 min each)
- Total restore time:      130 minutes
```

**Key insight**: Each incremental adds to total restore time.

## Chain Management Strategies

### When to Start New Chain

**Start new full backup chain when**:

1. **Chain becomes too long**
   - Rule of thumb: 7-30 incrementals maximum
   - Longer chains increase restore time significantly

2. **Scheduled full backup cycle**
   - Weekly full + daily incrementals (common pattern)
   - Monthly full + daily incrementals (longer retention)

3. **Breaking changes occur**
   - Missing incremental in sequence
   - Destination URI needs to change
   - Storage migration required

4. **Performance degradation**
   - Restores taking too long
   - Incremental backups growing larger

### Typical Backup Strategies

**Strategy 1: Weekly Full + Daily Incrementals**
```
Week 1:
  Sunday:     Full backup (new chain)
  Monday:     Incremental 1
  Tuesday:    Incremental 2
  Wednesday:  Incremental 3
  Thursday:   Incremental 4
  Friday:     Incremental 5
  Saturday:   Incremental 6

Week 2:
  Sunday:     Full backup (new chain)  ← Restart chain
  ...
```

**Chain length**: Maximum 7 backups (1 full + 6 incrementals)
**Restore time**: Moderate (up to 7 backups to apply)

**Strategy 2: Monthly Full + Daily Incrementals**
```
Month 1:
  Day 1:      Full backup (new chain)
  Day 2-30:   Incrementals 1-29

Month 2:
  Day 1:      Full backup (new chain)  ← Restart chain
  ...
```

**Chain length**: Maximum 30 backups (1 full + 29 incrementals)
**Restore time**: Longer (up to 30 backups to apply)
**Storage savings**: Better (fewer full backups stored)

**Strategy 3: Daily Full (No Incrementals)**
```
Day 1:      Full backup (chain of 1)
Day 2:      Full backup (chain of 1)
Day 3:      Full backup (chain of 1)
...
```

**Chain length**: Always 1 backup
**Restore time**: Fastest (no incrementals to apply)
**Storage cost**: Highest (every backup is full)

### Chain Length Trade-offs

| Chain Length | Restore Time | Storage Cost | Backup Time |
|--------------|--------------|--------------|-------------|
| Short (1-7)  | Fastest      | Highest      | Longer      |
| Medium (7-14)| Moderate     | Moderate     | Moderate    |
| Long (30+)   | Slowest      | Lowest       | Faster      |

**Choose based on**:
- Recovery Time Objective (RTO): Faster restore = shorter chains
- Storage budget: Lower cost = longer chains
- Backup window: Shorter window = prefer incrementals

## Breaking the Chain

### What Breaks a Chain

A chain is **broken** (must start new full backup) when:

1. **Missing incremental in sequence**
   ```
   Full backup         ← OK
   Incremental 1       ← OK
   [Incremental 2 deleted or missing]  ← BROKEN
   Incremental 3       ← Cannot apply (depends on Incremental 2)
   ```

2. **Changing destination URI**
   ```sql
   BACKUP INTO 'nodelocal://1/backups/prod';               -- Chain A
   BACKUP INTO LATEST IN 'nodelocal://2/backups/prod';     -- Chain B (different URI)
   ```

3. **Garbage collection removing base**
   - Full backup deleted while incrementals remain
   - Incrementals cannot be restored without full backup

### Recovery from Broken Chain

**If chain is broken, you must**:
1. Create new full backup to new or same destination
2. Abandon broken chain or restore before deletion
3. Resume incremental backups from new full backup

```sql
-- Chain is broken (Incremental 2 missing)
-- Solution: Start new chain

BACKUP INTO 'nodelocal://1/backups/prod-new'
  AS OF SYSTEM TIME '-10s';  -- New full backup

-- Future incrementals use new chain
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod-new'
  AS OF SYSTEM TIME '-10s';
```

## Monitoring Chain Health

### Check Chain Structure

**View backups in chain**:
```sql
SHOW BACKUPS IN 'nodelocal://1/backups/weekly';
```

**Output example**:
```
        path
--------------------------------
/2026/03/02-000000.00           -- Full backup
/2026/03/03-120000.00           -- Incremental 1
/2026/03/04-120000.00           -- Incremental 2
/2026/03/05-120000.00           -- Incremental 3
```

**Verify chain integrity**:
```sql
SHOW BACKUP FROM LATEST IN 'nodelocal://1/backups/weekly';
```

**Look for**:
- Sequential timestamps (no gaps)
- Full backup at chain start
- All incrementals reference same full backup

### Chain Length Monitoring

**Query backup job history**:
```sql
SELECT
  job_id,
  job_type,
  description,
  started,
  finished
FROM crdb_internal.jobs
WHERE job_type = 'BACKUP'
  AND description LIKE '%nodelocal://1/backups/weekly%'
ORDER BY started DESC;
```

**Calculate chain length**:
- Count backups between full backups
- Alert when threshold exceeded (e.g., > 14 incrementals)

## Best Practices

### 1. Plan Chain Length Based on RTO

**Fast RTO (< 1 hour)**:
- Short chains: 7 incrementals maximum
- Weekly or bi-weekly full backups
- Consider daily full backups for critical systems

**Moderate RTO (1-4 hours)**:
- Medium chains: 14 incrementals maximum
- Weekly full backups
- Daily incrementals

**Flexible RTO (> 4 hours)**:
- Longer chains: 30 incrementals maximum
- Monthly full backups
- Daily or more frequent incrementals

### 2. Test Restore Times

**Periodically measure**:
```sql
-- Restore from latest in chain to test environment
RESTORE FROM LATEST IN 'nodelocal://1/backups/weekly'
  AS OF SYSTEM TIME LATEST;
```

**Record metrics**:
- Time to complete restore
- Number of backups in chain
- Total data size restored

**Adjust strategy if**:
- Restore time exceeds RTO
- Chain length grows unexpectedly
- Incremental sizes increase significantly

### 3. Automate Chain Rotation

**Use scheduled backups**:
```sql
-- Weekly full backup (starts new chain)
CREATE SCHEDULE weekly_full
  FOR BACKUP INTO 'nodelocal://1/backups/scheduled'
  RECURRING '@weekly'
  FULL BACKUP ALWAYS;

-- Daily incremental backup (extends chain)
CREATE SCHEDULE daily_incremental
  FOR BACKUP INTO 'nodelocal://1/backups/scheduled'
  RECURRING '@daily'
  FULL BACKUP '@weekly';  -- New full weekly, otherwise incremental
```

### 4. Document Chain Strategy

**Document**:
- Full backup frequency (weekly/monthly)
- Incremental frequency (daily/hourly)
- Maximum chain length before rotation
- Expected restore time for each strategy
- Storage retention policy

### 5. Monitor Chain Integrity

**Regular checks**:
- Verify no missing incrementals
- Confirm full backup exists at chain base
- Test restore from latest backup monthly
- Alert on backup job failures immediately

## Common Patterns

### Pattern 1: Production Weekly Rotation
```sql
-- Sunday: Full backup
BACKUP INTO 'nodelocal://1/backups/prod'
  AS OF SYSTEM TIME '-10s';

-- Monday-Saturday: Incrementals
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod'
  AS OF SYSTEM TIME '-10s';
```

### Pattern 2: High-Frequency Incrementals
```sql
-- Once: Full backup, then every 4 hours: Incremental
BACKUP INTO LATEST IN 'nodelocal://1/backups/frequent'
  AS OF SYSTEM TIME '-10s';
```

### Pattern 3: Separate Chains for Retention
```sql
-- Weekly chain (7 day retention)
BACKUP INTO 'gs://bucket/backups/weekly'
  AS OF SYSTEM TIME '-10s';

-- Monthly chain (365 day retention)
BACKUP INTO 'gs://bucket/backups/monthly'
  AS OF SYSTEM TIME '-10s';
```

## Troubleshooting

### Issue: Restore Takes Too Long

**Symptom**: Restore from latest backup exceeds RTO

**Solution**:
1. Start new full backup to reset chain
2. Reduce time between full backups
3. Consider daily full backups for critical systems

### Issue: Missing Incremental in Chain

**Symptom**: Cannot restore from latest, gap in backup sequence

**Solution**:
1. Restore from most recent complete chain
2. Create new full backup immediately
3. Investigate why backup job failed (check logs)

## Related Skills

- `create-incremental-backups-with-backup-into-latest` - Creating incrementals that extend chains
- `understand-full-backup-scope-and-contents` - What's in the full backup (base of chain)
- `execute-cluster-level-full-backups` - Creating full backups that start chains
- `restore-from-backup-chains-with-as-of-system-time` - Using chains for point-in-time recovery
- `create-scheduled-backups-for-automation` - Automating chain rotation with schedules
- `configure-backup-retention-policies` - Managing chain lifecycle and deletion
- `inspect-backup-contents-with-show-backup` - Examining chain structure and integrity
