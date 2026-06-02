---
name: use-cockroach-node-status-with-filtering
description: Use cockroach node status command with filtering and scripting. Use when user asks "check node status", "filter node output", "parse node status", "script node checks", or "monitor nodes via CLI".
metadata:
  domain: Cluster Maintenance
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Use Cockroach Node Status with Filtering

## What This Skill Teaches

The `cockroach node status` command is the primary CLI tool for checking cluster health. This skill covers using it effectively with filtering, formatting, and scripting.

## Basic Node Status

### Simple Node Status

```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs
```

**Output**:
```
  id |     address     | build  |  started_at         | updated_at          | is_live | replicas | ranges
-----+-----------------+--------+---------------------+---------------------+---------+----------+--------
   1 | localhost:26257 | v26.1.0| 2026-03-05 08:00:00 | 2026-03-05 10:00:00 | true    |      142 |    142
   2 | localhost:26258 | v26.1.0| 2026-03-05 08:00:00 | 2026-03-05 10:00:00 | true    |      145 |    145
   3 | localhost:26259 | v26.1.0| 2026-03-05 08:00:00 | 2026-03-05 10:00:00 | true    |      140 |    140
```

**Key columns**:
- `id`: Node ID
- `address`: Network address
- `build`: CockroachDB version
- `is_live`: Node alive (true/false)
- `replicas`: Number of replicas on node
- `ranges`: Number of range leases on node

---

## Output Formats

### Table Format (Default)

```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=table
```

Human-readable, aligned columns.

---

### CSV Format (For Scripting)

```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv
```

**Output**:
```
id,address,build,started_at,updated_at,is_live,replicas,ranges
1,localhost:26257,v26.1.0,2026-03-05 08:00:00,2026-03-05 10:00:00,true,142,142
2,localhost:26258,v26.1.0,2026-03-05 08:00:00,2026-03-05 10:00:00,true,145,145
3,localhost:26259,v26.1.0,2026-03-05 08:00:00,2026-03-05 10:00:00,true,140,140
```

**Best for**: grep, awk, cut, scripting

---

### TSV Format

```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=tsv
```

Tab-separated values, good for parsing.

---

### JSON Format

```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=json
```

**Output**:
```json
{
  "nodes": [
    {
      "id": 1,
      "address": "localhost:26257",
      "build": "v26.1.0",
      "is_live": true,
      "replicas": 142,
      "ranges": 142
    }
  ]
}
```

**Best for**: jq processing, JSON tools

---

## Filtering Node Status

### Filter Specific Node

**By node ID**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs | grep "^  3"
```

**Using CSV with grep**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep "^3,"
```

---

### Filter Dead Nodes

```bash
# Using grep (table format)
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs | grep "false"

# Using CSV format
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep ",false,"
```

---

### Filter by Version

```bash
# Find nodes on specific version
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep "v26.1.0"

# Find nodes on OLD version during upgrade
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep "v25.2"
```

---

## Parsing with awk

### Extract Specific Columns

**Get node IDs only**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | tail -n +2 | cut -d, -f1
```

Output:
```
1
2
3
```

**Get node IDs and addresses**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | tail -n +2 | cut -d, -f1,2
```

Output:
```
1,localhost:26257
2,localhost:26258
3,localhost:26259
```

---

### Calculate Statistics

**Count total nodes**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | tail -n +2 | wc -l
```

**Count live nodes**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep ",true," | wc -l
```

**Count dead nodes**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep ",false," | wc -l
```

**Total replica count across cluster**:
```bash
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | tail -n +2 | cut -d, -f7 | awk '{sum+=$1} END {print sum}'
```

---

## Scripting Examples

### Alert on Dead Nodes

```bash
#!/bin/bash
# check-node-health.sh

HOST="localhost:26257"
CERTS_DIR="/tmp/certs"

DEAD_COUNT=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | grep ",false," | wc -l)

if [ $DEAD_COUNT -gt 0 ]; then
    echo "ALERT: $DEAD_COUNT nodes are down!"

    # Show dead nodes
    cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | grep ",false,"

    exit 1
else
    echo "All nodes healthy"
    exit 0
fi
```

---

### Monitor Node Count

```bash
#!/bin/bash
# monitor-node-count.sh

HOST="localhost:26257"
CERTS_DIR="/tmp/certs"
EXPECTED_NODES=3

ACTUAL_NODES=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | wc -l)

if [ $ACTUAL_NODES -lt $EXPECTED_NODES ]; then
    echo "WARNING: Expected $EXPECTED_NODES nodes, found $ACTUAL_NODES"
    exit 1
elif [ $ACTUAL_NODES -gt $EXPECTED_NODES ]; then
    echo "INFO: New nodes added. Expected $EXPECTED_NODES, found $ACTUAL_NODES"
else
    echo "Node count OK: $ACTUAL_NODES nodes"
fi
```

---

### Check Version Consistency

```bash
#!/bin/bash
# check-version-consistency.sh

HOST="localhost:26257"
CERTS_DIR="/tmp/certs"

VERSIONS=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | cut -d, -f3 | sort -u)

VERSION_COUNT=$(echo "$VERSIONS" | wc -l)

if [ $VERSION_COUNT -gt 1 ]; then
    echo "WARNING: Multiple CockroachDB versions detected:"
    echo "$VERSIONS"
    echo "Cluster may be in middle of upgrade"
else
    echo "All nodes on same version: $VERSIONS"
fi
```

---

### Monitor Replica Distribution

```bash
#!/bin/bash
# check-replica-balance.sh

HOST="localhost:26257"
CERTS_DIR="/tmp/certs"

# Get replica counts per node
cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | while IFS=, read id address build started updated is_live replicas ranges; do
    echo "Node $id: $replicas replicas"
done

# Check if imbalanced (max - min > 20%)
MAX=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | cut -d, -f7 | sort -n | tail -1)
MIN=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | cut -d, -f7 | sort -n | head -1)

DIFF=$((MAX - MIN))
THRESHOLD=$((MIN * 20 / 100))

if [ $DIFF -gt $THRESHOLD ]; then
    echo "WARNING: Replica imbalance detected (max: $MAX, min: $MIN, diff: $DIFF)"
else
    echo "Replica distribution balanced"
fi
```

---

## Decommission Status

### Check Decommissioning Nodes

```bash
cockroach node status --decommission --host=localhost:26257 --certs-dir=/tmp/certs
```

**Output shows membership**:
```
  id |  membership      | is_live | replicas | is_draining
-----+------------------+---------+----------+-------------
   1 | active           | true    |      142 | false
   2 | active           | true    |      145 | false
   3 | decommissioning  | true    |       28 | true
```

**Filter decommissioning nodes**:
```bash
cockroach node status --decommission --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep "decommissioning"
```

---

## Combining with Other Tools

### With jq (JSON Processing)

```bash
# Get all node IDs as array
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=json | jq '.nodes[].id'

# Filter dead nodes
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=json | jq '.nodes[] | select(.is_live == false)'

# Get addresses of live nodes
cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=json | jq -r '.nodes[] | select(.is_live == true) | .address'
```

---

### With watch (Continuous Monitoring)

```bash
# Update every 5 seconds
watch -n 5 'cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs'

# Monitor dead node count
watch -n 10 'cockroach node status --host=localhost:26257 --certs-dir=/tmp/certs --format=csv | grep ",false," | wc -l'
```

---

## Best Practices

1. **Use CSV for scripting** - Easier to parse than table format
2. **Always check exit code** - Command fails if cluster unreachable
3. **Filter carefully** - Ensure grep/awk patterns are precise
4. **Handle header row** - Use `tail -n +2` to skip CSV header
5. **Use --format=json for complex parsing** - Better than awk for nested data
6. **Script monitoring** - Automate health checks
7. **Log output** - Track node status over time

---

## Common Pitfalls

❌ **Forgetting header row in CSV**:
```bash
# Wrong (includes header)
cockroach node status --format=csv | wc -l

# Correct (skip header)
cockroach node status --format=csv | tail -n +2 | wc -l
```

❌ **Grep pattern too broad**:
```bash
# Wrong (matches "false" anywhere)
cockroach node status | grep "false"

# Correct (matches is_live column)
cockroach node status --format=csv | grep ",false,"
```

❌ **Not handling connection failures**:
```bash
# Wrong (script continues on error)
cockroach node status ...
process_output

# Correct (check exit code)
if cockroach node status ... > output.txt; then
    process_output output.txt
else
    echo "ERROR: Cannot connect to cluster"
    exit 1
fi
```

---

## Complete Monitoring Script

```bash
#!/bin/bash
# comprehensive-node-monitor.sh

HOST="localhost:26257"
CERTS_DIR="/tmp/certs"

echo "=== CockroachDB Node Status Monitor ==="
echo "Time: $(date)"
echo

# Check connectivity
if ! cockroach node status --host=$HOST --certs-dir=$CERTS_DIR > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to cluster at $HOST"
    exit 1
fi

# Node counts
TOTAL=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | wc -l)
LIVE=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | grep ",true," | wc -l)
DEAD=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | grep ",false," | wc -l)

echo "Node Status:"
echo "  Total: $TOTAL"
echo "  Live: $LIVE"
echo "  Dead: $DEAD"
echo

# Version consistency
VERSIONS=$(cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | cut -d, -f3 | sort -u | wc -l)
if [ $VERSIONS -gt 1 ]; then
    echo "WARNING: Multiple versions detected (upgrade in progress?)"
else
    echo "All nodes on same version"
fi
echo

# Replica distribution
echo "Replica Distribution:"
cockroach node status --host=$HOST --certs-dir=$CERTS_DIR --format=csv | tail -n +2 | cut -d, -f1,7 | while IFS=, read id replicas; do
    echo "  Node $id: $replicas replicas"
done
echo

# Alert on issues
if [ $DEAD -gt 0 ]; then
    echo "ALERT: $DEAD nodes down!"
    cockroach node status --host=$HOST --certs-dir=$CERTS_DIR | grep "false"
fi
```

---

## Related Skills

- `monitor-cluster-health-during-the-suspect-and-dead-node-states` - Uses node status for monitoring
- `monitor-data-movement-during-node-decommissioning` - Checks decommission progress
- `verify-cluster-replication-and-size` - Uses node status for validation
