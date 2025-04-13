#!/bin/bash
set -euxo pipefail

# Only execute the following lines if the code server is running
if command -v "code-server" > /dev/null 2>&1; then 

    ## INSTALLING CODE SERVER EXTENSIONS [sql]
    echo "[INFO] Installing code-server extensions [sql]..."
    code-server --install-extension mtxr.sqltools >> /var/log/vscode-ext.out 2>> /var/log/vscode-ext.err < /dev/null &
    code-server --install-extension mtxr.sqltools-driver-pg >> /var/log/vscode-ext.out 2>> /var/log/vscode-ext.err < /dev/null &
    code-server --install-extension mtxr.sqltools-driver-mysql >> /var/log/vscode-ext.out 2>> /var/log/vscode-ext.err < /dev/null &
    
fi