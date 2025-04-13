#!/bin/bash
set -euxo pipefail

export CODE_SERVER_VERSION=${CODE_SERVER_VERSION:-4.99.2}

## CODE SERVER
curl -sfOL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb
sudo dpkg -i code-server_${CODE_SERVER_VERSION}_amd64.deb
rm -rf code-server_${CODE_SERVER_VERSION}_amd64.deb

## EXPOSE PORTS
export PORT=3001
nohup code-server --auth none > /var/log/code-server-output.log 2> /var/log/code-server-error.log &
nohup socat tcp-listen:3000,reuseaddr,fork tcp:localhost:3001 > /var/log/listen-3000.out 2> /var/log/listen-3000.err < /dev/null &

## INSTALL BASE EXTENSIONS 
code-server --install-extension wildberries-theme.wildberries > /var/log/vscode-ext.out 2> /var/log/vscode-ext.err < /dev/null &

## BASE CONFIGURATION
SETTINGS_PATH=/root/.local/share/code-server
USER_PATH=$SETTINGS_PATH/User
mkdir -p $SETTINGS_PATH
mkdir -p $USER_PATH

cat > $USER_PATH/settings.json <<EOF
{
    "workbench.colorTheme": "Tomorrow Night Blue",
    "workbench.startupEditor": "none",
    "security.workspace.trust.enabled": false,
    "sqltools.autoConnectTo": "",
    "java.compile.nullAnalysis.mode": "automatic",
    "java.test.config": [
        {
          "name": "Spring Boot Test",
          "workingDirectory": "${workspaceFolder}",
          "vmArgs": "-ea"
        }
      ],
    "java.test.defaultConfig": "Spring Boot Test",
    "java.test.enabled": true,
    "java.test.log.level": "verbose",
    "java.debug.logLevel": "verbose",
    "java.debug.settings.console": "internalConsole",
    "java.configuration.runtimes": [
        {
          "name": "JavaSE-17",
          "path": "/usr/lib/jvm/java-17-openjdk-amd64",
          "default": true
        }
    ],
    "editor.formatOnSave": true
}
EOF

cat > $SETTINGS_PATH/coder.json <<EOF
{
  "query": {
    "folder": "/root/cockroachdb"
  }
}
EOF
