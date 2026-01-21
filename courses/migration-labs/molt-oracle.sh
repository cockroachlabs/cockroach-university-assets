#!/bin/bash
set -euxo pipefail

## INSTALLING MOLT WITH ORACLE SUPPORT
echo "[INFO] Installing MOLT with Oracle support..."

## INSTALL ORACLE INSTANT CLIENT (Required for MOLT Oracle drivers)
echo "[INFO] Installing Oracle Instant Client 23.26..."
ORACLE_CLIENT_DIR="/usr/lib/oracle/23.26/client64"
mkdir -p ${ORACLE_CLIENT_DIR}

# Install required packages
apt-get update
apt-get install -y libaio1 unzip wget

# Download and install Oracle Instant Client Basic
echo "[INFO] Downloading Oracle Instant Client Basic..."
wget -q https://download.oracle.com/otn_software/linux/instantclient/2326000/instantclient-basic-linux.x64-23.26.0.0.0.zip -O /tmp/instantclient-basic.zip

echo "[INFO] Extracting Oracle Instant Client..."
unzip -q /tmp/instantclient-basic.zip -d /tmp/
mv /tmp/instantclient_23_26/* ${ORACLE_CLIENT_DIR}/
rm -rf /tmp/instantclient-basic.zip /tmp/instantclient_23_26

# Create symlinks
ln -sf ${ORACLE_CLIENT_DIR}/libclntsh.so.23.1 ${ORACLE_CLIENT_DIR}/libclntsh.so

# Set environment variables
export ORACLE_HOME=${ORACLE_CLIENT_DIR}
export LD_LIBRARY_PATH=${ORACLE_CLIENT_DIR}
export PATH=${ORACLE_CLIENT_DIR}:${PATH}

# Add to bashrc for persistence (avoid trailing colon in LD_LIBRARY_PATH)
echo "export ORACLE_HOME=${ORACLE_CLIENT_DIR}" >> /root/.bashrc
echo "export LD_LIBRARY_PATH=${ORACLE_CLIENT_DIR}" >> /root/.bashrc
echo "export PATH=${ORACLE_CLIENT_DIR}:\${PATH}" >> /root/.bashrc

# Create ldconfig entry
echo ${ORACLE_CLIENT_DIR} > /etc/ld.so.conf.d/oracle-instantclient.conf
ldconfig

echo "[INFO] ✅ Oracle Instant Client installed"

## DOWNLOAD AND INSTALL MOLT WITH ORACLE SUPPORT
echo "[INFO] Downloading MOLT with Oracle drivers..."
curl -L https://molt.cockroachdb.com/molt/cli/molt-latest.linux-amd64-oracle.tgz -o /tmp/molt-oracle.tgz

echo "[INFO] Installing MOLT and Replicator..."
tar -xzf /tmp/molt-oracle.tgz -C /tmp/
cp /tmp/molt /tmp/replicator /usr/local/bin/
chmod +x /usr/local/bin/molt /usr/local/bin/replicator
rm -rf /tmp/molt-oracle.tgz /tmp/molt /tmp/replicator

echo "[INFO] ✅ MOLT with Oracle support installed"

# Verify installation
molt --version
echo "[INFO] MOLT installation complete"
