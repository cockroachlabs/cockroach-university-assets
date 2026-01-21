# Oracle Docker Setup Guide

## Overview

This guide explains how to use Docker-based Oracle for CockroachDB migration labs on Instruqt.

---

## Architecture

### Docker-Based Setup (Current)

**Advantages:**
- ✅ Fast setup (5-10 minutes with image pull, 2-3 minutes after)
- ✅ Official Oracle image (stable and maintained)
- ✅ Fully automated (no manual steps)
- ✅ Easy to manage (start/stop/remove container)
- ✅ Proven approach (based on working demos)

**How it works:**
1. `oracle-docker.sh` installs Docker and pulls Oracle Free image
2. Starts Oracle container named `oracle-source`
3. Waits for Oracle to be ready
4. Configures ARCHIVELOG mode and creates users
5. Creates schema and loads sample data
6. Downloads MOLT configs and Python apps

---

## Quick Start

### Step 1: Add to Your Instruqt Track

**Track Configuration (config.yml):**

```yaml
version: "3"
virtualmachines:
- name: migration-lab
  image: ubuntu-2204-lts  # Standard Ubuntu image
  machine_type: n1-standard-4
```

**Track Setup Script:**

```bash
#!/bin/bash
set -euxo pipefail

SCRIPTS=(
    "base/01-ubuntu.sh"
    "base/cockroachdb.sh"
    "base/cockroachdb-start.sh"
    "courses/migration-labs/molt.sh"
    "courses/migration-labs/oracle/oracle-docker.sh"  # ← Oracle Docker setup
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"

for SCRIPT_PATH in "${SCRIPTS[@]}"; do
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    curl -fsSL "${BASE_URL}${SCRIPT_PATH}" -o "/tmp/$SCRIPT_NAME"
    chmod +x "/tmp/$SCRIPT_NAME"
    "/tmp/$SCRIPT_NAME"
done
```

### Step 2: Use Docker Commands in Assignment

**Connecting to Oracle:**

```bash
# Interactive SQL*Plus
docker exec -i oracle-source sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1

# Execute SQL from host
docker exec oracle-source bash -c "sqlplus -s APP_USER/apppass@//localhost:1521/FREEPDB1 <<EOF
SELECT COUNT(*) FROM orders;
EXIT;
EOF
"
```

**Helper Scripts:**

```bash
/root/oracle/connect_oracle_app.sh        # Connect as APP_USER
/root/oracle/connect_oracle_migration.sh  # Connect as MIGRATION_USER
/root/oracle/oracle_exec.sh "SELECT * FROM orders;"  # Execute SQL
```

---

## What Gets Configured

### Oracle Container

- **Name:** `oracle-source`
- **Image:** `container-registry.oracle.com/database/free:latest`
- **Network:** `molt-network` (Docker bridge)
- **Ports:** 1521 (Oracle), 5500 (Oracle EM)
- **Database:** FREE (CDB)
- **PDB:** FREEPDB1

### Users and Passwords

**System Accounts:**
- **SYS:** `CockroachDB_123`
- **SYSTEM:** `CockroachDB_123`
- **PDBADMIN:** `CockroachDB_123`

**Application Accounts:**
- **C##MIGRATION_USER:** `migpass` (CDC/LogMiner user)
- **APP_USER:** `apppass` (schema owner)

### Schema (APP_USER)

**Tables:**
- `orders` (100+ rows)
- `order_fills` (100+ rows)

**Sequences:**
- `order_seq`
- `order_fill_seq`

**Triggers:**
- `order_set_id` (auto-increment for orders)
- `order_fill_set_id` (auto-increment for order_fills)

**View:**
- `orcl_order_fills_view`

### Files Downloaded to /root/oracle/

```
/root/oracle/
├── sql-scripts/
│   ├── oracle_source_schema.sql
│   ├── oracle_source_data.sql
│   ├── crdb_target_schema.sql
│   └── verification_queries.sql
├── python-apps/
│   ├── oracle-workload.py
│   ├── cockroach-workload.py
│   └── requirements.txt
├── molt-config/
│   ├── transforms.json
│   ├── molt_fetch.sh
│   ├── molt_verify.sh
│   └── start_replicator.sh
└── connect_*.sh (helper scripts)
```

---

## Connection Information

### From Host (VM)

**MOLT Connection Strings:**
```bash
# Source PDB (for data access)
oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREEPDB1

# Source CDB (for metadata)
oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREE

# Target CockroachDB
postgres://root@localhost:26257/target?sslmode=disable
```

**Python Connection:**
```python
import oracledb
connection = oracledb.connect(
    user="APP_USER",
    password="apppass",
    dsn="localhost:1521/FREEPDB1"
)
```

**SQL*Plus:**
```bash
docker exec -i oracle-source sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1
```

---

## Docker Container Management

### Check Status

```bash
# Check if container is running
docker ps | grep oracle-source

# Check database status
docker exec oracle-source bash -c "echo 'SELECT status FROM v\$instance;' | sqlplus -s / as sysdba"
```

### Start/Stop/Restart

```bash
# Stop Oracle container
docker stop oracle-source

# Start Oracle container
docker start oracle-source

# Restart Oracle container
docker restart oracle-source
```

### View Logs

```bash
# View all logs
docker logs oracle-source

# Follow logs in real-time
docker logs -f oracle-source

# View last 100 lines
docker logs --tail 100 oracle-source
```

### Execute Commands

```bash
# Execute SQL*Plus commands
docker exec oracle-source bash -c "sqlplus / as sysdba <<EOF
SELECT status FROM v\$instance;
EXIT;
EOF
"

# Execute shell commands
docker exec oracle-source bash -c "lsnrctl status"

# Interactive shell
docker exec -i oracle-source bash
```

### Remove Container

```bash
# Remove container (will lose all data)
docker rm -f oracle-source

# Re-run setup to recreate
/tmp/oracle-docker.sh
```

---

## MOLT Migration Workflow

### 1. MOLT Fetch (Bulk Migration)

```bash
# Run MOLT Fetch
/root/oracle/molt-config/molt_fetch.sh | tee /root/fetch.log

# Capture SCN for replication
SCN=$(grep 'backfillFromSCN' /root/fetch.log | jq -r '.cdc_cursor' | cut -d'=' -f2 | cut -d',' -f1)
echo $SCN > /root/scn.txt
```

### 2. MOLT Verify

```bash
# Verify data consistency
/root/oracle/molt-config/molt_verify.sh | tee /root/verify.log

# View summary
grep 'type.*summary' /root/verify.log | jq
```

### 3. Replicator (CDC)

```bash
# Start Replicator with captured SCN
SCN=$(cat /root/scn.txt)
nohup /root/oracle/molt-config/start_replicator.sh $SCN > /root/replicator.log 2>&1 &
echo $! > /root/replicator.pid

# Monitor replication
tail -f /root/replicator.log

# Stop Replicator
kill $(cat /root/replicator.pid)
```

---

## Troubleshooting

### Container Won't Start

**Symptom:** `docker ps` doesn't show `oracle-source`

**Check:**
```bash
# Verify Docker is running
systemctl status docker

# Start Docker if needed
systemctl start docker

# Check for errors
docker logs oracle-source
```

**Fix:**
```bash
# Remove failed container
docker rm -f oracle-source

# Re-run setup
bash /tmp/oracle-docker.sh
```

### Oracle Database Not Ready

**Symptom:** Can't connect to Oracle after container starts

**Check:**
```bash
# Check database status
docker exec oracle-source bash -c "echo 'SELECT status FROM v\$instance;' | sqlplus -s / as sysdba"

# Should output: OPEN
```

**Wait Time:**
- Normal startup: 2-5 minutes
- If stuck after 10 minutes, restart:

```bash
docker restart oracle-source
```

### MOLT Can't Connect

**Symptom:** MOLT Fetch fails with connection error

**Check:**
```bash
# Verify Oracle is accessible on port 1521
docker exec oracle-source bash -c "lsnrctl status"

# Test connection
docker exec oracle-source bash -c "sqlplus C##MIGRATION_USER/migpass@//localhost:1521/FREEPDB1 <<EOF
SELECT 1 FROM DUAL;
EXIT;
EOF
"
```

**Fix:**
```bash
# Check if ARCHIVELOG is enabled
docker exec oracle-source bash -c "echo 'SELECT log_mode FROM v\$database;' | sqlplus -s / as sysdba"

# Should output: ARCHIVELOG
```

### Port Conflict

**Symptom:** Error: "port 1521 is already allocated"

**Check:**
```bash
# See what's using port 1521
netstat -tuln | grep 1521
```

**Fix:**
```bash
# Stop conflicting process
# OR modify oracle-docker.sh to use different port:
docker run -p 1522:1521 ...
```

### Permission Denied Errors

**Symptom:** Docker commands fail with permission errors

**Fix:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Restart session or run:
newgrp docker
```

### Python Apps Can't Connect

**Symptom:** Python workload fails with connection error

**Check:**
```bash
# Test Oracle connection from host
docker exec oracle-source bash -c "sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1 <<EOF
SELECT 1 FROM DUAL;
EXIT;
EOF
"
```

**Fix:**
```bash
# Ensure Python Oracle libraries are installed
pip3 install cx_Oracle oracledb --break-system-packages
```

---

## Performance Optimization

### Container Resources

**Default allocation:**
- CPU: Uses available cores
- Memory: ~1-2 GB

**Limit resources:**
```bash
docker run -d \
  --name oracle-source \
  --cpus="2" \
  --memory="2g" \
  ...
```

### Persistent Storage

**Add volume for persistence:**
```bash
docker run -d \
  --name oracle-source \
  -v oracle-data:/opt/oracle/oradata \
  ...
```

---

## Advanced Configuration

### Custom Oracle Configuration

**Modify container after startup:**
```bash
# Connect as SYSDBA
docker exec -i oracle-source sqlplus / as sysdba

# Modify configuration
ALTER SYSTEM SET processes=200 SCOPE=SPFILE;
SHUTDOWN IMMEDIATE;
STARTUP;
```

### Enable Additional Oracle Features

```bash
# Enable supplemental logging for specific tables
docker exec oracle-source bash -c "sqlplus / as sysdba <<EOF
ALTER TABLE APP_USER.orders ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE APP_USER.order_fills ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
EXIT;
EOF
"
```

### Custom Schema

**Add your own schema:**
```bash
# Create custom SQL file
cat > /root/custom_schema.sql <<'EOF'
CREATE TABLE my_table (
    id NUMBER PRIMARY KEY,
    name VARCHAR2(100)
);
EOF

# Execute in container
docker cp /root/custom_schema.sql oracle-source:/tmp/
docker exec oracle-source bash -c "sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1 @/tmp/custom_schema.sql"
```

---

## Comparison: Docker vs Native Installation

| Feature | Docker | Native Installation |
|---------|--------|-------------------|
| **Setup Time** | 5-10 min (first), 2-3 min (after) | 15-30 min |
| **Automation** | Fully automated | Manual password entry |
| **Reliability** | Official Oracle image | DBCA bugs |
| **Isolation** | Container (easy cleanup) | System-wide |
| **Port Conflicts** | Easy to remap | Harder to resolve |
| **Debugging** | Container logs | System logs scattered |
| **Maintenance** | Pull new image | Manual updates |

---

## Best Practices

1. ✅ **Always check container status** before running MOLT
2. ✅ **Monitor logs** during first run to ensure successful startup
3. ✅ **Capture SCN** from MOLT Fetch for replication
4. ✅ **Test connections** before starting migration
5. ✅ **Use helper scripts** for consistent connections
6. ✅ **Keep container running** during entire lab session
7. ✅ **Document any custom changes** to schema or configuration

---

## Support

For issues or questions:
1. Review this guide thoroughly
2. Check Docker and Oracle container logs
3. Verify network connectivity (port 1521)
4. Test connections with helper scripts
5. Contact CockroachDB Education team

---

## Example Tracks

**Working implementation:**
- Track: `cu-migration-oracle-to-cockroachdb`
- Location: `/Users/felipeg/Roach/Instruqt/individual-modules/cu-migration-oracle-to-cockroachdb`

**Based on demo:**
- Demo: Oracle MOLT full pipeline
- Location: `/Users/felipeg/Roach/Instruqt/oracle-molt/CRL-PS-MOLT-Demos`
