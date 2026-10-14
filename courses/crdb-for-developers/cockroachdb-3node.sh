#!/bin/bash
set -euxo pipefail

# Start a 3-node insecure CockroachDB cluster on a single VM for the
# "Stay Online" labs. The app connects with a multi-host DSN, so the driver
# fails over when a node is stopped — no load balancer required.

if command -v cockroach &>/dev/null \
   && [ -f /usr/local/lib/cockroach/libgeos.so ] \
   && [ -f /usr/local/lib/cockroach/libgeos_c.so ]; then
    echo "[INFO] CockroachDB is installed"
else
    echo "❌ CockroachDB is not installed"; exit 1
fi

# Clean any previous attempt.
pkill -9 -x cockroach 2>/dev/null || true
rm -rf /root/n1 /root/n2 /root/n3

JOIN=localhost:26257,localhost:26258,localhost:26259
nohup cockroach start --insecure --store=/root/n1 --listen-addr=localhost:26257 --http-addr=0.0.0.0:8080 --join=$JOIN > /dev/null 2>&1 < /dev/null & disown
nohup cockroach start --insecure --store=/root/n2 --listen-addr=localhost:26258 --http-addr=0.0.0.0:8081 --join=$JOIN > /dev/null 2>&1 < /dev/null & disown
nohup cockroach start --insecure --store=/root/n3 --listen-addr=localhost:26259 --http-addr=0.0.0.0:8082 --join=$JOIN > /dev/null 2>&1 < /dev/null & disown

sleep 5
cockroach init --insecure --host=localhost:26257 || true
until cockroach sql --insecure --host=localhost:26257 -e "SELECT 1" >/dev/null 2>&1; do sleep 1; done

# DB Console redirect for Instruqt.
nohup socat tcp-listen:3080,reuseaddr,fork tcp:localhost:8080 > /dev/null 2>&1 < /dev/null & disown || true
echo "[INFO] 3-node cluster ready"
