#!/bin/bash
set -euxo pipefail

## INSTALLING COCKROACHDB
export COCKROACH_VER=${1:-${COCKROACH_VER:-v25.4.0}}
echo "[INFO] Installing CockroachDB version ${COCKROACH_VER}"
echo "[INFO] Downloading CockroachDB binaries..."
curl https://binaries.cockroachdb.com/cockroach-${COCKROACH_VER}.linux-amd64.tgz | tar -xz && sudo cp -i cockroach-${COCKROACH_VER}.linux-amd64/cockroach /usr/local/bin/
mkdir -p /usr/local/lib/cockroach
cp -i cockroach-${COCKROACH_VER}.linux-amd64/lib/libgeos.so /usr/local/lib/cockroach/
cp -i cockroach-${COCKROACH_VER}.linux-amd64/lib/libgeos_c.so /usr/local/lib/cockroach/
rm -rf cockroach-${COCKROACH_VER}.linux-amd64
echo "[INFO] CockroachDB installation completed successfully"
