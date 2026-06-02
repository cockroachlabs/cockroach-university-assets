---
name: manage-backup-retention-policies
description: Design and implement backup retention policies balancing RPO requirements with storage costs. Use storage lifecycle rules (S3/GCS) or manual cleanup scripts. Implement graduated retention strategies (daily 30d, weekly 90d, monthly 1yr). Ensure retention exceeds recovery window and meets compliance requirements.
metadata:
  domain: Backup and Restore
  bloom_level: Analyze
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Manage Backup Retention Policies

**Domain**: Backup and Restore
**Bloom's Level**: Analyze
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to design, implement, and manage backup retention policies that balance recovery point objectives (RPO), storage costs, and compliance requirements. You'll learn to use cloud storage lifecycle rules, manual cleanup scripts, and graduated retention strategies.

**When to use this skill:**
- Designing backup strategies for new production systems
- Optimizing backup storage costs without sacrificing recoverability
- Implementing compliance-driven retention requirements (SOX, HIPAA, GDPR)
- Migrating backup strategies to cloud storage with lifecycle management
- Troubleshooting retention policy failures or unexpected deletions

**Key concepts:**
- **RPO (Recovery Point Objective)**: Maximum acceptable data loss (e.g., 24 hours)
- **RTO (Recovery Time Objective)**: Maximum acceptable recovery time (e.g., 2 hours)
- **Retention window**: How long backups are kept before deletion
- **Graduated retention**: Different retention periods for different backup frequencies
- **Compliance retention**: Legal/regulatory minimum retention requirements

**Common retention strategies:**
- Daily backups: 7-30 days
- Weekly backups: 30-90 days
- Monthly backups: 90-365 days
- Quarterly backups: 1-7 years (compliance)

## Instructions

### Understanding Retention Policy Requirements

Before implementing retention policies, define requirements:

**Recovery Requirements:**
- RPO: How much data loss is acceptable? (e.g., 24 hours = daily backups)
- RTO: How fast must recovery complete? (e.g., 2 hours = shorter backup chains)
- Recovery window: How far back must you be able to restore? (e.g., 30 days)

**Compliance Requirements:**
- Industry regulations (HIPAA: 6 years, SOX: 7 years)
- Legal holds (litigation, investigations)
- Audit trail requirements

**Cost Constraints:**
- Storage budget ($/TB/month)
- Network egress costs (restore operations)

### Calculating Retention Policy Storage Requirements

Estimate storage costs for different retention strategies:

```sql
-- Strategy A: Daily full backups for 30 days
-- 30 backups × ~13 TB average = 390 TB
-- Monthly cost at $0.023/GB: 390 TB × $23.55/TB = $9,185/month

-- Strategy B: Weekly full + daily incrementals for 30 days
-- Week 1: 10 TB full + (6 × 0.5 TB incr) = 13 TB
-- Total 4 weeks: ~54 TB
-- Monthly cost: 54 TB × $23.55/TB = $1,272/month
-- Savings: $7,913/month (86% reduction)

-- Strategy C: Graduated retention (recommended)
-- Daily backups: 7 days (13 TB)
-- Weekly backups: 30 days (42 TB)
-- Monthly backups: 365 days (132 TB)
-- Total: 187 TB, $4,404/month
-- Benefits: Granular recovery + compliance coverage
```

### Implementing Storage Lifecycle Policies (S3)

Use AWS S3 lifecycle rules for automated retention:

```json
{
  "Rules": [
    {
      "Id": "daily-backups-7day-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "daily-backups/"},
      "Expiration": {"Days": 7}
    },
    {
      "Id": "weekly-backups-30day-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "weekly-backups/"},
      "Expiration": {"Days": 30}
    },
    {
      "Id": "monthly-backups-365day-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "monthly-backups/"},
      "Expiration": {"Days": 365}
    }
  ]
}
```

**Apply lifecycle policy with AWS CLI:**

```bash
# Create lifecycle configuration JSON file
cat > lifecycle-policy.json << 'EOF'
{
  "Rules": [
    {
      "Id": "daily-7d-weekly-30d-monthly-1y",
      "Status": "Enabled",
      "Filter": {"Prefix": "backups/"},
      "Expiration": {"Days": 365}
    }
  ]
}
EOF

# Apply lifecycle policy to S3 bucket
aws s3api put-bucket-lifecycle-configuration \
  --bucket acme-cockroachdb-backups \
  --lifecycle-configuration file://lifecycle-policy.json

# Verify lifecycle policy
aws s3api get-bucket-lifecycle-configuration \
  --bucket acme-cockroachdb-backups
```

### Implementing Storage Lifecycle Policies (GCS)

Use Google Cloud Storage lifecycle rules:

```bash
# Create lifecycle configuration JSON file
cat > lifecycle-policy.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 7, "matchesPrefix": ["daily-backups/"]}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 30, "matchesPrefix": ["weekly-backups/"]}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 365, "matchesPrefix": ["monthly-backups/"]}
      }
    ]
  }
}
EOF

# Apply lifecycle policy to GCS bucket
gsutil lifecycle set lifecycle-policy.json gs://acme-cockroachdb-backups

# Verify lifecycle policy
gsutil lifecycle get gs://acme-cockroachdb-backups
```

### Implementing Manual Retention Cleanup Scripts

For environments without cloud storage lifecycle support:

```bash
#!/bin/bash
# safe-backup-cleanup.sh
# Validates backups before deletion

set -euo pipefail

BACKUP_LOCATION="gs://acme-backups/daily"
RETENTION_DAYS=7
DB_URL="postgresql://root@localhost:26257/defaultdb?sslmode=disable"

CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)

echo "=== Safe Backup Cleanup ==="
echo "Retention policy: Keep backups newer than $CUTOFF_DATE"

# Step 1: List all backups
cockroach sql --url "$DB_URL" << EOF
  SHOW BACKUPS IN '$BACKUP_LOCATION';
EOF

# Step 2: Validate newest backup before cleanup
NEWEST_BACKUP=$(cockroach sql --url "$DB_URL" --format=csv << EOF
  SELECT path FROM [SHOW BACKUPS IN '$BACKUP_LOCATION']
  ORDER BY path DESC LIMIT 1;
EOF
)

echo "Validating backup: $NEWEST_BACKUP"
cockroach sql --url "$DB_URL" << EOF
  SHOW BACKUP '$NEWEST_BACKUP' IN '$BACKUP_LOCATION' WITH check_files;
EOF

if [ $? -ne 0 ]; then
  echo "ERROR: Newest backup validation failed. Aborting cleanup."
  exit 1
fi

# Step 3: Delete old backups
BACKUPS_TO_DELETE=$(cockroach sql --url "$DB_URL" --format=csv << EOF
  SELECT path FROM [SHOW BACKUPS IN '$BACKUP_LOCATION']
  WHERE path < '$CUTOFF_DATE' ORDER BY path;
EOF
)

for backup in $BACKUPS_TO_DELETE; do
  echo "Deleting: $backup"
  gsutil -m rm -r "$BACKUP_LOCATION/$backup/"
done

echo "=== Cleanup Complete ==="
```

## Common Patterns

### Pattern 1: Graduated Retention Strategy Implementation

Complete implementation of multi-tier retention:

```sql
-- Tier 1: Daily backups (7-day retention)
CREATE SCHEDULE daily_backup_7d FOR BACKUP DATABASE production
INTO 'gs://acme-backups/daily-backups/'
WITH revision_history
RECURRING '@daily';

-- Tier 2: Weekly backups (30-day retention)
CREATE SCHEDULE weekly_backup_30d FOR BACKUP DATABASE production
INTO 'gs://acme-backups/weekly-backups/'
WITH revision_history
RECURRING '@weekly';

-- Tier 3: Monthly backups (365-day retention)
CREATE SCHEDULE monthly_backup_1y FOR BACKUP DATABASE production
INTO 'gs://acme-backups/monthly-backups/'
WITH revision_history
RECURRING '0 0 1 * *';

-- Apply storage lifecycle policies to each tier
```

### Pattern 2: Cost-Optimized Retention with Storage Tiering

Minimize storage costs using cloud storage tiers:

```bash
cat > cost-optimized-retention.json << 'EOF'
{
  "Rules": [
    {
      "Id": "cost-optimized-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "backups/"},
      "Transitions": [
        {"Days": 7, "StorageClass": "STANDARD_IA"},
        {"Days": 30, "StorageClass": "GLACIER"},
        {"Days": 90, "StorageClass": "DEEP_ARCHIVE"}
      ],
      "Expiration": {"Days": 365}
    }
  ]
}
EOF

# Cost savings: 88% vs S3 Standard only
```

### Pattern 3: Compliance-Driven Retention with Immutability

Implement retention for regulatory compliance:

```bash
# Enable Object Lock on bucket (must be done at creation)
aws s3api create-bucket \
  --bucket acme-compliance-backups \
  --object-lock-enabled-for-bucket \
  --region us-east-1

# Configure Object Lock default retention
aws s3api put-object-lock-configuration \
  --bucket acme-compliance-backups \
  --object-lock-configuration '{
    "ObjectLockEnabled": "Enabled",
    "Rule": {
      "DefaultRetention": {"Mode": "COMPLIANCE", "Days": 2555}
    }
  }'

# Compliance mode prevents deletion until retention expires
```

### Pattern 4: Retention Audit and Validation Workflow

```bash
#!/bin/bash
# retention-audit.sh - Regular validation of retention compliance

DB_URL="postgresql://root@localhost:26257/defaultdb?sslmode=disable"

# Check daily backups (should have 7 days)
DAILY_COUNT=$(cockroach sql --url "$DB_URL" --format=csv << EOF
  SELECT COUNT(*) FROM [SHOW BACKUPS IN 'gs://acme-backups/daily-backups/'];
EOF
)
echo "Daily backups: $DAILY_COUNT (expected: ~7)"

# Calculate total storage and costs
TOTAL_SIZE=$(gsutil du -s gs://acme-backups/ | awk '{print $1}')
TOTAL_GB=$((TOTAL_SIZE / 1024 / 1024 / 1024))
echo "Total storage: ${TOTAL_GB} GB, Cost: \$$(echo "scale=2; $TOTAL_GB * 0.023" | bc)/month"
```

## Troubleshooting

### Issue 1: Lifecycle Policy Deleting Active Backups

**Symptoms:**
- Recent backups unexpectedly deleted
- Restore operations fail due to missing backups

**Diagnosis:**
```bash
# Check current S3 lifecycle configuration
aws s3api get-bucket-lifecycle-configuration \
  --bucket acme-cockroachdb-backups

# Check recently deleted objects (S3 versioning required)
aws s3api list-object-versions \
  --bucket acme-cockroachdb-backups \
  --prefix backups/ \
  --query 'DeleteMarkers[?IsLatest==`true`]'
```

**Solutions:**
```bash
# Fix lifecycle policy prefix mismatch
# Incorrect: "Prefix": "backups/"  # Too broad!
# Correct:   "Prefix": "backups/daily/"  # Specific tier

# Restore deleted backups (if versioning enabled)
aws s3api list-object-versions \
  --bucket acme-cockroachdb-backups \
  --prefix backups/2026-03-01/
```

### Issue 2: Retention Policy Not Deleting Old Backups

**Symptoms:**
- Backup storage growing beyond expected size
- Old backups not being deleted

**Diagnosis:**
```bash
# Check if lifecycle policy is enabled
aws s3api get-bucket-lifecycle-configuration \
  --bucket acme-cockroachdb-backups

# Verify bucket has lifecycle management enabled
# If empty result, no lifecycle policy configured

# List all objects and check LastModified dates
aws s3api list-objects-v2 \
  --bucket acme-cockroachdb-backups \
  --prefix backups/daily/ \
  --query 'Contents[].[Key,LastModified]'
```

**Solutions:**
```bash
# Verify lifecycle policy syntax
# Common mistakes: wrong "Days" vs "Date", incorrect prefix

# Check lifecycle policy status
aws s3api get-bucket-lifecycle-configuration \
  --bucket acme-cockroachdb-backups \
  --query 'Rules[*].[Id,Status]'

# Update to "Enabled" if needed (re-apply policy)

# Manual cleanup for immediate space recovery
gsutil -m rm -r gs://acme-backups/daily-backups/2026-02-{01..20}-*
```

### Issue 3: Compliance Retention Insufficient

**Symptoms:**
- Audit reveals backups deleted before compliance period
- Cannot restore data for historical compliance queries

**Diagnosis:**
```bash
# Verify retention periods meet compliance requirements
cockroach sql --url "$DB_URL" << EOF
  SELECT path, MIN(start_time) AS oldest_backup,
         now() - MIN(start_time) AS retention_period
  FROM [SHOW BACKUPS IN 'gs://acme-backups/compliance-backups/']
  GROUP BY path ORDER BY oldest_backup;
EOF

# Check compliance requirements (example: SOX = 7 years)
# If retention_period < 7 years, compliance violation
```

**Solutions:**
```bash
# Extend retention period immediately
cat > extended-compliance-retention.json << 'EOF'
{
  "Rules": [
    {
      "Id": "compliance-7y-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "compliance-backups/"},
      "Expiration": {"Days": 2555}
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket acme-compliance-backups \
  --lifecycle-configuration file://extended-compliance-retention.json

# Enable Object Lock for immutability
# Prevents deletion/modification during retention period

# Document retention policy for compliance
cat > RETENTION-POLICY.md << 'EOF'
# Backup Retention Policy
## Compliance Requirements
- Regulation: SOX Section 802
- Retention period: 7 years
- Immutability: Required

## Validation
- Monthly backup count audit
- Annual restore test from oldest backup
EOF
```

## Best Practices

1. **Design Graduated Retention Strategy**
   - Daily: 7-30 days, Weekly: 30-90 days, Monthly: 90-365 days, Compliance: 1-7 years

2. **Balance Cost and Recovery Requirements**
   - Use storage tiering (S3 Standard → IA → Glacier → Deep Archive)
   - Calculate total cost of ownership (storage + retrieval + egress)
   - Monitor storage costs monthly and adjust as needed

3. **Automate Retention Enforcement**
   - Prefer cloud storage lifecycle policies over manual scripts
   - Test lifecycle policies in non-production first
   - Monitor lifecycle policy execution (CloudWatch, GCS logs)
   - Alert on unexpected backup count deviations

4. **Ensure Compliance Coverage**
   - Document retention requirements clearly
   - Implement Object Lock for immutable compliance backups
   - Audit retention compliance quarterly
   - Test restore procedures from oldest compliance backups annually

5. **Protect Against Accidental Deletion**
   - Enable versioning on backup buckets
   - Use separate buckets for different retention tiers
   - Implement least-privilege IAM policies for backup storage
   - Require multi-factor authentication for bucket deletion

6. **Validate Before Deletion**
   - Verify newest backup before deleting old backups
   - Check backup chain integrity (incrementals don't outlive full backups)
   - Test retention policy in non-production environment first
   - Maintain deletion audit logs for compliance

7. **Monitor and Alert**
   - Alert when backup count deviates from expected range
   - Monitor storage costs for unexpected increases
   - Track backup age to ensure retention compliance

## Related Skills

- **verify-backup-file-integrity-with-checkfiles**: Validate backups before retention cleanup
- **analyze-incremental-backup-efficiency**: Optimize backup strategy to reduce storage costs
- **create-automated-backup-schedules**: Implement multi-tier backup schedules
- **inspect-backup-contents-with-show-backup**: Audit backup contents and ages
- **understand-backup-chain-structure**: Ensure retention preserves backup chain integrity
- **create-incremental-backups-with-backup-into-latest**: Create storage-efficient backup chains
