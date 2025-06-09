#!/bin/bash

echo "[Sequence Caching] in setup"

# Delete if bookly exists
cockroach sql --insecure --execute="DROP DATABASE IF EXISTS bookly CASCADE;"

# Load bookdb workload
cockroach sql --insecure --execute="CREATE DATABASE bookly;"

exit 0