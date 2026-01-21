#!/bin/bash
set -euxo pipefail

## INSTALLATION
echo "[INFO] Installing databases..."

# Determine package manager (dnf for newer RHEL/Fedora/CentOS, yum for older)
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

echo "[INFO] Using package manager: ${PKG_MGR}"

# Update package cache
sudo ${PKG_MGR} update -y

# Install MySQL/MariaDB and PostgreSQL
sudo ${PKG_MGR} install -y \
    mariadb-server \
    postgresql-server \
    postgresql-contrib

# Initialize PostgreSQL database (required on RHEL-based systems)
if [ ! -d "/var/lib/pgsql/data" ]; then
    sudo postgresql-setup --initdb || sudo /usr/bin/postgresql-setup initdb
fi

# Start and enable services
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo systemctl start postgresql
sudo systemctl enable postgresql

echo "[INFO] Databases installed and started successfully"
