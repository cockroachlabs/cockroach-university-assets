#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Oracle 26ai Minimal Installation for Host Image"
echo "[INFO] This creates a basic working Oracle database"
echo "[INFO] ============================================"

## INSTALL ORACLE RPM ONLY
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

echo "[INFO] Installing dependencies..."
sudo ${PKG_MGR} install -y libaio bc binutils glibc make curl

cd /tmp
ORACLE_RPM="oracle-ai-database-free-26ai-23.26.0-1.el8.x86_64.rpm"
ORACLE_RPM_URL="https://download.oracle.com/otn-pub/otn_software/db-free/${ORACLE_RPM}"

if [ ! -f "${ORACLE_RPM}" ]; then
    echo "[INFO] Downloading Oracle RPM..."
    curl -# -L -o "${ORACLE_RPM}" "${ORACLE_RPM_URL}"
fi

echo "[INFO] Installing Oracle RPM..."
sudo rpm -ivh --nodeps "${ORACLE_RPM}"

export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH

echo "[INFO] Creating directories and minimal database..."
sudo -u oracle bash << 'ORACLE_SETUP'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib

# Create directories
mkdir -p /opt/oracle/oradata/FREE
mkdir -p /opt/oracle/admin/FREE/adump

# Create minimal init file
cat > $ORACLE_HOME/dbs/initFREE.ora << 'EOF'
db_name=FREE
memory_target=1G
processes=150
db_block_size=8192
compatible=23.0.0
control_files=(/opt/oracle/oradata/FREE/control01.ctl)
undo_tablespace=UNDOTBS1
EOF

# Create password file
$ORACLE_HOME/bin/orapwd file=$ORACLE_HOME/dbs/orapwFREE password=CockroachDB123 entries=10

# Start instance and create minimal database
$ORACLE_HOME/bin/sqlplus / as sysdba << 'SQLEOF'
STARTUP NOMOUNT PFILE='/opt/oracle/product/26ai/dbhomeFree/dbs/initFREE.ora';

-- Create minimal database (no PDB, just CDB)
CREATE DATABASE FREE
  USER SYS IDENTIFIED BY CockroachDB123
  USER SYSTEM IDENTIFIED BY CockroachDB123
  LOGFILE GROUP 1 ('/opt/oracle/oradata/FREE/redo01.log') SIZE 50M,
          GROUP 2 ('/opt/oracle/oradata/FREE/redo02.log') SIZE 50M
  MAXLOGFILES 5
  MAXDATAFILES 100
  CHARACTER SET AL32UTF8
  NATIONAL CHARACTER SET AL16UTF16
  DATAFILE '/opt/oracle/oradata/FREE/system01.dbf' SIZE 500M AUTOEXTEND ON
  SYSAUX DATAFILE '/opt/oracle/oradata/FREE/sysaux01.dbf' SIZE 300M AUTOEXTEND ON
  DEFAULT TABLESPACE users DATAFILE '/opt/oracle/oradata/FREE/users01.dbf' SIZE 100M AUTOEXTEND ON
  DEFAULT TEMPORARY TABLESPACE temp TEMPFILE '/opt/oracle/oradata/FREE/temp01.dbf' SIZE 50M AUTOEXTEND ON
  UNDO TABLESPACE undotbs1 DATAFILE '/opt/oracle/oradata/FREE/undotbs01.dbf' SIZE 100M AUTOEXTEND ON;

-- Database is now created and mounted, open it
ALTER DATABASE OPEN;

-- Create SPFILE
CREATE SPFILE FROM PFILE;

-- Show status
SELECT instance_name, status FROM v$instance;
SELECT name, open_mode FROM v$database;

EXIT;
SQLEOF
ORACLE_SETUP

echo "[INFO] ✅ Minimal Oracle database created"

# Create listener config
sudo -u oracle bash << 'EOF'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
mkdir -p $ORACLE_HOME/network/admin

cat > $ORACLE_HOME/network/admin/listener.ora << 'LISTEOF'
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    )
  )
LISTEOF

# Start listener
$ORACLE_HOME/bin/lsnrctl start
EOF

echo "[INFO] ✅ Listener started"

# Verify
sleep 3
if pgrep -f "ora_pmon_FREE" > /dev/null; then
    echo "[INFO] ✅ Oracle Database is running!"
    echo ""
    echo "[INFO] Database: FREE (CDB only, no PDB)"
    echo "[INFO] Password: CockroachDB123"
    echo "[INFO] Port: 1521"
    echo ""
    echo "[INFO] Next: Save this VM as your Instruqt host image"
else
    echo "[ERROR] Database failed to start"
    exit 1
fi
