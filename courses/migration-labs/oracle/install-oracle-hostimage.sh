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

## CONFIGURE ORACLE DATABASE USING OFFICIAL SCRIPT
echo "[INFO] Configuring Oracle Database using official configuration script..."

# Set password in configuration file
sudo sed -i 's/^ORACLE_PASSWORD=.*/ORACLE_PASSWORD=Cr0ckr0@ch#2026/' /etc/sysconfig/oracle-free-26ai.conf || true

# Run Oracle's official configuration script
sudo /etc/init.d/oracle-free-26ai configure

echo "[INFO] ✅ Database configured"

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
