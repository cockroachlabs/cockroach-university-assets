#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Oracle Docker Setup for Migration Lab"
echo "[INFO] ============================================"

## INSTALL DOCKER (if not already installed)
if ! command -v docker &> /dev/null; then
    echo "[INFO] Installing Docker..."

    # Install Docker using official script
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh

    # Start Docker service
    systemctl start docker
    systemctl enable docker

    echo "[INFO] ✅ Docker installed"
else
    echo "[INFO] Docker already installed"
fi

# Verify Docker is running
systemctl status docker --no-pager || systemctl start docker

## CREATE DOCKER NETWORK
echo "[INFO] Creating Docker network..."
docker network create molt-network 2>/dev/null || echo "[INFO] Network molt-network already exists"

## PULL ORACLE DOCKER IMAGE
echo "[INFO] Pulling Oracle Docker image (this may take 5-10 minutes)..."
docker pull container-registry.oracle.com/database/free:latest

## START ORACLE CONTAINER
echo "[INFO] Starting Oracle container..."
docker rm -f oracle-source 2>/dev/null || true

docker run -d \
  --name oracle-source \
  --network molt-network \
  -p 1521:1521 \
  -p 5500:5500 \
  -e ORACLE_PWD=CockroachDB_123 \
  container-registry.oracle.com/database/free:latest

echo "[INFO] Oracle container started, waiting for database to be ready..."

## WAIT FOR ORACLE TO BE READY
MAX_WAIT=600  # 10 minutes (Oracle takes a while to fully start)
COUNTER=0

echo "[INFO] Waiting for Oracle database to be OPEN (this may take 3-5 minutes)..."

while [ $COUNTER -lt $MAX_WAIT ]; do
    # Check if database status is OPEN
    DB_STATUS=$(docker exec oracle-source bash -c "echo 'SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT status FROM v\$instance;
EXIT;' | sqlplus -s / as sysdba 2>/dev/null" | grep -v '^$' | tail -1 | tr -d '[:space:]')

    if [ "$DB_STATUS" = "OPEN" ]; then
        echo "[INFO] ✅ Oracle database is OPEN and ready"
        break
    fi

    sleep 10
    COUNTER=$((COUNTER + 10))
    echo "[INFO] Waiting for Oracle database to open... (${COUNTER}s elapsed, status: ${DB_STATUS:-starting})"
done

if [ $COUNTER -ge $MAX_WAIT ]; then
    echo "[ERROR] Oracle database failed to open within ${MAX_WAIT} seconds"
    echo "[ERROR] Last status: ${DB_STATUS:-unknown}"
    docker logs oracle-source | tail -50
    exit 1
fi

## ENABLE ARCHIVELOG MODE (Required for CDC/Replicator)
echo "[INFO] Checking ARCHIVELOG mode..."

# Check if ARCHIVELOG is already enabled
ARCHIVELOG_STATUS=$(docker exec oracle-source bash -c "sqlplus -s / as sysdba <<'EOF'
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT log_mode FROM v\$database;
EXIT;
EOF
" | grep -v '^$' | tail -1 | tr -d '[:space:]')

echo "[INFO] Current ARCHIVELOG status: ${ARCHIVELOG_STATUS}"

if [ "$ARCHIVELOG_STATUS" != "ARCHIVELOG" ]; then
    echo "[INFO] Enabling ARCHIVELOG mode..."

    # Add a small delay to ensure database is fully ready
    sleep 5

    docker exec oracle-source bash -c "sqlplus / as sysdba <<'SQLEOF'
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
EXIT;
SQLEOF
"
    echo "[INFO] ✅ ARCHIVELOG mode enabled"
else
    echo "[INFO] ✅ ARCHIVELOG already enabled, skipping"
fi

## ENABLE FORCE LOGGING AND GOLDENGATE REPLICATION
echo "[INFO] Enabling FORCE LOGGING and GoldenGate replication..."
docker exec oracle-source bash -c "sqlplus / as sysdba <<'SQLEOF' || true
ALTER DATABASE FORCE LOGGING;
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;
EXIT;
SQLEOF
"

echo "[INFO] ✅ Force logging and GoldenGate replication enabled"

## ENABLE SUPPLEMENTAL LOGGING (Required for CDC)
echo "[INFO] Enabling supplemental logging..."
docker exec oracle-source bash -c "sqlplus / as sysdba <<'SQLEOF'
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
EXIT;
SQLEOF
"

echo "[INFO] ✅ Supplemental logging enabled"

## CREATE MIGRATION USER
echo "[INFO] Creating C##MIGRATION_USER..."
docker exec oracle-source bash -c "sqlplus / as sysdba <<'SQLEOF'
-- Create common migration user
CREATE USER C##MIGRATION_USER IDENTIFIED BY migpass CONTAINER=ALL;
GRANT CONNECT, RESOURCE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT CREATE SESSION TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ANY TABLE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT_CATALOG_ROLE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT EXECUTE_CATALOG_ROLE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION TO C##MIGRATION_USER CONTAINER=ALL;
GRANT LOGMINING TO C##MIGRATION_USER CONTAINER=ALL;
GRANT UNLIMITED TABLESPACE TO C##MIGRATION_USER CONTAINER=ALL;

-- Grant additional privileges for LogMiner
GRANT SELECT ON V_\$DATABASE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ON V_\$LOG TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ON V_\$LOGFILE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ON V_\$ARCHIVED_LOG TO C##MIGRATION_USER CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR TO C##MIGRATION_USER CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR_D TO C##MIGRATION_USER CONTAINER=ALL;
EXIT;
SQLEOF
"

echo "[INFO] ✅ C##MIGRATION_USER created"

## GRANT PDB-SPECIFIC PERMISSIONS
echo "[INFO] Granting PDB-specific permissions to C##MIGRATION_USER..."
docker exec oracle-source bash -c "sqlplus / as sysdba <<'SQLEOF'
-- Switch to PDB
ALTER SESSION SET CONTAINER = FREEPDB1;

-- Grant explicit table access for migration
GRANT SELECT, FLASHBACK ON APP_USER.ORDERS TO C##MIGRATION_USER;
GRANT SELECT, FLASHBACK ON APP_USER.ORDER_FILLS TO C##MIGRATION_USER;
GRANT SELECT, INSERT, UPDATE ON APP_USER.REPLICATOR_SENTINEL TO C##MIGRATION_USER;

-- Additional PDB-level grants
GRANT CONNECT TO C##MIGRATION_USER;
GRANT CREATE SESSION TO C##MIGRATION_USER;
GRANT SELECT_CATALOG_ROLE TO C##MIGRATION_USER;

-- Grant access to V$ views in PDB context
GRANT SELECT ON V_\$SESSION TO C##MIGRATION_USER;
GRANT SELECT ON V_\$TRANSACTION TO C##MIGRATION_USER;
GRANT SELECT ON V_\$DATABASE TO C##MIGRATION_USER;
GRANT SELECT ON V_\$LOG TO C##MIGRATION_USER;
GRANT SELECT ON V_\$LOGFILE TO C##MIGRATION_USER;
GRANT SELECT ON V_\$LOGMNR_CONTENTS TO C##MIGRATION_USER;
GRANT SELECT ON V_\$ARCHIVED_LOG TO C##MIGRATION_USER;
GRANT SELECT ON V_\$LOG_HISTORY TO C##MIGRATION_USER;
GRANT SELECT ON V_\$THREAD TO C##MIGRATION_USER;
GRANT SELECT ON V_\$PARAMETER TO C##MIGRATION_USER;
GRANT SELECT ON V_\$TIMEZONE_NAMES TO C##MIGRATION_USER;
GRANT SELECT ON V_\$INSTANCE TO C##MIGRATION_USER;

EXIT;
SQLEOF
"

echo "[INFO] ✅ PDB-specific permissions granted"

## INSTALL PYTHON ORACLE DEPENDENCIES
echo "[INFO] Installing Python Oracle dependencies..."
if command -v apt-get &> /dev/null; then
    PKG_MGR="apt-get"
    apt-get update
    apt-get install -y python3-pip python3-dev gcc
elif command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
    dnf install -y python3-pip python3-devel gcc
else
    PKG_MGR="yum"
    yum install -y python3-pip python3-devel gcc
fi

pip3 install cx_Oracle oracledb --break-system-packages 2>/dev/null || pip3 install cx_Oracle oracledb

## DOWNLOAD SQL SCRIPTS, PYTHON APPS, AND MOLT CONFIGS
echo "[INFO] Downloading Oracle migration resources from GitHub..."

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/courses/migration-labs/oracle"
ORACLE_DIR="/root/oracle"

# Create directory structure
mkdir -p ${ORACLE_DIR}/{sql-scripts,python-apps,molt-config}

# Download SQL scripts
echo "[INFO] Downloading SQL scripts..."
curl -fsSL "${BASE_URL}/sql-scripts/oracle_source_schema.sql" -o "${ORACLE_DIR}/sql-scripts/oracle_source_schema.sql"
curl -fsSL "${BASE_URL}/sql-scripts/oracle_source_data.sql" -o "${ORACLE_DIR}/sql-scripts/oracle_source_data.sql"
curl -fsSL "${BASE_URL}/sql-scripts/crdb_target_schema.sql" -o "${ORACLE_DIR}/sql-scripts/crdb_target_schema.sql"
curl -fsSL "${BASE_URL}/sql-scripts/verification_queries.sql" -o "${ORACLE_DIR}/sql-scripts/verification_queries.sql"

# Download Python apps
echo "[INFO] Downloading Python applications..."
curl -fsSL "${BASE_URL}/python-apps/oracle-workload.py" -o "${ORACLE_DIR}/python-apps/oracle-workload.py"
curl -fsSL "${BASE_URL}/python-apps/cockroach-workload.py" -o "${ORACLE_DIR}/python-apps/cockroach-workload.py"
curl -fsSL "${BASE_URL}/python-apps/requirements.txt" -o "${ORACLE_DIR}/python-apps/requirements.txt"

# Download MOLT configs
echo "[INFO] Downloading MOLT configuration files..."
curl -fsSL "${BASE_URL}/molt-config/transforms.json" -o "${ORACLE_DIR}/molt-config/transforms.json"
curl -fsSL "${BASE_URL}/molt-config/molt_fetch.sh" -o "${ORACLE_DIR}/molt-config/molt_fetch.sh"
curl -fsSL "${BASE_URL}/molt-config/molt_verify.sh" -o "${ORACLE_DIR}/molt-config/molt_verify.sh"
curl -fsSL "${BASE_URL}/molt-config/start_replicator.sh" -o "${ORACLE_DIR}/molt-config/start_replicator.sh"

# Make scripts executable
chmod +x ${ORACLE_DIR}/molt-config/*.sh
chmod +x ${ORACLE_DIR}/python-apps/*.py

## EXECUTE ORACLE SOURCE SCHEMA CREATION
echo "[INFO] Creating Oracle source schema..."

# Copy SQL scripts into container
docker cp ${ORACLE_DIR}/sql-scripts/oracle_source_schema.sql oracle-source:/tmp/
docker cp ${ORACLE_DIR}/sql-scripts/oracle_source_data.sql oracle-source:/tmp/

# Execute schema and data creation
docker exec oracle-source bash -c "sqlplus / as sysdba @/tmp/oracle_source_schema.sql"
docker exec oracle-source bash -c "sqlplus / as sysdba @/tmp/oracle_source_data.sql"

## CREATE CRDB TARGET SCHEMA (only if CockroachDB is running)
if command -v cockroach &> /dev/null && pgrep -f cockroach > /dev/null; then
    echo "[INFO] Creating CockroachDB target schema..."
    cockroach sql --insecure < ${ORACLE_DIR}/sql-scripts/crdb_target_schema.sql
else
    echo "[INFO] CockroachDB not running yet, skipping target schema creation"
    echo "[INFO] You can run this later: cockroach sql --insecure < ${ORACLE_DIR}/sql-scripts/crdb_target_schema.sql"
fi

## SETUP CONNECTION SCRIPTS
echo "[INFO] Creating connection helper scripts..."

# Oracle connection script for APP_USER
cat > /root/oracle/connect_oracle_app.sh << 'EOF'
#!/bin/bash
docker exec -i oracle-source sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1
EOF
chmod +x /root/oracle/connect_oracle_app.sh

# Oracle connection script for MIGRATION_USER
cat > /root/oracle/connect_oracle_migration.sh << 'EOF'
#!/bin/bash
docker exec -i oracle-source sqlplus 'C##MIGRATION_USER/migpass@//localhost:1521/FREE'
EOF
chmod +x /root/oracle/connect_oracle_migration.sh

# CockroachDB connection script
cat > /root/oracle/connect_crdb.sh << 'EOF'
#!/bin/bash
cockroach sql --insecure -d target
EOF
chmod +x /root/oracle/connect_crdb.sh

# Create helper script to run SQL commands in Oracle
cat > /root/oracle/oracle_exec.sh << 'EOF'
#!/bin/bash
# Helper script to execute SQL commands in Oracle container
# Usage: ./oracle_exec.sh "SELECT * FROM orders;"
docker exec oracle-source bash -c "echo \"$1\" | sqlplus -s APP_USER/apppass@//localhost:1521/FREEPDB1"
EOF
chmod +x /root/oracle/oracle_exec.sh

echo "[INFO] ============================================"
echo "[INFO] Oracle Docker Setup Complete!"
echo "[INFO] ============================================"
echo "[INFO] Oracle Container: oracle-source"
echo "[INFO] Oracle Port: 1521"
echo "[INFO] Oracle PDB: FREEPDB1"
echo "[INFO] Passwords:"
echo "[INFO]   - SYS/SYSTEM: CockroachDB_123"
echo "[INFO]   - C##MIGRATION_USER: migpass"
echo "[INFO]   - APP_USER: apppass"
echo "[INFO] ============================================"
echo "[INFO] Connection scripts:"
echo "[INFO]   - /root/oracle/connect_oracle_app.sh"
echo "[INFO]   - /root/oracle/connect_oracle_migration.sh"
echo "[INFO]   - /root/oracle/connect_crdb.sh"
echo "[INFO]   - /root/oracle/oracle_exec.sh"
echo "[INFO] ============================================"
echo "[INFO] Oracle resources available at: ${ORACLE_DIR}"
echo "[INFO] ============================================"
