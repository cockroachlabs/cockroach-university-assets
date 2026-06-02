---
name: understand-full-backup-scope-and-contents
description: Explains what CockroachDB full backups capture including all data, metadata, schemas, and system tables. Use when user asks "what does a full backup include", "full backup contents", "what's in a backup", "backup scope", or wants to understand disaster recovery capabilities.
metadata:
  domain: Backup and Restore
  bloom_level: Understand
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Understand Full Backup Scope and Contents

## What This Skill Teaches

A CockroachDB full backup is a complete, self-contained snapshot of your entire cluster at a specific point in time. Understanding what's included helps you plan disaster recovery strategies and set appropriate backup schedules.

## What a Full Backup Captures

### 1. All User Data

**Tables and Rows**:
- Every row in every table across all user databases
- Data stored at the exact state when backup started
- Includes all column values and data types

**Multiple Databases**:
- All user-created databases
- All schemas within each database
- Cross-database references preserved

### 2. All Metadata and Schema

**Table Definitions**:
- CREATE TABLE statements
- Column definitions and types
- Default values and computed columns

**Indexes**:
- Primary key indexes
- Secondary indexes
- Partial indexes
- Covering indexes (STORING clause)

**Constraints**:
- PRIMARY KEY constraints
- FOREIGN KEY relationships
- UNIQUE constraints
- CHECK constraints
- NOT NULL constraints

### 3. Security and Access Control

**Users and Roles**:
- All user accounts
- Role definitions
- Role memberships

**Permissions**:
- GRANT statements for databases
- GRANT statements for tables
- GRANT statements for schemas
- Object ownership

### 4. System Tables and Configuration

**Zone Configurations**:
- Replication factor settings
- Placement constraints
- Leaseholder preferences
- GC TTL settings

**Cluster Settings** (partial):
- Some cluster-wide settings
- Database-specific settings
- Table-level settings

**Descriptors**:
- Internal table descriptors
- Database descriptors
- Schema descriptors

**Job History**:
- Previous backup jobs
- Schema change history
- Import/export job records

### 5. What's NOT Included

**Excluded from backups**:
- Temporary tables (created with CREATE TEMP TABLE)
- Active connections and sessions
- In-flight transactions
- Node-specific configurations
- TLS certificates
- Encryption keys (store separately)

**Cluster-level exclusions**:
- Node binary versions
- Node addresses and topology
- Store paths
- Runtime metrics and statistics

## Why This Matters

### Self-Contained Recovery

Full backups are **self-contained** - you can restore from a full backup alone without any dependencies:

```sql
-- No prerequisites needed, just restore
RESTORE FROM LATEST IN 'nodelocal://1/backups/full';
```

Unlike incremental backups which require the full backup chain, a full backup is the complete foundation.

### Disaster Recovery Foundation

Full backups enable:
- **Complete cluster rebuild** after catastrophic failure
- **Migration to new infrastructure** (different cloud, region, hardware)
- **Cluster cloning** for testing or development
- **Compliance and auditing** requirements

### Point-in-Time Consistency

All data in a full backup reflects the cluster state at a **single consistent timestamp**:
- No partial transactions
- All foreign key relationships intact
- All constraints satisfied
- Cross-table consistency guaranteed

## Common Use Cases

### Use Case 1: Disaster Recovery

**Scenario**: Data center failure, complete cluster loss

**What the backup provides**:
- All application data to restore service
- User accounts to restore access
- Permissions to maintain security
- Complete schema to rebuild functionality

**Recovery**: Deploy new cluster, restore full backup, service restored

### Use Case 2: Cluster Migration

**Scenario**: Moving from on-prem to cloud, or cloud provider migration

**What the backup provides**:
- Complete cluster state
- No data left behind
- No manual schema recreation needed
- No permission re-configuration

**Migration**: Backup from old cluster → Restore to new cluster → Update app connection strings

### Use Case 3: Compliance and Archival

**Scenario**: Regulatory requirement to retain data for 7 years

**What the backup provides**:
- Complete data snapshot at point in time
- Immutable record for audits
- Can restore years later for investigation
- Proves data retention compliance

## Backup Size Considerations

Full backup size equals:
- **Total row data** across all tables
- **Index data** (secondary indexes add storage)
- **System table data** (usually small)
- **Metadata overhead** (minimal)

**Example sizing**:
```
Database size: 100 GB
Indexes: 20 GB (20% overhead typical)
System tables: 500 MB
Full backup size: ~120 GB
```

**Planning tip**: Add 20-30% to your data size for indexes and overhead.

## Consistency Guarantees

### Transactional Consistency

Full backups use CockroachDB's MVCC (Multi-Version Concurrency Control):

- Backup reads from a consistent snapshot
- No locks on tables during backup
- Applications continue running normally
- Zero downtime for backup operations

### AS OF SYSTEM TIME

Backups can specify exact timestamp:

```sql
-- Backup as of 10 seconds ago (recommended)
BACKUP INTO 'nodelocal://1/backups' AS OF SYSTEM TIME '-10s';
```

**Why 10 seconds ago**:
- Avoids active transactions
- Ensures data already committed
- Prevents lock conflicts
- Standard best practice

## Backup Chain Foundation

Full backups serve as the **base** of a backup chain:

```
Timeline:
[Full Backup] ────> [Incremental 1] ────> [Incremental 2]
   (base)           (changes only)        (changes only)
```

**Restore sequence**:
1. Restore full backup first
2. Apply incremental 1
3. Apply incremental 2
4. Data now at incremental 2 timestamp

## Storage Considerations

### Destination Options

Full backups support multiple storage backends:

**Cloud Storage**:
- Amazon S3: `s3://bucket/path`
- Google Cloud Storage: `gs://bucket/path`
- Azure Blob Storage: `azure://container/path`

**Local Storage** (testing only):
- Node-local: `nodelocal://1/path`
- External volumes: `nodelocal://self/path`

**Best practice**: Use cloud storage for production, node-local for testing

### Retention Planning

Typical retention strategy:
- Keep daily full backups for 7 days
- Keep weekly full backups for 4 weeks
- Keep monthly full backups for 12 months

**Example schedule**:
- Daily incrementals (small, frequent)
- Weekly full backups (restore foundation)
- Monthly full backups (long-term archive)

## Comparison: Full vs Incremental

| Aspect | Full Backup | Incremental Backup |
|--------|-------------|-------------------|
| **Size** | Large (all data) | Small (changes only) |
| **Duration** | Longer (hours for TB) | Shorter (minutes) |
| **Restore Speed** | Fast (one operation) | Slower (chain restore) |
| **Storage Cost** | Higher | Lower |
| **Independence** | Self-contained | Requires full backup |
| **Best For** | DR foundation | Frequent RPO |

## Key Takeaways

1. **Complete Snapshot**: Full backups capture everything needed to rebuild your cluster
2. **Self-Contained**: No dependencies on other backups
3. **Consistent**: All data from single point in time
4. **Foundation**: Required base for incremental backup chains
5. **Disaster Recovery**: Essential for complete cluster recovery
6. **Size Planning**: Expect ~120-130% of your data size

## Next Steps

- Learn about **incremental backups** to reduce storage and frequency
- Explore **backup schedules** to automate full and incremental backups
- Study **restore procedures** to recover from full backups
- Plan **retention policies** balancing cost and recovery requirements

## Related Skills

- `understand-incremental-backup-concepts` - Learn about incremental backups
- `execute-cluster-level-full-backups` - Create full backups
- `restore-database-from-backup` - Restore from backups
