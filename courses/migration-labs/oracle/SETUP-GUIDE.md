# Oracle Host Image Setup Guide

## Overview

This guide explains how to create an Instruqt host image with Oracle 26ai pre-installed for fast lab startup times.

## Two-Phase Approach

### Phase 1: Create Host Image (One-time, ~20 minutes)
Use `install-oracle-hostimage.sh` to create a host image with Oracle fully installed.

### Phase 2: Lab Runtime (Every track run, ~2-3 minutes)
Use `oracle-setup-existing.sh` to configure schemas and users for each learner.

---

## Phase 1: Creating the Host Image

### Step 1: Start Fresh Instruqt VM

Create a new Instruqt sandbox with:
- **OS**: CentOS Stream 9 or Rocky Linux 9
- **Memory**: At least 4GB RAM
- **Disk**: At least 20GB

### Step 2: Download and Run Installation Script

```bash
# Download the host image installation script
curl -fsSL https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/courses/migration-labs/oracle/install-oracle-hostimage.sh -o /tmp/install-oracle.sh

# Make it executable
chmod +x /tmp/install-oracle.sh

# Run it (takes ~20 minutes)
bash /tmp/install-oracle.sh
```

### Step 3: Verify Oracle Installation

After the script completes, verify:

```bash
# Check Oracle is running
pgrep -f ora_pmon_FREE && echo "✅ Oracle is running"

# Check database files exist
ls -la /opt/oracle/oradata/FREE/

# Test connection
sudo -u oracle sqlplus / as sysdba <<< "SELECT status FROM v\$instance;"
```

You should see:
```
STATUS
------------
OPEN
```

### Step 4: Save as Host Image

In Instruqt:
1. Stop the sandbox
2. Save it as a custom host image
3. Name it something like: `oracle-26ai-free-ready`

### What's Included in the Host Image

✅ Oracle AI Database 26ai Free installed
✅ Listener configured on port 1521
✅ Database FREE created and running
✅ PDB FREEPDB1 created
✅ Auto-start configured (systemd service)
✅ Password: `Cr0ckr0@ch#2026`

---

## Phase 2: Using the Host Image in Tracks

### Step 1: Configure Your Instruqt Track

In your track configuration:

```yaml
version: "3"
type: track
containers:
- name: oracle-migration
  image: oracle-26ai-free-ready  # Your custom host image
  ports:
  - 1521  # Oracle
  - 26257 # CockroachDB
  - 8080  # CockroachDB UI
```

### Step 2: Update Setup Script

Your track's setup script should use:

```bash
SCRIPTS=(
    "base-redhat/01-redhat.sh"
    "base-redhat/cockroachdb.sh"
    "base-redhat/cockroachdb-start.sh"
    "courses/migration-labs/molt.sh"
    "courses/migration-labs/oracle/oracle-setup-existing.sh"  # ← Fast setup
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

1. ✅ Starts Oracle (if not running)
2. ✅ Enables ARCHIVELOG mode for CDC
3. ✅ Creates C##MIGRATION_USER with privileges
4. ✅ Creates APP_USER schema
5. ✅ Loads sample data
6. ✅ Downloads MOLT configs and Python apps
7. ✅ Creates CockroachDB target schema
8. ✅ Sets up connection helper scripts

**Time**: ~2-3 minutes

---

## Credentials and Connection Info

### System Passwords (in host image)
- **SYS**: `Cr0ckr0@ch#2026`
- **SYSTEM**: `Cr0ckr0@ch#2026`

### Application Users (created by oracle-setup-existing.sh)
- **C##MIGRATION_USER**: `migpass`
- **APP_USER**: `apppass`

### Connection Strings

```bash
# Oracle CDB (as SYS)
sqlplus sys/Cr0ckr0@ch#2026@localhost:1521/FREE as sysdba

# Oracle PDB (as APP_USER)
sqlplus APP_USER/apppass@localhost:1521/FREEPDB1

# Oracle (as MIGRATION_USER)
sqlplus 'C##MIGRATION_USER/migpass@localhost:1521/FREE'

# CockroachDB
cockroach sql --insecure -d target
```

### Helper Scripts (created in /root/oracle/)

```bash
/root/oracle/connect_oracle_app.sh          # Connect as APP_USER
/root/oracle/connect_oracle_migration.sh    # Connect as MIGRATION_USER
/root/oracle/connect_crdb.sh                # Connect to CockroachDB
```

---

## Performance Comparison

| Method | Setup Time | Notes |
|--------|------------|-------|
| **Without host image** | 25-45 min | Downloads Oracle, converts RPM to DEB with alien |
| **With host image** | 2-3 min | Oracle pre-installed, just configure schemas |
| **Time saved** | ~20-40 min | Per learner! |

---

## Troubleshooting

### Oracle not starting in track

```bash
# Check if Oracle service exists
systemctl status oracle-free.service

# Start manually if needed
sudo systemctl start oracle-free.service

# Or start components directly
sudo -u oracle bash -c '
  export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
  export ORACLE_SID=FREE
  export PATH=$ORACLE_HOME/bin:$PATH
  lsnrctl start
  dbstart $ORACLE_HOME
'
```

### Check database status

```bash
# Check processes
pgrep -f ora_ | wc -l  # Should show multiple Oracle processes

# Check database
sudo -u oracle sqlplus / as sysdba <<< "SELECT status FROM v\$instance;"

# Check PDB
sudo -u oracle sqlplus / as sysdba <<< "SELECT name, open_mode FROM v\$pdbs;"
```

### View Oracle logs

```bash
# Alert log
tail -100 /opt/oracle/admin/FREE/adump/alert_FREE.log

# Listener log
tail -100 /opt/oracle/diag/tnslsnr/*/listener/trace/listener.log
```

---

## Files Structure

```
courses/migration-labs/oracle/
├── install-oracle-hostimage.sh    # Phase 1: Create host image
├── oracle-setup-existing.sh       # Phase 2: Track runtime setup
├── sql-scripts/                   # SQL files for schemas/data
├── python-apps/                   # Workload generators
├── molt-config/                   # MOLT configurations
├── SETUP-GUIDE.md                 # This file
└── README.md                      # General documentation
```

---

## Next Steps

1. **Create host image** using `install-oracle-hostimage.sh`
2. **Test the image** by starting a track with it
3. **Update track configs** to use your new host image
4. **Deploy** and enjoy 20-40 minute faster lab startup!
