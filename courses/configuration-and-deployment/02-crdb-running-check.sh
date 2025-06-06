#!/bin/bash
set -euxo pipefail

## CHECKING COCKROACHDB STATUS
echo "[INFO] Checking CockroachDB status..."
if pgrep -x cockroach > /dev/null; then
    echo "[INFO] CockroachDB is running"
else
    echo "[INFO] CockroachDB is not running"
fi
