# Oracle Docker Setup for Migration Labs

This directory contains the Docker-based Oracle setup for CockroachDB migration labs.

## Quick Start

### Using Docker Oracle in Your Track

**Track Configuration:**

In your `config.yml`, use a standard Ubuntu VM:

```yaml
version: "3"
virtualmachines:
- name: migration-lab
  image: ubuntu-2204-lts
  machine_type: n1-standard-4
```

**Track Setup Script:**

Your track's setup script should download and execute `oracle-docker.sh`:

```bash
SCRIPTS=(
    "base/01-ubuntu.sh"
    "base/cockroachdb.sh"
    "base/cockroachdb-start.sh"
    "courses/migration-labs/molt.sh"
    "courses/migration-labs/oracle/oracle-docker.sh"  # ← Docker Oracle setup
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"

for SCRIPT_PATH in "${SCRIPTS[@]}"; do
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    curl -fsSL "${BASE_URL}${SCRIPT_PATH}" -o "/tmp/$SCRIPT_NAME"
    chmod +x "/tmp/$SCRIPT_NAME"
    "/tmp/$SCRIPT_NAME"
done
```

---

## What Gets Installed

The `oracle-docker.sh` script does the following:

1. ✅ Installs Docker (if not already installed)
2. ✅ Pulls Oracle Free image: `container-registry.oracle.com/database/free:latest`
3. ✅ Starts Oracle container: `oracle-source` on port 1521
4. ✅ Enables ARCHIVELOG mode (required for CDC/Replicator)
5. ✅ Creates migration user: `C##MIGRATION_USER` with LogMiner privileges
6. ✅ Creates application schema: `APP_USER` with sample data
7. ✅ Downloads MOLT configurations and Python workload apps
8. ✅ Creates CockroachDB target schema
9. ✅ Creates connection helper scripts

**Setup Time:** ~5-10 minutes (first run with image pull), ~2-3 minutes (subsequent runs)

---

## Connection Information

### Oracle Container

- **Container Name:** `oracle-source`
- **Ports:** 1521 (Oracle), 5500 (Oracle EM)
- **Database:** FREE (CDB)
- **PDB:** FREEPDB1

### System Passwords

- **SYS/SYSTEM/PDBADMIN:** `CockroachDB_123`

### Application Users

- **C##MIGRATION_USER:** `migpass` (for MOLT/LogMiner)
- **APP_USER:** `apppass` (application schema)

### Connection Examples

**Interactive SQL*Plus (inside container):**
```bash
docker exec -i oracle-source sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1
```

**Execute SQL from host:**
```bash
docker exec oracle-source bash -c "sqlplus -s APP_USER/apppass@//localhost:1521/FREEPDB1 <<EOF
SELECT COUNT(*) FROM orders;
EXIT;
EOF
"
```

**Helper Scripts (created in /root/oracle/):**
```bash
/root/oracle/connect_oracle_app.sh        # Connect as APP_USER
/root/oracle/connect_oracle_migration.sh  # Connect as MIGRATION_USER
/root/oracle/connect_crdb.sh              # Connect to CockroachDB
/root/oracle/oracle_exec.sh              # Execute SQL commands from host
```

**MOLT Connection Strings:**
- Source PDB: `oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREEPDB1`
- Source CDB: `oracle://C%23%23MIGRATION_USER:migpass@localhost:1521/FREE`
- Target CRDB: `postgres://root@localhost:26257/target?sslmode=disable`

---

## Files in This Directory

| File/Directory | Purpose |
|---------------|---------|
| `oracle-docker.sh` | **Main setup script** - Installs Docker, pulls Oracle image, configures everything |
| `sql-scripts/` | SQL files for Oracle and CockroachDB schemas |
| `python-apps/` | Python workload generators for Oracle and CockroachDB |
| `molt-config/` | MOLT Fetch, Verify, and Replicator configuration scripts |
| `README.md` | This file - quick reference guide |
| `SETUP-GUIDE.md` | Detailed setup and troubleshooting guide |

---

## Oracle Schema

**Schema Owner:** APP_USER

**Tables:**
- `orders` - Order records (100+ rows)
  - Columns: order_id, account_id, symbol, order_started, order_completed, total_shares_purchased, total_cost_of_order
  - Primary Key: order_id (auto-generated via sequence + trigger)

- `order_fills` - Order fill records (100+ rows)
  - Columns: fill_id, order_id, account_id, symbol, fill_time, shares_filled, total_cost_of_fill, price_at_time_of_fill
  - Primary Key: fill_id (auto-generated via sequence + trigger)

**Sequences:**
- `order_seq` - Generates order_id values
- `order_fill_seq` - Generates fill_id values

**Triggers:**
- `order_set_id` - Populates order_id before INSERT
- `order_fill_set_id` - Populates fill_id before INSERT

**View:**
- `orcl_order_fills_view` - Joins orders and order_fills

---

## Docker Commands

### Container Management

**Check container status:**
```bash
docker ps | grep oracle-source
```

**View container logs:**
```bash
docker logs oracle-source
docker logs -f oracle-source  # Follow logs
```

**Stop container:**
```bash
docker stop oracle-source
```

**Start container:**
```bash
docker start oracle-source
```

**Restart container:**
```bash
docker restart oracle-source
```

**Remove container:**
```bash
docker rm -f oracle-source
```

### Database Status

**Check Oracle database status:**
```bash
docker exec oracle-source bash -c "echo 'SELECT status FROM v\$instance;' | sqlplus -s / as sysdba"
```

**Check listener status:**
```bash
docker exec oracle-source bash -c "lsnrctl status"
```

**Check PDB status:**
```bash
docker exec oracle-source bash -c "echo 'SELECT name, open_mode FROM v\$pdbs;' | sqlplus -s / as sysdba"
```

---

## Troubleshooting

### Oracle Container Not Starting

**Check Docker service:**
```bash
systemctl status docker
systemctl start docker
```

**Check container logs:**
```bash
docker logs oracle-source
```

**Look for:** "DATABASE IS READY TO USE!"

### Can't Connect to Oracle

**Verify container is running:**
```bash
docker ps | grep oracle-source
```

**Check database status:**
```bash
docker exec oracle-source bash -c "echo 'SELECT status FROM v\$instance;' | sqlplus -s / as sysdba"
```

**Should output:** `OPEN`

### Port Conflict (1521 already in use)

**Check what's using port 1521:**
```bash
netstat -tuln | grep 1521
```

**Stop conflicting service or use different port:**
```bash
docker run -p 1522:1521 ...
```

### Oracle Takes Too Long to Start

**Normal startup time:** 2-5 minutes

**Monitor progress:**
```bash
docker logs -f oracle-source
```

**If stuck after 10 minutes:**
```bash
docker restart oracle-source
```

---

## MOLT Configuration

All MOLT scripts are downloaded to `/root/oracle/molt-config/`:

### MOLT Fetch
```bash
/root/oracle/molt-config/molt_fetch.sh
```

Performs bulk data migration from Oracle to CockroachDB.

### MOLT Verify
```bash
/root/oracle/molt-config/molt_verify.sh
```

Validates data consistency between source and target.

### Replicator (CDC)
```bash
# Get SCN from MOLT Fetch
SCN=$(grep 'backfillFromSCN' /root/fetch.log | jq -r '.cdc_cursor' | cut -d'=' -f2 | cut -d',' -f1)

# Start Replicator
/root/oracle/molt-config/start_replicator.sh $SCN
```

Uses Oracle LogMiner for ongoing change data capture.

---

## Performance

| Metric | Value |
|--------|-------|
| **Setup time (first run)** | 5-10 minutes (includes image pull) |
| **Setup time (subsequent)** | 2-3 minutes |
| **Oracle image size** | ~1.2 GB |
| **Container memory** | ~1-2 GB |
| **ARCHIVELOG enabled** | Yes (required for CDC) |

---

## Advantages of Docker Approach

✅ **Reliable** - Official Oracle image, tested and maintained
✅ **Fast** - No manual Oracle installation or DBCA configuration
✅ **Automated** - No manual password entry or interactive steps
✅ **Isolated** - Runs in container, easy to clean up
✅ **Proven** - Based on working Oracle MOLT demos

---

## Support

For issues or questions:
1. Check the [SETUP-GUIDE.md](./SETUP-GUIDE.md) for detailed troubleshooting
2. Review Docker and Oracle container logs
3. Verify all connection strings use `localhost:1521`
4. Contact the CockroachDB Education team

---

## Example Track: cu-migration-oracle-to-cockroachdb

See the working implementation at:
`/Users/felipeg/Roach/Instruqt/individual-modules/cu-migration-oracle-to-cockroachdb`

This track demonstrates the complete Oracle → CockroachDB migration workflow using the Docker setup.
