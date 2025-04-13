#!/bin/bash
set -euxo pipefail

## BASE CONFIGURATION
SETTINGS_PATH=/root/.local/share/code-server
USER_PATH=$SETTINGS_PATH/User

## Creating Directories
mkdir -p $SETTINGS_PATH
mkdir -p $USER_PATH

cat > $USER_PATH/settings.json <<EOF1
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
EOF1

cat > $SETTINGS_PATH/coder.json <<EOF2
{
  "query": {
    "folder": "/root/cockroachdb"
  }
}
EOF2
