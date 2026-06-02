---
name: configure-locality-aware-backups
description: Configure backups with COCKROACH_LOCALITY URL parameter to write backup data to storage locations matching node locality. Minimizes cross-region data transfer costs and latency while supporting data sovereignty compliance by keeping data within geographic boundaries.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - backup-restore
    - multi-region
    - locality
    - cost-optimization
    - data-sovereignty
---

# Configure Locality-Aware Backups

Configure backups with the COCKROACH_LOCALITY URL parameter to write backup data to storage locations matching node locality. This technique minimizes cross-region data transfer costs and latency while supporting data sovereignty compliance by keeping data within geographic boundaries. Each region's data is stored in its corresponding regional storage bucket.

## When to Use This Skill

Use locality-aware backups when you need to:

- Minimize egress costs in multi-region cloud deployments by keeping backup data within the same region
- Reduce backup latency by writing to nearby storage endpoints
- Support data sovereignty requirements by ensuring regional data stays in regional storage
- Comply with regulatory frameworks requiring geographic data boundaries
- Optimize backup performance in geographically distributed clusters
- Separate backup data by region for operational or compliance purposes

## Prerequisites

Before configuring locality-aware backups:

- Multi-region cluster with nodes configured with locality metadata
- Regional storage buckets created (S3, GCS, or Azure) in each region
- Appropriate IAM permissions for each regional bucket
- Understanding of your cluster's locality configuration
- Backup storage URLs prepared for each region

## Core Concepts

### COCKROACH_LOCALITY URL Parameter

The COCKROACH_LOCALITY URL parameter maps backup data to storage locations based on node locality:

```sql
-- URL format with locality parameter
's3://bucket-name/path?COCKROACH_LOCALITY=<locality-key>=<locality-value>'
```

When CockroachDB writes backup data:
- Each node writes its data to the storage URL matching its locality
- Nodes with locality `region=us-east` write to the `us-east` bucket
- Nodes with locality `region=eu-west` write to the `eu-west` bucket
- Data never crosses regional boundaries during backup

### How Locality Matching Works

CockroachDB matches node locality to storage URLs:

1. Each node reads its configured locality metadata
2. The backup coordinator distributes work to nodes
3. Each node writes data to the URL matching its locality tier
4. If no exact match exists, the backup falls back to the default URL
5. All backup metadata is written to the default (first) URL

### Cost and Performance Benefits

Locality-aware backups provide significant advantages:

- **Reduced egress costs**: Data stays within the same cloud region
- **Lower latency**: Writes go to nearby storage endpoints
- **Better bandwidth utilization**: No cross-region network saturation
- **Improved backup speed**: Parallel regional writes without contention
- **Predictable costs**: Eliminates variable cross-region transfer charges

## Configuration Instructions

### Step 1: Verify Node Locality Configuration

Check that all cluster nodes have locality metadata configured:

```sql
-- View locality for all nodes
SELECT node_id, locality FROM crdb_internal.kv_node_status;

-- Expected output shows region and zone for each node
  node_id |              locality
----------+-------------------------------------
        1 | region=us-east,zone=us-east-1a
        2 | region=us-east,zone=us-east-1b
        3 | region=us-west,zone=us-west-2a
        4 | region=us-west,zone=us-west-2b
        5 | region=eu-west,zone=eu-west-1a
        6 | region=eu-west,zone=eu-west-1b
```

### Step 2: Prepare Regional Storage Buckets

Create storage buckets in each region where you have cluster nodes:

**S3 Example:**
```bash
# Create regional S3 buckets
aws s3 mb s3://myapp-backups-us-east --region us-east-1
aws s3 mb s3://myapp-backups-us-west --region us-west-2
aws s3 mb s3://myapp-backups-eu-west --region eu-west-1
```

**GCS Example:**
```bash
# Create regional GCS buckets
gsutil mb -l us-east1 gs://myapp-backups-us-east
gsutil mb -l us-west2 gs://myapp-backups-us-west
gsutil mb -l europe-west1 gs://myapp-backups-eu-west
```

### Step 3: Configure IAM Permissions for Each Bucket

Ensure cluster nodes can write to regional buckets:

**S3 IAM Policy Example:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::myapp-backups-us-east/*",
        "arn:aws:s3:::myapp-backups-us-west/*",
        "arn:aws:s3:::myapp-backups-eu-west/*"
      ]
    }
  ]
}
```

### Step 4: Create Locality-Aware Backup

Execute a backup with multiple locality-aware URLs:

```sql
-- Full cluster backup with regional storage
BACKUP INTO
  ('s3://myapp-backups-us-east/cluster?COCKROACH_LOCALITY=region=us-east',
   's3://myapp-backups-us-west/cluster?COCKROACH_LOCALITY=region=us-west',
   's3://myapp-backups-eu-west/cluster?COCKROACH_LOCALITY=region=eu-west')
WITH revision_history;

-- Database backup with regional storage
BACKUP DATABASE mydb INTO
  ('s3://myapp-backups-us-east/mydb?COCKROACH_LOCALITY=region=us-east',
   's3://myapp-backups-us-west/mydb?COCKROACH_LOCALITY=region=us-west',
   's3://myapp-backups-eu-west/mydb?COCKROACH_LOCALITY=region=eu-west');

-- Table backup with regional storage
BACKUP TABLE orders INTO
  ('gs://myapp-backups-us-east/orders?COCKROACH_LOCALITY=region=us-east',
   'gs://myapp-backups-us-west/orders?COCKROACH_LOCALITY=region=us-west',
   'gs://myapp-backups-eu-west/orders?COCKROACH_LOCALITY=region=eu-west');
```

### Step 5: Verify Backup Distribution

Check that data was written to regional buckets:

```bash
# S3 verification
aws s3 ls s3://myapp-backups-us-east/cluster/ --recursive
aws s3 ls s3://myapp-backups-us-west/cluster/ --recursive
aws s3 ls s3://myapp-backups-eu-west/cluster/ --recursive

# GCS verification
gsutil ls -r gs://myapp-backups-us-east/orders/
gsutil ls -r gs://myapp-backups-us-west/orders/
gsutil ls -r gs://myapp-backups-eu-west/orders/
```

Each bucket should contain SST files corresponding to data from that region's nodes.

## Common Patterns

### Pattern 1: Multi-Region Cluster with Regional Buckets

Standard configuration for globally distributed clusters:

```sql
-- Schedule daily backups to regional storage
CREATE SCHEDULE daily_backup
FOR BACKUP INTO
  ('s3://backups-us-east/daily?COCKROACH_LOCALITY=region=us-east',
   's3://backups-us-west/daily?COCKROACH_LOCALITY=region=us-west',
   's3://backups-eu-west/daily?COCKROACH_LOCALITY=region=eu-west')
WITH revision_history
RECURRING '@daily'
WITH SCHEDULE OPTIONS first_run = 'now';
```

### Pattern 2: Zone-Level Locality for Fine-Grained Control

Use multiple locality tiers for more granular backup distribution:

```sql
-- Backup with zone-level locality
BACKUP INTO
  ('s3://backups-us-east-1a?COCKROACH_LOCALITY=region=us-east,zone=us-east-1a',
   's3://backups-us-east-1b?COCKROACH_LOCALITY=region=us-east,zone=us-east-1b',
   's3://backups-us-west-2a?COCKROACH_LOCALITY=region=us-west,zone=us-west-2a')
WITH detached;
```

### Pattern 3: Combining with Execution Locality

Optimize both coordinator placement and storage location:

```sql
-- Execute backup in us-east and use regional storage
BACKUP DATABASE mydb INTO
  ('s3://backups-us-east?COCKROACH_LOCALITY=region=us-east',
   's3://backups-us-west?COCKROACH_LOCALITY=region=us-west')
WITH EXECUTION LOCALITY = 'region=us-east';
```

## Restore from Locality-Aware Backups

### Restore Using All Regional Locations

Provide all regional URLs to restore the complete backup:

```sql
-- Restore from all regional buckets
RESTORE FROM LATEST IN
  ('s3://myapp-backups-us-east/cluster',
   's3://myapp-backups-us-west/cluster',
   's3://myapp-backups-eu-west/cluster');

-- Restore specific database
RESTORE DATABASE mydb FROM LATEST IN
  ('s3://myapp-backups-us-east/mydb',
   's3://myapp-backups-us-west/mydb',
   's3://myapp-backups-eu-west/mydb');
```

### Restore from Specific Backup Timestamp

```sql
-- Restore from a specific backup
RESTORE FROM '2026-03-06 10:00:00' IN
  ('s3://myapp-backups-us-east/cluster',
   's3://myapp-backups-us-west/cluster',
   's3://myapp-backups-eu-west/cluster');
```

## Monitoring and Verification

### Check Backup Job Progress

```sql
-- Monitor backup job status
SHOW JOBS
WHERE job_type = 'BACKUP'
  AND status = 'running';

-- View backup job details
SELECT job_id, description, fraction_completed, running_status
FROM [SHOW JOBS]
WHERE job_id = <job_id>;
```

### Inspect Backup Metadata

```sql
-- View backup contents
SHOW BACKUP FROM LATEST IN
  ('s3://myapp-backups-us-east/cluster',
   's3://myapp-backups-us-west/cluster',
   's3://myapp-backups-eu-west/cluster');

-- Check which files are in each locality
SHOW BACKUP FILES FROM LATEST IN
  ('s3://myapp-backups-us-east/cluster',
   's3://myapp-backups-us-west/cluster',
   's3://myapp-backups-eu-west/cluster');
```

## Troubleshooting

### Issue: Backup Falls Back to Default URL

**Symptom**: All backup data written to the first URL instead of distributed regionally.

**Common Causes**:
- Locality parameter doesn't match node locality configuration
- Typo in locality key or value
- Nodes missing locality metadata

**Resolution**:
```sql
-- Verify node locality matches URL parameters
SELECT node_id, locality FROM crdb_internal.kv_node_status;

-- Ensure locality keys match exactly
-- Wrong: 'region=us-east1' when nodes use 'region=us-east'
-- Correct: 'region=us-east'

-- Example with correct matching
BACKUP INTO
  ('s3://bucket?COCKROACH_LOCALITY=region=us-east')  -- Must match node locality
```

### Issue: Permission Denied Writing to Regional Bucket

**Symptom**: Backup fails with "permission denied" or "access denied" errors.

**Common Causes**:
- IAM role lacks permissions for specific regional bucket
- Bucket policy restricts access from certain IPs or regions
- Credentials not configured for regional endpoints

**Resolution**:
```bash
# Test bucket access from cluster node
aws s3 ls s3://myapp-backups-us-east/

# Verify IAM role has permissions
aws iam get-role-policy --role-name cockroachdb-backup-role \
  --policy-name backup-policy

# Add missing permissions
# Ensure policy includes all regional buckets
```

### Issue: Missing Backup Files in Regional Buckets

**Symptom**: Some regional buckets are empty or have incomplete data.

**Common Causes**:
- No nodes with matching locality for that URL
- Nodes with matching locality have no data (empty ranges)
- Region was recently added without data rebalancing

**Resolution**:
```sql
-- Check if cluster has nodes in each region
SELECT DISTINCT regexp_extract(locality, 'region=([^,]+)') as region
FROM crdb_internal.kv_node_status;

-- Verify data distribution across regions
SELECT
  regexp_extract(locality, 'region=([^,]+)') as region,
  count(*) as range_count
FROM crdb_internal.ranges
JOIN crdb_internal.kv_node_status ON ranges.replicas::string LIKE '%' || node_id || '%'
GROUP BY region;

-- If region has no data, it's expected that bucket has no/few files
```

## Best Practices

1. **Match Bucket Regions to Node Regions**: Create storage buckets in the same cloud regions as your cluster nodes to minimize latency and costs.

2. **Use Consistent Locality Keys**: Ensure the locality keys in backup URLs exactly match your cluster's locality configuration (case-sensitive).

3. **Include All Regional URLs for Restore**: Always provide all regional URLs when restoring to ensure complete data recovery.

4. **Test Restore Procedures**: Periodically verify you can restore from regional backups to validate configuration and permissions.

5. **Monitor Storage Costs**: Track storage costs per region to ensure locality-aware backups provide expected savings.

6. **Document Regional Mappings**: Maintain clear documentation mapping regions to storage buckets for operational teams.

7. **Combine with Execution Locality**: Use WITH EXECUTION LOCALITY to further optimize backup performance and costs.

## Related Skills

- **optimize-cross-region-backup-with-execution-locality**: Control where backup jobs execute to minimize cross-region traffic
- **support-data-sovereignty-with-locality-aware-backups**: Use locality-aware backups for regulatory compliance
- **execute-cluster-level-full-backups**: General cluster backup procedures
- **create-automated-backup-schedules**: Schedule regular locality-aware backups
- **restore-cluster-from-full-backup**: Restore operations for locality-aware backups
- **set-node-locality-metadata**: Configure locality information for cluster nodes
- **design-multi-region-schema-design-patterns**: Multi-region database architecture
- **analyze-range-distribution-across-regions**: Verify data distribution across regions

## Additional Resources

- CockroachDB Documentation: Locality-Aware Backups
- CockroachDB Documentation: Multi-Region Capabilities
- CockroachDB Documentation: Backup and Restore Overview
- Cloud Provider Storage Documentation: S3, GCS, Azure Blob Storage
