#!/bin/bash
set -euxo pipefail

echo "Movr workload Check"

if [ "$(cockroach sql --insecure -e "SHOW DATABASES;" | grep -c movr)" -eq 0 ]; then
    fail-message "Movr does not seem to exist, run *cockroach workload init movr* step"
else
    echo "Good job, you have loaded the movr database correctly!"
fi

echo "Done with Movr workload Check"