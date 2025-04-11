#!/bin/bash
set -euxo pipefail

## INSTALLATION
export DEBIAN_FRONTEND=noninteractive
sudo apt -y update
sudo apt -q -y --force-yes install \
    curl \
    wget \
    unzip \
    jq \
    htop \
    socat \
    haproxy 