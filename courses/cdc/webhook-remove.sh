#!/bin/bash
set -euxo pipefail

echo "[INFO] Stopping CDC application..."
pkill -f CdcApplication

echo "[INFO] Removing CDC app..."  
rm -rf /root/cockroach/cdc