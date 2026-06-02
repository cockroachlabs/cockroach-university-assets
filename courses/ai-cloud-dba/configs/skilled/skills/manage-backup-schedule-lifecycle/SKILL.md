---
name: manage-backup-schedule-lifecycle
description: Manage backup schedule lifecycle with PAUSE, RESUME, and DROP SCHEDULES commands. Use when user asks to "pause backups", "stop schedule", "resume backups", "delete schedule", or needs to manage automated backup schedules for maintenance or decommissioning.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Manage Backup Schedule Lifecycle

Control backup schedule lifecycle with PAUSE, RESUME, and DROP commands for maintenance and operations.

## Schedule Lifecycle

**Create** → **ACTIVE** → **PAUSE** → **RESUME** → **DROP**

## PAUSE SCHEDULES

**Purpose**: Temporarily stop backups without deleting schedule

```sql
-- Pause by ID
PAUSE SCHEDULES 123;

-- Pause multiple schedules
PAUSE SCHEDULES 123, 456, 789;

-- Pause by query
PAUSE SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%dev%'
);
```

### When to Pause

- Cluster maintenance windows
- Storage system maintenance
- Cost optimization (temporarily disable dev backups)
- Investigating backup failures
- Before cluster upgrade

### What Happens

**Immediate**:
- schedule_status changes to PAUSED
- No new backup jobs scheduled
- Currently running backup continues

**Ongoing**:
- Schedule remains in system
- Can be resumed anytime
- Configuration preserved

## RESUME SCHEDULES

**Purpose**: Restart paused schedules

```sql
-- Resume by ID
RESUME SCHEDULES 123;

-- Resume multiple
RESUME SCHEDULES 123, 456;

-- Resume all paused dev schedules
RESUME SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%dev%'
    AND schedule_status = 'PAUSED'
);
```

### After Resume

- schedule_status returns to ACTIVE
- next_run calculated based on CRON
- Backups resume normally

## DROP SCHEDULES

**Purpose**: Permanently remove schedule

```sql
-- Drop by ID
DROP SCHEDULES 123;

-- Drop multiple
DROP SCHEDULES 123, 456, 789;

-- Drop old schedules
DROP SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%old%'
);
```

**⚠️ Warning**: 
- Cannot be undone
- Must recreate schedule if needed
- Does NOT delete existing backups (backups remain in storage)

## Common Patterns

### Pattern 1: Maintenance Window

```sql
-- Before maintenance
PAUSE SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%prod%'
);

-- Perform maintenance
-- ...

-- After maintenance
RESUME SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%prod%'
    AND schedule_status = 'PAUSED'
);
```

### Pattern 2: Pause Dev During Business Hours

```sql
-- Morning: Pause dev backups (save resources)
PAUSE SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%dev%'
);

-- Evening: Resume dev backups
RESUME SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%dev%'
);
```

### Pattern 3: Replace Schedule

```sql
-- Drop old schedule
DROP SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label = 'Old Daily Backup'
);

-- Create new schedule
CREATE SCHEDULE new_hourly_backup
  FOR BACKUP INTO 'nodelocal://1/backups/new'
  RECURRING '@hourly'
  WITH SCHEDULE OPTIONS label = 'New Hourly Backup';
```

## Verify Operations

### After PAUSE

```sql
SELECT id, label, schedule_status
FROM [SHOW SCHEDULES]
WHERE id = 123;
-- Expect: schedule_status = 'PAUSED'
```

### After RESUME

```sql
SELECT id, label, schedule_status, next_run
FROM [SHOW SCHEDULES]
WHERE id = 123;
-- Expect: schedule_status = 'ACTIVE', next_run populated
```

### After DROP

```sql
SELECT * FROM [SHOW SCHEDULES] WHERE id = 123;
-- Expect: No rows (schedule deleted)
```

## Operational Workflows

### Planned Maintenance

```bash
#!/bin/bash
# Pause backups for maintenance

# 1. List current schedules
echo "Current schedules:"
cockroach sql --execute="SHOW SCHEDULES;"

# 2. Pause all backup schedules
echo "Pausing all backup schedules..."
cockroach sql --execute="
  PAUSE SCHEDULES (SELECT id FROM [SHOW SCHEDULES]);
"

# 3. Perform maintenance
echo "Maintenance window - backups paused"

# 4. Resume after maintenance
echo "Resuming backup schedules..."
cockroach sql --execute="
  RESUME SCHEDULES (
    SELECT id FROM [SHOW SCHEDULES]
    WHERE schedule_status = 'PAUSED'
  );
"

echo "Backups resumed"
```

### Cost Optimization

```sql
-- Weekday: Pause non-critical backups
PAUSE SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%dev%' OR label LIKE '%test%'
);

-- Weekend: Resume all backups
RESUME SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE schedule_status = 'PAUSED'
);
```

## Troubleshooting

### Cannot Resume Schedule

**Check schedule exists**:
```sql
SHOW SCHEDULES WHERE id = 123;
```

**If deleted**: Must recreate schedule

### Schedule Won't Pause

**Check if already paused**:
```sql
SELECT schedule_status FROM [SHOW SCHEDULES] WHERE id = 123;
```

**If already paused**: No error, idempotent operation

### Backups Still Running After Pause

**Normal**: Currently executing backup completes

**Verify no new jobs**:
```sql
SELECT job_id, created
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND description LIKE '%schedule_name%'
ORDER BY created DESC
LIMIT 5;
```

## Best Practices

1. **Communicate before pausing production** backups
2. **Document pause reason** in change tickets
3. **Set calendar reminders** to resume paused schedules
4. **Verify resume** with SHOW SCHEDULES after maintenance
5. **Don't drop schedules casually** - pause instead if temporary
6. **Test pause/resume** in dev before production use
7. **Monitor for forgotten paused schedules** with alerts

## Comparison: Pause vs Drop

| Aspect | PAUSE | DROP |
|--------|-------|------|
| Reversible | Yes (RESUME) | No (must recreate) |
| Config preserved | Yes | No |
| Use case | Temporary | Permanent |
| Existing backups | Unchanged | Unchanged |
| Best for | Maintenance | Decommission |

## Bulk Operations

### Pause All Schedules

```sql
PAUSE SCHEDULES (SELECT id FROM [SHOW SCHEDULES]);
```

### Resume All Paused

```sql
RESUME SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE schedule_status = 'PAUSED'
);
```

### Drop All Dev Schedules

```sql
DROP SCHEDULES (
  SELECT id FROM [SHOW SCHEDULES]
  WHERE label LIKE '%dev%'
);
```

## Related Skills

- `create-automated-backup-schedules` - Create schedules to manage
- `monitor-scheduled-backups-with-show-schedules` - Monitor schedule status
- `modify-backup-schedule-frequency` - Change schedule parameters
