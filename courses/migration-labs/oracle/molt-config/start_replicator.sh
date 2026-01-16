#!/bin/bash
# Start Replicator for ongoing replication from Oracle to CockroachDB
# Uses Oracle LogMiner for CDC

echo "========================================"
echo "🔄 Starting Replicator (Oracle LogMiner)"
echo "========================================"

# Check if SCN is provided
if [ -z "$1" ]; then
  echo "❌ Error: SCN (System Change Number) is required"
  echo "Usage: $0 <SCN>"
  echo ""
  echo "Example: $0 1234567"
  echo ""
  echo "You can get the SCN from MOLT Fetch output:"
  echo "  grep 'backfillFromSCN' fetch.log | jq '.cdc_cursor'"
  exit 1
fi

SCN=$1

# Connection strings
SOURCE_ORACLE="oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREEPDB1"
SOURCE_CDB="oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREE"
TARGET_CRDB="postgres://root@localhost:26257/target?sslmode=disable"

# Staging database
STAGING_DB="postgres://root@localhost:26257/replicator_staging?sslmode=disable"

echo "📊 Using SCN: ${SCN}"
echo "📂 Source: Oracle FREEPDB1"
echo "📂 Target: CockroachDB target database"
echo "========================================"

# Create staging database if it doesn't exist
cockroach sql --insecure -e "CREATE DATABASE IF NOT EXISTS replicator_staging;"

# Run Replicator with Oracle LogMiner
replicator oraclelogminer \
  --source "${SOURCE_ORACLE}" \
  --source-cdb "${SOURCE_CDB}" \
  --target "${TARGET_CRDB}" \
  --staging "${STAGING_DB}" \
  --scn "${SCN}" \
  --allow-tls-mode-disable \
  --logging info

echo "========================================"
echo "✅ Replicator started"
echo "========================================"
