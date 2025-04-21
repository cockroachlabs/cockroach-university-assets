#!/bin/bash
set -euxo pipefail

## INSTALLATION
echo "[INFO] Updating package list and installing required packages..."
export DEBIAN_FRONTEND=noninteractive
sudo apt -y update
sudo apt -q -y --force-yes install \
    curl \
    wget \
    unzip \
    git \
    jq \
    htop \
    python3-pip \
    python3.12-venv \
    socat \
    haproxy 