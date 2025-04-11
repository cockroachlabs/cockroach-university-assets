#!/bin/bash
set -euxo pipefail

## INSTALLATION
export DEBIAN_FRONTEND=noninteractive
sudo apt -y update
sudo apt -q -y --force-yes install \
    mysql-server \
    postgresql

## Create schemas directory
SCHEMAS=/root/cockroachdb/schemas
mkdir -p $SCHEMAS