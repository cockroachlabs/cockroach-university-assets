#!/bin/bash
set -euxo pipefail

## INSTALLATION
echo "[INFO] Updating package list and installing required packages..."

# Determine package manager (dnf for newer RHEL/Fedora/CentOS, yum for older)
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

echo "[INFO] Using package manager: ${PKG_MGR}"

# Install EPEL repository for additional packages (if not already installed)
sudo ${PKG_MGR} install -y epel-release || true

# Update package cache
sudo ${PKG_MGR} update -y

# Install required packages
sudo ${PKG_MGR} install -y \
    curl \
    wget \
    unzip \
    git \
    jq \
    python3-pip \
    python3-devel \
    gcc \
    postgresql-devel \
    tmux \
    tree \
    socat \
    haproxy

# Install psycopg2 via pip since python3-psycopg2 package name differs
pip3 install psycopg2-binary

echo "[INFO] RedHat base packages installed successfully"
