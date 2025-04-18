#!/bin/bash
set -euxo pipefail

TMP=/tmp/apps
APPS=/root/cockroachdb/
UUID=/root/cockroachdb/migration/

# If $TMP doesn't exist, create it
if [ ! -d "$TMP" ]; then
    echo "[INFO] Creating $TMP directory..."
    mkdir -p $TMP
else
    echo "[INFO] $TMP directory already exists."
fi
# If $APPS doesn't exist, create it
if [ ! -d "$APPS" ]; then
    echo "[INFO] Creating $APPS directory..."
    mkdir -p $APPS
else
    echo "[INFO] $APPS directory already exists."
fi
# If $UUID doesn't exist, create it
if [ ! -d "$UUID" ]; then
    echo "[INFO] Creating $UUID directory..."
    mkdir -p $UUID
else
    echo "[INFO] $UUID directory already exists."
fi

# If exists the program git, clone a repo
if command -v git >/dev/null 2>&1; then
    echo "[INFO] Cloning repository..."
    git clone https://github.com/cockroachlabs/cockroach-university-apps.git /tmp/apps/
    echo "[INFO] Cloning completed."
    echo "[INFO] Moving files..."
    # Move the apps to the correct directory
    mv $TMP/migration-java-apps/crm $APPS
    mv $TMP/migration-java-apps/logistics $APPS
    mv $TMP/migration-python-apps/int-to-uuid/* $UUID

    echo "[INFO] Moving completed."
    echo "[INFO] Removing $TMP directory..."
    rm -rf $TMP
else
    echo "[WARN] Git is not installed. Please install Git to proceed."
fi