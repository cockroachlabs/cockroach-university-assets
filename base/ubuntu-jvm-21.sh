#!/bin/bash
set -euxo pipefail

## INSTALLING JAVA
echo "[INFO] Installing Java 21..."
export DEBIAN_FRONTEND=noninteractive
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list
apt -y update
apt -y install temurin-21-jdk