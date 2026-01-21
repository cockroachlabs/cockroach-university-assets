# RedHat Base Scripts for Instruqt

This directory contains RedHat/CentOS/Fedora equivalents of the Ubuntu base scripts.

## Why RedHat for Oracle?

**Major Advantage**: Oracle Database RPM packages can be installed directly on RedHat-based systems without the `alien` conversion tool, saving **10-20 minutes** of setup time per lab instance.

## File Mapping

| Ubuntu Script | RedHat Equivalent | Notes |
|--------------|-------------------|-------|
| `base/01-ubuntu.sh` | `base-redhat/01-redhat.sh` | Package manager changed from apt to yum/dnf |
| `base/cockroachdb.sh` | `base-redhat/cockroachdb.sh` | **Identical** - CockroachDB binaries are platform-agnostic |
| `base/cockroachdb-start.sh` | `base-redhat/cockroachdb-start.sh` | **Identical** - Same startup process |
| `courses/migration-labs/01-ubuntu-dbs.sh` | `courses/migration-labs/01-redhat-dbs.sh` | MySQL/PostgreSQL installation for RedHat |
| `courses/migration-labs/oracle/oracle.sh` | `courses/migration-labs/oracle/oracle-redhat.sh` | **Direct RPM install** - no alien conversion needed! |

## Key Differences

### Package Managers
- **Ubuntu**: `apt` / `apt-get`
- **RedHat**: `yum` (older) or `dnf` (newer)

### Package Names
| Package Type | Ubuntu | RedHat |
|-------------|--------|--------|
| MySQL | `mysql-server` | `mariadb-server` |
| PostgreSQL | `postgresql` | `postgresql-server` |
| Python PostgreSQL | `python3-psycopg2` | Install via pip: `pip3 install psycopg2-binary` |
| Development tools | `build-essential` | `gcc`, `python3-devel` |

### Database Initialization
- **PostgreSQL on RedHat**: Requires explicit initialization with `postgresql-setup --initdb`
- **Services**: RedHat uses `systemctl` to start/enable services

## Using in Instruqt

### 1. Change Sandbox Image
In your Instruqt track configuration, change from:
```yaml
sandbox:
  image: ubuntu-22.04
```

To:
```yaml
sandbox:
  image: rockylinux-9  # or centos-stream-9, fedora-39, etc.
```

### 2. Update setup-migration-lab Script

Change the SCRIPTS array to use RedHat versions:

```bash
SCRIPTS=(
    "base-redhat/01-redhat.sh"
    "base-redhat/cockroachdb.sh"
    "base-redhat/cockroachdb-start.sh"
    "courses/migration-labs/01-redhat-dbs.sh"
    "courses/migration-labs/molt.sh"  # This one is platform-agnostic
    "courses/migration-labs/oracle/oracle-redhat.sh"
)
```

## Performance Comparison

### Ubuntu (with alien conversion)
1. Download Oracle RPM: ~5-10 min
2. **Convert RPM to DEB with alien: ~10-20 min** ⏱️
3. Install DEB: ~2-3 min
4. Configure Oracle: ~5-10 min
**Total: ~25-45 minutes**

### RedHat (direct RPM install)
1. Download Oracle RPM: ~5-10 min
2. **Install RPM directly: ~2-3 min** ✨
3. Configure Oracle: ~5-10 min
**Total: ~12-23 minutes**

**Time Saved: 10-20 minutes per lab instance!**

## Testing

To test the scripts:
```bash
# Test base installation
bash base-redhat/01-redhat.sh

# Test CockroachDB installation
bash base-redhat/cockroachdb.sh

# Test Oracle installation (RedHat optimized)
bash courses/migration-labs/oracle/oracle-redhat.sh
```

## Recommended RedHat Distributions for Instruqt

1. **Rocky Linux 9** (recommended - free RHEL clone)
2. **CentOS Stream 9**
3. **Fedora 39+**
4. **Oracle Linux 8/9** (if available in Instruqt)

All use `dnf` as package manager and support Oracle Database 26ai Free.
