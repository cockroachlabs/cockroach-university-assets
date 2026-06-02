---
name: monitor-backup-jobs-in-cloud-console
description: Monitor backup job status, progress, and history through the CockroachDB Cloud Console. Use when tracking backup execution, troubleshooting failed backups, validating backup schedules, or investigating backup performance issues.
metadata:
  domain: Cloud Ops
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: CockroachDB Cloud
  related_skills:
    - enable-and-configure-backups-in-cloud
    - restore-clusters-from-backups-in-cloud
    - monitor-cluster-health-in-cloud-console
  prerequisites:
    - Cloud Console access (Cluster Admin, Operator, or Developer role)
    - Understanding of backup concepts (frequency, retention)
  estimated_time_minutes: 15
  last_updated: "2026-03-07"
---

# Monitor Backup Jobs in Cloud Console

## Overview

Monitoring backup jobs ensures your disaster recovery strategy is functioning correctly. CockroachDB Cloud Console provides comprehensive visibility into backup job status, history, and performance metrics for managed backups.

**Key Concept**: Managed backups run automatically according to your configured schedule. Regular monitoring ensures backups complete successfully and are available for restore when needed.

## Accessing Backup Monitoring

### Navigate to Backup and Restore Interface

```
1. Log in to CockroachDB Cloud Console
2. Select your organization from dropdown
3. Click on your cluster
4. In left navigation, click "Backup and Restore"
5. Two main views available:
   - "Backups" tab: View completed backups
   - "Settings" tab: Configuration and upcoming schedule
```

**Initial View Layout**:
```
┌─────────────────────────────────────────────────┐
│ Backup and Restore                              │
├─────────────────────────────────────────────────┤
│ [Backups] [Settings]                            │
│                                                 │
│ Recent Backups                                  │
│ ┌───────────────────────────────────────────┐   │
│ │ Time               Size    Status  Actions│   │
│ │ 2026-03-07 14:00  105 GB  ✓       Restore │   │
│ │ 2026-03-07 08:00  104 GB  ✓       Restore │   │
│ │ 2026-03-07 02:00  104 GB  ✓       Restore │   │
│ │ 2026-03-06 20:00  103 GB  ✓       Restore │   │
│ └───────────────────────────────────────────┘   │
│                                                 │
│ Next backup: 2026-03-07 20:00 UTC              │
└─────────────────────────────────────────────────┘
```

## Viewing Backup Job Status

### Current Backup Status

**Backup States**:
```
Status      | Icon | Meaning                      | Actions Available
──────────────────────────────────────────────────────────────────────
Completed   | ✓    | Backup finished successfully | Restore, View details
In Progress | ⟳    | Backup currently running     | View progress
Failed      | ✗    | Backup encountered error     | View error, Retry
Scheduled   | ○    | Backup planned for future    | View schedule
```

### Viewing Completed Backups

```
Backups tab displays all successful backups:

┌──────────────────────────────────────────────────┐
│ Backup History                                   │
├──────────────────────────────────────────────────┤
│ Timestamp            Size      Status   Actions  │
│ 2026-03-07 14:00 UTC 105.2 GB  ✓       [Restore] │
│ 2026-03-07 08:00 UTC 104.8 GB  ✓       [Restore] │
│ 2026-03-07 02:00 UTC 104.5 GB  ✓       [Restore] │
│ 2026-03-06 20:00 UTC 103.9 GB  ✓       [Restore] │
│ 2026-03-06 14:00 UTC 103.1 GB  ✓       [Restore] │
│ ... (scrollable history)                         │
│                                                  │
│ Showing: Last 30 days                            │
│ [View all backups within retention period]      │
└──────────────────────────────────────────────────┘

Key information visible:
- Exact timestamp (in UTC)
- Backup size in GB
- Success status indicator
- Restore button for each backup
```

### Viewing In-Progress Backups

When a backup is running:

```
┌──────────────────────────────────────────────────┐
│ Current Backup Job                               │
├──────────────────────────────────────────────────┤
│ Status: In Progress                              │
│ Started: 2026-03-07 20:00:15 UTC                 │
│ Progress: ████████████░░░░░░░ 65%                │
│ Elapsed time: 12 minutes                         │
│ Estimated remaining: 6 minutes                   │
│                                                  │
│ Current phase: Backing up production_db          │
│ Data backed up: 68 GB / 105 GB                   │
│                                                  │
│ Databases:                                       │
│  ✓ analytics_db (15 GB) - Complete               │
│  ✓ reporting_db (8 GB) - Complete                │
│  ⟳ production_db (45/80 GB) - In progress       │
│  ○ staging_db - Pending                          │
│  ○ test_db - Pending                             │
└──────────────────────────────────────────────────┘

Progress indicators:
- Overall percentage complete
- Time elapsed and estimated remaining
- Per-database progress
- Data volume backed up
```

### Viewing Failed Backups

Failed backups appear with error indicators:

```
┌──────────────────────────────────────────────────┐
│ Failed Backup Job                                │
├──────────────────────────────────────────────────┤
│ Status: Failed ✗                                 │
│ Attempted: 2026-03-07 20:00 UTC                  │
│ Duration: 15 minutes before failure              │
│                                                  │
│ Error: Backup operation timed out                │
│ Details: Failed during production_db backup      │
│ Error code: BACKUP_TIMEOUT_EXCEEDED              │
│                                                  │
│ Retry: Automatic retry scheduled for:            │
│        2026-03-07 21:00 UTC                      │
│                                                  │
│ [View full error log]  [Contact support]        │
└──────────────────────────────────────────────────┘

Failed backup information:
- Timestamp of failure
- Error message
- Which database/phase failed
- Automatic retry schedule
- Links to detailed logs and support
```

## Viewing Backup Details

### Click on Individual Backup

Clicking any backup row opens detailed view:

```
┌──────────────────────────────────────────────────┐
│ Backup Details                                   │
├──────────────────────────────────────────────────┤
│ Backup ID: backup-1a2b3c4d5e6f                   │
│ Timestamp: 2026-03-07 14:00:00 UTC               │
│ Type: Full cluster backup (managed)              │
│ Status: Completed successfully                   │
│                                                  │
│ Performance:                                     │
│ • Duration: 28 minutes, 43 seconds               │
│ • Total size: 105.2 GB                           │
│ • Throughput: 62.8 MB/second                     │
│ • Started: 2026-03-07 14:00:15 UTC               │
│ • Completed: 2026-03-07 14:28:58 UTC             │
│                                                  │
│ Contents:                                        │
│ ├─ production_db: 80.1 GB (42 tables)            │
│ ├─ analytics_db: 15.3 GB (12 tables)             │
│ ├─ reporting_db: 8.2 GB (8 tables)               │
│ ├─ staging_db: 1.4 GB (15 tables)                │
│ └─ test_db: 0.2 GB (5 tables)                    │
│                                                  │
│ Point-in-time recovery:                          │
│ • Available from: 2026-02-06 14:00 UTC           │
│ • Available to: 2026-03-07 14:00 UTC             │
│ • Recovery window: 30 days                       │
│                                                  │
│ Storage:                                         │
│ • Location: Cockroach Labs managed               │
│ • Region: us-west-2                              │
│ • Encryption: AES-256 at rest                    │
│ • Retention: 30 days (expires 2026-04-06)        │
│                                                  │
│ [Restore from this backup]  [Close]              │
└──────────────────────────────────────────────────┘
```

**Key Details Available**:
- Unique backup ID
- Precise start and end times
- Total duration
- Backup throughput (MB/s)
- Database-by-database breakdown
- Table counts
- PITR availability window
- Storage location and encryption
- Retention expiration date

## Monitoring Backup Schedule

### View Upcoming Backups

Settings tab shows next scheduled backup:

```
┌──────────────────────────────────────────────────┐
│ Backup Settings                                  │
├──────────────────────────────────────────────────┤
│ Managed Backup Schedule                          │
│                                                  │
│ Status: ● Active                                 │
│ Frequency: Every 6 hours                         │
│ Retention: 90 days                               │
│                                                  │
│ Next backup scheduled:                           │
│ • Date/Time: 2026-03-07 20:00 UTC                │
│ • In: 2 hours, 47 minutes                        │
│ • Expected duration: ~30 minutes                 │
│ • Estimated completion: 20:30 UTC                │
│                                                  │
│ Recent schedule adherence:                       │
│ • Last 10 backups: 10/10 completed on time       │
│ • Average delay: 0 minutes                       │
│ • Success rate: 100%                             │
│                                                  │
│ [Modify schedule (0 changes remaining)]          │
└──────────────────────────────────────────────────┘
```

### Backup Schedule Adherence Tracking

Monitor whether backups run on schedule:

```
Schedule Performance (Last 30 days):
────────────────────────────────────────────────
Metric                          Value
────────────────────────────────────────────────
Scheduled backups:              120
Successful (on time):           118 (98.3%)
Successful (delayed):           1 (0.8%)
Failed:                         1 (0.8%)
Average start delay:            +32 seconds
Median duration:                28 minutes
Longest duration:               45 minutes
────────────────────────────────────────────────

Schedule adherence is considered excellent above 95%
```

## Monitoring via Activity Logs

### Access Activity Logs

```
Alternative monitoring through Activity page:

1. Navigate to cluster Overview
2. Click "Activity" tab in top navigation
3. Filter by event type: "Backup"
4. View chronological log of backup events

Activity Log View:
┌──────────────────────────────────────────────────┐
│ Cluster Activity - Filtered by: Backup           │
├──────────────────────────────────────────────────┤
│ Time                Event            Status       │
│ 2026-03-07 14:28   Backup completed  Success      │
│   Duration: 28m 43s, Size: 105.2 GB               │
│                                                  │
│ 2026-03-07 08:25   Backup completed  Success      │
│   Duration: 25m 12s, Size: 104.8 GB               │
│                                                  │
│ 2026-03-07 02:31   Backup completed  Success      │
│   Duration: 31m 05s, Size: 104.5 GB               │
│                                                  │
│ 2026-03-06 20:00   Backup failed     Failed       │
│   Error: Timeout during production_db backup      │
│   [View details] [Retry]                          │
│                                                  │
│ 2026-03-06 20:05   Backup completed  Success      │
│   Duration: 29m 44s, Size: 103.9 GB               │
│   Note: Automatic retry after previous failure    │
└──────────────────────────────────────────────────┘
```

**Activity Log Advantages**:
- Shows all cluster events in chronological order
- Correlate backups with other cluster operations
- View pattern of backup timing relative to maintenance
- Identify trends in backup performance

## Backup Job Metrics and Trends

### Size Trend Analysis

Monitor backup size growth over time:

```
Backup Size Trend (Last 30 days):
┌──────────────────────────────────────────┐
│                                          │
│ 120 GB┤                                  │
│       │                               ●  │
│ 110 GB┤                            ●     │
│       │                         ●        │
│ 100 GB┤                      ●           │
│       │                   ●              │
│  90 GB┤                ●                 │
│       │             ●                    │
│  80 GB┤          ●                       │
│       ├──────────────────────────────────┤
│       Feb 6    Feb 13   Feb 20   Mar 6   │
│                                          │
│ Growth rate: +2.1% per week              │
│ Projected size in 30 days: 113 GB        │
│ Storage headroom: 267 GB remaining       │
└──────────────────────────────────────────┘

Implications:
- Steady growth expected
- Storage capacity adequate
- No immediate action needed
- Review retention settings in 60 days
```

### Duration Trend Analysis

Track backup completion times:

```
Backup Duration Trend (Last 30 days):
┌──────────────────────────────────────────┐
│ Minutes to complete                      │
│                                          │
│  45 min┤               ●                 │
│        │                                 │
│  35 min┤  ● ●  ● ● ●●●  ●●● ● ● ●● ●●●  │
│        │                                 │
│  25 min┤                                 │
│        ├──────────────────────────────────┤
│        Feb 6    Feb 13   Feb 20   Mar 6  │
│                                          │
│ Average: 29 minutes                      │
│ P95: 34 minutes                          │
│ P99: 45 minutes                          │
│ Outlier (45m) on Feb 21 - investigated   │
└──────────────────────────────────────────┘

Performance assessment:
- Consistent performance
- One outlier investigated (cluster maintenance)
- Within acceptable limits
- No performance degradation trend
```

## Monitoring Backup Failures

### Failed Backup Investigation

When backup fails, detailed error information available:

```
Failed Backup Investigation View:
┌──────────────────────────────────────────────────┐
│ Backup Failure Details                           │
├──────────────────────────────────────────────────┤
│ Backup ID: backup-fail-xyz123                    │
│ Attempted: 2026-03-06 20:00 UTC                  │
│ Failed at: 2026-03-06 20:15 UTC                  │
│ Duration before failure: 15 minutes               │
│                                                  │
│ Error Information:                               │
│ ┌────────────────────────────────────────────┐   │
│ │ Error Code: BACKUP_TIMEOUT_EXCEEDED        │   │
│ │ Message: Backup operation exceeded         │   │
│ │ timeout limit during database backup       │   │
│ │                                            │   │
│ │ Failed Phase: production_db backup         │   │
│ │ Data backed up: 45 GB / 80 GB (56%)        │   │
│ │                                            │   │
│ │ Root cause: High cluster load during       │   │
│ │ backup window caused slower-than-expected  │   │
│ │ backup performance                         │   │
│ └────────────────────────────────────────────┘   │
│                                                  │
│ Automatic Retry:                                 │
│ • Scheduled: 2026-03-06 21:00 UTC                │
│ • Status: Completed successfully                 │
│ • Duration: 29 minutes                           │
│                                                  │
│ Recommendations:                                 │
│ • No action needed - retry succeeded             │
│ • Consider reviewing backup timing if frequent   │
│ • Monitor cluster load during backup windows     │
│                                                  │
│ [View cluster metrics during failure]            │
│ [Contact support]                                │
└──────────────────────────────────────────────────┘
```

### Common Failure Causes

```
Backup Failure Patterns:

Cause                    | Frequency | Typical Resolution
───────────────────────────────────────────────────────────
Timeout (high load)      | Common    | Auto-retry succeeds
Cluster unhealthy        | Uncommon  | Fix cluster health first
Storage quota exceeded   | Rare      | Cockroach Labs manages
Network issues           | Rare      | Auto-retry succeeds
Concurrent maintenance   | Uncommon  | Reschedule or defer
───────────────────────────────────────────────────────────

Automatic retry behavior:
- First retry: +1 hour after failure
- Second retry: +3 hours after first retry
- Third retry: +6 hours after second retry
- After 3 failures: Alert sent to Cluster Admins
```

## Setting Up Backup Monitoring Alerts

### Email Notifications (Automatic)

```
Default email notifications:

Cluster Admins receive emails for:
────────────────────────────────────────────
✓ Backup failed (after auto-retries exhausted)
✓ Backup schedule interrupted (3+ consecutive failures)
✓ Approaching storage quota (if applicable)
✓ Configuration changes to backup settings
────────────────────────────────────────────

Email notification example:
────────────────────────────────────────────
From: CockroachDB Cloud <alerts@cockroachlabs.cloud>
Subject: [Alert] Backup failed for production-cluster

Cluster: production-cluster
Time: 2026-03-06 23:00 UTC
Status: Failed after 3 automatic retries

Error: Backup operation timeout

Action required: Please review cluster health
View details: [Link to Console]
────────────────────────────────────────────

Cannot customize email settings in Console
All Cluster Admins receive notifications
```

### External Monitoring via API

For integration with monitoring systems:

```bash
#!/bin/bash
# Monitor backup status via Cloud API

export COCKROACH_API_SECRET="your_api_key"
export CLUSTER_ID="your_cluster_id"

# Get latest backup status
LATEST_BACKUP=$(curl -s -X GET \
  "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/backups?limit=1" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  -H "Cc-Version: 2024-09-16" \
  | jq -r '.backups[0]')

BACKUP_STATUS=$(echo "$LATEST_BACKUP" | jq -r '.status')
BACKUP_TIME=$(echo "$LATEST_BACKUP" | jq -r '.timestamp')
BACKUP_SIZE=$(echo "$LATEST_BACKUP" | jq -r '.size_bytes')

# Check if backup is recent (within expected frequency)
BACKUP_AGE_HOURS=$(( ($(date +%s) - $(date -d "$BACKUP_TIME" +%s)) / 3600 ))
EXPECTED_FREQUENCY_HOURS=6

if [ "$BACKUP_STATUS" != "COMPLETED" ]; then
  echo "ALERT: Latest backup failed or incomplete"
  echo "Status: $BACKUP_STATUS"
  echo "Time: $BACKUP_TIME"
  # Send to alerting system (PagerDuty, Slack, etc.)
  exit 1
elif [ $BACKUP_AGE_HOURS -gt $(($EXPECTED_FREQUENCY_HOURS + 2)) ]; then
  echo "ALERT: Backup overdue"
  echo "Last backup: $BACKUP_AGE_HOURS hours ago"
  echo "Expected frequency: $EXPECTED_FREQUENCY_HOURS hours"
  # Send to alerting system
  exit 1
else
  echo "OK: Backup healthy"
  echo "Last backup: $BACKUP_TIME ($BACKUP_AGE_HOURS hours ago)"
  echo "Size: $(($BACKUP_SIZE / 1024 / 1024 / 1024)) GB"
  exit 0
fi
```

### Integration with Monitoring Systems

```
Prometheus-style metrics (export from API):

# Backup age in hours
cockroachdb_cloud_backup_age_hours{cluster="production"} 3

# Backup status (0=failed, 1=success)
cockroachdb_cloud_backup_status{cluster="production"} 1

# Backup size in bytes
cockroachdb_cloud_backup_size_bytes{cluster="production"} 112742891520

# Backup duration in seconds
cockroachdb_cloud_backup_duration_seconds{cluster="production"} 1723

Alerting rules example:
- Alert if backup_age_hours > frequency + 2
- Alert if backup_status = 0
- Alert if backup_duration_seconds > P95 * 1.5
```

## Troubleshooting Backup Issues

### Backup Not Appearing

```
Symptom: Expected backup not showing in Console

Diagnosis:
1. Check current time vs scheduled time
   - Backups may be delayed by up to 15 minutes
   - High cluster load can delay backup start

2. Verify backup configuration active
   - Settings tab → Ensure status is "Active"
   - Check frequency setting

3. Review Activity logs
   - Check for failure messages
   - Look for cluster maintenance events

4. Verify cluster health
   - Overview → All nodes should be "Healthy"
   - Unhealthy cluster blocks backups

Resolution:
- If delayed <30 min: Wait for completion
- If cluster unhealthy: Fix health issues first
- If >1 hour overdue: Contact support with cluster ID
```

### Backup Size Unexpectedly Large

```
Symptom: Backup size much larger than database size

Investigation queries (via Cloud Console SQL Shell):

-- Check total database size
SELECT
  sum(range_size_mb)::INT as total_size_mb
FROM crdb_internal.ranges;

-- Check per-database size
SELECT
  database_name,
  sum(range_size_mb)::INT as size_mb
FROM crdb_internal.ranges
GROUP BY database_name
ORDER BY size_mb DESC;

-- Check for MVCC version accumulation
SELECT
  table_name,
  round(key_bytes::DECIMAL / 1024 / 1024, 2) as key_mb,
  round(value_bytes::DECIMAL / 1024 / 1024, 2) as value_mb,
  round((key_bytes + value_bytes - live_bytes)::DECIMAL / 1024 / 1024, 2) as garbage_mb
FROM crdb_internal.kv_store_status
ORDER BY garbage_mb DESC
LIMIT 10;

Common causes:
1. MVCC garbage accumulation
   - High update workload
   - GC not keeping pace
   - Backup captures pre-GC data

2. Index overhead
   - Multiple secondary indexes
   - Indexes significantly increase size

3. Deleted data not yet GC'd
   - Recent large deletes
   - Data in backup but will be GC'd soon

Resolution:
- Normal for high-update workloads
- Monitor if size grows beyond database size * 1.5
- Consider GC tuning if severe
```

### Backup Duration Increasing

```
Symptom: Backup time increasing week-over-week

Trend analysis:
Week 1: 25 minutes
Week 2: 28 minutes (+12%)
Week 3: 32 minutes (+14%)
Week 4: 38 minutes (+19%)

Investigation:
1. Check database size growth
   - Expected: Duration increases with data
   - Formula: ~3-5 minutes per 10 GB
   - Compare size growth to duration growth

2. Check cluster load during backups
   - Cloud Console → Monitoring → Metrics
   - View CPU/Memory during backup window
   - High load slows backup performance

3. Check for cluster changes
   - Added indexes?
   - More tables/databases?
   - Changed replication factor?

Acceptable duration increase:
- Proportional to size growth: Normal
- Example: +20% size → +20% duration is OK

Concerning duration increase:
- Disproportional to size growth
- Example: +5% size but +40% duration

Resolution:
- If proportional: No action needed
- If disproportional:
  1. Review cluster capacity
  2. Consider scaling cluster
  3. Adjust backup schedule to off-peak hours
  4. Contact support for investigation
```

## Best Practices

### Regular Backup Monitoring Schedule

```
Recommended monitoring cadence:

Daily (automated):
☐ Check latest backup completed successfully
☐ Verify backup within expected size range
☐ Alert if backup overdue (frequency + 2 hours)

Weekly (manual):
☐ Review backup schedule adherence rate
☐ Check backup size trend
☐ Review backup duration trend
☐ Verify no failed backups in past 7 days

Monthly (manual):
☐ Validate PITR recovery window matches expectations
☐ Review storage consumption vs budget
☐ Test restore from recent backup (DR drill)
☐ Review and update backup documentation

Quarterly:
☐ Full disaster recovery test
☐ Review and adjust backup retention if needed
☐ Audit backup monitoring alert effectiveness
☐ Update runbooks based on learnings
```

### Backup Health Scorecard

```
Backup Health Metrics:

Metric                          Target    Status
──────────────────────────────────────────────────
Success rate (30 days)          >99%      ✓ 100%
Schedule adherence              >95%      ✓ 98%
Average delay from schedule     <5 min    ✓ 2 min
Failed backups (consecutive)    0         ✓ 0
Backup age                      <freq+2h  ✓ 3h
Size growth rate                <10%/mo   ✓ 8%/mo
Duration increase               <size%    ✓ OK
PITR window availability        =retention✓ 30d
──────────────────────────────────────────────────

Overall Health: ✓ Excellent

Actions required: None
```

### Documentation

Maintain backup monitoring documentation:

```
Backup Monitoring Runbook Template:

1. Backup Configuration
   - Cluster: production-cluster
   - Frequency: Every 6 hours
   - Retention: 90 days
   - Last config change: 2026-01-15

2. Expected Behavior
   - Backup size: ~105 GB (±5%)
   - Duration: 25-35 minutes
   - Schedule: 02:00, 08:00, 14:00, 20:00 UTC

3. Monitoring Procedures
   - Daily check: Automated via API script
   - Alert channel: #ops-alerts Slack channel
   - Escalation: Page on-call if 2+ failures

4. Common Issues & Solutions
   - Issue: Backup timeout during peak load
     Solution: Auto-retry usually succeeds
   - Issue: Backup delayed by maintenance
     Solution: Expected, no action needed

5. Contacts
   - Primary: ops-team@company.com
   - Escalation: Cockroach Labs support
   - Support contract: Enterprise

6. Recent Changes
   - 2026-03-01: Changed frequency 24h → 6h
   - 2026-02-15: Increased retention 30d → 90d
```

## References

**Official Documentation**:
- [Backup and Restore Monitoring](https://www.cockroachlabs.com/docs/stable/backup-and-restore-monitoring)
- [Managed Backups in CockroachDB Advanced Clusters](https://www.cockroachlabs.com/docs/cockroachcloud/managed-backups-advanced)
- [Managed Backups in CockroachDB Standard Clusters](https://www.cockroachlabs.com/docs/cockroachcloud/managed-backups)
- [Backup and Restore in CockroachDB Cloud Overview](https://www.cockroachlabs.com/docs/cockroachcloud/backup-and-restore-overview)
- [Jobs Page](https://www.cockroachlabs.com/docs/stable/ui-jobs-page.html)
- [Schedules Page](https://www.cockroachlabs.com/docs/stable/ui-schedules-page)

**Related Skills**:
- Enable and configure backups in cloud
- Restore clusters from backups in cloud
- Monitor cluster health in cloud console
- Validate backup data integrity
