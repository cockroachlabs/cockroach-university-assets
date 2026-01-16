#!/bin/bash
# MOLT Verify - Validate data consistency between Oracle and CockroachDB

echo "========================================"
echo "🔍 Starting MOLT Verify"
echo "========================================"

# Connection strings
SOURCE_ORACLE="oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREEPDB1"
SOURCE_CDB="oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREE"
TARGET_CRDB="postgres://root@localhost:26257/target?sslmode=disable"

# Transformations file
TRANSFORMS_FILE="/root/oracle/molt-config/transforms.json"

# Run MOLT Verify
molt verify \
  --source "${SOURCE_ORACLE}" \
  --source-cdb "${SOURCE_CDB}" \
  --target "${TARGET_CRDB}" \
  --case-sensitive=false \
  --schema-filter 'APP_USER' \
  --table-filter '.*' \
  --transformations-file "${TRANSFORMS_FILE}" \
  --allow-tls-mode-disable \
  --logging info

echo "========================================"
echo "✅ MOLT Verify completed"
echo "========================================"
