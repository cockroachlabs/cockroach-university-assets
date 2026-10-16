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
    python3-venv \
    python3-psycopg2 \
    htop \
    tmux \
    tree \
    socat \
    haproxy

# Stop Instruqt's run-button paste from leaking bracketed-paste markers ("[200~"
# at the start, "~" at the end) into the shell on the first click of a fresh
# terminal. Disabling bracketed paste makes readline tell the terminal to stop
# sending the markers.
grep -q 'enable-bracketed-paste' /root/.inputrc 2>/dev/null || echo 'set enable-bracketed-paste off' >> /root/.inputrc

