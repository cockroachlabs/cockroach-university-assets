---
name: understand-incremental-backup-concepts
description: Explains CockroachDB incremental backups that capture only changed data since the last backup. Use when user asks "what are incremental backups", "how do incrementals work", "backup chains", "reduce backup size", or wants to understand storage-efficient backup strategies.
metadata:
  domain: Backup and Restore
  bloom_level: Understand
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Understand Incremental Backup Concepts

## What This Skill Teaches

Incremental backups capture only the data that changed since the last backup (full or incremental), dramatically reducing storage requirements and backup duration while enabling frequent backups with minimal performance impact.

## How Incremental Backups Work

### The Delta Approach

**Full backup** captures everything:
```
Full Backup: [All 1,000,000 rows] → 100 GB
```

**Incremental backup** captures only changes:
```
Incremental: [5,000 new/modified rows] → 500 MB
```

**Storage savings**: 99.5% reduction in backup size

### Change Detection

CockroachDB tracks changes using MVCC (Multi-Version Concurrency Control):

1. Each row has a timestamp indicating when it was last modified
2. Incremental backup scans for rows newer than the previous backup timestamp
3. Only modified rows are backed up
4. Deleted rows tracked with tombstone records

## Backup Chains

### Chain Structure

A backup chain consists of:
- **One full backup** (the base)
- **Zero or more incrementals** (the deltas)

```
Timeline:
Sunday    Monday      Tuesday     Wednesday
[Full] -> [Incr 1] -> [Incr 2] -> [Incr 3]
100 GB    2 GB        1.5 GB      2.5 GB

Total storage: 106 GB (vs. 400 GB for 4 full backups)
```

### Chain Dependencies

**Critical rule**: All backups in a chain must target the same destination URI.

**Example chain**:
```bash
# Sunday - Create full backup (base)
BACKUP INTO 'nodelocal://1/backups/weekly';

# Monday - Create first incremental
BACKUP INTO LATEST IN 'nodelocal://1/backups/weekly';

# Tuesday - Create second incremental
BACKUP INTO LATEST IN 'nodelocal://1/backups/weekly';
```

All use the same destination: `nodelocal://1/backups/weekly`

### Breaking the Chain

**Chain breaks if**:
- Different destination URI used
- Manual deletion of any backup in chain
- Storage corruption

**When chain breaks**:
- Must create new full backup to start fresh chain
- Cannot restore to points that depended on broken chain

## Storage Efficiency

### Space Savings Example

**Scenario**: 1 TB database, 2% daily change rate

**Without incrementals (daily full backups)**:
```
Day 1: 1 TB full backup
Day 2: 1 TB full backup
Day 3: 1 TB full backup
...
Week total: 7 TB storage
```

**With incrementals (weekly full + daily incrementals)**:
```
Sunday: 1 TB full backup
Monday: 20 GB incremental (2% of 1 TB)
Tuesday: 20 GB incremental
...
Week total: 1.12 TB storage
Savings: 83% less storage
```

### Duration Improvements

Backup duration roughly correlates with data size:

**Full backup**: 1 TB database
- Scan all 1 TB: ~2-4 hours (depends on I/O)

**Incremental backup**: 20 GB changes
- Scan only changed data: ~5-15 minutes

**Frequency benefit**: Can run hourly incrementals with minimal impact

## Restore Complexity

### Restore Process

To restore from incrementals, must apply the entire chain:

```
1. Restore full backup first (base)
   ↓
2. Apply incremental 1 (Monday changes)
   ↓
3. Apply incremental 2 (Tuesday changes)
   ↓
4. Apply incremental 3 (Wednesday changes)
   ↓
5. Data now at Wednesday state
```

**CockroachDB automates this**: `RESTORE FROM LATEST` automatically applies the chain

### Restore Time Trade-off

**More incrementals = Longer restore**:

**Strategy A**: Weekly full + daily incrementals (7 backups)
- Storage: Low
- Restore: Apply 1 full + up to 6 incrementals

**Strategy B**: Daily full backups (7 backups)
- Storage: High
- Restore: Apply 1 full only (faster)

**Recommendation**: Balance between storage cost and restore time based on RTO requirements

## RPO Considerations

### Recovery Point Objective (RPO)

RPO = Maximum acceptable data loss

**Example RPOs**:
- **1 hour RPO**: Run hourly incrementals → Max 1 hour data loss
- **15 minute RPO**: Run incrementals every 15 minutes
- **5 minute RPO**: Run incrementals every 5 minutes

### Incremental Frequency Patterns

**Pattern 1: Hourly Incrementals**
```
Frequency: Every hour
Storage: ~24 incrementals/day
RPO: 1 hour
Use case: Standard production
```

**Pattern 2: 15-Minute Incrementals**
```
Frequency: Every 15 minutes
Storage: ~96 incrementals/day
RPO: 15 minutes
Use case: Critical applications
```

**Pattern 3: Mixed Strategy**
```
Weekly full: Sunday 2 AM
Daily incrementals: 11 PM daily
Hourly incrementals: Every hour
RPO: 1 hour, reasonable storage
```

## Chain Management

### Typical Strategy

**Weekly full + daily incrementals**:
```
Week 1:
  Sunday: Full backup (base)
  Mon-Sat: Daily incrementals

Week 2:
  Sunday: New full backup (new chain)
  Mon-Sat: Daily incrementals
```

**Why start new chain weekly**:
- Limits restore chain length
- Independent recovery points
- Easier retention management

### Retention with Chains

**Keep complete chains**:
```
Keep:
  - Last 4 weekly full backups
  - All incrementals for each week

Delete:
  - Full backups older than 4 weeks
  - All incrementals associated with deleted fulls
```

**Never delete partial chains** - makes remaining incrementals useless

## Performance Impact

### Backup Performance

**Full backup impact**:
- Scans entire cluster
- High I/O during backup window
- May affect query performance
- Typically run during low-traffic hours

**Incremental backup impact**:
- Scans only changed ranges
- Minimal I/O impact
- Can run during business hours
- Negligible performance effect

### Change Rate Matters

**Low change rate** (0.1% daily):
- Incrementals very small
- Huge storage savings
- Perfect for read-heavy workloads

**High change rate** (50% daily):
- Incrementals still beneficial but less dramatic
- Consider more frequent full backups
- Evaluate if incremental strategy worth complexity

## Automatic Chain Detection

### BACKUP INTO LATEST

CockroachDB automatically:
1. Checks destination for existing backups
2. Finds most recent backup (full or incremental)
3. Creates new incremental based on that timestamp
4. Maintains proper chain structure

**No manual tracking needed**:
```sql
-- CockroachDB handles chain automatically
BACKUP INTO LATEST IN 'nodelocal://1/backups/prod';
```

### First Backup in Destination

If destination is empty, `BACKUP INTO LATEST` creates a full backup:

```sql
-- Destination empty → Creates full backup automatically
BACKUP INTO LATEST IN 'nodelocal://1/backups/new-location';
```

## Storage Cost Analysis

### Example Cost Calculation

**Assumptions**:
- 10 TB database
- 3% daily change rate (300 GB/day)
- S3 storage: $0.023/GB/month

**Strategy A: Daily full backups**:
```
7 daily full backups: 70 TB
Monthly storage: 70,000 GB × $0.023 = $1,610/month
```

**Strategy B: Weekly full + daily incrementals**:
```
1 full backup: 10 TB
6 daily incrementals: 1.8 TB
Total per week: 11.8 TB
4 weeks: 47.2 TB
Monthly storage: 47,200 GB × $0.023 = $1,086/month
Savings: $524/month (32%)
```

## Comparison Table

| Aspect | Full Backup | Incremental Backup |
|--------|-------------|-------------------|
| **Size** | 100% of data | 0.1%-10% typically |
| **Duration** | Hours | Minutes |
| **Frequency** | Weekly/Daily | Hourly/15-min |
| **Storage Cost** | High | Low |
| **Restore Speed** | Fast (one step) | Slower (chain) |
| **Restore Complexity** | Simple | Chain required |
| **Independence** | Self-contained | Depends on full |
| **RPO** | Lower frequency = higher RPO | Can achieve very low RPO |

## Trade-offs to Consider

### Storage vs. Restore Time

**More incrementals**:
- ✅ Lower storage costs
- ✅ More frequent RPO
- ❌ Longer restore chains
- ❌ More complex management

**Fewer incrementals**:
- ✅ Faster restore
- ✅ Simpler management
- ❌ Higher storage costs
- ❌ Higher RPO

### Choosing Your Strategy

**Use incrementals when**:
- Storage costs are significant concern
- Need frequent backups (hourly or more)
- Restore time flexibility acceptable
- Change rate is low to moderate (<20%)

**Use full backups when**:
- Fast restore is critical (low RTO)
- Storage cost not primary concern
- Change rate is very high (>50%)
- Simplicity valued over efficiency

## Key Takeaways

1. **Incrementals capture only changes** since last backup
2. **Backup chains** consist of 1 full + N incrementals
3. **Storage savings**: 70-95% typical reduction
4. **Restore trade-off**: Saves storage but requires applying full chain
5. **RPO improvement**: Can backup hourly with minimal impact
6. **Chain integrity**: All backups must use same destination
7. **Automatic management**: `BACKUP INTO LATEST` handles chain tracking

## Next Steps

- Learn **backup chains structure** for multi-backup strategies
- Explore **creating incremental backups** with BACKUP INTO LATEST
- Understand **restore from chains** to recover data
- Plan **backup schedules** balancing storage and RPO

## Related Skills

- `understand-full-backup-scope-and-contents` - Learn about full backups
- `create-incremental-backups-with-backup-into-latest` - Create incrementals
- `execute-cluster-level-full-backups` - Create full backups
