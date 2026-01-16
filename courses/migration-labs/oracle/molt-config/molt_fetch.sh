#!/bin/bash
# MOLT Fetch - Bulk data migration from Oracle to CockroachDB

echo "========================================"
echo "🚀 Starting MOLT Fetch"
echo "========================================"

# Connection strings
SOURCE_ORACLE="oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREEPDB1"
SOURCE_CDB="oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREE"
TARGET_CRDB="postgres://root@localhost:26257/target?sslmode=disable"

# Transformations file
TRANSFORMS_FILE="/root/oracle/molt-config/transforms.json"

# Run MOLT Fetch
molt fetch \
  --source "${SOURCE_ORACLE}" \
  --source-cdb "${SOURCE_CDB}" \
  --target "${TARGET_CRDB}" \
  --case-sensitive=false \
  --mode data-load \
  --direct-copy \
  --schema-filter 'APP_USER' \
  --table-filter '.*' \
  --table-handling truncate-if-exists \
  --allow-tls-mode-disable \
  --transformations-file "${TRANSFORMS_FILE}" \
  --logging info

echo "========================================"
echo "✅ MOLT Fetch completed"
echo "========================================"
