#!/bin/bash

echo "[Show Ranges Challenge] in cleanup"

# Delete the bookly database 
cockroach sql --insecure --execute="DROP DATABASE bookly CASCADE;"

exit 0