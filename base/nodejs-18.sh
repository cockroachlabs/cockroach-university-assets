#!/bin/bash

# This set line ensures that all failures will cause the script to error and exit
set -euxo pipefail

echo "[NODEJS] Starting Node.js 18 setup..."

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

echo "[NODEJS] Node.js 18 setup completed successfully."