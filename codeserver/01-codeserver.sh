#!/bin/bash
set -euxo pipefail

export CODE_SERVER_VERSION=${CODE_SERVER_VERSION:-4.22.0}

## CODE SERVER
echo "[INFO] Downloading code-server version $CODE_SERVER_VERSION ..."
curl -sfOL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb
sudo dpkg -i code-server_${CODE_SERVER_VERSION}_amd64.deb
rm -rf code-server_${CODE_SERVER_VERSION}_amd64.deb

## EXPOSE PORTS
echo "[INFO] Exposing ports..."
export PORT=3001
nohup code-server --auth none >> /var/log/code-server-output.log 2>> /var/log/code-server-error.log &
nohup socat tcp-listen:3000,reuseaddr,fork tcp:localhost:3001 >> /var/log/listen-3000.out 2>> /var/log/listen-3000.err < /dev/null &
