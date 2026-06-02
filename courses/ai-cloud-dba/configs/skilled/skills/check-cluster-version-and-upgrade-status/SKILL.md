---
name: check-cluster-version-and-upgrade-status
description: Check cluster version and upgrade status using version queries, cluster settings, and internal tables to monitor upgrade progress and verify version states
metadata:
  domain: Cluster Management
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
  test_environment: CockroachDB v26.1.0 localhost:26258
---

# Check Cluster Version and Upgrade Status

**Domain**: Cluster Management
**Bloom's Level**: Apply

## What This Skill Teaches

This skill teaches you how to check the current cluster version and monitor upgrade status in CockroachDB. You'll learn to use multiple methods to verify version information, understand the difference between binary version and active cluster version, interpret upgrade progress indicators, and recognize different version states during the upgrade lifecycle.

Understanding version status is critical for safe cluster operations. The active cluster version determines which features are available and controls backward compatibility behavior. During upgrades, monitoring version status helps you verify progress and identify when finalization has occurred.

## Prerequisites

- Access to CockroachDB cluster with SQL client
- Basic understanding of CockroachDB upgrade process
- Familiarity with cluster settings concept

## Core Concepts

### Version Types

**Binary Version**: The version of the CockroachDB executable installed on each node. This is the physical software version running the process.

**Active Cluster Version**: The logical version that controls feature availability and compatibility behavior across the cluster. This version is stored as a cluster setting.

**Node Build Info**: Detailed build metadata including version, platform, timestamp, and build type for each node.

During normal operations, binary version and active cluster version match. During upgrades, binaries are updated first while the active version remains at the previous version until finalization.

### Version States

**Pre-Upgrade**: All nodes run the same binary version, active cluster version matches binary version.

**During Upgrade**: Nodes run mixed binary versions (old and new), active cluster version remains at old version to maintain compatibility.

**Post-Upgrade (Pre-Finalization)**: All nodes run new binary version, active cluster version still at old version if downgrade option is set.

**Finalized**: All nodes run new binary version, active cluster version updated to match new version, new features activated.

## Instructions

### Check Active Cluster Version

The primary method to check the active cluster version:

```sql
-- Show the active cluster version
SHOW CLUSTER SETTING version;
```

Example output:
```
  version
-----------
  26.1
```

This returns the currently active version that controls feature behavior. This may differ from binary versions during upgrades.

### Check Binary Version (All Nodes)

To see the actual binary version running on each node:

```sql
-- Using the version() function
SELECT version();

-- Example output:
-- CockroachDB CCL v26.1.0 (x86_64-apple-darwin21.6.0, built 2025/01/15 18:23:45, go1.22.5 X:nocoverageredesign)
```

For detailed build information across all nodes:

```sql
-- Query node build info from internal table
SELECT
    node_id,
    field,
    value
FROM crdb_internal.node_build_info
WHERE field IN ('Version', 'Build', 'Distribution', 'Platform')
ORDER BY node_id, field;
```

Example output:
```
  node_id | field        | value
----------+--------------+------------------------------------------------
  1       | Build        | 2025/01/15 18:23:45
  1       | Distribution | CCL
  1       | Platform     | x86_64-apple-darwin21.6.0
  1       | Version      | v26.1.0
  2       | Build        | 2025/01/15 18:23:45
  2       | Distribution | CCL
  2       | Platform     | x86_64-apple-darwin21.6.0
  2       | Version      | v26.1.0
```

### Check for Version Mismatch

Identify nodes running different binary versions (indicates upgrade in progress):

```sql
-- Find nodes with different versions
WITH version_summary AS (
    SELECT
        node_id,
        value AS version
    FROM crdb_internal.node_build_info
    WHERE field = 'Version'
)
SELECT
    version,
    count(*) AS node_count,
    array_agg(node_id ORDER BY node_id) AS nodes
FROM version_summary
GROUP BY version
ORDER BY version;
```

Example output during rolling upgrade:
```
  version  | node_count | nodes
-----------+------------+--------
  v26.0.0  | 2          | {1,2}
  v26.1.0  | 2          | {3,4}
```

### Check Downgrade Option Status

The preserve downgrade option prevents automatic finalization:

```sql
-- Check if downgrade option is set
SHOW CLUSTER SETTING cluster.preserve_downgrade_option;
```

Possible values:
- `<version>` (e.g., "26.0"): Finalization is blocked at this version
- Empty string: Auto-finalization is enabled (default)

### Comprehensive Version Status Check

Combined query showing all version-related information:

```sql
-- Complete version status overview
WITH active_version AS (
    SELECT value AS cluster_version
    FROM [SHOW CLUSTER SETTING version]
),
downgrade_option AS (
    SELECT value AS preserve_downgrade
    FROM [SHOW CLUSTER SETTING cluster.preserve_downgrade_option]
),
node_versions AS (
    SELECT
        value AS binary_version,
        count(*) AS node_count
    FROM crdb_internal.node_build_info
    WHERE field = 'Version'
    GROUP BY value
)
SELECT
    av.cluster_version,
    do.preserve_downgrade,
    nv.binary_version,
    nv.node_count,
    CASE
        WHEN av.cluster_version = nv.binary_version AND nv.node_count = (SELECT count(DISTINCT node_id) FROM crdb_internal.node_build_info)
            THEN 'Stable (finalized)'
        WHEN do.preserve_downgrade != ''
            THEN 'Upgrade complete (awaiting finalization)'
        WHEN nv.node_count < (SELECT count(DISTINCT node_id) FROM crdb_internal.node_build_info)
            THEN 'Upgrade in progress (mixed versions)'
        ELSE 'Check required'
    END AS upgrade_status
FROM active_version av
CROSS JOIN downgrade_option do
CROSS JOIN node_versions nv;
```

### Monitor Upgrade Progress

Track which nodes have been upgraded:

```sql
-- Show upgrade progress across nodes
SELECT
    nbi.node_id,
    nbi.value AS binary_version,
    n.address,
    n.attrs,
    CASE
        WHEN nbi.value = (
            SELECT value
            FROM [SHOW CLUSTER SETTING version]
        ) THEN 'Finalized version'
        WHEN nbi.value > (
            SELECT value
            FROM [SHOW CLUSTER SETTING version]
        ) THEN 'Newer binary (not finalized)'
        ELSE 'Older binary (needs upgrade)'
    END AS version_status
FROM crdb_internal.node_build_info nbi
JOIN crdb_internal.gossip_nodes n ON nbi.node_id = n.node_id
WHERE nbi.field = 'Version'
ORDER BY nbi.node_id;
```

## Common Patterns

### Pre-Upgrade Verification

Before starting an upgrade, document current state:

```sql
-- Document pre-upgrade state
SHOW CLUSTER SETTING version;
SHOW CLUSTER SETTING cluster.preserve_downgrade_option;
SELECT node_id, value FROM crdb_internal.node_build_info WHERE field = 'Version';
```

### During Rolling Upgrade

Monitor progress as nodes are upgraded:

```sql
-- Quick check: count nodes by version
SELECT
    value AS version,
    count(*) AS nodes
FROM crdb_internal.node_build_info
WHERE field = 'Version'
GROUP BY value;
```

### Post-Upgrade Verification

Confirm all nodes run new binary before considering finalization:

```sql
-- Verify uniform version across all nodes
SELECT
    count(DISTINCT value) AS distinct_versions,
    max(value) AS highest_version,
    count(*) AS total_nodes
FROM crdb_internal.node_build_info
WHERE field = 'Version';
```

Expected: `distinct_versions = 1` confirms all nodes match.

### Finalization Status Check

After finalization (automatic or manual):

```sql
-- Verify finalization completed
SELECT
    (SELECT value FROM [SHOW CLUSTER SETTING version]) AS cluster_version,
    (SELECT max(value) FROM crdb_internal.node_build_info WHERE field = 'Version') AS binary_version,
    (SELECT value FROM [SHOW CLUSTER SETTING cluster.preserve_downgrade_option]) AS downgrade_option;
```

Finalized state: cluster_version matches binary_version, downgrade_option is empty.

## Common Mistakes

### Confusing Binary and Cluster Versions

**Mistake**: Assuming new features are available immediately after upgrading node binaries.

**Reality**: Features are gated by the active cluster version, not binary version. Until finalization occurs, the cluster operates with the previous version's feature set even if all binaries are upgraded.

**Solution**: Always check both binary versions and active cluster version. Understand that finalization is required to activate new version features.

### Ignoring Version Mismatch During Upgrade

**Mistake**: Not monitoring node versions during rolling upgrade, leading to prolonged mixed-version states.

**Reality**: CockroachDB supports mixed versions during rolling upgrades, but this is a temporary state. Extended mixed-version operation can impact performance and functionality.

**Solution**: Regularly check version distribution during upgrades. Complete the rolling upgrade promptly to minimize mixed-version duration.

### Misinterpreting Empty Downgrade Option

**Mistake**: Assuming empty `preserve_downgrade_option` means finalization hasn't occurred.

**Reality**: Empty downgrade option is the normal state after finalization (or when never set). It indicates auto-finalization is enabled, not that finalization is pending.

**Solution**: Compare active cluster version with binary versions to determine finalization status, not just downgrade option setting.

### Not Checking All Nodes

**Mistake**: Querying `version()` function on a single connection and assuming it represents the entire cluster.

**Reality**: The `version()` function returns information for the specific node serving the connection. Other nodes may run different versions.

**Solution**: Always query `crdb_internal.node_build_info` to see all nodes. Use aggregation to detect mismatches.

## Troubleshooting

### Active Version Doesn't Match Binary Version

**Symptom**: All nodes report binary version 26.1.0 but cluster version shows 26.0.

**Diagnosis**:
```sql
SHOW CLUSTER SETTING cluster.preserve_downgrade_option;
```

**Cause**: Downgrade option is set, preventing automatic finalization.

**Resolution**: This is expected if you set preserve downgrade option before upgrade. Clear it to enable finalization (covered in related skills).

### Version Query Returns Unexpected Format

**Symptom**: Version queries return values like "26.1-upgrading-to-26.2" or similar.

**Diagnosis**: This indicates an internal migration state.

**Cause**: Cluster is in the process of finalizing. Some internal upgrades use temporary version markers.

**Resolution**: Wait for finalization to complete. If stuck, check logs for migration errors.

### Node Build Info Shows No Results

**Symptom**: `crdb_internal.node_build_info` returns empty result set.

**Diagnosis**:
```sql
SELECT count(*) FROM crdb_internal.gossip_nodes;
```

**Cause**: Gossip network issue or node connectivity problem.

**Resolution**: Check node logs for gossip errors. Verify network connectivity between nodes. Ensure all nodes are running and joined to cluster.

### Different Nodes Report Different Active Versions

**Symptom**: Same query shows different cluster version on different nodes.

**Diagnosis**: Check cluster setting propagation:
```sql
SELECT node_id, variable, value
FROM crdb_internal.node_settings
WHERE variable = 'version';
```

**Cause**: Severe cluster inconsistency or catastrophic failure scenario.

**Resolution**: This indicates a serious problem. Check cluster health immediately. Review logs for errors. Contact support if issue persists.

## Best Practices

1. **Regular Version Checks**: Include version checks in routine cluster health monitoring
2. **Pre-Upgrade Documentation**: Record all version information before starting upgrades
3. **Aggregate Node Data**: Always query all nodes, never rely on single-node information
4. **Monitor During Upgrades**: Check version distribution regularly during rolling upgrades
5. **Verify Before Finalization**: Confirm all nodes run uniform binary version before finalizing
6. **Understand Version Lifecycle**: Know the difference between binary upgrades and cluster version finalization
7. **Automate Monitoring**: Create scripts or alerts for version mismatch detection
8. **Check After Finalization**: Verify both cluster version and downgrade option after finalization completes

## Related Skills

- `finalize-cluster-version-after-upgrade`: Complete version finalization process
- `set-downgrade-option-to-prevent-auto-finalization`: Control finalization timing
- `perform-rolling-upgrade-of-cockroachdb-cluster`: Execute cluster upgrades
- `verify-cluster-health-between-restarts`: Health checks during maintenance
- `monitor-cluster-health-metrics`: Comprehensive cluster monitoring

## References

- [CockroachDB Upgrade Documentation](https://www.cockroachlabs.com/docs/stable/upgrade-cockroach-version.html)
- [Cluster Settings Reference](https://www.cockroachlabs.com/docs/stable/cluster-settings.html)
- [Internal Tables Reference](https://www.cockroachlabs.com/docs/stable/crdb-internal.html)
- [Version Compatibility](https://www.cockroachlabs.com/docs/stable/upgrade-cockroach-version.html#version-compatibility)

## Notes

- Binary versions during rolling upgrades must be within one major version
- Active cluster version always represents a finalized version state
- Some advanced features may require specific binary AND cluster version combinations
- Version checks require no special permissions (available to all users)
- Cluster version cannot be downgraded after finalization (only through restore/backup)
