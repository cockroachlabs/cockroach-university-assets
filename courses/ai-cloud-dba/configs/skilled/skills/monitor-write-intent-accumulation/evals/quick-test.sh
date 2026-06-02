#!/bin/bash
# Quick single-command test runner
# Usage: ./quick-test.sh

COCKROACH="/Users/nathanzamecnik/bin/cockroach"
HOST="localhost:26258"
CERTS="/Users/nathanzamecnik/certs"

echo "Running all intent monitoring tests..."
echo "======================================="
echo ""

for test in test-*.sql; do
    echo ">>> $test"
    $COCKROACH sql --host=$HOST --certs-dir=$CERTS < "$test" 2>&1 | head -50
    echo ""
    echo "---"
    echo ""
done

echo "All tests completed!"
