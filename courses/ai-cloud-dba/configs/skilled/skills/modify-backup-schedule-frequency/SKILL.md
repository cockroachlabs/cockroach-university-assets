---
name: modify-backup-schedule-frequency
description: Modify existing backup schedule frequencies using ALTER BACKUP SCHEDULE. Change full backup intervals with SET FULL BACKUP or incremental intervals with SET RECURRING. Supports CRON expressions and shortcuts. Find schedule IDs with SHOW SCHEDULES. Use when adjusting RPO requirements, backup windows, or cost optimization.
metadata:
  domain: Backup and Restore
  tags: backup-restore, sql, performance, schedules
  phase: 1
  version: 1.1.0
  bloomsLevel: Apply
  minimumVersion: v26.1.0
  status: complete
---

# Modify Backup Schedule Frequency

## Overview

CockroachDB allows you to modify existing backup schedules without recreating them using `ALTER BACKUP SCHEDULE`. Changes take effect at the next scheduled run without disrupting backup chains.

**Key capabilities:**
- Modify full backup frequency with `SET FULL BACKUP`
- Modify incremental frequency with `SET RECURRING`
- Use CRON expressions or shortcuts (`@hourly`, `@daily`, `@weekly`)
- Changes apply immediately to schedule metadata, execute at next run

**Common use cases:** RPO adjustments, cost optimization, maintenance window alignment, seasonal workload changes

## Finding Schedule Information

```sql
-- Show all backup schedules
SHOW SCHEDULES;

-- Show specific schedule details
SHOW SCHEDULE 123456789;

-- Filter by label
SELECT * FROM [SHOW SCHEDULES] WHERE label LIKE '%production%';
```

**Key output columns:** `id` (schedule ID), `label`, `schedule_status`, `next_run`, `recurrence` (CRON expression)

**Note:** Each `CREATE SCHEDULE FOR BACKUP` creates two schedules - one for full backups, one for incrementals.

## Modifying Backup Frequencies

### ALTER BACKUP SCHEDULE Syntax

```sql
ALTER BACKUP SCHEDULE <schedule_id>
  SET FULL BACKUP '<cron_expression>'
  [SET RECURRING '<cron_expression>']
  [SET SCHEDULE OPTION <option> = <value>];
```

### Modify Full Backup Frequency

**Change from weekly to daily:**
```sql
-- Find the full backup schedule ID
SELECT * FROM [SHOW SCHEDULES] WHERE label LIKE '%full%';

-- Modify to daily at 2 AM
ALTER BACKUP SCHEDULE 789012345
  SET FULL BACKUP '@daily';
```

**Change to specific time:**
```sql
-- Run full backups every Sunday at 3 AM
ALTER BACKUP SCHEDULE 789012345
  SET FULL BACKUP '0 3 * * 0';
```

### Modify Incremental Backup Frequency

**Change from hourly to every 4 hours:**
```sql
-- Find the incremental schedule ID
SELECT * FROM [SHOW SCHEDULES] WHERE label LIKE '%incremental%';

-- Modify to every 4 hours
ALTER BACKUP SCHEDULE 123456789
  SET RECURRING '0 */4 * * *';
```

**Change from daily to hourly:**
```sql
-- Hourly backups at minute 0
ALTER BACKUP SCHEDULE 123456789
  SET RECURRING '@hourly';
```

### Modify Both Frequencies Together

```sql
-- Modify related full and incremental schedules
ALTER BACKUP SCHEDULE 789012345  -- Full backup schedule
  SET FULL BACKUP '@weekly';

ALTER BACKUP SCHEDULE 123456789  -- Incremental schedule
  SET RECURRING '@daily';
```

## CRON Expression Reference

### CRON Syntax

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of week (0 - 6, Sunday = 0)
│ │ │ │ │
* * * * *
```

### Common Shortcuts

| Shortcut | CRON Expression | Description |
|----------|----------------|-------------|
| `@hourly` | `0 * * * *` | Every hour at minute 0 |
| `@daily` | `0 0 * * *` | Daily at midnight |
| `@weekly` | `0 0 * * 0` | Weekly on Sunday at midnight |
| `@monthly` | `0 0 1 * *` | Monthly on the 1st at midnight |

### Common CRON Patterns

```sql
-- Every N hours
'0 */2 * * *'     -- Every 2 hours
'0 */6 * * *'     -- Every 6 hours

-- Specific times
'0 2 * * *'       -- Daily at 2 AM
'0 3 * * 0'       -- Weekly on Sunday at 3 AM
'0 6,18 * * *'    -- Twice daily (6 AM and 6 PM)
```

## Common Modification Scenarios

### Reduce RPO (Lower RTO)

```sql
-- Change from daily to every 4 hours
ALTER BACKUP SCHEDULE 123456789
  SET RECURRING '0 */4 * * *';
```

### Align with Maintenance Windows

```sql
-- Move full backups to Sunday 3 AM
ALTER BACKUP SCHEDULE 789012345
  SET FULL BACKUP '0 3 * * 0';
```

### Cost Optimization

```sql
-- Reduce from hourly to every 6 hours
ALTER BACKUP SCHEDULE 123456789
  SET RECURRING '0 */6 * * *';
```

### Seasonal Workload Adjustment

```sql
-- Peak season: hourly
ALTER BACKUP SCHEDULE 123456789 SET RECURRING '@hourly';

-- Off-peak: every 6 hours
ALTER BACKUP SCHEDULE 123456789 SET RECURRING '0 */6 * * *';
```

## Advanced Modifications

### Stagger Multiple Schedules

```sql
-- Prevent resource contention by staggering start times
ALTER BACKUP SCHEDULE 111111111 SET RECURRING '0 * * * *';   -- :00
ALTER BACKUP SCHEDULE 222222222 SET RECURRING '15 * * * *';  -- :15
ALTER BACKUP SCHEDULE 333333333 SET RECURRING '30 * * * *';  -- :30
```

## Impact and Timing

**When changes take effect:**
- Schedule metadata updates instantly
- `next_run` recalculates immediately
- Actual frequency changes at next scheduled run
- Running backups complete normally

**Backup chain continuity:**
- Incremental backups continue from last full
- No chain breaks or data loss
- All backups remain restorable

## Verification

```sql
-- Verify schedule modification
SHOW SCHEDULE 123456789;
-- Check: recurrence, next_run, schedule_status = 'ACTIVE'

-- Monitor next execution
SHOW JOBS
WHERE job_type = 'BACKUP'
  AND created > now() - INTERVAL '1 hour'
ORDER BY created DESC;

-- Verify backup completed
SHOW BACKUP FROM 's3://bucket/path?AUTH=implicit';
```

## Best Practices

**Before modifying:**
1. Review current schedules and document state
2. Calculate resource impact (frequency vs I/O and storage)
3. Test CRON expressions (use online validators)
4. Note timezone (CockroachDB uses UTC)

**Modification workflow:**
1. Identify schedule: `SELECT * FROM [SHOW SCHEDULES] WHERE label LIKE '%production%';`
2. Apply modification: `ALTER BACKUP SCHEDULE <id> SET ...`
3. Verify immediately: `SHOW SCHEDULE <id>;`
4. Monitor first execution

**Coordinating changes:**
- Modify full and incremental schedules together
- Maintain logical frequency ratios (incrementals > full)
- Stagger times to avoid conflicts

## Troubleshooting

**Schedule not updating:**
- Verify correct schedule ID with `SHOW SCHEDULES`
- Check CRON syntax validity (minutes 0-59, hours 0-23)
- Try pause/resume if needed

**Invalid CRON expression:**
```sql
-- Wrong: '60 * * * *' (minutes must be 0-59)
-- Right: '0 * * * *'
```

**Timezone issues:**
- CockroachDB uses UTC by default
- Convert local times: 2 AM PST = 10 AM UTC = `'0 10 * * *'`

**Modified wrong schedule:**
- Verify schedule type (full vs incremental)
- Each `CREATE SCHEDULE FOR BACKUP` creates two schedules


## Summary

Modifying backup schedule frequencies allows you to:

1. **Adjust to changing requirements** - Adapt RPO targets dynamically
2. **Optimize costs** - Balance frequency with storage expenses
3. **Align with operations** - Match maintenance windows and workload patterns
4. **Maintain continuity** - No disruption to existing backup chains
5. **Fine-tune performance** - Stagger schedules to avoid resource contention

**Key commands:**
```sql
-- View schedules
SHOW SCHEDULES;

-- Modify full backup frequency
ALTER BACKUP SCHEDULE <id> SET FULL BACKUP '<cron>';

-- Modify incremental frequency
ALTER BACKUP SCHEDULE <id> SET RECURRING '<cron>';

-- Verify changes
SHOW SCHEDULE <id>;
```

**Remember:**
- Changes apply at next scheduled run
- Use correct schedule ID (full vs incremental)
- Test CRON expressions before applying
- Monitor first execution after modification
- Document changes for audit trail
