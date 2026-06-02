---
name: enable-and-configure-backups-in-cloud
description: Enable and configure managed backups for CockroachDB Cloud clusters, adjusting backup frequency and retention to meet disaster recovery requirements. Use when setting up automated backups, adjusting RPO/RTO targets, or optimizing backup costs.
metadata:
  domain: Cloud Ops
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: CockroachDB Cloud
  related_skills:
    - restore-clusters-from-backups-in-cloud
    - monitor-backup-jobs-in-cloud-console
    - create-automated-backup-schedules
  prerequisites:
    - Cluster Admin or Cluster Operator role
    - Understanding of RPO and RTO concepts
    - Cloud Console or API access
  estimated_time_minutes: 20
  last_updated: "2026-03-07"
---

# Enable and Configure Backups in Cloud

## Overview

CockroachDB Cloud automatically enables managed backups for all clusters by default. These backups are stored in Cockroach Labs-managed cloud storage and provide point-in-time recovery capabilities. For Standard and Advanced clusters, you can customize backup frequency and retention to meet your disaster recovery requirements.

**Key Concept**: Managed backups are automatically enabled and cannot be fully disabled. You can only configure frequency and retention settings.

## Understanding Managed Backups

### Backup Types by Cluster Tier

**CockroachDB Basic**:
- Automatic managed backups enabled
- Fixed schedule: every 24 hours
- Fixed retention: 30 days
- Cannot customize frequency or retention
- Storage included in cluster cost
- Backups stored in Cockroach Labs cloud storage

**CockroachDB Standard**:
- Automatic managed backups enabled
- Configurable frequency: 1-24 hour intervals
- Configurable retention: 2, 7, 30, 90, 365 days
- Can modify settings ONE TIME only (important limitation)
- Storage costs separate from compute
- Backups stored in Cockroach Labs cloud storage

**CockroachDB Advanced**:
- Automatic managed backups enabled
- Configurable frequency: 1-24 hour intervals
- Configurable retention: 2, 7, 30, 90, 365 days
- Can modify settings ONE TIME only (important limitation)
- Storage costs separate from compute
- Backups stored in Cockroach Labs cloud storage

### Default Backup Configuration

**Default Settings** (all new clusters):
```
Frequency: Every 24 hours
Retention: 30 days
Backup time: Varies by cluster (distributed across hours)
Storage location: Cockroach Labs-managed (region-specific)
Backup type: Full cluster backup
Point-in-time recovery: Available within retention period
```

**What Gets Backed Up**:
- All databases (except system database internals)
- All schemas and tables
- All data at backup time
- User-created types, sequences, functions
- NOT included: cluster settings, user passwords (separately managed)

### Important Limitation: One-Time Modification Rule

**Critical**: You can change backup frequency and retention settings only ONCE after cluster creation.

```
Modification Timeline:
─────────────────────────────────────────────────────
Cluster creation → Default: 24h frequency, 30d retention
                   Can modify settings: YES

First modification → Change to: 6h frequency, 90d retention
                    Can modify settings: NO (permanently locked)

Future → Settings locked to: 6h frequency, 90d retention
         Can modify settings: NO
─────────────────────────────────────────────────────

Exception: If you modify from default 30-day retention
to another value, that modification counts as your ONE change.
If initial retention is non-default, no further changes allowed.
```

**Implication**: Choose your backup configuration carefully before applying changes!

## Backup Frequency Configuration

### Available Frequency Options

```
Frequency      | RPO    | Use Case
────────────────────────────────────────────────────────────
Every 1 hour   | 1 hour | Mission-critical, minimal data loss tolerance
Every 6 hours  | 6 hours| Production, balanced RPO/cost
Every 12 hours | 12 hours| Standard production workloads
Every 24 hours | 24 hours| Default, development, low-change workloads
```

**RPO (Recovery Point Objective)**: Maximum acceptable data loss measured in time

### Selecting Backup Frequency

**Every 1 Hour** - Most Aggressive:
```
Use when:
- Financial transactions
- High-value data changes
- Regulatory compliance requiring minimal data loss
- Can tolerate higher storage costs

Trade-offs:
✓ Minimal data loss (1 hour max)
✓ Most granular recovery points
✗ Highest storage costs (24 backups/day)
✗ More storage consumption
✗ Higher incremental backup overhead
```

**Every 6 Hours** - Balanced:
```
Use when:
- Production applications
- Important but not mission-critical data
- Balanced RPO and cost requirements
- Standard SLAs (e.g., 6-hour RPO)

Trade-offs:
✓ Good RPO (6 hours max data loss)
✓ Reasonable storage costs (4 backups/day)
✓ Lower overhead than hourly
✗ More data loss than hourly backups
```

**Every 12 Hours** - Moderate:
```
Use when:
- Less critical production workloads
- Data changes infrequently
- Cost optimization important
- 12-hour data loss acceptable

Trade-offs:
✓ Low storage costs (2 backups/day)
✓ Minimal performance overhead
✗ Up to 12 hours of data loss
✗ Fewer recovery points available
```

**Every 24 Hours** - Default:
```
Use when:
- Development and test environments
- Low-change production workloads
- Analytics/reporting databases
- Cost minimization priority

Trade-offs:
✓ Lowest storage costs (1 backup/day)
✓ Negligible performance impact
✗ Up to 24 hours of data loss
✗ Limited recovery point options
```

## Backup Retention Configuration

### Available Retention Options

```
Retention | Recovery Window | Use Case                    | Storage Multiplier
────────────────────────────────────────────────────────────────────────────
2 days    | 48 hours       | Development/testing          | ~1x
7 days    | 1 week         | Short-term production        | ~1.5x
30 days   | 1 month        | Standard production (default)| ~2x
90 days   | 3 months       | Compliance/audit requirements| ~3x
365 days  | 1 year         | Long-term compliance/legal   | ~6x+
```

**Storage Multiplier**: Approximate storage overhead compared to data size (varies with change rate)

### Selecting Retention Period

**2 Days** - Minimal:
```
Use when:
- Development environments
- Test clusters
- Ephemeral data
- Cost absolutely minimized

Recovery scenarios:
- Quick rollback from recent changes
- Short-term testing needs
- NOT suitable for production
```

**7 Days** - Short-term Production:
```
Use when:
- Non-critical production workloads
- Fast-changing data with limited historical value
- Weekly compliance cycles
- Cost-sensitive deployments

Recovery scenarios:
- Recover from errors within a week
- Weekly data validation cycles
- Short incident response window
```

**30 Days** - Standard (Default):
```
Use when:
- Most production workloads
- Standard compliance requirements
- Monthly reporting cycles
- Balanced cost and safety

Recovery scenarios:
- Monthly compliance audits
- Extended incident investigation
- Data corruption discovered within a month
- Point-in-time recovery for recent month
```

**90 Days** - Extended Compliance:
```
Use when:
- Financial services
- Healthcare (HIPAA)
- Quarterly compliance audits
- Regulatory requirements
- Critical production data

Recovery scenarios:
- Quarterly audit requests
- Extended forensic investigation
- Regulatory compliance recovery
- Long-term data validation
```

**365 Days** - Long-term Archival:
```
Use when:
- Legal hold requirements
- Annual compliance audits
- Financial year-end recovery
- Historical data preservation
- Regulated industries (SOX, GDPR data protection)

Recovery scenarios:
- Annual audit requirements
- Legal discovery requests
- Long-term data forensics
- Year-over-year analysis recovery
```

## Configuring Backups via Cloud Console

### Step 1: Navigate to Backup Settings

```
1. Log in to CockroachDB Cloud Console
2. Select your organization
3. Navigate to your cluster (Standard or Advanced)
4. Click "Backup and Restore" in left navigation
5. Click "Settings" tab (or "Backup settings" tab)
```

### Step 2: Review Current Configuration

```
Current backup settings displayed:
┌───────────────────────────────────────┐
│ Managed Backup Configuration          │
├───────────────────────────────────────┤
│ Status: Enabled (cannot disable)      │
│ Frequency: Every 24 hours             │
│ Retention: 30 days                    │
│                                       │
│ Storage: Cockroach Labs managed       │
│ Last backup: 2026-03-07 02:15 UTC     │
│ Next backup: 2026-03-08 02:15 UTC     │
│                                       │
│ Modifications remaining: 1            │
│ [Edit settings]                       │
└───────────────────────────────────────┘
```

**Important**: Note "Modifications remaining" counter before making changes!

### Step 3: Modify Backup Frequency

```
1. Click "Edit settings" button
2. Locate "Backup frequency" section
3. Select from dropdown:
   ┌─────────────────────────┐
   │ Every 1 hour            │
   │ Every 6 hours           │
   │ Every 12 hours          │
   │ Every 24 hours (current)│
   └─────────────────────────┘
4. Choose desired frequency
5. Do NOT save yet (configure retention too)
```

### Step 4: Modify Retention Period

```
1. Locate "Retention period" section
2. Select from dropdown:
   ┌──────────────────┐
   │ 2 days           │
   │ 7 days           │
   │ 30 days (current)│
   │ 90 days          │
   │ 365 days         │
   └──────────────────┘
3. Choose desired retention
4. Review implications below dropdown
```

### Step 5: Review Cost Impact

```
Configuration changes show estimated cost impact:

┌────────────────────────────────────────────┐
│ Cost Impact Estimate                       │
├────────────────────────────────────────────┤
│ Current configuration:                     │
│ • Frequency: Every 24 hours                │
│ • Retention: 30 days                       │
│ • Estimated storage: 150 GB                │
│ • Monthly cost: $15/month                  │
│                                            │
│ New configuration:                         │
│ • Frequency: Every 6 hours                 │
│ • Retention: 90 days                       │
│ • Estimated storage: 600 GB                │
│ • Monthly cost: $60/month                  │
│                                            │
│ Monthly cost increase: +$45/month          │
└────────────────────────────────────────────┘

⚠️ Warning: This is your ONLY configuration change allowed
```

### Step 6: Save Configuration

```
1. Review all settings carefully
2. Click "Save changes" button
3. Confirmation dialog appears:
   ┌────────────────────────────────────────┐
   │ Confirm Backup Configuration           │
   ├────────────────────────────────────────┤
   │ This will change your backup settings  │
   │ to:                                    │
   │                                        │
   │ Frequency: Every 6 hours               │
   │ Retention: 90 days                     │
   │                                        │
   │ ⚠️ IMPORTANT: You can only modify      │
   │ these settings ONE TIME. Future        │
   │ changes will not be possible.          │
   │                                        │
   │ Are you sure?                          │
   │                                        │
   │ [Cancel]  [Confirm and apply]          │
   └────────────────────────────────────────┘

4. Click "Confirm and apply"
5. Settings updated immediately
6. Next backup uses new frequency
```

### Step 7: Verify Configuration

```
After saving, verify in Backup settings:

┌───────────────────────────────────────┐
│ Managed Backup Configuration          │
├───────────────────────────────────────┤
│ Status: Enabled                       │
│ Frequency: Every 6 hours ✓ Updated    │
│ Retention: 90 days ✓ Updated          │
│                                       │
│ Storage: Cockroach Labs managed       │
│ Last backup: 2026-03-07 02:15 UTC     │
│ Next backup: 2026-03-07 08:15 UTC     │
│                                       │
│ Modifications remaining: 0            │
│ Settings are now locked               │
└───────────────────────────────────────┘

No "Edit settings" button (locked permanently)
```

## Configuring Backups via Cloud API

### Get Current Backup Configuration

```bash
# Set environment variables
export COCKROACH_API_SECRET="your_api_key"
export CLUSTER_ID="your_cluster_id"

# GET current backup configuration
curl -X GET \
  "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  -H "Cc-Version: 2024-09-16" \
  | jq '.backup_config'

# Response:
{
  "frequency_hours": 24,
  "retention_days": 30,
  "modifications_remaining": 1,
  "last_backup_time": "2026-03-07T02:15:00Z",
  "next_backup_time": "2026-03-08T02:15:00Z"
}
```

### Update Backup Configuration via API

```bash
# PATCH request to update backup settings
# Example: Change to 6-hour frequency, 90-day retention

curl -X PATCH \
  "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  -H "Cc-Version: 2024-09-16" \
  -H "Content-Type: application/json" \
  -d '{
    "backup_config": {
      "frequency_hours": 6,
      "retention_days": 90
    }
  }' \
  | jq '.'

# Success response:
{
  "id": "cluster-id",
  "backup_config": {
    "frequency_hours": 6,
    "retention_days": 90,
    "modifications_remaining": 0,
    "last_modified": "2026-03-07T15:30:00Z"
  }
}
```

### API Validation Rules

```bash
# Valid frequency_hours values
Allowed: 1, 6, 12, 24
Invalid: 2, 3, 4, 5, 8, etc.

# Valid retention_days values
Allowed: 2, 7, 30, 90, 365
Invalid: 5, 15, 60, 180, etc.

# Error response for invalid values:
{
  "error": "invalid_backup_config",
  "message": "frequency_hours must be one of: 1, 6, 12, 24",
  "code": 400
}
```

### Terraform Configuration

```hcl
# Configure backups via Terraform
resource "cockroach_cluster" "production" {
  name          = "production-cluster"
  cloud_provider = "AWS"
  plan          = "STANDARD"

  # Backup configuration
  backup_config {
    frequency_hours = 6
    retention_days  = 90
  }

  serverless {
    regions = [{
      name = "us-west-2"
    }]
    usage_limits {
      provisioned_virtual_cpus = 8
    }
  }
}

# WARNING: Can only apply once!
# Changing these values after initial apply will FAIL
# if modification count exhausted
```

## Backup Configuration Best Practices

### Matching RPO and RTO Requirements

**Calculate Required Frequency**:
```
Business Requirement: "We can tolerate up to 4 hours of data loss"

RPO = 4 hours
Required frequency ≤ 4 hours

Available options: 1 hour (over-provisioned) or 6 hours (violation)
Recommendation: Choose 1-hour frequency to meet 4-hour RPO
```

**Calculate Required Retention**:
```
Business Requirement: "Must be able to restore to any point in last 60 days"

RTO requirement = 60 days
Required retention ≥ 60 days

Available options: 30 days (insufficient) or 90 days (meets requirement)
Recommendation: Choose 90-day retention
```

### Configuration Decision Matrix

```
Workload Type           | Recommended Frequency | Recommended Retention
────────────────────────────────────────────────────────────────────────
E-commerce production   | 1-6 hours            | 30-90 days
Financial transactions  | 1 hour               | 90-365 days
SaaS production        | 6-12 hours           | 30-90 days
Internal tools         | 12-24 hours          | 7-30 days
Development/staging    | 24 hours             | 2-7 days
Analytics/reporting    | 24 hours             | 30 days
Regulated data (HIPAA) | 6 hours              | 90-365 days
Regulated data (SOX)   | 6 hours              | 365 days
```

### Cost Optimization Strategies

**Storage Cost Formula** (approximate):
```
Daily backup size = Database size × (1 + daily_change_rate)
Total storage = (Retention_days / Frequency_hours × 24) × Daily_backup_size

Example:
- Database: 100 GB
- Daily change rate: 5% (5 GB changes/day)
- Frequency: 6 hours (4 backups/day)
- Retention: 90 days

Total storage ≈ (90 / 6 × 24) × (100 × 1.05)
              ≈ (90 / 4) × 105
              ≈ 22.5 × 105
              ≈ 2,363 GB (~2.4 TB)

At $0.10/GB/month: ~$236/month for backup storage
```

**Optimization Tips**:
```
1. Start conservative (24h/30d), measure actual RPO needs
2. Increase frequency only if business requires it
3. Monitor restore time vs retention cost trade-off
4. Use longer retention only for compliance
5. Consider self-managed backups for cost control (Advanced)
```

### Testing and Validation

**Before Setting Configuration** (critical for one-time change):
```
1. Document RPO/RTO requirements
   - Interview stakeholders
   - Review compliance requirements
   - Calculate acceptable data loss

2. Test restore times
   - Create test cluster
   - Restore from backup
   - Measure actual RTO
   - Validate data integrity

3. Estimate costs
   - Use CockroachDB Cloud pricing calculator
   - Factor in data growth projections
   - Compare against budget

4. Get approval
   - Present configuration to stakeholders
   - Show cost vs benefit analysis
   - Obtain sign-off before applying

⚠️ Remember: You only get ONE chance to configure!
```

## Monitoring Backup Configuration

### Verify Backups Running

```
1. Navigate to Cloud Console → Backup and Restore
2. View "Backups" tab
3. Check for recent backups:
   ┌────────────────────────────────────────────┐
   │ Recent Backups                             │
   ├────────────────────────────────────────────┤
   │ Timestamp            Size      Status      │
   │ 2026-03-07 14:15    105 GB    Completed    │
   │ 2026-03-07 08:15    104 GB    Completed    │
   │ 2026-03-07 02:15    104 GB    Completed    │
   │ 2026-03-06 20:15    103 GB    Completed    │
   └────────────────────────────────────────────┘

4. Verify:
   - Backups occurring at expected frequency
   - Backup sizes reasonable (growing with data)
   - All backups show "Completed" status
   - No gaps in backup timeline
```

### Backup Alerts

Set up monitoring for backup failures:

```
Cloud Console provides automatic alerts:
- Email notifications for failed backups
- Sent to Cluster Admins
- Includes failure reason and timestamp

Recommended external monitoring:
1. Use Cloud API to check backup status
2. Alert if last_backup_time > frequency + 2 hours
3. Alert if backup status = "failed"
4. Weekly backup restore test verification
```

**API-based Monitoring Script**:
```bash
#!/bin/bash
# Check if backup is overdue

CLUSTER_ID="your-cluster-id"
FREQUENCY_HOURS=6
ALERT_THRESHOLD_HOURS=8  # frequency + 2 hour buffer

LAST_BACKUP=$(curl -s -X GET \
  "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}" \
  -H "Authorization: Bearer ${COCKROACH_API_SECRET}" \
  | jq -r '.backup_config.last_backup_time')

CURRENT_TIME=$(date -u +%s)
BACKUP_TIME=$(date -u -d "$LAST_BACKUP" +%s)
HOURS_SINCE_BACKUP=$(( ($CURRENT_TIME - $BACKUP_TIME) / 3600 ))

if [ $HOURS_SINCE_BACKUP -gt $ALERT_THRESHOLD_HOURS ]; then
  echo "ALERT: Backup overdue! Last backup was $HOURS_SINCE_BACKUP hours ago"
  # Send to alerting system (PagerDuty, Slack, etc.)
fi
```

## Troubleshooting

### Cannot Modify Backup Settings

```
Error: "Backup configuration cannot be modified"

Cause: Modification limit exhausted (already changed once)

Resolution:
- Settings are permanently locked
- Cannot change via Console, API, or Terraform
- Options:
  1. Accept current configuration
  2. Use self-managed backups for more control (Advanced only)
  3. Create new cluster with desired settings (migrate data)
  4. Contact support (may help in exceptional cases)
```

### Backup Failed

```
Symptom: Backup shows "Failed" status in Console

Diagnosis:
1. Check Activity logs for error message
2. Common causes:
   - Cluster unhealthy during backup window
   - Insufficient permissions (rare - managed backups)
   - Storage quota issues (Cockroach Labs managed)
   - Temporary cloud provider issue

Resolution:
- Managed backups auto-retry
- Usually resolves on next scheduled backup
- If persistent (>3 failures), contact support
- Verify cluster health in meantime
```

### Backup Size Unexpectedly Large

```
Symptom: Backup size much larger than database size

Causes:
1. MVCC version accumulation
   - Multiple versions of data retained
   - Large UPDATE workloads create versions

2. Deleted data not yet garbage collected
   - GC runs periodically
   - Backup captures pre-GC data

3. Index overhead
   - Secondary indexes included in backups
   - Can significantly increase backup size

Diagnosis:
# Check database size vs backup size
SELECT
  database_name,
  sum(range_size_mb) as db_size_mb
FROM crdb_internal.ranges
GROUP BY database_name;

# Compare to backup size in Console

Resolution:
- Normal if database has high update rate
- Consider adjusting gc.ttlseconds (default 90000s = 25h)
- Monitor over time - size should stabilize
- Large size impacts storage costs
```

## References

**Official Documentation**:
- [Managed Backups in CockroachDB Advanced Clusters](https://www.cockroachlabs.com/docs/cockroachcloud/managed-backups-advanced)
- [Managed Backups in CockroachDB Standard Clusters](https://www.cockroachlabs.com/docs/cockroachcloud/managed-backups)
- [Managed Backups in CockroachDB Basic Clusters](https://www.cockroachlabs.com/docs/cockroachcloud/managed-backups-basic)
- [Backup and Restore in CockroachDB Cloud Overview](https://www.cockroachlabs.com/docs/cockroachcloud/backup-and-restore-overview)
- [Take and Restore Self-Managed Backups](https://www.cockroachlabs.com/docs/cockroachcloud/take-and-restore-self-managed-backups)
- [Understand CockroachDB Cloud Costs](https://www.cockroachlabs.com/docs/cockroachcloud/costs)

**Related Skills**:
- Restore clusters from backups
- Monitor backup jobs in console
- Point-in-time recovery procedures
