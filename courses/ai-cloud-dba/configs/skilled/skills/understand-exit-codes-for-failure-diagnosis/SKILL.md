---
name: understand-exit-codes-for-failure-diagnosis
description: Interpret CockroachDB exit codes and error codes to diagnose and resolve failure scenarios
metadata:
  domain: Resilience and Failure Handling
  bloom_level: Understand
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Understand Exit Codes for Failure Diagnosis

**Domain**: Resilience and Failure Handling
**Bloom's Level**: Understand

## What This Skill Teaches

When CockroachDB processes encounter errors or failures, they communicate the nature of the problem through exit codes, error codes, and log messages. Understanding these signals is essential for rapid troubleshooting and recovery. This skill teaches you how to:

- Interpret CockroachDB exit codes (0, 1, 2, 10)
- Understand SQL error codes (SQLSTATE) and their meanings
- Identify critical error conditions from exit codes and log messages
- Map exit codes to specific failure scenarios and resolution strategies
- Diagnose issues by correlating exit codes with log messages and system state

Exit codes provide a standardized way to communicate process termination reasons, enabling automated monitoring, alerting, and recovery workflows.

## Prerequisites

- Basic Linux/Unix command-line knowledge
- Understanding of process exit codes and signals
- Access to CockroachDB logs
- Familiarity with CockroachDB node operations
- Knowledge of system monitoring and logging tools

## CockroachDB Exit Codes

### Exit Code 0: Successful Termination

**Meaning**: Process terminated successfully with no errors

**Common Scenarios**:
- Graceful shutdown initiated by user (`cockroach quit`, `SIGTERM`)
- Command completed successfully (e.g., `cockroach sql`, `cockroach cert list`)
- Planned node drain and shutdown
- Successful execution of administrative commands

**Example**:

```bash
# Graceful shutdown returns exit code 0
cockroach quit --host=localhost:26257 --certs-dir=certs
echo $?
# Output: 0

# Successful command execution
cockroach node status --host=localhost:26257 --certs-dir=certs
echo $?
# Output: 0
```

**Verification**:

```bash
# Check exit code after command
command_output=$(cockroach sql --host=localhost:26257 --certs-dir=certs -e "SELECT 1")
exit_code=$?

if [ $exit_code -eq 0 ]; then
  echo "Command succeeded"
else
  echo "Command failed with exit code: $exit_code"
fi
```

**Implications**:
- No remediation needed
- Process terminated cleanly
- System resources released properly
- Safe to restart or proceed with next operation

### Exit Code 1: General Error

**Meaning**: Unspecified error occurred during execution

**Common Scenarios**:
- Connection failures (cannot reach cluster)
- Authentication failures (invalid certificates, credentials)
- SQL execution errors
- Configuration errors
- Insufficient permissions
- Resource constraints (memory, file descriptors)
- General operational failures

**Example Detection**:

```bash
# Attempt to connect with invalid credentials
cockroach sql --host=localhost:26257 --certs-dir=/invalid/path -e "SELECT 1"
echo $?
# Output: 1

# Check logs for error details
grep "ERROR:" cockroach.log | tail -5
```

**Diagnostic Process**:

1. **Capture Exit Code**:
```bash
cockroach start --certs-dir=certs --store=data --listen-addr=localhost:26257
start_exit_code=$?

if [ $start_exit_code -eq 1 ]; then
  echo "Node failed to start - checking logs"
fi
```

2. **Examine stderr Output**:
```bash
# Exit code 1 errors typically write to stderr
cockroach start --certs-dir=certs --store=data 2> error.log
cat error.log
```

3. **Review Log Files**:
```bash
# Check cockroach.log for error context
tail -100 cockroach.log | grep -A5 -B5 "ERROR:"

# Look for FATAL severity messages
grep "FATAL" cockroach.log | tail -20
```

**Common Exit Code 1 Scenarios and Solutions**:

#### Scenario 1: Connection Refused

**Symptoms**:
```
ERROR: cannot dial server.
Is the server running?
Error: dial tcp 127.0.0.1:26257: connect: connection refused
```

**Diagnosis**:
```bash
# Verify node is running
ps aux | grep cockroach

# Check if port is listening
netstat -tuln | grep 26257
lsof -i :26257

# Test connectivity
telnet localhost 26257
```

**Resolution**:
- Start the CockroachDB node if not running
- Verify correct host and port in connection string
- Check firewall rules allowing port 26257
- Ensure node has completed startup (check logs)

#### Scenario 2: Certificate Authentication Failure

**Symptoms**:
```
ERROR: authentication failed
Error: x509: certificate signed by unknown authority
```

**Diagnosis**:
```bash
# Verify certificates exist and are valid
cockroach cert list --certs-dir=certs

# Check certificate permissions
ls -la certs/

# Verify CA certificate matches
openssl x509 -in certs/ca.crt -noout -text | grep -A2 "Subject:"
```

**Resolution**:
```bash
# Regenerate certificates if expired or invalid
cockroach cert create-client root --certs-dir=certs --ca-key=my-safe-directory/ca.key

# Fix certificate permissions
chmod 644 certs/*.crt
chmod 600 certs/*.key

# Retry connection with correct certs-dir
cockroach sql --host=localhost:26257 --certs-dir=certs
```

#### Scenario 3: Insufficient Permissions

**Symptoms**:
```
ERROR: open /var/lib/cockroach/data: permission denied
Exit code: 1
```

**Diagnosis**:
```bash
# Check directory ownership and permissions
ls -la /var/lib/cockroach/

# Verify running user
ps aux | grep cockroach | grep -v grep
```

**Resolution**:
```bash
# Fix ownership
sudo chown -R cockroach:cockroach /var/lib/cockroach/

# Fix permissions
sudo chmod 700 /var/lib/cockroach/data
```

### Exit Code 2: Incorrect Usage / Invalid Arguments

**Meaning**: Command invoked with incorrect syntax, invalid flags, or incompatible options

**Common Scenarios**:
- Missing required flags
- Invalid flag combinations
- Incorrect flag values
- Typos in command names
- Deprecated or removed flags

**Example**:

```bash
# Invalid flag
cockroach start --invalid-flag
echo $?
# Output: 2

# Missing required flag
cockroach cert create-node
echo $?
# Output: 2

# Incompatible flag combination
cockroach start --insecure --certs-dir=certs
echo $?
# Output: 2
```

**Diagnostic Process**:

1. **Review Command Syntax**:
```bash
# Get help for command
cockroach start --help

# Check for typos in flags
cockroach start --certs-dir=certs --store=data --listen-adr=localhost:26257
# Error: unknown flag: --listen-adr (should be --listen-addr)
```

2. **Verify Flag Compatibility**:
```bash
# Check CockroachDB version for flag support
cockroach version

# Review release notes for deprecated flags
# https://www.cockroachlabs.com/docs/releases/
```

**Common Exit Code 2 Scenarios**:

#### Invalid Flag Syntax

**Error**:
```
Error: unknown flag: --stores
```

**Resolution**:
```bash
# Use correct flag name
cockroach start --store=data --certs-dir=certs
```

#### Missing Required Arguments

**Error**:
```
Error: requires at least 1 arg(s), only received 0
```

**Resolution**:
```bash
# Provide required arguments
cockroach cert create-node localhost 127.0.0.1 \
  --certs-dir=certs --ca-key=ca.key
```

#### Conflicting Flags

**Error**:
```
Error: cannot specify both --insecure and --certs-dir
```

**Resolution**:
```bash
# Choose one security mode
# Secure mode:
cockroach start --certs-dir=certs --store=data

# Insecure mode (dev only):
cockroach start --insecure --store=data
```

**Prevention**:
- Always use `--help` to verify flag syntax
- Test commands in development environment first
- Document working commands in runbooks
- Use configuration files for complex flag combinations

### Exit Code 10: Disk Full

**Meaning**: Node detected insufficient disk space and exited to prevent data corruption

**Critical Importance**: This is a **safety mechanism** that prevents CockroachDB from running out of disk space during operation, which could lead to data loss or corruption.

**Detection Trigger**:

During node startup, CockroachDB checks available disk space on each store. If available disk space is **≤ 50% of the ballast file size**, the node exits immediately with exit code 10.

**Formula**:
```
If available_disk_space <= (ballast_file_size / 2):
    exit(10)  # Disk Full
```

**Default Ballast File Size**:
- 1% of total disk capacity, OR
- 1 GiB (whichever is smaller)

**Example Scenario**:

```bash
# Node with 100 GB disk and 1 GB ballast file
# Exits if available space <= 500 MB (50% of 1 GB ballast)

# Startup attempt with low disk space
cockroach start --certs-dir=certs --store=/data
# Process exits immediately with code 10

echo $?
# Output: 10
```

**Log Messages**:

```
I000000 00:00:00.000000 1 server/config.go:xxx  [-] 1  available disk space (450 MB) is below minimum threshold (500 MB)
F000000 00:00:00.000001 1 server/config.go:xxx  [-] 1  insufficient disk space, exiting with code 10
```

**Diagnostic Process**:

1. **Check Disk Space**:
```bash
# Check available space on store directory
df -h /var/lib/cockroach/data

# Example output:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sda1       100G   99G  450M  100% /var/lib/cockroach
```

2. **Verify Ballast File**:
```bash
# Check ballast file size
ls -lh /var/lib/cockroach/data/auxiliary/EMERGENCY_BALLAST

# Calculate threshold (50% of ballast)
ballast_size=$(stat -f%z /var/lib/cockroach/data/auxiliary/EMERGENCY_BALLAST 2>/dev/null || \
               stat -c%s /var/lib/cockroach/data/auxiliary/EMERGENCY_BALLAST 2>/dev/null)
threshold=$((ballast_size / 2))
echo "Minimum required space: $threshold bytes"
```

3. **Review Startup Logs**:
```bash
# Check for disk space errors in logs
grep -i "disk\|ballast\|exit.*10" cockroach.log | tail -20
```

**Resolution Strategies**:

#### Option 1: Delete Ballast File for Emergency Recovery

```bash
# WARNING: Only use in emergency to allow node to start
# This removes your emergency disk space buffer!

# Delete ballast file
rm /var/lib/cockroach/data/auxiliary/EMERGENCY_BALLAST

# Start node (will start without ballast protection)
cockroach start --certs-dir=certs --store=/var/lib/cockroach/data

# Monitor disk space and free space IMMEDIATELY
df -h /var/lib/cockroach/data
```

**After Emergency Recovery**:
```bash
# Free up disk space by:
# - Deleting old log files
find /var/lib/cockroach/logs -name "*.log" -mtime +30 -delete

# - Removing old debug zips
find /var/lib/cockroach -name "cockroach-debug-*.zip" -mtime +7 -delete

# - Clearing system logs
sudo journalctl --vacuum-time=7d

# Recreate ballast file once space is available
# (Will be recreated automatically on next restart if space available)
```

#### Option 2: Expand Disk Space

```bash
# Cloud provider disk expansion (example: GCP)
gcloud compute disks resize cockroach-disk-1 --size=200GB

# Resize filesystem
sudo resize2fs /dev/sda1

# Verify new space
df -h /var/lib/cockroach/data

# Restart node
cockroach start --certs-dir=certs --store=/var/lib/cockroach/data
```

#### Option 3: Configure Smaller Ballast File

```bash
# Start with smaller ballast file
# Only use if you understand the risks (less emergency buffer)

cockroach start \
  --certs-dir=certs \
  --store=path=/var/lib/cockroach/data,ballast-size=500MiB

# This reduces minimum required space but also reduces safety buffer
```

#### Option 4: Add Additional Store

```bash
# Add new store on different disk with more space
cockroach start \
  --certs-dir=certs \
  --store=path=/var/lib/cockroach/data1 \
  --store=path=/mnt/newssd/data2
```

**Monitoring and Prevention**:

```bash
# Set up monitoring alert for disk space
# Alert when disk usage > 85%

# Prometheus alert example:
# - alert: DiskSpaceHigh
#   expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.15
#   annotations:
#     summary: "Less than 15% disk space available"

# Set up automated cleanup tasks
cat > /etc/cron.daily/cleanup-cockroach-logs << 'EOF'
#!/bin/bash
find /var/lib/cockroach/logs -name "*.log" -mtime +30 -delete
find /var/lib/cockroach -name "cockroach-debug-*.zip" -mtime +7 -delete
EOF

chmod +x /etc/cron.daily/cleanup-cockroach-logs
```

## SQL Error Codes (SQLSTATE)

While exit codes indicate process-level failures, SQL error codes (SQLSTATE) indicate query-level errors.

### SQLSTATE 40001: Transaction Retry Error

**Meaning**: Transaction encountered a conflict and must be retried

**Common Causes**:
- Concurrent transactions modifying same data
- Read/write conflicts under serializable isolation
- Transaction timestamp pushed forward

**Example**:

```sql
-- Application receives error:
-- ERROR: restart transaction: TransactionRetryWithProtoRefreshError
-- SQLSTATE: 40001
```

**Detection**:

```bash
# Search logs for transaction retry errors
grep "SQLSTATE: 40001" cockroach.log | tail -20

# Count retry errors
grep -c "restart transaction" cockroach.log
```

**Resolution**:

Applications **must** implement retry logic for SQLSTATE 40001 errors:

```python
# Python example with retry logic
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_SERIALIZABLE

def run_transaction(conn, func):
    max_retries = 3
    for retry in range(max_retries):
        try:
            with conn.cursor() as cur:
                conn.set_isolation_level(ISOLATION_LEVEL_SERIALIZABLE)
                result = func(cur)
                conn.commit()
                return result
        except psycopg2.Error as e:
            if e.pgcode == '40001':  # SQLSTATE 40001
                conn.rollback()
                continue  # Retry
            else:
                raise  # Other error, don't retry
    raise Exception("Transaction failed after max retries")
```

### SQLSTATE 40003: Statement Completion Unknown

**Meaning**: Uncertain whether transaction committed (ambiguous result)

**Common Causes**:
- Network failure after commit sent but before confirmation received
- Node failure during commit phase
- Connection timeout during commit

**Example**:

```
ERROR: result is ambiguous
SQLSTATE: 40003
```

**Handling**:

```python
# Applications must handle ambiguous results carefully
try:
    cursor.execute("UPDATE accounts SET balance = balance + 100 WHERE id = 1")
    conn.commit()
except psycopg2.Error as e:
    if e.pgcode == '40003':
        # Transaction may or may not have committed
        # Verify state before retrying
        check_transaction_completion()
        # Consider idempotency or transaction ID tracking
```

### Other Common SQL Error Codes

**SQLSTATE 08006**: Connection failure
```
ERROR: connection to server was lost
```

**SQLSTATE 42P01**: Undefined table
```
ERROR: relation "tablename" does not exist
```

**SQLSTATE 23505**: Unique constraint violation
```
ERROR: duplicate key value violates unique constraint "primary"
```

## Critical Log Messages and Exit Conditions

### FATAL Severity: Immediate Node Shutdown

**Meaning**: Critical error requiring immediate process termination

**Common FATAL Scenarios**:

#### Clock Synchronization Error

**Log Message**:
```
F000000 00:00:00.000000 1 server/node.go:xxx  [-] 1
clock synchronization error detected: this node's clock is more than 400ms offset
from at least half the other nodes in the cluster.
This node will shut down.
```

**Exit Behavior**: Node spontaneously shuts down

**Cause**: Node's clock drifted > 80% of maximum offset (default 500ms)

**Diagnosis**:
```bash
# Check clock offset
timedatectl status

# Compare with other nodes
for node in node1 node2 node3; do
  echo "$node: $(ssh $node date -u)"
done
```

**Resolution**:
```bash
# Sync clock with NTP
sudo ntpdate -u pool.ntp.org
sudo systemctl restart chronyd  # or ntpd

# Verify sync
timedatectl status | grep "System clock synchronized"

# Restart node
cockroach start --certs-dir=certs --store=data
```

#### Storage Engine Write Failure

**Log Message**:
```
F000000 00:00:00.000000 1 storage/engine.go:xxx  [-] 1
storage engine failed to write log
terminating cockroach process
```

**Exit Behavior**: Process terminated immediately

**Causes**:
- Disk I/O failure
- Filesystem corruption
- Disk full (despite ballast file)
- Hardware failure

**Diagnosis**:
```bash
# Check disk health
dmesg | grep -i "error\|fail"
smartctl -a /dev/sda

# Check filesystem
sudo fsck -n /dev/sda1

# Review storage metrics
grep "storage.disk" cockroach.log | tail -50
```

### Node Exit Without Error Message

**Scenario**: Node process terminates without logging an error

**Most Common Cause**: Operating system killed the process due to **out of memory (OOM)**

**Detection**:

```bash
# Check system logs for OOM killer
dmesg | grep -i "out of memory"
grep "Out of memory" /var/log/syslog
journalctl | grep -i "killed process"

# Example output:
# Out of memory: Kill process 1234 (cockroach) score 950 or sacrifice child
# Killed process 1234 (cockroach), UID 1000, total-vm:50GB, anon-rss:40GB
```

**Diagnosis**:

```bash
# Check available memory
free -h

# Review CockroachDB memory usage before crash
grep "memory" cockroach.log | tail -100

# Check configured memory limit
grep "cache" cockroach.log | head -20
```

**Resolution**:

```bash
# Option 1: Increase system memory
# (Cloud provider or hardware upgrade)

# Option 2: Configure CockroachDB memory limits
cockroach start \
  --certs-dir=certs \
  --store=data \
  --cache=25% \
  --max-sql-memory=25%

# Option 3: Reduce workload
# - Limit concurrent queries
# - Optimize query memory usage
# - Scale out to more nodes
```

## Troubleshooting Workflow Using Exit Codes

### Step 1: Capture Exit Code

```bash
# For interactive commands
cockroach start --certs-dir=certs --store=data
exit_code=$?
echo "Exit code: $exit_code"

# For background processes
cockroach start --certs-dir=certs --store=data --background
wait $!
exit_code=$?

# For systemd services
systemctl status cockroach
# Check exit code in status output
```

### Step 2: Map Exit Code to Category

```bash
case $exit_code in
  0)
    echo "Success - no action needed"
    ;;
  1)
    echo "General error - check logs and stderr"
    grep "ERROR:\|FATAL:" cockroach.log | tail -20
    ;;
  2)
    echo "Invalid command syntax - verify flags"
    cockroach start --help
    ;;
  10)
    echo "Disk full - free space or delete ballast"
    df -h /var/lib/cockroach/data
    ;;
  *)
    echo "Unknown exit code: $exit_code - check logs"
    tail -100 cockroach.log
    ;;
esac
```

### Step 3: Examine stderr and Logs

```bash
# Capture stderr for immediate error context
cockroach start --certs-dir=certs --store=data 2> startup_errors.log

if [ $? -ne 0 ]; then
  echo "Startup failed with errors:"
  cat startup_errors.log
fi

# Check cockroach.log for detailed error trace
tail -200 cockroach.log | grep -A10 "ERROR:\|FATAL:"
```

### Step 4: Cross-Reference System State

```bash
# Check system resources
echo "=== Disk Space ==="
df -h

echo "=== Memory ==="
free -h

echo "=== CPU ==="
uptime

echo "=== Network ==="
netstat -tuln | grep 26257

echo "=== Processes ==="
ps aux | grep cockroach
```

### Step 5: Consult Documentation

```bash
# For specific error codes, consult CockroachDB docs
# https://www.cockroachlabs.com/docs/stable/common-errors
# https://www.cockroachlabs.com/docs/stable/critical-log-messages
# https://www.cockroachlabs.com/docs/stable/transaction-retry-error-reference
```

## Automated Monitoring Based on Exit Codes

### Shell Script Example

```bash
#!/bin/bash
# monitor-cockroach-health.sh

CERTS_DIR="/var/lib/cockroach/certs"
LOG_FILE="/var/log/cockroach-monitor.log"

check_node_health() {
  # Attempt to connect and run simple query
  cockroach sql --host=localhost:26257 --certs-dir=$CERTS_DIR \
    -e "SELECT 1" > /dev/null 2>&1

  exit_code=$?

  case $exit_code in
    0)
      echo "$(date): Node healthy (exit code 0)" >> $LOG_FILE
      return 0
      ;;
    1)
      echo "$(date): ERROR - Connection or query failed (exit code 1)" >> $LOG_FILE
      # Send alert
      echo "Node health check failed" | mail -s "CockroachDB Alert" admin@example.com
      return 1
      ;;
    10)
      echo "$(date): CRITICAL - Disk full (exit code 10)" >> $LOG_FILE
      # Emergency alert
      echo "URGENT: Disk full on CockroachDB node" | mail -s "CRITICAL Alert" admin@example.com
      return 10
      ;;
    *)
      echo "$(date): UNKNOWN - Unexpected exit code $exit_code" >> $LOG_FILE
      return $exit_code
      ;;
  esac
}

# Run health check
check_node_health
```

### Systemd Integration

```ini
# /etc/systemd/system/cockroach.service

[Unit]
Description=CockroachDB
After=network.target

[Service]
Type=notify
User=cockroach
ExecStart=/usr/local/bin/cockroach start --certs-dir=/var/lib/cockroach/certs --store=/var/lib/cockroach/data
ExecStop=/usr/local/bin/cockroach quit --certs-dir=/var/lib/cockroach/certs
Restart=on-failure
RestartSec=10

# Exit code 10 (disk full) should not auto-restart
# Requires manual intervention
RestartPreventExitStatus=10

[Install]
WantedBy=multi-user.target
```

### Prometheus Alert Example

```yaml
# Alert on node process exit (non-zero exit code)
- alert: CockroachDBProcessExit
  expr: changes(process_start_time_seconds{job="cockroachdb"}[5m]) > 0
  for: 1m
  annotations:
    summary: "CockroachDB process restarted on {{ $labels.instance }}"
    description: "Check exit code and logs for failure reason"

# Alert on disk space (prevent exit code 10)
- alert: CockroachDBDiskSpaceLow
  expr: node_filesystem_avail_bytes{mountpoint="/var/lib/cockroach"} < 2e9
  annotations:
    summary: "CockroachDB disk space below 2GB on {{ $labels.instance }}"
    description: "Risk of exit code 10 (disk full). Free space immediately."
```

## Best Practices

### 1. Always Check Exit Codes in Scripts

```bash
# Don't ignore exit codes
cockroach sql -e "CREATE DATABASE mydb"
if [ $? -ne 0 ]; then
  echo "Failed to create database"
  exit 1
fi

# Or use set -e to exit on any error
set -e
cockroach sql -e "CREATE DATABASE mydb"
cockroach sql -e "CREATE TABLE mydb.users (id INT PRIMARY KEY)"
```

### 2. Log Exit Codes for Audit Trail

```bash
# Wrapper function to log all commands and exit codes
run_cockroach_command() {
  local cmd="$@"
  echo "$(date): Running: $cmd" >> /var/log/cockroach-commands.log

  eval "$cmd"
  local exit_code=$?

  echo "$(date): Exit code: $exit_code" >> /var/log/cockroach-commands.log
  return $exit_code
}

# Usage
run_cockroach_command cockroach node status --host=localhost:26257 --certs-dir=certs
```

### 3. Implement Retry Logic for Transient Failures

```bash
# Retry with exponential backoff for exit code 1 (may be transient)
retry_command() {
  local max_attempts=3
  local timeout=1
  local attempt=1
  local exit_code=0

  while [ $attempt -le $max_attempts ]; do
    "$@"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
      return 0
    fi

    if [ $exit_code -eq 10 ]; then
      echo "Exit code 10 (disk full) - not retrying"
      return 10
    fi

    echo "Attempt $attempt failed with exit code $exit_code. Retrying in $timeout seconds..."
    sleep $timeout
    attempt=$((attempt + 1))
    timeout=$((timeout * 2))
  done

  echo "Command failed after $max_attempts attempts"
  return $exit_code
}

# Usage
retry_command cockroach sql --host=localhost:26257 -e "SELECT 1"
```

### 4. Configure Appropriate Alerts

**Alert Priorities**:
- **P0 (Critical)**: Exit code 10 (disk full), FATAL log messages
- **P1 (High)**: Exit code 1 with node down > 5 minutes, OOM kills
- **P2 (Medium)**: Repeated exit code 1, transaction retry errors
- **P3 (Low)**: Exit code 2 (user error), informational messages

### 5. Document Common Exit Code Scenarios

Create a runbook mapping exit codes to resolution procedures:

```markdown
# CockroachDB Exit Code Runbook

## Exit Code 0
- **Action**: None required
- **Notes**: Normal termination

## Exit Code 1: General Error
- **Check**: Logs, network, certificates, permissions
- **Common fixes**:
  - Restart node if transient
  - Fix certificate issues
  - Resolve permission problems
  - Clear network issues

## Exit Code 2: Invalid Usage
- **Check**: Command syntax and flags
- **Common fixes**:
  - Review command help
  - Fix typos
  - Update deprecated flags

## Exit Code 10: Disk Full
- **URGENT**: Manual intervention required
- **Steps**:
  1. Delete ballast file if emergency
  2. Free up disk space immediately
  3. Expand disk if possible
  4. Restart node
  5. Recreate ballast file
```

### 6. Monitor Disk Space Proactively

```bash
# Prevent exit code 10 with proactive monitoring
# Alert at 85% disk usage (well before ballast threshold)

# Create monitoring script
cat > /usr/local/bin/check-cockroach-disk.sh << 'EOF'
#!/bin/bash
THRESHOLD=85
STORE_PATH="/var/lib/cockroach/data"

usage=$(df -h "$STORE_PATH" | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$usage" -gt "$THRESHOLD" ]; then
  echo "ALERT: Disk usage at ${usage}% on $STORE_PATH"
  exit 1
fi

echo "OK: Disk usage at ${usage}%"
exit 0
EOF

chmod +x /usr/local/bin/check-cockroach-disk.sh

# Run every 5 minutes
echo "*/5 * * * * /usr/local/bin/check-cockroach-disk.sh" | crontab -
```

### 7. Test Failure Scenarios

```bash
# Test exit code handling in staging environment

# Test exit code 1 (connection failure)
cockroach sql --host=invalid-host:26257 -e "SELECT 1"
echo "Exit code 1 test: $?"

# Test exit code 2 (invalid flag)
cockroach start --invalid-flag
echo "Exit code 2 test: $?"

# Test exit code 10 (simulate low disk space)
# WARNING: Only in test environment!
# Fill disk to trigger exit code 10, verify monitoring alerts

# Verify your monitoring and alerting catches these scenarios
```

## Related Skills

- **troubleshoot-cluster-connectivity**: Diagnose connection failures (exit code 1)
- **handle-disk-space-emergencies-with-ballast-files**: Recover from exit code 10
- **monitor-node-liveness-and-health**: Detect node failures and exit conditions
- **implement-client-side-transaction-retry-logic**: Handle SQLSTATE 40001 errors
- **diagnose-node-failures-using-multiple-signals**: Combine exit codes with other diagnostics
- **handle-certificate-expiration-failures**: Resolve authentication errors (exit code 1)
- **configure-logging-output-and-levels**: Access detailed error information
- **critical-log-messages**: Understand FATAL and ERROR log severities
- **configure-ntp-for-clock-synchronization**: Prevent clock sync FATAL errors

## References

- [Common Errors and Solutions](https://www.cockroachlabs.com/docs/stable/common-errors)
- [Critical Log Messages](https://www.cockroachlabs.com/docs/stable/critical-log-messages)
- [Transaction Retry Error Reference](https://www.cockroachlabs.com/docs/stable/transaction-retry-error-reference)
- [Troubleshoot Self-Hosted Setup](https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting)
- [Configure Logs](https://www.cockroachlabs.com/docs/stable/configure-logs)
- [Logging Overview](https://www.cockroachlabs.com/docs/stable/logging-overview)
- [cockroach start Command](https://www.cockroachlabs.com/docs/stable/cockroach-start)
- [Troubleshooting Overview](https://www.cockroachlabs.com/docs/stable/troubleshooting-overview)
