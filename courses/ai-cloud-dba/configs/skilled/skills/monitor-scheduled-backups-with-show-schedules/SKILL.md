---
name: monitor-scheduled-backups-with-show-schedules
description: Monitor and inspect backup schedules using SHOW SCHEDULES command. Use when user asks "show schedules", "list backup schedules", "check schedule status", "monitor backups", or needs operational oversight of automated backups.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Monitor Scheduled Backups with SHOW SCHEDULES

Monitor backup schedule health and status using SHOW SCHEDULES for operational oversight.

## Basic Usage

```sql
-- List all schedules
SHOW SCHEDULES;

-- List only backup schedules
SHOW SCHEDULES FOR BACKUP;
```

## Output Columns

**Key columns**:
- `id` - Schedule ID (for PAUSE/RESUME/DROP)
- `label` - Descriptive name
- `schedule_status` - ACTIVE or PAUSED
- `next_run` - Next scheduled execution time
- `state` - Current state
- `recurrence` - CRON expression
- `jobsrunning` - 0 (idle) or 1 (executing)
- `owner` - User who created schedule

## Common Queries

### Check All Backup Schedules

```sql
SHOW SCHEDULES FOR BACKUP;
```

### Find Specific Schedule

```sql
-- By label
SELECT * FROM [SHOW SCHEDULES]
WHERE label LIKE '%prod%';

-- By ID
SELECT * FROM [SHOW SCHEDULES]
WHERE id = 123;
```

### Check Schedule Status

```sql
-- Active schedules
SELECT id, label, next_run
FROM [SHOW SCHEDULES]
WHERE schedule_status = 'ACTIVE'
ORDER BY next_run;

-- Paused schedules (need attention)
SELECT id, label, schedule_status
FROM [SHOW SCHEDULES]
WHERE schedule_status = 'PAUSED';
```

### Currently Running Backups

```sql
SELECT id, label, jobsrunning
FROM [SHOW SCHEDULES]
WHERE jobsrunning = 1;
```

## Monitoring Patterns

### Pattern 1: Daily Health Check

```sql
-- Verify all prod schedules active
SELECT label, schedule_status, next_run
FROM [SHOW SCHEDULES]
WHERE label LIKE '%prod%'
ORDER BY next_run;
```

**Look for**:
- All status = 'ACTIVE'
- next_run times reasonable
- No unexpected PAUSED schedules

### Pattern 2: Next Backup Times

```sql
-- When will backups run next?
SELECT label, next_run
FROM [SHOW SCHEDULES]
WHERE schedule_status = 'ACTIVE'
ORDER BY next_run
LIMIT 10;
```

### Pattern 3: Backup Job History

```sql
-- Recent backup jobs from schedules
SELECT job_id, status, created, description
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND description LIKE '%BACKUP SCHEDULE%'
ORDER BY created DESC
LIMIT 20;
```

## Verifying Schedule Health

### Checklist

```sql
-- 1. Schedule exists and active
SELECT id, label, schedule_status
FROM [SHOW SCHEDULES]
WHERE label = 'Prod Hourly';
-- Expect: schedule_status = 'ACTIVE'

-- 2. Next run scheduled
SELECT next_run FROM [SHOW SCHEDULES]
WHERE label = 'Prod Hourly';
-- Expect: timestamp in near future

-- 3. Recent jobs succeeded
SELECT status, created
FROM [SHOW JOBS]
WHERE description LIKE '%Prod Hourly%'
ORDER BY created DESC
LIMIT 5;
-- Expect: status = 'succeeded'
```

## Combining with Job Monitoring

### Full Backup Pipeline Status

```sql
-- Schedule status
SELECT id, label, schedule_status, next_run
FROM [SHOW SCHEDULES]
WHERE label = 'Prod Hourly';

-- Recent backup jobs
SELECT job_id, status, fraction_completed, created
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND description LIKE '%Prod Hourly%'
ORDER BY created DESC
LIMIT 10;
```

## Alerting Queries

### Paused Schedules

```sql
-- Alert if production schedules paused
SELECT id, label, schedule_status
FROM [SHOW SCHEDULES]
WHERE label LIKE '%prod%'
  AND schedule_status = 'PAUSED';
```

### Failed Recent Backups

```sql
-- Alert if recent backups failed
SELECT job_id, status, error
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND status = 'failed'
  AND created > now() - INTERVAL '24 hours'
ORDER BY created DESC;
```

### Schedules Not Running

```sql
-- Alert if no backup in last 25 hours (for hourly schedule)
SELECT label
FROM [SHOW SCHEDULES] s
WHERE label LIKE '%hourly%'
  AND schedule_status = 'ACTIVE'
  AND NOT EXISTS (
    SELECT 1 FROM [SHOW JOBS] j
    WHERE j.job_type = 'BACKUP'
      AND j.description LIKE '%' || s.label || '%'
      AND j.created > now() - INTERVAL '25 hours'
  );
```

## Troubleshooting

### Schedule Shows PAUSED

**Check why**:
```sql
-- Was it manually paused?
SELECT label, state FROM [SHOW SCHEDULES]
WHERE schedule_status = 'PAUSED';
```

**Resume**:
```sql
RESUME SCHEDULES <id>;
```

### No Recent Backup Jobs

**Possible causes**:
1. Schedule recently created (wait for first_run)
2. Schedule paused
3. CRON expression wrong (next_run far in future)

**Verify**:
```sql
SELECT label, next_run, recurrence
FROM [SHOW SCHEDULES]
WHERE label = 'Missing Backups';
```

### Jobs Running But Failing

```sql
SELECT job_id, status, error
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND status IN ('failed', 'canceled')
ORDER BY created DESC
LIMIT 10;
```

## Best Practices

1. **Check SHOW SCHEDULES daily** for paused schedules
2. **Monitor next_run times** to catch incorrect CRON expressions
3. **Alert on PAUSED status** for production schedules
4. **Track job success rate** from SHOW JOBS
5. **Document expected schedules** in runbook
6. **Set up automated monitoring** with queries above

## Automation Example

```bash
#!/bin/bash
# Daily schedule health check

cockroach sql --host=localhost:26258 --execute="
  SELECT label, schedule_status, next_run
  FROM [SHOW SCHEDULES]
  WHERE label LIKE '%prod%'
    AND schedule_status != 'ACTIVE';
" | mail -s "Paused Backup Schedules Alert" ops@example.com
```

## Related Skills

- `create-automated-backup-schedules` - Create schedules to monitor
- `manage-backup-schedule-lifecycle` - Pause/resume/drop schedules
- `modify-backup-schedule-frequency` - Change schedule timing
