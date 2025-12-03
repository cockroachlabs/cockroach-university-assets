#!/bin/bash
set -euxo pipefail

echo "Configuring PostgreSQL..."
# Ensure logical replication is available (commonly needed)
sed -i "s/#wal_level = replica/wal_level = logical/" /etc/postgresql/*/main/postgresql.conf || true
sed -i "s/#max_replication_slots = 10/max_replication_slots = 10/" /etc/postgresql/*/main/postgresql.conf || true
# Increase resources slightly for general use
sed -i "s/shared_buffers = 128MB/shared_buffers = 512MB/" /etc/postgresql/*/main/postgresql.conf || true
sed -i "s/max_connections = 100/max_connections = 200/" /etc/postgresql/*/main/postgresql.conf || true

service postgresql start

# Set postgres user password
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"