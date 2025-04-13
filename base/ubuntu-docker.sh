#!/bin/bash
set -euxo pipefail

## INSTALLING DOCKER AND DOCKER COMPOSE
echo "[INFO] Installing Docker..."
echo "[INFO] Installing Docker Compose..."
export DEBIAN_FRONTEND=noninteractive
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
