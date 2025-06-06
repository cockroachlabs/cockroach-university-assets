#!/bin/bash
set -euxo pipefail

echo "entering the check script for 07-install-crdb"

# Check if the command "cockroach" exists and both geos files are present
if command -v cockroach &> /dev/null && \
   [ -f "/usr/local/lib/cockroach/libgeos.so" ] && \
   [ -f "/usr/local/lib/cockroach/libgeos_c.so" ]; then
    echo "Good job, you have installed CockroachDB correctly"
else
    fail-message "Check that the cockroach binary and the two library files exist in the correct folders"
fi

echo "exiting the check script for 07-install-crdb"