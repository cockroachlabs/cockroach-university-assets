---
name: support-data-sovereignty-with-locality-aware-backups
description: Use locality-aware backups with COCKROACH_LOCALITY URL parameters to ensure backup data remains within specific geographic regions. Meets regulatory requirements like GDPR for data transfers and supports compliance in regulated industries and multinational deployments.
metadata:
  domain: Backup and Restore
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  tags:
    - backup-restore
    - data-sovereignty
    - compliance
    - gdpr
    - multi-region
    - regulatory
---

# Support Data Sovereignty with Locality-Aware Backups

Use locality-aware backups with COCKROACH_LOCALITY URL parameters to ensure backup data remains within specific geographic regions. This approach meets regulatory requirements such as GDPR Article 44-49 for data transfers, supports data residency laws, and enables compliance in regulated industries and multinational deployments.

## When to Use This Skill

Use locality-aware backups for data sovereignty when you need to:

- Comply with GDPR requirements for data protection and cross-border transfers
- Meet data residency laws requiring data to remain in specific countries
- Support industry regulations (healthcare, finance, government) with geographic data restrictions
- Ensure customer data stays within contracted geographic boundaries
- Maintain compliance during disaster recovery and backup operations
- Provide evidence of geographic data controls for audits
- Support multi-tenant systems with per-tenant data sovereignty requirements

## Prerequisites

Before implementing data sovereignty controls:

- Understanding of applicable regulatory requirements (GDPR, CCPA, local data protection laws)
- Multi-region cluster with nodes configured with locality metadata
- Regional storage infrastructure in compliant jurisdictions
- IAM policies restricting cross-region access
- Documentation of data classification and geographic requirements
- Legal review of backup and recovery procedures

## Core Concepts

### Data Sovereignty in Distributed Systems

Data sovereignty refers to the concept that digital data is subject to the laws of the country where it is located. In distributed databases:

- Data may be replicated across multiple geographic regions
- Backup operations could move data across borders
- Without controls, backups may violate data residency requirements
- Restore operations must maintain geographic boundaries

### How Locality-Aware Backups Ensure Compliance

CockroachDB's locality-aware backups provide technical controls:

1. **Geographic Partitioning**: Each region's data is written to region-specific storage
2. **No Cross-Border Transfers**: Data never leaves its designated jurisdiction during backup
3. **Audit Trail**: Backup metadata shows which data went to which location
4. **Restore Verification**: Restore operations can be constrained to compliant regions

### Regulatory Frameworks Supported

Locality-aware backups help comply with:

- **GDPR (EU)**: Articles 44-49 on international data transfers
- **CCPA (California)**: Consumer privacy protections
- **LGPD (Brazil)**: General Data Protection Law
- **PIPEDA (Canada)**: Personal Information Protection
- **Data Protection Act (UK)**: Post-Brexit data protection
- **Industry-specific**: HIPAA (healthcare), PCI-DSS (payments), FedRAMP (government)

## Implementation Instructions

### Step 1: Identify Data Classification and Requirements

Document which data must stay in which regions:

```sql
-- Create documentation table for data sovereignty requirements
CREATE TABLE data_sovereignty_policy (
  database_name STRING,
  table_name STRING,
  data_classification STRING,
  required_regions STRING[],
  regulatory_basis STRING,
  PRIMARY KEY (database_name, table_name)
);

-- Example policy records
INSERT INTO data_sovereignty_policy VALUES
  ('eu_customers', 'users', 'PII-GDPR', ARRAY['eu-west'], 'GDPR Article 44'),
  ('us_customers', 'health_records', 'PHI-HIPAA', ARRAY['us-east'], 'HIPAA Security Rule');
```

### Step 2: Configure Regional Storage with Access Controls

Set up storage buckets with geographic and access restrictions:

**S3 Example with Bucket Policies**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnforceEUDataSovereignty",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::eu-backups-gdpr/*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["eu-west-1", "eu-central-1"]
        }
      }
    },
    {
      "Sid": "AllowCockroachDBBackups",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/cockroachdb-eu-backup-role"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::eu-backups-gdpr",
        "arn:aws:s3:::eu-backups-gdpr/*"
      ]
    }
  ]
}
```

**GCS Example with Organization Policies**:
```bash
# Set organization policy to restrict storage locations
gcloud resource-manager org-policies set-policy \
  --project=eu-compliant-project \
  policy-restrict-locations.yaml

# policy-restrict-locations.yaml
constraint: constraints/gcp.resourceLocations
listPolicy:
  allowedValues:
    - in:eu-locations
```

### Step 3: Verify Node Locality Configuration

Ensure cluster nodes have accurate locality metadata:

```sql
-- Verify all nodes have region locality
SELECT
  node_id,
  address,
  locality,
  regexp_extract(locality, 'region=([^,]+)') as region
FROM crdb_internal.kv_node_status
ORDER BY region, node_id;

-- Expected output shows clear regional boundaries
  node_id |      address      |                locality                |  region
----------+-------------------+----------------------------------------+-----------
        1 | 10.1.0.10:26257  | region=eu-west,zone=eu-west-1a         | eu-west
        2 | 10.1.0.11:26257  | region=eu-west,zone=eu-west-1b         | eu-west
        3 | 10.2.0.10:26257  | region=us-east,zone=us-east-1a         | us-east
        4 | 10.2.0.11:26257  | region=us-east,zone=us-east-1b         | us-east
```

### Step 4: Create Compliant Backup Configuration

Execute backups with strict geographic boundaries:

```sql
-- EU data backup - stays within EU
BACKUP DATABASE eu_customers INTO
  ('s3://eu-backups-gdpr/customers?COCKROACH_LOCALITY=region=eu-west')
WITH
  EXECUTION LOCALITY = 'region=eu-west',
  revision_history;

-- Multi-region backup with geographic separation
BACKUP DATABASE global_app INTO
  ('s3://eu-backups-gdpr/global?COCKROACH_LOCALITY=region=eu-west',
   's3://us-backups-compliant/global?COCKROACH_LOCALITY=region=us-east')
WITH revision_history;

-- Ensure no fallback to non-compliant storage
-- Only include compliant regional URLs
```

### Step 5: Create Scheduled Compliant Backups

Automate compliant backups with schedules:

```sql
-- Schedule daily EU-only backups
CREATE SCHEDULE eu_gdpr_daily_backup
FOR BACKUP DATABASE eu_customers INTO
  ('s3://eu-backups-gdpr/daily?COCKROACH_LOCALITY=region=eu-west')
WITH
  EXECUTION LOCALITY = 'region=eu-west',
  revision_history
RECURRING '@daily'
WITH SCHEDULE OPTIONS
  first_run = 'now',
  on_execution_failure = 'pause',
  on_previous_running = 'wait';

-- Schedule US-only backups for healthcare data
CREATE SCHEDULE us_hipaa_daily_backup
FOR BACKUP DATABASE us_health INTO
  ('s3://us-backups-hipaa/daily?COCKROACH_LOCALITY=region=us-east')
WITH
  EXECUTION LOCALITY = 'region=us-east',
  revision_history
RECURRING '@daily';
```

### Step 6: Verify Backup Compliance

Confirm backup data stayed within geographic boundaries:

```sql
-- Check backup metadata
SHOW BACKUP FROM LATEST IN
  ('s3://eu-backups-gdpr/customers');

-- Verify files are only in compliant buckets
SHOW BACKUP FILES FROM LATEST IN
  ('s3://eu-backups-gdpr/customers');

-- Check backup job execution details
SELECT
  job_id,
  description,
  status,
  coordinator_id,
  created,
  finished
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND description LIKE '%eu_customers%'
ORDER BY created DESC
LIMIT 5;

-- Verify coordinator was in compliant region
SELECT
  node_id,
  locality
FROM crdb_internal.kv_node_status
WHERE node_id = <coordinator_id>;
```

### Step 7: Document Compliance Controls

Create audit trail for backup operations:

```sql
-- Create compliance audit log
CREATE TABLE backup_compliance_log (
  log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_job_id INT,
  database_name STRING,
  storage_locations STRING[],
  coordinator_region STRING,
  regulatory_basis STRING,
  verification_timestamp TIMESTAMPTZ DEFAULT now()
);
```

## Common Patterns

### Pattern 1: GDPR-Compliant Multi-Region Architecture

Separate EU and non-EU data completely:

```sql
-- EU database with EU-only backup
BACKUP DATABASE eu_production INTO
  ('s3://eu-backups-gdpr/production?COCKROACH_LOCALITY=region=eu-west',
   's3://eu-backups-gdpr-replica/production?COCKROACH_LOCALITY=region=eu-central')
WITH
  EXECUTION LOCALITY = 'region=eu-west',
  revision_history;

-- US database with US-only backup
BACKUP DATABASE us_production INTO
  ('s3://us-backups-compliant/production?COCKROACH_LOCALITY=region=us-east',
   's3://us-backups-compliant-replica/production?COCKROACH_LOCALITY=region=us-west')
WITH
  EXECUTION LOCALITY = 'region=us-east',
  revision_history;
```

### Pattern 2: Multi-Tenant with Per-Tenant Sovereignty

Different tenants in different regions:

```sql
-- Backup EU tenants to EU storage only
BACKUP TABLE
  tenants.tenant_1_data,
  tenants.tenant_2_data
INTO 's3://eu-backups-gdpr/tenants?COCKROACH_LOCALITY=region=eu-west'
WITH
  EXECUTION LOCALITY = 'region=eu-west';

-- Backup US tenants to US storage only
BACKUP TABLE
  tenants.tenant_3_data,
  tenants.tenant_4_data
INTO 's3://us-backups-compliant/tenants?COCKROACH_LOCALITY=region=us-east'
WITH
  EXECUTION LOCALITY = 'region=us-east';
```

### Pattern 3: Industry-Specific Compliance (Healthcare/HIPAA)

Healthcare data with strict geographic controls:

```sql
-- HIPAA-compliant backup for US healthcare data
BACKUP DATABASE patient_records INTO
  ('s3://us-hipaa-compliant-backups/patients?COCKROACH_LOCALITY=region=us-east')
WITH
  EXECUTION LOCALITY = 'region=us-east',
  revision_history,
  encryption_passphrase = '<strong-passphrase>';

-- Additional encryption for PHI data
-- Combine locality controls with encryption for defense-in-depth
```

## Restore Operations with Data Sovereignty

### Compliant Restore Procedures

```sql
-- Restore EU data only to EU cluster
RESTORE DATABASE eu_customers FROM LATEST IN
  ('s3://eu-backups-gdpr/customers')
WITH into_db = 'eu_customers_restored';

-- Point-in-Time Recovery with compliance
RESTORE DATABASE eu_customers
FROM '2026-03-06 10:00:00' IN
  ('s3://eu-backups-gdpr/customers')
WITH into_db = 'eu_customers_pitr';
```

## Monitoring and Audit

```sql
-- Verify EU data backups use EU-only storage
SELECT job_id, description, created, status
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND description LIKE '%eu_%'
  AND created > now() - INTERVAL '30 days'
ORDER BY created DESC;

-- Monthly compliance report
SELECT
  date_trunc('month', created) as backup_month,
  count(*) as backups,
  count(*) FILTER (WHERE status = 'succeeded') as successful
FROM [SHOW JOBS]
WHERE job_type = 'BACKUP'
  AND description LIKE '%eu_%'
  AND created > now() - INTERVAL '1 year'
GROUP BY backup_month
ORDER BY backup_month DESC;
```

## Troubleshooting

### Issue: Backup Data Leaked to Non-Compliant Region

**Symptom**: Audit discovers backup data in storage bucket outside permitted region.

**Common Causes**:
- Missing COCKROACH_LOCALITY parameter on URL
- Backup job coordinator in wrong region accessed default storage
- Manual backup command didn't include locality constraints

**Resolution**:
```sql
-- Immediately delete non-compliant backup
-- (Use cloud provider CLI or console)
aws s3 rm s3://us-backups/eu-data/ --recursive

-- Create compliant backup
BACKUP DATABASE eu_customers INTO
  ('s3://eu-backups-gdpr/customers?COCKROACH_LOCALITY=region=eu-west')
WITH EXECUTION LOCALITY = 'region=eu-west';

-- Document incident for compliance records
INSERT INTO compliance_incidents VALUES
  (gen_random_uuid(), 'Data sovereignty violation',
   'Backup data found in non-compliant region',
   'Deleted non-compliant backup, created new compliant backup',
   now());
```

### Issue: Cannot Restore Due to Storage Location Restrictions

**Symptom**: Restore operation fails because cluster cannot access regional storage.

**Resolution**:
```sql
-- Verify cluster has nodes in the required region
SELECT DISTINCT regexp_extract(locality, 'region=([^,]+)')
FROM crdb_internal.kv_node_status;

-- Ensure cluster includes compliant region before restore
```

### Issue: Compliance Audit Requires Proof

**Symptom**: Auditor requests evidence data never left specific region.

**Resolution**:
```sql
-- Generate audit report showing coordinator localities
SELECT
  j.job_id,
  j.created,
  n.locality as coordinator_locality
FROM [SHOW JOBS] j
LEFT JOIN crdb_internal.kv_node_status n
  ON j.coordinator_id = n.node_id
WHERE j.job_type = 'BACKUP'
  AND j.description LIKE '%eu_%'
ORDER BY j.created;
```

## Best Practices

1. **Document Regulatory Requirements**: Maintain clear mapping between data, regulations, and geographic requirements
2. **Use Explicit Locality Parameters**: Always specify COCKROACH_LOCALITY to prevent cross-border transfers
3. **Combine Locality Controls**: Use both COCKROACH_LOCALITY and EXECUTION LOCALITY for defense-in-depth
4. **Implement Storage Access Controls**: Use IAM and bucket policies to enforce geographic boundaries
5. **Automate Compliance Verification**: Create scheduled jobs to verify backup locations
6. **Maintain Audit Trails**: Log all backup operations with geographic metadata
7. **Test Restore Procedures**: Regularly verify compliant data restore processes
8. **Encrypt Sensitive Data**: Combine locality controls with encryption

## Compliance Documentation

Maintain documentation for audits:

1. Data Classification Matrix showing which databases contain regulated data
2. Geographic Mapping of storage requirements and restrictions
3. Technical Architecture Diagram showing regional isolation
4. Backup Configuration Audit with geographic constraints
5. IAM Policy Documentation enforcing boundaries
6. Compliance Verification Reports of backup locations

## Related Skills

- **configure-locality-aware-backups**: Technical configuration of locality-aware backups
- **optimize-cross-region-backup-with-execution-locality**: Control backup job placement
- **execute-cluster-level-full-backups**: General backup procedures
- **create-automated-backup-schedules**: Schedule compliant backups
- **understand-data-sovereignty-and-compliance-requirements**: Understand regulatory landscape
- **implement-data-domiciling-policies-with-super-regions**: Super regions for data domiciling
- **configure-regional-by-row-locality**: Row-level geographic data placement
- **enable-encryption-at-rest**: Combine encryption with geographic controls
- **set-node-locality-metadata**: Configure cluster locality metadata
- **create-super-regions-for-data-domiciling**: Advanced geographic data controls

## Additional Resources

- CockroachDB Documentation: Locality-Aware Backups
- GDPR Official Text: Articles 44-49 (Data Transfers)
- CCPA Official Text: California Consumer Privacy Act
- HIPAA Security Rule: Administrative Safeguards
- CockroachDB Documentation: Multi-Region Capabilities
- Cloud Provider Compliance Documentation: AWS GDPR, GCP Compliance, Azure Trust Center
