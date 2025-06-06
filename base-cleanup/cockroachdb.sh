#!/bin/bash
set -euxo pipefail

echo "General Cleanuop Script for CockroachDB Installation"

# Check for running cockroach process and kill it if found
if pgrep -x cockroach > /dev/null; then
  pkill -9 cockroach
fi

# Remove cockroach binary
rm -rf /usr/local/bin/cockroach

# Remove any files/directories starting with "node" in /root
rm -rf /root/node*

# Remove geos libraries from cockroach installation
rm -rf /usr/local/lib/cockroach/libgeos*

echo "Exiting CockroachDB Cleanup"