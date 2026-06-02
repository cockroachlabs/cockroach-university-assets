# Monitor Decommission Progress

**Skill ID**: monitor-decommission-progress
**Domain**: Cluster Maintenance
**Bloom's Level**: Evaluate
**Version**: 1.0.0
**CockroachDB Compatibility**: v26.1.0+

---

## Description

Monitor and track the progress of node decommissioning in real-time, estimate completion time, and identify issues during the decommission process. Effective monitoring prevents surprises and enables proactive intervention when problems occur.

---

## Why This Matters

Monitoring decommission progress is critical:

- **Time Planning**: Know when decommission will complete
- **Early Detection**: Identify stalled or stuck decommissioning
- **Resource Visibility**: Track data movement across cluster
- **Problem Prevention**: Catch issues before they become critical
- **Communication**: Inform stakeholders of progress and ETA

Without monitoring:
- Unknown completion time (hours of uncertainty)
- Missed stalls requiring intervention
- No visibility into replica movement
- Cannot plan subsequent operations

---

## Key Metrics to Monitor

### Replica Count
**Most Important**: Number of replicas remaining on decommissioning node
- Target: 0
- Direction: Decreasing
- Rate: Varies (10-100 replicas/minute typical)

### Decommission State
- `decommissioning`: Should be `true`
- `is_live`: Should remain `true` during decommission
- `is_available`: May transition to `false`

### Cluster Health
- Under-replicated ranges: Should be 0
- Ranges with errors: Should be 0
- Other nodes: Should show increasing replica counts

---

## Basic Monitoring

### Watch Node Status

```bash
# Continuous monitoring with watch
watch -n 30 'cockroach node status --host=localhost:26257 --certs-dir=certs'

# Focus on decommissioning node (ID 4)
watch -n 30 'cockroach node status --host=localhost:26257 --certs-dir=certs | grep "^  4"'
```

---

### Manual Status Checks

```bash
# Check current status
cockroach node status --host=localhost:26257 --certs-dir=certs | grep "^  4"

# Output:
#  4 | node4:26257 | v26.1.0 | true | true | true | 523  ← Check replicas column
```

---

## Advanced Monitoring

### Track Replica Movement Rate

```bash
#!/bin/bash
# Calculate replica movement rate

NODE_ID=4
HOST="localhost:26257"
CERTS_DIR="certs"

# Get initial count
INITIAL=$(cockroach sql --host=$HOST --certs-dir=$CERTS_DIR --execute="
  SET allow_unsafe_internals = true;
  SELECT count(*) FROM (SELECT unnest(replicas) AS node_id FROM crdb_internal.ranges) WHERE node_id = $NODE_ID;
" --format=csv | tail -1)

echo "Initial replicas: $INITIAL at $(date +%T)"

# Wait 5 minutes
sleep 300

# Get current count
CURRENT=$(cockroach sql --host=$HOST --certs-dir=$CERTS_DIR --execute="
  SET allow_unsafe_internals = true;
  SELECT count(*) FROM (SELECT unnest(replicas) AS node_id FROM crdb_internal.ranges) WHERE node_id = $NODE_ID;
" --format=csv | tail -1)

MOVED=$((INITIAL - CURRENT))
RATE=$(echo "scale=2; $MOVED / 5" | bc)

echo "Current replicas: $CURRENT at $(date +%T)"
echo "Moved: $MOVED replicas in 5 minutes"
echo "Rate: $RATE replicas/minute"

if [ "$MOVED" -gt 0 ]; then
  REMAINING_MIN=$(echo "scale=0; $CURRENT / $RATE" | bc)
  echo "Estimated time remaining: $REMAINING_MIN minutes"
fi
```

---

### Monitor Cluster-Wide Distribution

```sql
-- See how replicas are redistributing
SET allow_unsafe_internals = true;

SELECT
  node_id,
  count(*) AS replica_count
FROM (
  SELECT unnest(replicas) AS node_id
  FROM crdb_internal.ranges
) AS r
GROUP BY node_id
ORDER BY node_id;
```

**Expected**: Decommissioning node count decreasing, others increasing.

---

## Continuous Monitoring Script

```bash
#!/bin/bash
# Comprehensive decommission monitoring

NODE_ID=4
HOST="localhost:26257"
CERTS_DIR="certs"
LOG_FILE="decommission_$NODE_ID.log"

echo "Starting decommission monitoring for node $NODE_ID" | tee $LOG_FILE
echo "Start time: $(date)" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

LAST_REPLICAS=0

while true; do
  # Get current status
  REPLICAS=$(cockroach sql --host=$HOST --certs-dir=$CERTS_DIR --execute="
    SET allow_unsafe_internals = true;
    SELECT count(*) FROM (SELECT unnest(replicas) AS node_id FROM crdb_internal.ranges) WHERE node_id = $NODE_ID;
  " --format=csv 2>/dev/null | tail -1)

  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

  # Check if completed
  if [ "$REPLICAS" -eq 0 ]; then
    echo "[$TIMESTAMP] ✅ Decommission COMPLETE" | tee -a $LOG_FILE
    break
  fi

  # Calculate delta
  if [ "$LAST_REPLICAS" -ne 0 ]; then
    DELTA=$((LAST_REPLICAS - REPLICAS))
    echo "[$TIMESTAMP] Replicas: $REPLICAS (moved $DELTA in last minute)" | tee -a $LOG_FILE
  else
    echo "[$TIMESTAMP] Replicas: $REPLICAS" | tee -a $LOG_FILE
  fi

  # Check for stall
  if [ "$LAST_REPLICAS" -eq "$REPLICAS" ] && [ "$LAST_REPLICAS" -ne 0 ]; then
    echo "[$TIMESTAMP] ⚠️  WARNING: No progress in last minute" | tee -a $LOG_FILE
  fi

  LAST_REPLICAS=$REPLICAS
  sleep 60
done

echo "" | tee -a $LOG_FILE
echo "End time: $(date)" | tee -a $LOG_FILE
echo "Monitoring log saved to: $LOG_FILE"
```

---

## Common Patterns

### Pattern 1: Dashboard View

```bash
#!/bin/bash
# Real-time dashboard for decommission

NODE_ID=4

while true; do
  clear
  echo "===== DECOMMISSION DASHBOARD ====="
  echo "Node: $NODE_ID | Time: $(date +%T)"
  echo ""

  # Node status
  echo "Node Status:"
  cockroach node status --host=localhost:26257 --certs-dir=certs | grep -E "(id|^  $NODE_ID)"
  echo ""

  # Replica distribution
  echo "Cluster Replica Distribution:"
  cockroach sql --host=localhost:26257 --certs-dir=certs --execute="
    SET allow_unsafe_internals = true;
    SELECT node_id, count(*) AS replicas
    FROM (SELECT unnest(replicas) AS node_id FROM crdb_internal.ranges)
    GROUP BY node_id ORDER BY node_id;" --format=table
  echo ""

  # Check completion
  REPLICAS=$(cockroach sql --host=localhost:26257 --certs-dir=certs --execute="
    SET allow_unsafe_internals = true;
    SELECT count(*) FROM (SELECT unnest(replicas) AS node_id FROM crdb_internal.ranges) WHERE node_id = $NODE_ID;
  " --format=csv | tail -1)

  if [ "$REPLICAS" -eq 0 ]; then
    echo "✅ DECOMMISSION COMPLETE"
    break
  fi

  sleep 30
done
```

---

### Pattern 2: Alert on Stall

```bash
#!/bin/bash
# Alert if decommission stalls

NODE_ID=4
STALL_THRESHOLD=300  # 5 minutes

LAST_REPLICAS=-1
LAST_CHANGE_TIME=$(date +%s)

while true; do
  REPLICAS=$(cockroach sql --host=localhost:26257 --certs-dir=certs --execute="
    SET allow_unsafe_internals = true;
    SELECT count(*) FROM (SELECT unnest(replicas) AS node_id FROM crdb_internal.ranges) WHERE node_id = $NODE_ID;
  " --format=csv | tail -1)

  if [ "$REPLICAS" -eq 0 ]; then
    echo "Decommission complete"
    break
  fi

  # Check for progress
  if [ "$REPLICAS" -ne "$LAST_REPLICAS" ]; then
    LAST_CHANGE_TIME=$(date +%s)
    echo "$(date +%T): Progress detected ($REPLICAS replicas)"
  else
    # Check stall time
    NOW=$(date +%s)
    STALL_TIME=$((NOW - LAST_CHANGE_TIME))

    if [ "$STALL_TIME" -ge "$STALL_THRESHOLD" ]; then
      echo "$(date +%T): ⚠️  ALERT: No progress for $STALL_TIME seconds"
      # Send alert (email, slack, pagerduty, etc.)
    fi
  fi

  LAST_REPLICAS=$REPLICAS
  sleep 60
done
```

---

## Troubleshooting During Monitoring

### Stalled Progress

**Symptom**: Replica count not decreasing for >5 minutes

**Check**:
```sql
-- Check for under-replicated ranges
SET allow_unsafe_internals = true;
SELECT count(*) FROM crdb_internal.ranges WHERE array_length(replicas, 1) < 3;
```

---

### Slow Progress

**Symptom**: Decommission moving very slowly (< 1 replica/minute)

**Check**:
```sql
-- Check cluster load
SELECT * FROM crdb_internal.node_metrics WHERE name LIKE '%queue.replicate%';

-- Large replication queue may slow decommissioning
```

---

## Important Notes

⚠️ **Patience Required**: Decommissioning can take 6-24+ hours for large nodes. Monitor but don't force.

⚠️ **Log Everything**: Keep logs of progress for troubleshooting and capacity planning.

⚠️ **Alert on Stalls**: Set up automated alerts for > 10 minute stalls.

⚠️ **Don't Intervene Prematurely**: Brief stalls (< 5 min) are normal during rebalancing.

---

## Related Skills

- **check-node-decommission-status** - Basic status checking
- **decommission-node-safely** - Initiate decommission
- **handle-decommission-failures** - Troubleshoot issues

---

## CockroachDB v26.1 Notes

### Monitoring Queries (v26.1)

All `crdb_internal` queries require:
```sql
SET allow_unsafe_internals = true;
```

### Key Tables
- `crdb_internal.ranges` - Replica locations
- `crdb_internal.gossip_liveness` - Node decommission state
- `crdb_internal.node_metrics` - Performance metrics

---

## References

- [CockroachDB Docs: Remove Nodes](https://www.cockroachlabs.com/docs/v26.1/remove-nodes)
- [CockroachDB Docs: Node Status](https://www.cockroachlabs.com/docs/v26.1/cockroach-node-status)
