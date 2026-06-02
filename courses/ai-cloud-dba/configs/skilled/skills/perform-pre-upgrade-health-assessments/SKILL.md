---
name: perform-pre-upgrade-health-assessments
description: Validate upgrade readiness using cockroach node status, SHOW JOBS, checking for under-replicated/unavailable ranges, and reviewing release notes. Use when user asks "pre-upgrade checks", "validate before upgrade", "upgrade readiness", or "health check before upgrade".
metadata:
  domain: Cluster Maintenance
  bloom_level: Analyze
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Perform Pre-Upgrade Health Assessments

## What This Skill Teaches

Before upgrading CockroachDB, you must validate that your cluster is healthy and ready for the upgrade process. This skill covers comprehensive pre-upgrade health checks to minimize risk and ensure a smooth upgrade.

## Why Pre-Upgrade Checks Matter

### Prevent Upgrade Failures

**Starting upgrade with issues**:
- Under-replicated ranges → Data loss risk during upgrade
- Running schema changes → Lock conflicts, failures
- Unhealthy nodes → Quorum loss during upgrade
- Resource exhaustion → Node failures during upgrade

**Pre-checks prevent**:
- Failed upgrades requiring rollback
- Extended downtime
- Data unavailability
- Emergency troubleshooting

### Establish Baseline

**Document current state**:
- Node versions and health
- Replication status
- Running jobs
- Resource utilization

**Benefits**:
- Know what "normal" looks like
- Detect upgrade-related changes
- Troubleshoot issues faster

## Complete Pre-Upgrade Checklist

### 1. All Nodes Alive and Healthy

**Check**: Verify all nodes are live and available

```bash
cockroach node status --certs-dir=certs
```

**Expected output**:
```
  id |     address     |  build    | is_live | is_available
-----+-----------------+-----------+---------+--------------
   1 | 10.0.0.1:26257  | v25.2.5   | true    | true
   2 | 10.0.0.2:26257  | v25.2.5   | true    | true
   3 | 10.0.0.3:26257  | v25.2.5   | true    | true
```

**Requirements**:
- ✅ All nodes show `is_live = true`
- ✅ All nodes show `is_available = true`
- ✅ All nodes on same version
- ❌ FAIL if any node dead or unavailable

**Action if fails**: Investigate and fix dead nodes before upgrading

### 2. No Under-Replicated Ranges

**Check**: Ensure all ranges have sufficient replicas

```sql
SELECT count(*) FROM crdb_internal.ranges
WHERE array_length(replicas, 1) < 3;
```

**Expected result**: `0`

**Alternative check**:
```sql
SHOW RANGES FROM DATABASE system;

-- Check replicas column
-- All should show 3 or more replicas
```

**Requirements**:
- ✅ Zero under-replicated ranges
- ❌ FAIL if any under-replicated

**Action if fails**:
- Investigate why ranges under-replicated
- Add nodes if cluster undersized
- Wait for replication to complete
- Recheck before upgrading

### 3. No Unavailable Ranges

**Check**: Verify no ranges are unavailable

```sql
SELECT count(*) FROM crdb_internal.ranges
WHERE unavailable = true;
```

**Expected result**: `0`

**More detailed check**:
```sql
SELECT range_id, start_key, end_key, replicas
FROM crdb_internal.ranges
WHERE unavailable = true;
```

**Requirements**:
- ✅ Zero unavailable ranges
- ❌ FAIL if any unavailable

**Action if fails**:
- **CRITICAL**: Do not upgrade with unavailable ranges
- Indicates serious cluster health issue
- Troubleshoot and resolve before upgrading

### 4. No Running Schema Changes

**Check**: Ensure no schema changes in progress

```sql
SHOW JOBS;
```

**Filter for schema changes**:
```sql
SELECT job_id, job_type, status, description
FROM [SHOW JOBS]
WHERE job_type IN ('SCHEMA CHANGE', 'NEW SCHEMA CHANGE')
  AND status IN ('running', 'pending');
```

**Expected result**: Empty (no running/pending schema changes)

**Requirements**:
- ✅ No running CREATE INDEX
- ✅ No running ALTER TABLE
- ✅ No running schema migrations
- ❌ FAIL if any schema changes running

**Action if fails**:
- Wait for schema changes to complete
- Or cancel if safe to do so: `CANCEL JOB <job_id>`
- Recheck before upgrading

### 5. Adequate Disk Space

**Check**: Verify sufficient free disk on all nodes

```bash
# On each node
df -h /path/to/cockroach/store
```

**Requirements**:
- ✅ At least 25% free disk space
- ✅ More is better (50%+ ideal)
- ❌ FAIL if <10% free

**Why it matters**:
- Upgrades may trigger rebalancing
- Snapshots consume temporary space
- Low disk can cause node failures

**Action if fails**:
- Free up disk space
- Add more storage
- Or add more nodes to distribute data

### 6. Stable CPU and Memory

**Check**: Monitor resource utilization

```bash
# Check CPU usage
top

# Check memory
free -h

# Or use cockroach node status
cockroach node status --certs-dir=certs --format=table
```

**Requirements**:
- ✅ CPU <70% average
- ✅ Memory <80% used
- ❌ FAIL if resources maxed out

**Action if fails**:
- Upgrade during low-traffic period
- Scale cluster before upgrading
- Optimize queries reducing load

### 7. Review Release Notes

**Check**: Read release notes for target version

**URL format**:
```
https://www.cockroachlabs.com/docs/releases/v26.1
```

**Look for**:
- **Breaking changes**: Require application changes?
- **Deprecated features**: Using any deprecated features?
- **Known issues**: Any affecting your use case?
- **New requirements**: OS, hardware, configuration changes?

**Requirements**:
- ✅ No breaking changes affecting you
- ✅ No deprecated features you rely on
- ✅ No blockers in known issues

**Action if issues found**:
- Plan application updates
- Test in staging first
- Consider waiting for patch release

### 8. Backup Current State

**Check**: Recent valid backup exists

```sql
SHOW BACKUPS IN 'nodelocal://1/backups/production';
```

**Requirements**:
- ✅ Backup taken within last 24 hours
- ✅ Backup tested and verified
- ✅ Can restore if upgrade fails

**Action**:
```sql
-- Create pre-upgrade backup
BACKUP INTO 'nodelocal://1/backups/pre-upgrade-v26.1'
  AS OF SYSTEM TIME '-10s';
```

### 9. Test in Staging/Development

**Check**: Upgraded staging cluster successfully?

**Requirements**:
- ✅ Staging upgrade completed without issues
- ✅ Application tested against new version
- ✅ Performance validated
- ✅ No unexpected behavior

**Action if no staging**:
- Consider creating staging environment
- Or perform extra production validation
- Document rollback procedure

### 10. Verify Load Balancer Configuration

**Check**: Load balancer health checks working

```bash
# Test health endpoint
curl https://node1:8080/health?ready=1

# Should return 200 OK
```

**Requirements**:
- ✅ Health checks configured
- ✅ Returning correct status
- ✅ Will detect drained nodes

**Why it matters**:
- During upgrade, nodes will drain
- Load balancer should route traffic away
- Prevents connection errors

## Using cockroach debug doctor

### Comprehensive Health Check

**Command**:
```bash
cockroach debug doctor examine cluster --certs-dir=certs
```

**What it checks**:
- Descriptor consistency
- Zone configuration validity
- Orphaned table descriptors
- Invalid foreign key references
- Replication issues

**Expected output**: No errors

**Example output**:
```
Examining 156 descriptors and 42 namespace entries...
Examining 2456 jobs...
No problems found!
```

**If issues found**:
```
ERROR: descriptor 52 (table "users"): invalid foreign key reference
ERROR: orphaned descriptor 73

2 problems found
```

**Action**: Resolve all problems before upgrading

## Pre-Upgrade Health Script

### Automated Check Script

```bash
#!/bin/bash
# pre-upgrade-health-check.sh

COCKROACH="/usr/local/bin/cockroach"
CERTS_DIR="/path/to/certs"
ERRORS=0

echo "=== CockroachDB Pre-Upgrade Health Check ==="
echo ""

# 1. Node status
echo "Checking node status..."
DEAD_NODES=$($COCKROACH node status --certs-dir=$CERTS_DIR --format=csv | \
  tail -n +2 | grep -c ",false,")
if [ $DEAD_NODES -gt 0 ]; then
  echo "❌ FAIL: $DEAD_NODES dead nodes found"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASS: All nodes alive"
fi

# 2. Under-replicated ranges
echo "Checking for under-replicated ranges..."
UNDER_REP=$($COCKROACH sql --certs-dir=$CERTS_DIR --format=csv --execute="
  SELECT count(*) FROM crdb_internal.ranges
  WHERE array_length(replicas, 1) < 3;" | tail -n 1)
if [ "$UNDER_REP" != "0" ]; then
  echo "❌ FAIL: $UNDER_REP under-replicated ranges"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASS: No under-replicated ranges"
fi

# 3. Unavailable ranges
echo "Checking for unavailable ranges..."
UNAVAIL=$($COCKROACH sql --certs-dir=$CERTS_DIR --format=csv --execute="
  SELECT count(*) FROM crdb_internal.ranges
  WHERE unavailable = true;" | tail -n 1)
if [ "$UNAVAIL" != "0" ]; then
  echo "❌ FAIL: $UNAVAIL unavailable ranges"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASS: No unavailable ranges"
fi

# 4. Running schema changes
echo "Checking for running schema changes..."
SCHEMA_JOBS=$($COCKROACH sql --certs-dir=$CERTS_DIR --format=csv --execute="
  SELECT count(*) FROM [SHOW JOBS]
  WHERE job_type IN ('SCHEMA CHANGE', 'NEW SCHEMA CHANGE')
    AND status IN ('running', 'pending');" | tail -n 1)
if [ "$SCHEMA_JOBS" != "0" ]; then
  echo "❌ FAIL: $SCHEMA_JOBS running schema changes"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASS: No running schema changes"
fi

# Summary
echo ""
echo "=== Summary ==="
if [ $ERRORS -eq 0 ]; then
  echo "✅ Cluster ready for upgrade!"
  exit 0
else
  echo "❌ $ERRORS issues found - resolve before upgrading"
  exit 1
fi
```

## Version-Specific Checks

### Check Current Version

```bash
cockroach node status --certs-dir=certs --format=csv | \
  tail -n +2 | cut -d',' -f4 | sort -u
```

**Should show**: Single version (all nodes same)

**Example**: `v25.2.5`

### Verify Upgrade Path

**Supported upgrade paths** (check release notes):
- Patch: v26.1.1 → v26.1.3 ✅
- Minor: v26.1 → v26.2 ✅
- Major: v25.2 → v26.1 ✅
- Skip minor: v26.1 → v26.3 ❌ (must go through v26.2)
- Skip major: v24.2 → v26.1 ❌ (must go through v25.x)

## Common Pre-Upgrade Issues

### Issue 1: Under-Replicated Ranges

**Symptom**: Count > 0 from under-replicated query

**Common causes**:
- Recent node addition (still rebalancing)
- Dead node (replicas not recovered yet)
- Insufficient nodes for replication factor

**Solution**:
```sql
-- Check replication factor
SHOW ZONE CONFIGURATIONS;

-- If 3-node cluster with RF=5, change RF to 3
ALTER RANGE default CONFIGURE ZONE USING num_replicas = 3;
```

### Issue 2: Long-Running Schema Changes

**Symptom**: SHOW JOBS shows running schema change for hours

**Solution**:
```sql
-- Check progress
SELECT job_id, fraction_completed, description
FROM [SHOW JOBS]
WHERE job_type = 'NEW SCHEMA CHANGE';

-- If safe, cancel
CANCEL JOB <job_id>;

-- Or wait for completion
```

### Issue 3: Disk Space Low

**Symptom**: df shows >90% disk usage

**Solution**:
```bash
# Clean up logs
rm -f /var/log/cockroach/*.log.*

# Increase disk size
# Or add nodes to distribute data
```

## Best Practices

1. **Run checks 24-48 hours before upgrade** - time to fix issues
2. **Document all check results** - baseline for comparison
3. **Fix all issues before starting** - don't upgrade unhealthy cluster
4. **Use automated script** - ensures consistency
5. **Check twice** - right before upgrade starts
6. **Have rollback plan** - if issues discovered during upgrade
7. **Test in staging first** - catch version-specific issues

## Checklist Summary

Before upgrading, confirm:

- [ ] All nodes alive (`cockroach node status`)
- [ ] No under-replicated ranges (count = 0)
- [ ] No unavailable ranges (count = 0)
- [ ] No running schema changes (`SHOW JOBS`)
- [ ] Adequate disk space (>25% free)
- [ ] Stable CPU/memory (<70% CPU, <80% memory)
- [ ] Release notes reviewed
- [ ] Recent backup exists and validated
- [ ] Tested in staging environment
- [ ] Load balancer health checks working
- [ ] `cockroach debug doctor` shows no issues

**All checks pass?** ✅ Proceed with upgrade

**Any checks fail?** ❌ Fix issues first

## Key Takeaways

1. **Never skip pre-upgrade checks** - prevents failures
2. **All nodes must be healthy** - dead nodes block upgrades
3. **Zero under-replicated/unavailable ranges** - requirement
4. **No running schema changes** - avoid conflicts
5. **Adequate resources** - disk, CPU, memory headroom
6. **Review release notes** - know what's changing
7. **Test in staging** - catch issues early
8. **Automate checks** - ensure nothing missed

## Related Skills

- `perform-rolling-upgrades` - Execute upgrade after health checks
- `download-and-stage-new-cockroachdb-binaries` - Prepare binaries
- `perform-rolling-major-version-upgrades` - Upgrade execution
- `handle-upgrade-failures` - Recover from issues
- `verify-cluster-after-node-removal` - Post-upgrade validation
