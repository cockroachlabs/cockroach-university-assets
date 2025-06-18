#!/bin/bash
set -euxo pipefail

BRANCH=main
TMP=/tmp/apps
APPS=/root/cockroachdb/

## INSTALLATION
echo "[INFO] Clonning repository..."

if command -v git >/dev/null 2>&1; then
    echo "[INFO] Sparse Checkout..."
    mkdir -p $TMP
    cd $TMP
    git init
    git remote add origin https://github.com/cockroachlabs/cockroach-university-apps.git
    git config core.sparseCheckout true
    echo "cdc" >> .git/info/sparse-checkout
    git pull origin $BRANCH

    echo "[INFO] Cloning completed."
    echo "[INFO] Moving files..."
    # Move the apps to the correct directory
    mv $TMP/cdc $APPS
    
    echo "[INFO] Moving completed."
    echo "[INFO] Removing $TMP directory..."
    rm -rf $TMP
else
    echo "[WARN] Git is not installed. Please install Git to proceed."
fi