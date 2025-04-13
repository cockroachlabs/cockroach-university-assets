#!/bin/bash
set -euxo pipefail

TMP=/tmp/apps
APPS=/root/cockroachdb/
mkdir -p $TMP

# If exists the program git, clone a repo
if command -v git >/dev/null 2>&1; then
    git clone https://github.com/cockroachlabs/cockroach-university-apps.git /tmp/apps/
    mv $TMP/migration-java-apps/crm $APPS
    mv $TMP/migration-java-apps/logistics $APPS
else
    echo "Git is not installed. Please install Git to proceed."
fi