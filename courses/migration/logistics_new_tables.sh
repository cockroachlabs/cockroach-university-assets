#!/bin/bash
set -euxo pipefail
## ADDING MYSQL CONFIGURATION
echo "[INFO] Adding NEW PostgreSQL Logistics Tables..."

SCHEMAS=/root/cockroachdb/schemas

## Make sure the schemas directory exists
if [ ! -d "$SCHEMAS" ]; then
    echo "[ERROR] Schemas directory does not exist. Please create it first."
    exit 0
fi

echo "[INFO] Creating PostgreSQL schema..."
sudo -u postgres psql -d postgres < $SCHEMAS/logistics_new_table.sql
echo "[INFO] PostgreSQL schema created successfully."
