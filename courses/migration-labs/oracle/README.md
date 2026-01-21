# Oracle to CockroachDB Migration Lab

This directory contains scripts and resources for Oracle to CockroachDB migration labs using **pre-configured host images**.

## Architecture

### Host Image (One-time Setup)
Your Instruqt host image has **Oracle AI Database 26ai Free pre-installed** with:
- Oracle Database 26ai Free (CentOS/Rocky Linux based)
- Listener configured on port 1521
- Database: FREE
- PDB: FREEPDB1
- System passwords: OraclePass123

### Track Runtime (Fast Setup)
When learners start the track, only lightweight configuration is needed (~2-3 minutes):
- Start Oracle if not running
- Create migration schemas and users
- Load sample data
- Download MOLT tools and configurations

## Files

```
oracle/
├── oracle-setup-existing.sh    # Track setup script (use this in your track)
├── sql-scripts/                # SQL scripts for schemas and data
├── python-apps/                # Python workload generators
└── molt-config/                # MOLT configuration files
```

## Usage in Instruqt Track

### 1. Track Configuration

Specify your custom host image in the track config:

```yaml
version: "3"
type: track
slug: oracle-to-cockroachdb-migration
title: Oracle to CockroachDB Migration

containers:
- name: oracle-migration
  image: your-custom-oracle-image  # Your pre-configured host image
  ports:
  - 1521  # Oracle
  - 26257 # CockroachDB
  - 8080  # CockroachDB UI
```

### 2. Setup Script

In your track's setup script, reference the lightweight setup:

```bash
SCRIPTS=(
    "base-redhat/01-redhat.sh"
    "base-redhat/cockroachdb.sh"
    "base-redhat/cockroachdb-start.sh"
    "courses/migration-labs/molt.sh"
    "courses/migration-labs/oracle/oracle-setup-existing.sh"  # ← Uses pre-installed Oracle
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"

for SCRIPT_PATH in "${SCRIPTS[@]}"; do
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    curl -fsSL "${BASE_URL}${SCRIPT_PATH}" -o "/tmp/$SCRIPT_NAME"
    chmod +x "/tmp/$SCRIPT_NAME"
    "/tmp/$SCRIPT_NAME"
done
```

## What oracle-setup-existing.sh Does

1. **Verifies Oracle is running** - Starts it if needed
2. **Enables ARCHIVELOG mode** - Required for CDC/Replicator
3. **Creates migration user** - C##MIGRATION_USER with necessary privileges
4. **Installs Python dependencies** - cx_Oracle, oracledb
5. **Downloads resources** - SQL scripts, Python apps, MOLT configs
6. **Creates schemas** - Oracle source schema and CockroachDB target schema
7. **Creates helper scripts** - Connection scripts for easy access

## Performance

### Without Host Image (Ubuntu + alien conversion)
- Download Oracle RPM: ~5-10 min
- Convert RPM to DEB: ~10-20 min
- Install and configure: ~5-10 min
- **Total: ~25-45 minutes** ⏱️

### With Host Image (RedHat + pre-installed Oracle)
- Start Oracle: ~30 seconds
- Configure schemas: ~1-2 minutes
- **Total: ~2-3 minutes** ✨

**Time saved per learner: ~20-40 minutes!**

## Connection Information

After setup completes, learners can connect to:

### Oracle Connections
```bash
# Connect as APP_USER (application schema)
/root/oracle/connect_oracle_app.sh

# Connect as migration user
/root/oracle/connect_oracle_migration.sh

# Or connect directly
sqlplus APP_USER/apppass@//localhost:1521/FREEPDB1
```

### CockroachDB Connection
```bash
# Connect to CockroachDB
/root/oracle/connect_crdb.sh

# Or connect directly
cockroach sql --insecure -d target
```

## Migration Resources

### SQL Scripts (`sql-scripts/`)
- `oracle_source_schema.sql` - Creates Oracle source schema
- `oracle_source_data.sql` - Loads sample data into Oracle
- `crdb_target_schema.sql` - Creates CockroachDB target schema
- `verification_queries.sql` - Queries to verify migration

### Python Apps (`python-apps/`)
- `oracle-workload.py` - Generates workload on Oracle
- `cockroach-workload.py` - Generates workload on CockroachDB
- `requirements.txt` - Python dependencies

### MOLT Configs (`molt-config/`)
- `transforms.json` - Schema transformation rules
- `molt_fetch.sh` - MOLT Fetch wrapper script
- `molt_verify.sh` - MOLT Verify wrapper script
- `start_replicator.sh` - MOLT Replicator wrapper script

## Troubleshooting

### Oracle not starting
```bash
# Check Oracle processes
ps aux | grep ora_

# Start Oracle manually
sudo -u oracle bash -c "
  export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
  export ORACLE_SID=FREE
  export PATH=\$ORACLE_HOME/bin:\$PATH
  lsnrctl start
  echo 'STARTUP;' | sqlplus / as sysdba
"
```

### Check database status
```bash
sudo -u oracle bash -c "
  export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
  export ORACLE_SID=FREE
  export PATH=\$ORACLE_HOME/bin:\$PATH
  echo 'SELECT status FROM v\$instance;' | sqlplus -s / as sysdba
"
```

## Building the Host Image

If you need to rebuild the host image, see the separate documentation in `base-redhat/README.md` for the full installation process.

The key script used during host image creation was `/tmp/oracle-configure-headless.sh` which:
1. Configured the listener manually (headless mode)
2. Created the database using DBCA in silent mode
3. Set system passwords to OraclePass123
