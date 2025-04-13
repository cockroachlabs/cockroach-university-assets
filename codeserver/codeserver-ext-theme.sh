#!/bin/bash
set -euxo pipefail

# Only execute the following lines if the code server is running
if command -v "code-server" > /dev/null 2>&1; then 

    ## INSTALLING CODE SERVER EXTENSIONS
    echo "[INFO] Installing code-server extensions [theme]..." 
    code-server --install-extension wildberries-theme.wildberries >> /var/log/vscode-ext.out 2>> /var/log/vscode-ext.err < /dev/null &
fi