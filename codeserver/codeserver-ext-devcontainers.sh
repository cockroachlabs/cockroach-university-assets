#!/bin/bash
set -euxo pipefail

# Only execute the following lines if the code server is running
if command -v "code-server" > /dev/null 2>&1; then 

    ## INSTALLING CODE SERVER EXTENSIONS\
    echo "[INFO] Installing code-server extensions [devcontainers]..."
    code-server --install-extension ms-vscode-remote.remote-containers >> /var/log/vscode-ext.out 2>> /var/log/vscode-ext.err < /dev/null &
    
fi