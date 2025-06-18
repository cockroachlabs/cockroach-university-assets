#!/bin/bash
set -euxo pipefail

## BASE CONFIGURATION
SETTINGS_PATH=/root/.local/share/code-server
USER_PATH=$SETTINGS_PATH/User

## Creating Directories
echo "[INFO] Creating Code Server directories..."
mkdir -p $SETTINGS_PATH
mkdir -p $USER_PATH

echo "[INFO] Creating Code Server settings.json..."
cat > $USER_PATH/settings.json <<'EOF1'
{
    "workbench.colorTheme": "Tomorrow Night Blue",
    "workbench.startupEditor": "none",
    "security.workspace.trust.enabled": false,
    "sqltools.autoConnectTo": "",
    "java.telemetry.enabled": true,
    "java.compile.nullAnalysis.mode": "automatic",
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

echo "[INFO] Creating Code Server coder.json..."
DEFAULT_PATH="/root/cockroachdb"
MY_PATH=${1:-$DEFAULT_PATH}

cat > $SETTINGS_PATH/coder.json <<EOF2
{
  "query": {
    "folder": "$MY_PATH"
  }
}
EOF2

if [ -f "$USER_PATH/settings.json" ]; then
    echo "[INFO] settings.json exists." 
else
    echo "[WARN] settings.json does not exist."     
fi

if [ -f "$SETTINGS_PATH/coder.json" ]; then
    echo "[INFO] coder.json exists."
else
    echo "[WARN] coder.json does not exist."
fi
