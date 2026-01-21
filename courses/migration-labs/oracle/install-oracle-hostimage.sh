#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Installing Oracle Database 23ai Free for Host Image"
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
ORACLE_RPM="oracle-database-free-23ai-1.0-1.el8.x86_64.rpm"
ORACLE_RPM_URL="https://download.oracle.com/otn-pub/otn_software/db-free/${ORACLE_RPM}"

if [ ! -f "${ORACLE_RPM}" ]; then
    echo "[INFO] Downloading Oracle 23ai Free RPM (~1.2GB, this may take 5-10 minutes)..."
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
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
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

## CONFIGURE ORACLE DATABASE USING OFFICIAL SCRIPT
echo ""
echo "[INFO] ============================================"
echo "[INFO] Oracle Database Configuration"
echo "[INFO] ============================================"
echo "[INFO] You will be prompted to enter a password for database accounts."
echo "[INFO] "
echo "[INFO] IMPORTANT: Use this password: CockroachDB_123"
echo "[INFO] "
echo "[INFO] You'll need to enter it 3 times for:"
echo "[INFO]   1. SYS user password"
echo "[INFO]   2. SYSTEM user password"
echo "[INFO]   3. PDBADMIN user password"
echo "[INFO] "
echo "[INFO] Configuration takes 5-15 minutes. Please be patient..."
echo "[INFO] ============================================"
echo ""

# Run Oracle's official configuration script (requires manual password entry)
echo "[INFO] Running Oracle configuration script..."
echo "[INFO] NOTE: This may fail with DBCA errors - that's expected!"
echo ""

sudo /etc/init.d/oracle-free-23ai configure || {
    echo ""
    echo "[WARNING] ============================================"
    echo "[WARNING] DBCA configuration failed (this is expected)"
    echo "[WARNING] Now we'll manually complete the database setup"
    echo "[WARNING] ============================================"
    echo ""
}

# Manual database completion (in case DBCA failed)
echo "[INFO] Completing database setup manually..."

sudo -u oracle bash << 'MANUAL_COMPLETION'
export ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib

# Check if database files exist
if [ -d "/opt/oracle/oradata/FREE" ] && [ "$(ls -A /opt/oracle/oradata/FREE 2>/dev/null)" ]; then
    echo "[INFO] Database files found, attempting to start existing database..."

    # Try to start existing database
    $ORACLE_HOME/bin/sqlplus / as sysdba << 'SQLEOF'
STARTUP MOUNT;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
EXIT;
SQLEOF

    if [ $? -eq 0 ]; then
        echo "[INFO] ✅ Existing database started successfully"
        exit 0
    fi
fi

# If no database or startup failed, create fresh
echo "[INFO] Creating fresh database manually..."

# Clean up any partial files
rm -rf /opt/oracle/oradata/FREE/*
mkdir -p /opt/oracle/oradata/FREE
mkdir -p /opt/oracle/admin/FREE/adump

# Create listener config
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
$ORACLE_HOME/bin/lsnrctl start || echo "[INFO] Listener may already be running"

# Create init file
cat > $ORACLE_HOME/dbs/initFREE.ora << 'INITEOF'
db_name=FREE
memory_target=1G
processes=150
db_block_size=8192
compatible=23.0.0
control_files=(/opt/oracle/oradata/FREE/control01.ctl)
undo_tablespace=UNDOTBS1
INITEOF

# Create password file
$ORACLE_HOME/bin/orapwd file=$ORACLE_HOME/dbs/orapwFREE password=CockroachDB_123 entries=10 force=y

# Create database using DBCA in silent mode (simpler than SQL)
$ORACLE_HOME/bin/dbca -silent \
  -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname FREE \
  -sid FREE \
  -sysPassword CockroachDB_123 \
  -systemPassword CockroachDB_123 \
  -characterSet AL32UTF8 \
  -memoryPercentage 40 \
  -emConfiguration NONE \
  -storageType FS \
  -datafileDestination /opt/oracle/oradata || {

    echo "[WARNING] DBCA silent mode also failed, trying basic SQL creation..."

    # Last resort: simplest possible database
    $ORACLE_HOME/bin/sqlplus / as sysdba << 'SQLEOF'
STARTUP NOMOUNT;
CREATE DATABASE FREE
  CONTROLFILE REUSE
  LOGFILE GROUP 1 ('/opt/oracle/oradata/FREE/redo01.log') SIZE 50M
  CHARACTER SET AL32UTF8
  NATIONAL CHARACTER SET AL16UTF16
  DATAFILE '/opt/oracle/oradata/FREE/system01.dbf' SIZE 500M AUTOEXTEND ON
  SYSAUX DATAFILE '/opt/oracle/oradata/FREE/sysaux01.dbf' SIZE 300M AUTOEXTEND ON
  UNDO TABLESPACE undotbs1 DATAFILE '/opt/oracle/oradata/FREE/undotbs01.dbf' SIZE 100M AUTOEXTEND ON;
ALTER DATABASE OPEN;
CREATE SPFILE FROM PFILE;
EXIT;
SQLEOF
}

MANUAL_COMPLETION

echo ""
echo "[INFO] ✅ Database setup completed"

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
Description=Oracle Database 23ai Free
After=network.target

[Service]
Type=forking
User=oracle
Group=oinstall
Environment="ORACLE_HOME=/opt/oracle/product/23ai/dbhomeFree"
Environment="ORACLE_SID=FREE"
Environment="PATH=/opt/oracle/product/23ai/dbhomeFree/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin"
Environment="LD_LIBRARY_PATH=/opt/oracle/product/23ai/dbhomeFree/lib"
ExecStart=/opt/oracle/product/23ai/dbhomeFree/bin/dbstart /opt/oracle/product/23ai/dbhomeFree
ExecStop=/opt/oracle/product/23ai/dbhomeFree/bin/dbshut /opt/oracle/product/23ai/dbhomeFree
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
echo "[INFO] ✅ Oracle Database 23ai Free Installation Complete!"
echo "[INFO] ============================================"
echo "[INFO] Database: FREE (CDB)"
echo "[INFO] PDB: FREEPDB1"
echo "[INFO] SYS/SYSTEM/PDBADMIN password: CockroachDB_123"
echo "[INFO] Listener: Running on port 1521"
echo "[INFO] Auto-start: Enabled (Oracle service)"
echo "[INFO] ============================================"
echo "[INFO] Database files: /opt/oracle/oradata/FREE/"
echo "[INFO] ============================================"
echo ""
echo "[INFO] 🎯 Next Steps:"
echo "[INFO] 1. Download and run verification script:"
echo "[INFO]    curl -fsSL https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/courses/migration-labs/oracle/verify-oracle-hostimage.sh -o /tmp/verify.sh"
echo "[INFO]    bash /tmp/verify.sh"
echo "[INFO] 2. If all checks pass, SAVE this VM as your Instruqt host image"
echo "[INFO] ============================================"
