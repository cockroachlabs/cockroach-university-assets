#!/bin/bash
set -euxo pipefail

# Only execute the following lines if the code server is running
if pgrep -x "code-server" > /dev/null; then 

    ## INSTALLING CODE SERVER EXTENSIONS
    code-server --install-extension ms-vscode-remote.remote-containers > /var/log/vscode-ext.out 2> /var/log/vscode-ext.err < /dev/null &
    
fi