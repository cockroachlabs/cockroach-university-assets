#!/bin/bash
set -euxo pipefail

## INSTALLING MOLT
echo "[INFO] Installing MOLT..."
sudo curl -L https://molt.cockroachdb.com/molt/cli/molt-latest.linux-amd64.tgz -o /tmp/molt.tgz
tar -xzf /tmp/molt.tgz
mkdir -p /root/cockroachdb
cp molt replicator /root/cockroachdb/
sudo mv molt replicator /usr/local/bin/
rm -rf /tmp/molt.tgz