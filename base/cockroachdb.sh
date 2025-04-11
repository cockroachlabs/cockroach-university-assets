#!/bin/bash
set -euxo pipefail

## INSTALLING COCKROACHDB
export COCKROACH_VER=${COCKROACH_VER:-v25.1.2}
curl https://binaries.cockroachdb.com/cockroach-${COCKROACH_VER}.linux-amd64.tgz | tar -xz && sudo cp -i cockroach-${COCKROACH_VER}.linux-amd64/cockroach /usr/local/bin/
mkdir -p /usr/local/lib/cockroach
cp -i cockroach-${COCKROACH_VER}.linux-amd64/lib/libgeos.so /usr/local/lib/cockroach/
cp -i cockroach-${COCKROACH_VER}.linux-amd64/lib/libgeos_c.so /usr/local/lib/cockroach/
rm -rf cockroach-${COCKROACH_VER}.linux-amd64

# START UP COCKROACHDB
echo "[TRACK SETUP] Starting 1 CockroachDB node"
nohup cockroach start-single-node --insecure --background > foo.out 2> foo.err < /dev/null & disown

# COCKROACHDB UI
nohup socat tcp-listen:3080,reuseaddr,fork tcp:localhost:8080 > /var/log/listen-3080.out 2> /var/log/listen-3080.err < /dev/null &

## CREATING DEFAULT WORKING DIRECTORY
mkdir -p /root/cockroachdb