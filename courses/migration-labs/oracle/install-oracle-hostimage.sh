#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Installing Oracle AI Database 26ai Free for Host Image"
echo "[INFO] This script will install and configure Oracle completely"
echo "[INFO] Compatible with CentOS Stream 9/10, Rocky Linux 9"
echo "[INFO] ============================================"

## PREREQUISITES
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

echo "[INFO] Using package manager: ${PKG_MGR}"

## INSTALL DEPENDENCIES
echo "[INFO] Installing dependencies..."

# Core dependencies that must succeed
sudo ${PKG_MGR} install -y \
    libaio \
    bc \
    binutils \
    glibc \
    glibc-devel \
    libgcc \
    libstdc++ \
    libstdc++-devel \
    make \
    curl || {
    echo "[ERROR] Failed to install core dependencies"
    exit 1
}

# Optional dependencies (may not exist in all versions)
sudo ${PKG_MGR} install -y \
    unixODBC \
    ksh \
    sysstat \
    numactl-libs \
    smartmontools \
    compat-libcap1 \
    wget 2>/dev/null || echo "[WARNING] Some optional packages not available"

# Verify libaio is actually installed
if [ ! -f /usr/lib64/libaio.so.1 ]; then
    echo "[ERROR] libaio.so.1 not found - this is required for Oracle"
    echo "[ERROR] Trying alternative installation..."
    sudo ${PKG_MGR} install -y libaio libaio-devel || {
        echo "[ERROR] Cannot install libaio"
        exit 1
    }
fi

echo "[INFO] ✅ Core dependencies installed"
ls -la /usr/lib64/libaio.so* 2>/dev/null || echo "[WARNING] libaio location may vary"

## DOWNLOAD ORACLE RPM
cd /tmp
ORACLE_RPM="oracle-ai-database-free-26ai-23.26.0-1.el8.x86_64.rpm"
ORACLE_RPM_URL="https://download.oracle.com/otn-pub/otn_software/db-free/${ORACLE_RPM}"

if [ ! -f "${ORACLE_RPM}" ]; then
    echo "[INFO] Downloading Oracle 26ai RPM (~1.4GB, this may take 5-10 minutes)..."
    if command -v wget &> /dev/null; then
        wget --progress=dot:giga --timeout=600 --tries=3 "${ORACLE_RPM_URL}" || {
            curl -# -L -o "${ORACLE_RPM}" "${ORACLE_RPM_URL}"
        }
    else
        curl -# -L -o "${ORACLE_RPM}" "${ORACLE_RPM_URL}"
    fi

    # Verify download
    if [ ! -s "${ORACLE_RPM}" ]; then
        echo "[ERROR] Download failed or file is empty"
        exit 1
    fi
    echo "[INFO] ✅ Oracle RPM downloaded: $(ls -lh ${ORACLE_RPM} | awk '{print $5}')"
else
    echo "[INFO] Oracle RPM already exists, skipping download"
fi

## INSTALL ORACLE
echo "[INFO] Installing Oracle Database..."
sudo rpm -ivh --nodeps "${ORACLE_RPM}" || {
    echo "[WARNING] RPM installation had warnings, continuing..."
}

## SET ENVIRONMENT
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}

# Verify Oracle binaries exist
if [ ! -f "$ORACLE_HOME/bin/sqlplus" ]; then
    echo "[ERROR] Oracle installation failed - sqlplus not found"
    exit 1
fi

echo "[INFO] ✅ Oracle binaries installed"

# Create oracle user home if needed
ORACLE_USER_HOME=$(getent passwd oracle | cut -d: -f6)
if [ ! -d "$ORACLE_USER_HOME" ]; then
    sudo mkdir -p "$ORACLE_USER_HOME"
    sudo chown oracle:oinstall "$ORACLE_USER_HOME"
fi

## CONFIGURE LISTENER MANUALLY (no GUI)
echo "[INFO] Configuring Oracle Listener..."
sudo mkdir -p $ORACLE_HOME/network/admin
sudo chown oracle:oinstall $ORACLE_HOME/network/admin

sudo -u oracle bash << 'EOF'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE

# Create listener.ora
cat > $ORACLE_HOME/network/admin/listener.ora << 'LISTEOF'
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
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
LISTEOF

# Create tnsnames.ora
cat > $ORACLE_HOME/network/admin/tnsnames.ora << 'TNSEOF'
FREE =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = FREE)
    )
  )

FREEPDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = FREEPDB1)
    )
  )
TNSEOF

# Create sqlnet.ora
cat > $ORACLE_HOME/network/admin/sqlnet.ora << 'SQLEOF'
NAMES.DIRECTORY_PATH= (TNSNAMES, EZCONNECT)
SQLEOF
EOF

echo "[INFO] ✅ Listener configured"

## START LISTENER
echo "[INFO] Starting listener..."
sudo -u oracle bash << 'EOF'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}
$ORACLE_HOME/bin/lsnrctl start || echo "[INFO] Listener may already be running"
EOF

echo "[INFO] ✅ Listener started"

## CREATE DATABASE USING SEED FILES (Most reliable method)
echo "[INFO] Creating Oracle FREE database from seed files (this takes 5-10 minutes)..."

sudo -u oracle bash << 'EOF'
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}

# Create directories
echo "[INFO] Creating database directories..."
mkdir -p /opt/oracle/oradata/FREE
mkdir -p /opt/oracle/admin/FREE/adump
mkdir -p /opt/oracle/fast_recovery_area

# Copy seed database files
echo "[INFO] Copying seed database files..."
cp $ORACLE_HOME/assistants/dbca/templates/FREE_Seed_Database.ctl /opt/oracle/oradata/FREE/control01.ctl
cp $ORACLE_HOME/assistants/dbca/templates/FREE_Seed_Database.dfb* /opt/oracle/oradata/FREE/

# Rename data files to proper names
cd /opt/oracle/oradata/FREE
mv FREE_Seed_Database.dfb1 system01.dbf
mv FREE_Seed_Database.dfb2 sysaux01.dbf
mv FREE_Seed_Database.dfb3 undotbs01.dbf
mv FREE_Seed_Database.dfb4 users01.dbf
mv FREE_Seed_Database.dfb5 temp01.dbf

echo "[INFO] ✅ Seed files copied and renamed"

# Create init parameter file (fixed for 26ai)
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

# Create password file with complex password
echo "[INFO] Creating password file..."
$ORACLE_HOME/bin/orapwd file=$ORACLE_HOME/dbs/orapwFREE password='Cr0ckr0@ch#2026' entries=10

# Start database
echo "[INFO] Starting Oracle database..."
$ORACLE_HOME/bin/sqlplus / as sysdba << 'SQLEOF'
STARTUP PFILE='/opt/oracle/product/26ai/dbhomeFree/dbs/initFREE.ora';
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER SYSTEM ARCHIVE LOG CURRENT;

-- Create SPFILE from PFILE for automatic startup
CREATE SPFILE FROM PFILE='/opt/oracle/product/26ai/dbhomeFree/dbs/initFREE.ora';

-- Change SYS password to match our standard
ALTER USER SYS IDENTIFIED BY "Cr0ckr0@ch#2026";
ALTER USER SYSTEM IDENTIFIED BY "Cr0ckr0@ch#2026";

-- Show database status
SELECT instance_name, status FROM v$instance;
SELECT name, open_mode FROM v$database;
SELECT name, open_mode FROM v$pdbs;

EXIT;
SQLEOF

echo "[INFO] ✅ Database created and opened"
EOF

## VERIFY DATABASE IS RUNNING
echo "[INFO] Verifying Oracle Database..."
sleep 5

if pgrep -f "ora_pmon_FREE" > /dev/null; then
    echo "[INFO] ✅ Oracle Database is running"
else
    echo "[ERROR] Oracle Database failed to start"
    echo "[ERROR] Check logs at: /opt/oracle/admin/FREE/adump/"
    exit 1
fi

## CONFIGURE AUTO-START (for when host image boots)
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

# Enable the service
systemctl daemon-reload
systemctl enable oracle-free.service
SYSTEMD_EOF

echo "[INFO] ✅ Auto-start configured"

## FINAL VERIFICATION
echo ""
echo "[INFO] ============================================"
echo "[INFO] ✅ Oracle AI Database 26ai Free Installation Complete!"
echo "[INFO] ============================================"
echo "[INFO] Database: FREE"
echo "[INFO] PDB: FREEPDB1"
echo "[INFO] SYS/SYSTEM password: Cr0ckr0@ch#2026"
echo "[INFO] Listener: Running on port 1521"
echo "[INFO] Auto-start: Enabled (systemd)"
echo "[INFO] ============================================"
echo "[INFO] Database files: /opt/oracle/oradata/FREE/"
echo "[INFO] ============================================"
echo ""
echo "[INFO] 🎯 Next Steps:"
echo "[INFO] 1. Run verification: bash verify-oracle-hostimage.sh"
echo "[INFO] 2. If all checks pass, SAVE this VM as your Instruqt host image"
echo "[INFO] ============================================"
