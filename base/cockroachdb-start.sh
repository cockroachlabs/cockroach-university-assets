#!/bin/bash
set -euxo pipefail

## Make sure CockroachDB is installed
if command -v cockroach &> /dev/null && \
   [ -f "/usr/local/lib/cockroach/libgeos.so" ] && \
   [ -f "/usr/local/lib/cockroach/libgeos_c.so" ]; then
    echo "CockroachDB is installed correctly"
else
    echo "CockroachDB is not installed"
    exit 1
fi

# START UP COCKROACHDB
echo "[TRACK SETUP] Starting 1 CockroachDB node"
nohup cockroach start-single-node --insecure --background > foo.out 2> foo.err < /dev/null & disown

# COCKROACHDB UI
nohup socat tcp-listen:3080,reuseaddr,fork tcp:localhost:8080 > /var/log/listen-3080.out 2> /var/log/listen-3080.err < /dev/null &
