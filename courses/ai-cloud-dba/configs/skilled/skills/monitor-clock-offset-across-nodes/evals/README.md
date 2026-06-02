# Eval Tests: Monitor Clock Offset Across Nodes

## Overview

This directory contains evaluation tests for the `monitor-clock-offset-across-nodes` skill. The tests verify that the skill's SQL queries, monitoring approaches, and threshold classifications are accurate against a live CockroachDB v26.1 cluster.

## Test Files

### `test-clock-offset-monitoring.sql`
Complete SQL test suite with 7 tests covering:
- Basic clock offset queries
- Alert/threshold detection
- Comprehensive health checks
- Node status verification
- Clock metrics discovery
- HLC timestamp validation
- Cluster settings verification

### `run-tests.sh`
Automated test runner that:
- Executes all SQL tests against the cluster
- Captures results and generates formatted output
- Analyzes current clock offset health
- Validates skill accuracy
- Produces `TEST-RESULTS.md` report

### `TEST-RESULTS.md` (generated)
Detailed test execution report including:
- Test pass/fail status
- Query results
- Clock offset health assessment
- Skill validation findings
- Recommendations for skill updates

## Running the Tests

### Prerequisites

1. **CockroachDB cluster running**:
   ```bash
   # Verify cluster is accessible
   /Users/nathanzamecnik/bin/cockroach sql --host=localhost:26258 --certs-dir=/Users/nathanzamecnik/certs --execute="SELECT version();"
   ```

2. **Permissions**:
   ```bash
   chmod +x run-tests.sh
   ```

### Execute Test Suite

```bash
# Run automated test suite
./run-tests.sh

# Or manually execute individual tests
/Users/nathanzamecnik/bin/cockroach sql \
  --host=localhost:26258 \
  --certs-dir=/Users/nathanzamecnik/certs \
  < test-clock-offset-monitoring.sql
```

## Expected Results

### Healthy Cluster
- All 7 tests should pass
- Clock offset < 50ms (excellent)
- Status: "OK"
- No action needed

### Test Output Example
```
=========================================
Clock Offset Monitoring Test Suite
=========================================
Timestamp: 2026-03-07 14:30:00
Cluster: localhost:26258

Running TEST 1: Basic Clock Offset Query
✓ PASSED

Running TEST 2: Alert Query
✓ PASSED

...

=========================================
Test Execution Complete
=========================================
Tests Passed: 7
Tests Failed: 0
Success Rate: 100.0%

Current Clock Offset: 12.50ms

All tests passed!
```

## Test Coverage

### 1. Basic Clock Offset Query
**Purpose**: Verify primary monitoring query works
**Query**: `crdb_internal.node_metrics` for `clock-offset.meannanos`
**Pass Criteria**: Returns cluster-wide offset value with correct status

### 2. Alert Query (Threshold Detection)
**Purpose**: Test filtering for high offset values
**Query**: Same as #1 but with `WHERE value > 100000000`
**Pass Criteria**: Returns 0 rows if offset < 100ms, 1 row if > 100ms

### 3. Comprehensive Health Check
**Purpose**: Validate full health check query with recommendations
**Query**: CTE with threshold classification and action recommendations
**Pass Criteria**: Returns complete health assessment

### 4. Node Status Query
**Purpose**: Verify node information is queryable
**Query**: `crdb_internal.kv_node_status`
**Pass Criteria**: Returns all active nodes

### 5. Clock Metrics Discovery
**Purpose**: List all available clock-related metrics
**Query**: `LIKE '%clock%'` on node_metrics
**Pass Criteria**: Returns `clock-offset.meannanos` and other clock metrics

### 6. HLC Timestamp Function
**Purpose**: Verify Hybrid Logical Clock is functioning
**Query**: `cluster_logical_timestamp()`
**Pass Criteria**: Returns valid HLC timestamp, monotonically increasing

### 7. Cluster Settings
**Purpose**: Verify max_offset configuration
**Query**: `SHOW CLUSTER SETTING server.clock.max_offset`
**Pass Criteria**: Returns 500ms (default)

## Threshold Reference

| Offset (ms) | Status | Action | Test Behavior |
|-------------|--------|--------|---------------|
| < 50 | OK | None | All tests pass, excellent health |
| 50-100 | OK | Monitor | All tests pass, good health |
| 100-250 | CAUTION | Verify NTP | Test #2 returns results |
| 250-400 | WARNING | Investigate | Test #3 shows warning |
| 400-500 | CRITICAL | Immediate action | Test #3 shows critical |
| ≥ 500 | FATAL | Node crashes | Should not reach this in testing |

## Key Findings (v26.1)

### ✅ What Works
- `crdb_internal.node_metrics` query for `clock-offset.meannanos`
- Cluster-wide metric availability
- Threshold classifications (500ms fatal, 250ms warning)
- DB Console Hardware dashboard
- HLC timestamp queries
- `allow_unsafe_internals` setting

### ⚠️ Version Notes
- In v26.1, `clock-offset.meannanos` is a **cluster-wide** metric (not per-node)
- For per-node visualization, use DB Console Hardware dashboard
- Per-node SQL queries not directly available in v26.1

### 📝 Skill Updates Recommended
1. Add note about cluster-wide vs per-node metrics in v26.1+
2. Emphasize DB Console for per-node details
3. All threshold values and monitoring guidance are accurate

## Troubleshooting

### Test Fails: Permission Denied
```bash
# Verify certs directory permissions
ls -la /Users/nathanzamecnik/certs

# Test connection manually
/Users/nathanzamecnik/bin/cockroach sql --host=localhost:26258 --certs-dir=/Users/nathanzamecnik/certs
```

### Test Fails: allow_unsafe_internals
Some queries require `SET allow_unsafe_internals = true`. This is included in test queries.

### Test Fails: Metric Not Found
If `clock-offset.meannanos` not found:
```sql
-- List all available metrics
SELECT DISTINCT name FROM crdb_internal.node_metrics ORDER BY name;
```

### Test Shows High Offset
If clock offset > 100ms during testing:
1. Check NTP status: `chronyc tracking`
2. Verify NTP service: `systemctl status chronyd`
3. Force sync: `chronyc makestep`
4. Re-run tests after NTP synchronization

## Integration with CI/CD

These tests can be integrated into automated testing:

```bash
#!/bin/bash
# ci-test-clock-monitoring.sh

cd /Users/nathanzamecnik/.claude/skills/monitor-clock-offset-across-nodes/evals

# Run tests
./run-tests.sh

# Check exit code
if [ $? -eq 0 ]; then
  echo "Clock monitoring skill validated"
  exit 0
else
  echo "Clock monitoring skill validation failed"
  cat TEST-RESULTS.md
  exit 1
fi
```

## Additional Validation

### Manual NTP Verification
Complement SQL tests with system-level NTP checks:

```bash
# Check NTP synchronization status
timedatectl status

# Verify NTP sources
chronyc sources -v

# Check tracking
chronyc tracking

# Test NTP server connectivity
ntpdate -q time.cloudflare.com
```

### DB Console Validation
1. Navigate to `https://localhost:8080`
2. Go to **Metrics** → **Hardware**
3. View **Clock Offset** graph
4. Verify graph shows flat line near zero

## Related Skills

- `configure-ntp-for-clock-synchronization` - Configure NTP for clock sync
- `understand-mvcc-multi-version-concurrency-control-concepts` - How HLC affects MVCC
- `handle-clock-drift-issues` - Troubleshoot clock problems

## Documentation References

- [Clock Synchronization](https://www.cockroachlabs.com/docs/stable/recommended-production-settings.html#clock-synchronization)
- [Hardware Dashboard](https://www.cockroachlabs.com/docs/stable/ui-hardware-dashboard.html)
- [Node Metrics](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html)

---

**Last Updated**: 2026-03-07
**Skill Version**: 1.0.0
**Tested Against**: CockroachDB v26.1
