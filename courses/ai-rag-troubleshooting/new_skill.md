---
name: resolve-clock-skew-issues
description: Diagnose and resolve clock synchronization issues between CockroachDB nodes that cause transaction errors and cluster instability
metadata:
  domain: Cluster Maintenance
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v25.2+
  status: stable
  related_skills:
    - monitor-cluster-health-during-maintenance
    - tune-failure-detection-and-recovery-settings
---

# Resolve Clock Skew Issues

**Domain**: Cluster Maintenance
**Bloom's Level**: Apply
**CockroachDB Version**: v25.2+

## What This Skill Teaches

This skill teaches you to diagnose and resolve clock synchronization problems in CockroachDB clusters. Clock skew occurs when node clocks drift apart beyond acceptable bounds, causing transaction failures, reduced performance, and potential data inconsistency. CockroachDB requires clocks to be synchronized within a 500ms maximum offset (default).

You'll learn to identify clock skew symptoms, diagnose root causes using monitoring tools, and apply fixes ranging from NTP configuration to cluster setting adjustments.

## Symptoms of Clock Skew

Common indicators of clock synchronization problems:

- **Transaction errors**: `uncertainty interval` or `clock skew detected` errors in application logs
- **Node instability**: Nodes repeatedly marked as suspect or dead
- **Increased latency**: Higher-than-normal P99 query latency
- **DB Console warnings**: Clock offset alerts on the Runtime dashboard

**Check current clock offsets**:
```sql
SELECT node_id, address,
       round(clock_offset_ns / 1000000.0, 2) as offset_ms
FROM crdb_internal.kv_node_status
ORDER BY abs(clock_offset_ns) DESC;
```

**Critical threshold**: Offsets > 400ms are dangerous; > 500ms causes node rejection.

## Diagnosing Clock Skew

### Step 1: Check Node Clock Offsets

```sql
-- View clock offsets across all nodes
SELECT node_id, address,
       clock_offset_ns / 1000000 as offset_ms,
       is_live, is_available
FROM crdb_internal.kv_node_status
ORDER BY abs(clock_offset_ns) DESC;
```

### Step 2: Check NTP Service Status

```bash
# On each node, verify NTP is running
ssh node1 "timedatectl status"

# Check NTP sync status
ssh node1 "chronyc tracking"
# or
ssh node1 "ntpq -p"
```

### Step 3: Check CockroachDB Maximum Clock Offset Setting

```sql
SHOW CLUSTER SETTING server.clock.max_offset;
-- Default: 500ms
```

## Fixing Clock Skew

### Fix 1: Configure NTP Properly

Ensure all nodes use the same NTP time source:

```bash
# Install and configure chrony (recommended)
sudo apt-get install -y chrony

# Edit /etc/chrony/chrony.conf
# Add reliable NTP servers:
# server time.google.com iburst
# server time.cloudflare.com iburst

# Restart chrony
sudo systemctl restart chrony

# Verify synchronization
chronyc tracking
```

### Fix 2: Force Time Sync

```bash
# Force immediate NTP synchronization
sudo chronyc -a makestep

# Verify the offset decreased
chronyc tracking | grep "System time"
```

### Fix 3: Adjust Maximum Clock Offset (Temporary)

```sql
-- Only if you understand the trade-offs
-- Increasing max_offset reduces transaction safety guarantees
SET CLUSTER SETTING server.clock.max_offset = '800ms';

-- After fixing NTP, restore default
SET CLUSTER SETTING server.clock.max_offset = '500ms';
```

**Warning**: Increasing `max_offset` trades consistency guarantees for availability. Only use as a temporary measure while fixing the underlying NTP issue.

## Best Practices

1. **Use Google Public NTP or Cloudflare NTP** for consistent time sources across cloud providers
2. **Monitor clock offsets** as part of standard cluster health checks
3. **Set up alerts** for clock offset > 300ms (warning) and > 400ms (critical)
4. **Use chrony over ntpd** for faster convergence after drift
5. **Test NTP configuration** before deploying new nodes
6. **Never manually set system time** on a running CockroachDB node
7. **Same time source for all nodes** prevents relative drift between nodes

## Related Skills

- **monitor-cluster-health-during-maintenance**: Track clock offsets during operations
- **tune-failure-detection-and-recovery-settings**: Adjust related timeout settings
