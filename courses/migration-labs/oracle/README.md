# Oracle 26ai Host Image Setup

This directory contains scripts to create an Instruqt host image with Oracle AI Database 26ai Free pre-installed.

## Quick Start for Developers

### Creating the Host Image (One-time setup)

1. **Start a fresh Instruqt VM** (CentOS Stream 9/10 or Rocky Linux 9, minimum 4GB RAM, 20GB disk)

2. **Run the installation script:**

```bash
curl -fsSL https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/courses/migration-labs/oracle/install-oracle-hostimage.sh -o /tmp/install-oracle.sh

chmod +x /tmp/install-oracle.sh

bash /tmp/install-oracle.sh
```

3. **⚠️ IMPORTANT: Enter password when prompted** (you'll be asked 3 times):

```
Password: CockroachDB_123
```

Enter this same password for:
- SYS user password
- SYSTEM user password
- PDBADMIN user password

⏱️ **Wait 5-15 minutes** for Oracle to configure the database after entering passwords.

4. **Verify the installation:**

```bash
curl -fsSL https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/courses/migration-labs/oracle/verify-oracle-hostimage.sh -o /tmp/verify.sh

bash /tmp/verify.sh
```

5. **Save the VM as Instruqt host image** if all checks pass ✅

---

## What Gets Installed in the Host Image

- ✅ Oracle AI Database 26ai Free
- ✅ Database: `FREE` (CDB - Container Database)
- ✅ Pluggable Database: `FREEPDB1`
- ✅ Listener on port `1521`
- ✅ Auto-start service enabled
- ✅ System passwords: `CockroachDB_123`

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `install-oracle-hostimage.sh` | **Creates Oracle host image** (requires manual password entry - one-time setup) |
| `verify-oracle-hostimage.sh` | **Verifies** Oracle installation is complete and working |
| `oracle-setup-existing.sh` | **Fast setup for tracks** using the host image (~2-3 min) |
| `SETUP-GUIDE.md` | Detailed setup guide and documentation |
| `README.md` | This file - quick reference |
| `sql-scripts/` | SQL scripts for Oracle schemas and sample data |
| `python-apps/` | Python workload generators |
| `molt-config/` | MOLT Fetch/Verify/Replicator configurations |

---

## Using the Host Image in Tracks

Once you have the host image saved, update your Instruqt track configuration:

```yaml
version: "3"
type: track
containers:
- name: oracle-migration
  image: oracle-26ai-free-ready  # Your saved host image name
  ports:
  - 1521  # Oracle
  - 26257 # CockroachDB
  - 8080  # CockroachDB UI
```

### Track Setup Script

In your track's setup script, use `oracle-setup-existing.sh` for fast configuration:

```bash
SCRIPTS=(
    "base-redhat/01-redhat.sh"
    "base-redhat/cockroachdb.sh"
    "base-redhat/cockroachdb-start.sh"
    "courses/migration-labs/molt.sh"
    "courses/migration-labs/oracle/oracle-setup-existing.sh"  # ← Fast setup using pre-installed Oracle
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"

for SCRIPT_PATH in "${SCRIPTS[@]}"; do
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    curl -fsSL "${BASE_URL}${SCRIPT_PATH}" -o "/tmp/$SCRIPT_NAME"
    chmod +x "/tmp/$SCRIPT_NAME"
    "/tmp/$SCRIPT_NAME"
done
```

### What oracle-setup-existing.sh Does

1. ✅ Verifies Oracle is running (starts if needed)
2. ✅ Enables ARCHIVELOG mode for CDC support
3. ✅ Creates `C##MIGRATION_USER` with LogMiner privileges
4. ✅ Installs Python dependencies (cx_Oracle, oracledb)
5. ✅ Downloads SQL scripts, Python apps, and MOLT configs
6. ✅ Creates Oracle source schema with sample data
7. ✅ Creates CockroachDB target schema
8. ✅ Creates connection helper scripts

**Time**: ~2-3 minutes (vs 25-45 minutes without host image!)

---

## Connection Information

### System Accounts (in host image)
- **SYS**: `CockroachDB_123`
- **SYSTEM**: `CockroachDB_123`
- **PDBADMIN**: `CockroachDB_123`

### Application Users (created by oracle-setup-existing.sh)
- **C##MIGRATION_USER**: `migpass` (for CDC/LogMiner)
- **APP_USER**: `apppass` (application schema)

### Connection Examples

```bash
# Connect to CDB as SYS
sqlplus sys/CockroachDB_123@localhost:1521/FREE as sysdba

# Connect to PDB as APP_USER
sqlplus APP_USER/apppass@localhost:1521/FREEPDB1

# Connect as migration user
sqlplus 'C##MIGRATION_USER/migpass@localhost:1521/FREE'

# Use helper scripts
/root/oracle/connect_oracle_app.sh        # APP_USER connection
/root/oracle/connect_oracle_migration.sh  # MIGRATION_USER connection
/root/oracle/connect_crdb.sh              # CockroachDB connection
```

---

## Performance Comparison

| Method | Setup Time | Notes |
|--------|------------|-------|
| **Without host image** | 25-45 min | Downloads Oracle, converts RPM to DEB with alien |
| **With host image** | 2-3 min | Oracle pre-installed, just configure schemas |
| **Time saved** | ~20-40 min | **Per learner!** |

---

## Important Notes

### Why Manual Password Entry?

Oracle's official configuration script (`/etc/init.d/oracle-free-26ai configure`) requires interactive password entry and doesn't support automation easily. This is a **one-time setup** when creating the host image - learners using the host image won't need to enter passwords.

### Password Requirements

The password `CockroachDB_123` meets Oracle's complexity requirements:
- ✅ At least 8 characters
- ✅ Contains uppercase letters (C, D, B)
- ✅ Contains lowercase letters (ockroach)
- ✅ Contains digits (123)
- ✅ Contains special character (underscore _)

---

## Troubleshooting

### Oracle not starting in track

```bash
# Check service status
systemctl status oracle-free-26ai

# Start manually if needed
sudo systemctl start oracle-free-26ai

# Check processes
pgrep -f ora_pmon_FREE && echo "✅ Running" || echo "❌ Not running"
```

### Check database status

```bash
sudo -u oracle bash -c "
  export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
  export ORACLE_SID=FREE
  export PATH=\$ORACLE_HOME/bin:\$PATH
  echo 'SELECT instance_name, status FROM v\$instance;' | sqlplus -s / as sysdba
"
```

### View Oracle logs

```bash
# Alert log
tail -100 /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log

# Listener log
tail -100 /opt/oracle/diag/tnslsnr/*/listener/trace/listener.log
```

---

## Migration Resources

All resources are downloaded to `/root/oracle/` by `oracle-setup-existing.sh`:

### SQL Scripts (`/root/oracle/sql-scripts/`)
- `oracle_source_schema.sql` - Creates Oracle source schema (APP_USER)
- `oracle_source_data.sql` - Loads sample data into Oracle
- `crdb_target_schema.sql` - Creates CockroachDB target schema
- `verification_queries.sql` - Queries to verify migration success

### Python Apps (`/root/oracle/python-apps/`)
- `oracle-workload.py` - Generates workload on Oracle source
- `cockroach-workload.py` - Generates workload on CockroachDB target
- `requirements.txt` - Python dependencies

### MOLT Configs (`/root/oracle/molt-config/`)
- `transforms.json` - Schema transformation rules for MOLT Fetch
- `molt_fetch.sh` - MOLT Fetch wrapper script
- `molt_verify.sh` - MOLT Verify wrapper script
- `start_replicator.sh` - MOLT Replicator wrapper script for CDC

---

## Additional Documentation

See [SETUP-GUIDE.md](./SETUP-GUIDE.md) for comprehensive documentation including:
- Detailed step-by-step instructions
- Two-phase architecture explanation (host image vs runtime setup)
- Advanced troubleshooting
- File structure details

---

## Support

For issues or questions:
1. Check the [SETUP-GUIDE.md](./SETUP-GUIDE.md) troubleshooting section
2. Review Oracle logs (see Troubleshooting above)
3. Verify all host image checks pass with `verify-oracle-hostimage.sh`
4. Contact the CockroachDB Education team
