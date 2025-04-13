#!/bin/bash
set -euxo pipefail

# Only execute the following lines if the code server is running
if command -v "code-server" > /dev/null 2>&1; then 

    ## INSTALLING CODE SERVER EXTENSIONS [jvm]
    echo "[INFO] Installing code-server extensions [jvm]..."
    code-server --install-extension vscjava.vscode-java-pack >> /var/log/vscode-ext.out 2>> /var/log/vscode-ext.err < /dev/null &
    code-server --install-extension vmware.vscode-boot-dev-pack >> /var/log/vscode-ext.out 2>> /var/log/vscode-ext.err < /dev/null &
fi