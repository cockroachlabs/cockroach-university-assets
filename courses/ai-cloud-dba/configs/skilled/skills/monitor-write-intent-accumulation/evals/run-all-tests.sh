#!/bin/bash

# Master test runner for monitor-write-intent-accumulation skill
# Tests intent monitoring queries and detection techniques

COCKROACH_BIN="/Users/nathanzamecnik/bin/cockroach"
CERTS_DIR="/Users/nathanzamecnik/certs"
HOST="localhost:26258"
EVAL_DIR="/Users/nathanzamecnik/.claude/skills/monitor-write-intent-accumulation/evals"

echo "=========================================="
echo "Monitor Write Intent Accumulation - Evaluation Tests"
echo "=========================================="
echo "Cluster: $HOST"
echo "Time: $(date)"
echo ""

# Array of test files
tests=(
    "test-01-query-cluster-locks.sql"
    "test-02-intent-accumulation.sql"
    "test-03-long-running-transaction.sql"
    "test-04-session-intent-correlation.sql"
    "test-05-intent-resolution-rate.sql"
)

# Run each test
for test in "${tests[@]}"; do
    echo "=========================================="
    echo "Running: $test"
    echo "=========================================="
    echo ""

    "$COCKROACH_BIN" sql \
        --host="$HOST" \
        --certs-dir="$CERTS_DIR" \
        < "$EVAL_DIR/$test"

    result=$?

    if [ $result -eq 0 ]; then
        echo ""
        echo "✓ $test PASSED"
    else
        echo ""
        echo "✗ $test FAILED (exit code: $result)"
    fi

    echo ""
    echo "Press Enter to continue to next test..."
    read
done

echo ""
echo "=========================================="
echo "All tests completed"
echo "=========================================="
