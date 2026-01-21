#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Continuing Oracle Setup After libaio Fix"
echo "[INFO] ============================================"

# Install missing libaio
echo "[INFO] Installing libaio..."
sudo dnf install -y libaio

# Verify
ls -la /usr/lib64/libaio.so.1 || {
    echo "[ERROR] libaio still not found"
    exit 1
}

echo "[INFO] ✅ libaio installed"

# Set environment
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}

# Configure listener
echo "[INFO] Configuring Oracle Listener..."
sudo -u oracle bash << 'LISTENER_EOF'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE

mkdir -p $ORACLE_HOME/network/admin

cat > $ORACLE_HOME/network/admin/listener.ora << 'LISTENEREOF'
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    )
  )
SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = FREE)
      (ORACLE_HOME = /opt/oracle/product/26ai/dbhomeFree)
      (SID_NAME = FREE)
    )
  )
LISTENEREOF

cat > $ORACLE_HOME/network/admin/tnsnames.ora << 'TNSNEOF'
FREE =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA = (SERVICE_NAME = FREE))
  )
FREEPDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA = (SERVICE_NAME = FREEPDB1))
  )
TNSNEOF
LISTENER_EOF

echo "[INFO] ✅ Listener configured"

# Start listener
echo "[INFO] Starting listener..."
sudo -u oracle bash << 'LSNR_START'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
$ORACLE_HOME/bin/lsnrctl start
LSNR_START

echo "[INFO] ✅ Listener started"

# Create database from seed files
echo "[INFO] Creating Oracle database from seed files..."
sudo -u oracle bash << 'CREATE_DB'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib

echo "[INFO] Creating directories..."
mkdir -p /opt/oracle/oradata/FREE
mkdir -p /opt/oracle/admin/FREE/adump
mkdir -p /opt/oracle/fast_recovery_area

echo "[INFO] Copying seed database files..."
cp $ORACLE_HOME/assistants/dbca/templates/FREE_Seed_Database.ctl /opt/oracle/oradata/FREE/control01.ctl
cp $ORACLE_HOME/assistants/dbca/templates/FREE_Seed_Database.dfb* /opt/oracle/oradata/FREE/

cd /opt/oracle/oradata/FREE
mv FREE_Seed_Database.dfb1 system01.dbf
mv FREE_Seed_Database.dfb2 sysaux01.dbf
mv FREE_Seed_Database.dfb3 undotbs01.dbf
mv FREE_Seed_Database.dfb4 users01.dbf
mv FREE_Seed_Database.dfb5 temp01.dbf

echo "[INFO] Creating init parameter file..."
cat > $ORACLE_HOME/dbs/initFREE.ora << 'INITEOF'
db_name=FREE
memory_target=2G
processes=300
db_block_size=8192
compatible=23.0.0
control_files=(/opt/oracle/oradata/FREE/control01.ctl)
enable_pluggable_database=true
undo_tablespace=UNDOTBS1
db_recovery_file_dest=/opt/oracle/fast_recovery_area
db_recovery_file_dest_size=10G
INITEOF

echo "[INFO] Creating password file..."
$ORACLE_HOME/bin/orapwd file=$ORACLE_HOME/dbs/orapwFREE password='Cr0ckr0@ch#2026' entries=10

echo "[INFO] Starting Oracle database..."
$ORACLE_HOME/bin/sqlplus / as sysdba << 'SQLEOF'
STARTUP PFILE='/opt/oracle/product/26ai/dbhomeFree/dbs/initFREE.ora';
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
CREATE SPFILE FROM PFILE='/opt/oracle/product/26ai/dbhomeFree/dbs/initFREE.ora';
ALTER USER SYS IDENTIFIED BY "Cr0ckr0@ch#2026";
ALTER USER SYSTEM IDENTIFIED BY "Cr0ckr0@ch#2026";
SELECT instance_name, status FROM v$instance;
SELECT name, open_mode FROM v$pdbs;
EXIT;
SQLEOF
CREATE_DB

echo "[INFO] Verifying Oracle is running..."
sleep 5

if pgrep -f ora_pmon_FREE > /dev/null; then
    echo "[INFO] ============================================"
    echo "[INFO] ✅ Oracle Database 26ai Free is running!"
    echo "[INFO] ============================================"
    echo "[INFO] Database: FREE"
    echo "[INFO] PDB: FREEPDB1"
    echo "[INFO] Password: Cr0ckr0@ch#2026"
    echo "[INFO] ============================================"

    # Configure auto-start
    echo "[INFO] Configuring Oracle auto-start..."
    sudo bash << 'SYSTEMD_EOF'
cat > /etc/systemd/system/oracle-free.service << 'SERVICEEOF'
[Unit]
Description=Oracle Database 26ai Free
After=network.target

[Service]
Type=forking
User=oracle
Group=oinstall
Environment="ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree"
Environment="ORACLE_SID=FREE"
Environment="PATH=/opt/oracle/product/26ai/dbhomeFree/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin"
Environment="LD_LIBRARY_PATH=/opt/oracle/product/26ai/dbhomeFree/lib"
ExecStart=/opt/oracle/product/26ai/dbhomeFree/bin/dbstart /opt/oracle/product/26ai/dbhomeFree
ExecStop=/opt/oracle/product/26ai/dbhomeFree/bin/dbshut /opt/oracle/product/26ai/dbhomeFree
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable oracle-free.service
SYSTEMD_EOF

    echo "[INFO] ============================================"
    echo "[INFO] ✅ Setup Complete! Save this as host image!"
    echo "[INFO] ============================================"
else
    echo "[ERROR] ❌ Oracle Database failed to start"
    echo "[ERROR] Check logs at: /opt/oracle/admin/FREE/adump/"
    exit 1
fi
