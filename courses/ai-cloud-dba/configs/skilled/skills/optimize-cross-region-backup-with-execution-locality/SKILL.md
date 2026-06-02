---
name: optimize-cross-region-backup-with-execution-locality
description: Use WITH EXECUTION LOCALITY option to control where backup job executes. Constrains backup coordinator to nodes matching locality filter, reducing cross-region traffic by executing backup near data. Provides significant cost savings in multi-region deployments.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - backup-restore
    - multi-region
    - performance
    - cost-optimization
    - execution-locality
---

# Optimize Cross-Region Backup with Execution Locality

Use the WITH EXECUTION LOCALITY option to control where backup job coordinators execute. This feature constrains the backup coordinator to nodes matching a locality filter, reducing cross-region traffic by executing the backup near the data. When combined with locality-aware storage URLs, this provides significant cost savings and performance improvements in multi-region deployments.

## When to Use This Skill

Use execution locality for backups when you need to:

- Minimize cross-region network egress costs in multi-region clusters
- Reduce backup latency by coordinating near the data
- Control which region handles backup coordination
- Optimize backup performance for region-specific workloads
- Prevent backup jobs from overloading specific regions
- Comply with data processing location requirements
- Combine with locality-aware storage for maximum efficiency

## Prerequisites

Before using execution locality:

- Multi-region cluster with nodes configured with locality metadata
- Understanding of your cluster's locality topology
- Knowledge of where your data is concentrated
- Regional storage buckets configured (for optimal results)
- CockroachDB v26.1.0 or later (execution locality support)

## Core Concepts

### Backup Job Coordination

When a backup job runs:

1. A coordinator node is selected to manage the backup job
2. The coordinator distributes work to nodes across the cluster
3. Nodes read their local data and write to the backup storage
4. The coordinator tracks progress and finalizes the backup

Without execution locality, the coordinator may be in a different region than the data, causing unnecessary cross-region coordination traffic.

### How Execution Locality Works

The WITH EXECUTION LOCALITY option filters which nodes can become the backup coordinator:

```sql
-- Execute backup coordinator in us-east region
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east';
```

CockroachDB ensures:
- Only nodes matching `region=us-east` can coordinate the backup
- Coordinator placement is optimal for data access patterns
- Cross-region coordination traffic is minimized
- Backup job metadata stays within the specified region

### Cost and Performance Benefits

Using execution locality provides:

- **Reduced cross-region coordination**: Coordinator communicates with nearby nodes
- **Lower egress costs**: Less data crosses region boundaries
- **Improved backup speed**: Coordinator has lower latency to data
- **Predictable costs**: Backup traffic stays within known regions
- **Better resource utilization**: Spread coordination across regions

## Configuration Instructions

### Step 1: Identify Optimal Coordinator Region

Determine where your data is concentrated:

```sql
-- Check data distribution across regions
SELECT
  regexp_extract(locality, 'region=([^,]+)') as region,
  count(*) as range_count,
  sum(range_size_mb) as total_data_mb
FROM crdb_internal.ranges_no_leases
CROSS JOIN LATERAL (
  SELECT round(range_size / 1024 / 1024, 2) as range_size_mb
) AS sizes
JOIN crdb_internal.kv_node_status
  ON ranges_no_leases.lease_holder = kv_node_status.node_id
GROUP BY region
ORDER BY total_data_mb DESC;

-- Expected output shows data concentration
  region  | range_count | total_data_mb
----------+-------------+---------------
 us-east  |        4523 |       12457.32
 us-west  |        1892 |        4234.56
 eu-west  |        1245 |        2890.12
```

Choose the region with the most data for optimal execution locality.

### Step 2: Verify Node Availability in Target Region

Ensure nodes exist in the target region:

```sql
-- List nodes by region
SELECT
  node_id,
  address,
  regexp_extract(locality, 'region=([^,]+)') as region
FROM crdb_internal.kv_node_status
ORDER BY region, node_id;

-- Expected output
  node_id |      address      |  region
----------+-------------------+----------
        1 | 10.0.1.10:26257  | us-east
        2 | 10.0.1.11:26257  | us-east
        3 | 10.0.2.10:26257  | us-west
        4 | 10.0.2.11:26257  | us-west
```

### Step 3: Execute Backup with Execution Locality

Create a backup constrained to a specific region:

```sql
-- Database backup with execution locality
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east';

-- Full cluster backup with execution locality
BACKUP INTO 's3://backups/cluster'
WITH
  EXECUTION LOCALITY = 'region=us-east',
  revision_history;

-- Table backup with execution locality
BACKUP TABLE orders, customers INTO 's3://backups/tables'
WITH EXECUTION LOCALITY = 'region=us-west';
```

### Step 4: Combine with Locality-Aware Storage

For maximum optimization, combine execution locality with locality-aware storage:

```sql
-- Optimal configuration: execution locality + locality-aware storage
BACKUP DATABASE mydb INTO
  ('s3://backups-us-east/mydb?COCKROACH_LOCALITY=region=us-east',
   's3://backups-us-west/mydb?COCKROACH_LOCALITY=region=us-west',
   's3://backups-eu-west/mydb?COCKROACH_LOCALITY=region=eu-west')
WITH EXECUTION LOCALITY = 'region=us-east';

-- This configuration ensures:
-- 1. Coordinator runs in us-east (where most data resides)
-- 2. Each region's data writes to its regional bucket
-- 3. Minimal cross-region traffic for both coordination and storage
```

### Step 5: Monitor Job Execution

Verify the backup coordinator ran in the correct region:

```sql
-- Check which node coordinated the backup
SELECT
  job_id,
  description,
  status,
  running_status,
  coordinator_id
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND created > now() - INTERVAL '1 hour'
ORDER BY created DESC
LIMIT 5;

-- Check coordinator node's locality
SELECT
  node_id,
  locality
FROM crdb_internal.kv_node_status
WHERE node_id = <coordinator_id>;
```

## Common Patterns

### Pattern 1: Region-Specific Scheduled Backups

Schedule backups that execute in the region with the most data:

```sql
-- Schedule daily backup to run in us-east
CREATE SCHEDULE daily_backup_us_east
FOR BACKUP DATABASE mydb INTO
  ('s3://backups-us-east/daily?COCKROACH_LOCALITY=region=us-east',
   's3://backups-us-west/daily?COCKROACH_LOCALITY=region=us-west')
WITH
  EXECUTION LOCALITY = 'region=us-east',
  revision_history
RECURRING '@daily'
WITH SCHEDULE OPTIONS first_run = 'now';

-- Schedule weekly backup to run in eu-west for EU data
CREATE SCHEDULE weekly_backup_eu
FOR BACKUP DATABASE eu_data INTO
  's3://backups-eu-west/weekly'
WITH EXECUTION LOCALITY = 'region=eu-west'
RECURRING '@weekly';
```

### Pattern 2: Multi-Tier Locality Constraints

Use zone-level locality for fine-grained control:

```sql
-- Execute in specific availability zone
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east,zone=us-east-1a';

-- Execute in any us-east zone (broader filter)
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east';
```

### Pattern 3: Regional Table Backups

Backup regional tables in their primary region:

```sql
-- Backup US data in US region
BACKUP TABLE us_orders, us_customers INTO
  's3://backups-us-east/us-tables'
WITH EXECUTION LOCALITY = 'region=us-east';

-- Backup EU data in EU region
BACKUP TABLE eu_orders, eu_customers INTO
  's3://backups-eu-west/eu-tables'
WITH EXECUTION LOCALITY = 'region=eu-west';
```

## Advanced Configurations

### Incremental Backups with Execution Locality

```sql
-- Create full backup
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east';

-- Create incremental backup (inherits execution locality)
BACKUP DATABASE mydb INTO LATEST IN 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east';
```

### Point-in-Time Recovery with Execution Locality

```sql
-- Backup with revision history for PITR
BACKUP DATABASE mydb INTO
  ('s3://backups-us-east/pitr?COCKROACH_LOCALITY=region=us-east',
   's3://backups-us-west/pitr?COCKROACH_LOCALITY=region=us-west')
WITH
  EXECUTION LOCALITY = 'region=us-east',
  revision_history;

-- Restore from specific point in time
RESTORE DATABASE mydb FROM '2026-03-06 10:00:00' IN
  ('s3://backups-us-east/pitr',
   's3://backups-us-west/pitr');
```

### Detached Backups with Execution Locality

```sql
-- Start backup in background
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH
  EXECUTION LOCALITY = 'region=us-east',
  detached;

-- Returns job ID immediately
        job_id
----------------------
  123456789012345678

-- Monitor progress
SHOW JOB 123456789012345678;
```

## Monitoring and Optimization

### Measure Cross-Region Traffic Reduction

```sql
-- View backup job metrics
SELECT
  job_id,
  description,
  fraction_completed,
  running_status,
  coordinator_id
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND status = 'running';

-- Check coordinator locality
SELECT
  n.node_id,
  n.locality,
  n.address
FROM crdb_internal.kv_node_status n
WHERE n.node_id = <coordinator_id>;
```

### Analyze Backup Performance

```sql
-- View backup job history with execution time
SELECT
  created,
  finished,
  finished - created as duration,
  description,
  coordinator_id
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND created > now() - INTERVAL '7 days'
ORDER BY created DESC;

-- Compare backups with/without execution locality
-- to measure performance improvement
```

### Monitor Regional Resource Usage

```sql
-- Check CPU usage on coordinator nodes
SELECT
  node_id,
  regexp_extract(locality, 'region=([^,]+)') as region,
  cpu_percent
FROM crdb_internal.kv_node_status
WHERE regexp_extract(locality, 'region=([^,]+)') = 'us-east'
ORDER BY cpu_percent DESC;
```

## Troubleshooting

### Issue: No Nodes Match Execution Locality Filter

**Symptom**: Backup job fails with "no nodes match execution locality filter" error.

**Common Causes**:
- Typo in locality key or value
- No nodes configured with the specified locality
- All matching nodes are unavailable

**Resolution**:
```sql
-- Verify available localities
SELECT DISTINCT locality
FROM crdb_internal.kv_node_status;

-- Check for matching nodes
SELECT node_id, locality, is_live
FROM crdb_internal.kv_node_status
WHERE locality LIKE '%region=us-east%';

-- Fix: Use a locality that exists in your cluster
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east';  -- Ensure this matches
```

### Issue: Backup Slower with Execution Locality

**Symptom**: Backup takes longer when using execution locality compared to without it.

**Common Causes**:
- Coordinator region has fewer nodes
- Coordinator region is underpowered
- Data is primarily in a different region

**Resolution**:
```sql
-- Check data distribution
SELECT
  regexp_extract(locality, 'region=([^,]+)') as region,
  count(*) as range_count
FROM crdb_internal.ranges_no_leases
JOIN crdb_internal.kv_node_status
  ON ranges_no_leases.lease_holder = kv_node_status.node_id
GROUP BY region;

-- Use execution locality matching primary data location
-- If most data is in us-west, use:
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-west';
```

### Issue: Coordinator Node Overloaded

**Symptom**: High CPU or memory usage on coordinator during backup.

**Common Causes**:
- Too few nodes in the execution locality region
- Large backup overwhelming single coordinator
- Concurrent backups running on same nodes

**Resolution**:
```sql
-- Spread load by using broader locality filter
-- Instead of specific zone, use entire region:
BACKUP DATABASE mydb INTO 's3://backups/mydb'
WITH EXECUTION LOCALITY = 'region=us-east';  -- Any node in region

-- Or schedule backups at different times to avoid overlap
CREATE SCHEDULE morning_backup
FOR BACKUP DATABASE db1 INTO 's3://backups/db1'
WITH EXECUTION LOCALITY = 'region=us-east'
RECURRING '@daily'
WITH SCHEDULE OPTIONS first_run = '2026-03-07 02:00:00';

CREATE SCHEDULE afternoon_backup
FOR BACKUP DATABASE db2 INTO 's3://backups/db2'
WITH EXECUTION LOCALITY = 'region=us-east'
RECURRING '@daily'
WITH SCHEDULE OPTIONS first_run = '2026-03-07 14:00:00';
```

## Best Practices

1. **Match Execution Locality to Data Location**: Place the coordinator in the region with the most data to minimize cross-region reads.

2. **Combine with Locality-Aware Storage**: Use both execution locality and locality-aware storage URLs for maximum cost savings.

3. **Use Region-Level Filters**: Prefer `region=us-east` over `region=us-east,zone=us-east-1a` to give CockroachDB flexibility in coordinator selection.

4. **Verify Node Availability**: Ensure multiple nodes match the execution locality filter to provide redundancy.

5. **Monitor Coordinator Distribution**: Track which nodes coordinate backups to ensure even load distribution.

6. **Test Both With and Without**: Compare backup performance and costs with and without execution locality to validate benefits.

7. **Document Regional Strategies**: Maintain clear documentation of which backups execute in which regions and why.

8. **Schedule Regionally**: Align backup schedules with business hours in different regions to minimize impact.

## Cost Savings Analysis

### Example Cost Reduction

For a 3-region cluster backing up 1TB of data:

**Without Execution Locality**:
- Coordinator in us-east, data split across us-east, us-west, eu-west
- Cross-region coordination traffic: ~500GB
- Cross-region storage writes: ~1TB
- Estimated egress cost: $45-90 per backup

**With Execution Locality + Locality-Aware Storage**:
- Coordinator in us-east (where data is concentrated)
- Each region writes to local storage
- Cross-region coordination traffic: ~50GB
- Cross-region storage writes: ~0GB
- Estimated egress cost: $5-10 per backup

**Monthly Savings** (daily backups): ~$1,200-2,400

## Related Skills

- **configure-locality-aware-backups**: Configure regional storage URLs for backups
- **support-data-sovereignty-with-locality-aware-backups**: Use locality-aware backups for compliance
- **execute-cluster-level-full-backups**: General cluster backup procedures
- **create-automated-backup-schedules**: Schedule backups with execution locality
- **set-node-locality-metadata**: Configure locality metadata on cluster nodes
- **analyze-range-distribution-across-regions**: Understand where data resides
- **monitor-scheduled-backups-with-show-schedules**: Monitor scheduled backup execution
- **design-multi-region-schema-design-patterns**: Multi-region database architecture

## Additional Resources

- CockroachDB Documentation: Backup with Execution Locality
- CockroachDB Documentation: Locality-Aware Backups
- CockroachDB Documentation: Multi-Region Capabilities
- Cloud Provider Pricing: AWS Data Transfer, GCP Network Egress, Azure Bandwidth
