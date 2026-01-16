#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Installing and configuring Oracle Database 23ai Free"
echo "[INFO] ============================================"

## PREREQUISITES
export DEBIAN_FRONTEND=noninteractive

## INSTALL ORACLE 23ai FREE
echo "[INFO] Installing Oracle Database 23ai Free..."

# Download Oracle Database 23ai Free .deb package
cd /tmp
wget -q https://download.oracle.com/otn-pub/otn_software/db-free/oracle-database-free-23ai_1.0-1_amd64.deb

# Install dependencies
sudo apt-get update
sudo apt-get install -y alien libaio1 unixodbc

# Install Oracle
sudo dpkg -i oracle-database-free-23ai_1.0-1_amd64.deb || true
sudo apt-get install -f -y

# Configure Oracle
echo "[INFO] Configuring Oracle Database..."
sudo /etc/init.d/oracle-free-23ai configure

# Set environment variables
cat >> ~/.bashrc << 'EOF'
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH
EOF

source ~/.bashrc

# Wait for database to be ready
echo "[INFO] Waiting for Oracle database to be ready..."
sleep 30

## ENABLE ARCHIVELOG MODE (Required for CDC/Replicator)
echo "[INFO] Enabling ARCHIVELOG mode for CDC support..."
sudo su - oracle << 'ORACLE_SETUP'
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH

sqlplus / as sysdba << EOF
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER DATABASE FORCE LOGGING;
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;
EXIT;
EOF
ORACLE_SETUP

## CREATE MIGRATION USER (Common user for CDB and PDB)
echo "[INFO] Creating migration user C##MIGRATION_USER..."
sudo su - oracle << 'ORACLE_USER'
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH

sqlplus / as sysdba << EOF
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
GRANT CREATE TABLESPACE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT ALTER TABLESPACE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT UNLIMITED TABLESPACE TO C##MIGRATION_USER CONTAINER=ALL;

-- Grant additional privileges for LogMiner
GRANT SELECT ON V_\$DATABASE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ON V_\$LOG TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ON V_\$LOGFILE TO C##MIGRATION_USER CONTAINER=ALL;
GRANT SELECT ON V_\$ARCHIVED_LOG TO C##MIGRATION_USER CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR TO C##MIGRATION_USER CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR_D TO C##MIGRATION_USER CONTAINER=ALL;

EXIT;
EOF
ORACLE_USER

## INSTALL PYTHON ORACLE DEPENDENCIES
echo "[INFO] Installing Python Oracle dependencies..."
sudo apt-get install -y python3-pip python3-venv
pip3 install cx_Oracle oracledb --break-system-packages

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
sudo su - oracle << ORACLE_SCHEMA
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH

sqlplus / as sysdba @${ORACLE_DIR}/sql-scripts/oracle_source_schema.sql
sqlplus / as sysdba @${ORACLE_DIR}/sql-scripts/oracle_source_data.sql
ORACLE_SCHEMA

## CREATE CRDB TARGET SCHEMA
echo "[INFO] Creating CockroachDB target schema..."
cockroach sql --insecure < ${ORACLE_DIR}/sql-scripts/crdb_target_schema.sql

## SETUP CONNECTION SCRIPTS
echo "[INFO] Creating connection helper scripts..."

# Oracle connection script for APP_USER
cat > /root/oracle/connect_oracle_app.sh << 'EOF'
#!/bin/bash
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1
EOF
chmod +x /root/oracle/connect_oracle_app.sh

# Oracle connection script for MIGRATION_USER
cat > /root/oracle/connect_oracle_migration.sh << 'EOF'
#!/bin/bash
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
sqlplus 'C##MIGRATION_USER/migpass@//localhost:1521/FREE'
EOF
chmod +x /root/oracle/connect_oracle_migration.sh

# CockroachDB connection script
cat > /root/oracle/connect_crdb.sh << 'EOF'
#!/bin/bash
cockroach sql --insecure -d target
EOF
chmod +x /root/oracle/connect_crdb.sh

echo "[INFO] ============================================"
echo "[INFO] Oracle Database 23ai Free setup complete!"
echo "[INFO] ============================================"
echo "[INFO] Oracle resources available at: ${ORACLE_DIR}"
echo "[INFO] Connection scripts:"
echo "[INFO]   - /root/oracle/connect_oracle_app.sh"
echo "[INFO]   - /root/oracle/connect_oracle_migration.sh"
echo "[INFO]   - /root/oracle/connect_crdb.sh"
echo "[INFO] ============================================"
