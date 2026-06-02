---
name: configure-cron-expressions-for-backup-schedules
description: Understand and configure CRON expressions for CockroachDB backup schedules. Use when user asks "how to write cron", "schedule syntax", "cron format", "backup timing", or needs to configure custom backup frequencies beyond shortcuts.
metadata:
  domain: Backup and Restore
  bloom_level: Understand
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Configure CRON Expressions for Backup Schedules

Understand CRON expression syntax to create precise backup schedules matching your RPO requirements.

## CRON Expression Format

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of week (0 - 6) (Sunday to Saturday)
│ │ │ │ │
* * * * *
```

## Common Shortcuts

| Shortcut | Equivalent | Frequency |
|----------|-----------|-----------|
| `@hourly` | `0 * * * *` | Every hour, top of hour |
| `@daily` | `0 0 * * *` | Daily at midnight UTC |
| `@weekly` | `0 0 * * 0` | Sunday at midnight UTC |
| `@monthly` | `0 0 1 * *` | 1st day of month at midnight |

**Recommended**: Use shortcuts when possible - clearer intent

## Examples by Use Case

### Hourly Patterns

```sql
-- Every hour
'0 * * * *'  or  '@hourly'

-- Every 2 hours
'0 */2 * * *'

-- Every 15 minutes
'*/15 * * * *'

-- Top of business hours (9 AM - 5 PM)
'0 9-17 * * *'
```

### Daily Patterns

```sql
-- Daily at midnight
'0 0 * * *'  or  '@daily'

-- Daily at 2:30 AM
'30 2 * * *'

-- Twice daily (2 AM and 2 PM)
'0 2,14 * * *'

-- Every weekday at 6 PM
'0 18 * * 1-5'
```

### Weekly Patterns

```sql
-- Every Sunday midnight
'0 0 * * 0'  or  '@weekly'

-- Every Friday at 11 PM
'0 23 * * 5'

-- Monday and Thursday at 3 AM
'0 3 * * 1,4'

-- Weekends only at noon
'0 12 * * 0,6'
```

### Monthly Patterns

```sql
-- First day of month
'0 0 1 * *'  or  '@monthly'

-- 15th of each month at 3 AM
'0 3 15 * *'

-- Last day of month (use day 28-31 with care)
'0 0 28-31 * *'

-- First Monday of month
'0 0 1-7 * 1'
```

## Interval Syntax

**Format**: `*/N` means "every N units"

```sql
-- Every 5 minutes
'*/5 * * * *'

-- Every 3 hours
'0 */3 * * *'

-- Every 6 hours starting at midnight
'0 0,6,12,18 * * *'
```

## Range Syntax

**Format**: `X-Y` means "from X to Y inclusive"

```sql
-- Business hours (9 AM - 5 PM) every hour
'0 9-17 * * *'

-- Weekdays only
'0 0 * * 1-5'

-- Q1 months (Jan-Mar) at midnight
'0 0 1 1-3 *'
```

## List Syntax

**Format**: `X,Y,Z` means "X and Y and Z"

```sql
-- 6 AM and 6 PM daily
'0 6,18 * * *'

-- Mon, Wed, Fri at 2 AM
'0 2 * * 1,3,5'

-- 1st and 15th of month
'0 0 1,15 * *'
```

## Combining Patterns

```sql
-- Weekdays at 2 AM and 2 PM
'0 2,14 * * 1-5'

-- Every 30 min during business hours, weekdays only
'0,30 9-17 * * 1-5'

-- First and third Monday of month at 3 AM
'0 3 1-7,15-21 * 1'
```

## RPO Planning

### 15-Minute RPO (Critical Systems)

```sql
CREATE SCHEDULE critical_backup
  FOR BACKUP INTO 'nodelocal://1/backups/critical'
  RECURRING '*/15 * * * *'    -- Every 15 minutes
  FULL BACKUP '0 2 * * 0';    -- Sunday 2 AM
```

### 1-Hour RPO (Standard Production)

```sql
CREATE SCHEDULE prod_backup
  FOR BACKUP INTO 'nodelocal://1/backups/prod'
  RECURRING '@hourly'         -- Every hour
  FULL BACKUP '@weekly';      -- Sunday midnight
```

### 4-Hour RPO (Non-Critical)

```sql
CREATE SCHEDULE standard_backup
  FOR BACKUP INTO 'nodelocal://1/backups/standard'
  RECURRING '0 */4 * * *'     -- Every 4 hours
  FULL BACKUP '@weekly';
```

### 24-Hour RPO (Development)

```sql
CREATE SCHEDULE dev_backup
  FOR BACKUP INTO 'nodelocal://1/backups/dev'
  RECURRING '@daily';         -- Daily at midnight
```

## Time Zone Considerations

**Important**: All CRON times in **UTC**

```sql
-- 2 AM UTC = 9 PM EST (previous day)
'0 2 * * *'

-- For 2 AM EST, use 7 AM UTC
'0 7 * * *'
```

**Best practice**: Document timezone in schedule label

## Testing CRON Expressions

### Validate Syntax

Use https://crontab.guru/ to validate and understand CRON expressions

### Test Schedule

```sql
-- Create test schedule with first_run soon
CREATE SCHEDULE test_cron
  FOR BACKUP DATABASE test_db INTO 'nodelocal://1/backups/test'
  RECURRING '*/5 * * * *'
  WITH SCHEDULE OPTIONS first_run = now() + INTERVAL '2 minutes';

-- Watch for execution
SHOW SCHEDULES WHERE label LIKE '%test%';

-- Check job runs
SELECT * FROM [SHOW JOBS] WHERE description LIKE '%test_cron%';

-- Clean up
DROP SCHEDULES (SELECT id FROM [SHOW SCHEDULES] WHERE label LIKE '%test%');
```

## Common Mistakes

### Mistake 1: Forgetting UTC

```sql
-- WRONG: Thinking this is 2 AM local time
'0 2 * * *'

-- RIGHT: Know it's 2 AM UTC (document what this is locally)
'0 2 * * *'  -- 9 PM EST, 11 PM PST, etc.
```

### Mistake 2: Invalid Day/Month

```sql
-- WRONG: February 31st doesn't exist
'0 0 31 2 *'

-- RIGHT: Use valid dates
'0 0 28 2 *'  -- Feb 28th
```

### Mistake 3: Conflicting Patterns

```sql
-- WRONG: Can't be both day 15 AND Monday
'0 0 15 * 1'  -- Only runs if 15th falls on Monday

-- RIGHT: Separate schedules or use OR logic correctly
'0 0 15 * *'  -- 15th of every month
```

## Frequency Recommendations

| System Type | Incremental | Full | CRON Examples |
|-------------|------------|------|---------------|
| Mission Critical | 15 min | Weekly | `*/15 * * * *` + `@weekly` |
| Production | Hourly | Weekly | `@hourly` + `@weekly` |
| Standard | 4 hours | Weekly | `0 */4 * * *` + `@weekly` |
| Development | Daily | N/A | `@daily` |
| Archive | Weekly | Monthly | `@weekly` + `@monthly` |

## Related Skills

- `create-automated-backup-schedules` - Create schedules with CRON
- `modify-backup-schedule-frequency` - Change CRON expressions
- `monitor-scheduled-backups-with-show-schedules` - Verify schedule timing
