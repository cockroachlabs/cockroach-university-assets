#!/bin/bash
set -euo pipefail

echo "============================================"
echo "Oracle Host Image Verification"
echo "============================================"
echo ""

PASS=0
FAIL=0

check() {
    if eval "$2"; then
        echo "✅ $1"
        ((PASS++))
    else
        echo "❌ $1"
        ((FAIL++))
    fi
}

# Set environment
export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree
export ORACLE_SID=FREE
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}

echo "1. Oracle Installation Checks"
echo "--------------------------------------------"
check "Oracle Home exists" "[ -d '$ORACLE_HOME' ]"
check "sqlplus binary exists" "[ -f '$ORACLE_HOME/bin/sqlplus' ]"
check "lsnrctl binary exists" "[ -f '$ORACLE_HOME/bin/lsnrctl' ]"
check "Oracle user exists" "id oracle &>/dev/null"
check "libaio library installed" "[ -f /usr/lib64/libaio.so.1 ]"
echo ""

echo "2. Oracle Process Checks"
echo "--------------------------------------------"
check "Listener process running" "pgrep -f tnslsnr &>/dev/null"
check "PMON process running" "pgrep -f ora_pmon_FREE &>/dev/null"
check "SMON process running" "pgrep -f ora_smon_FREE &>/dev/null"
check "Database processes count (should be 15+)" "[ \$(pgrep -f ora_ | wc -l) -gt 15 ]"
echo ""

echo "3. Database File Checks"
echo "--------------------------------------------"
check "Database directory exists" "[ -d /opt/oracle/oradata/FREE ]"
check "Control file exists" "[ -f /opt/oracle/oradata/FREE/control01.ctl ]"
check "System datafile exists" "[ -f /opt/oracle/oradata/FREE/system01.dbf ]"
check "SPFILE exists" "[ -f $ORACLE_HOME/dbs/spfileFREE.ora ]"
check "Password file exists" "[ -f $ORACLE_HOME/dbs/orapwFREE ]"
echo ""

echo "4. Listener Configuration"
echo "--------------------------------------------"
check "listener.ora exists" "[ -f $ORACLE_HOME/network/admin/listener.ora ]"
check "tnsnames.ora exists" "[ -f $ORACLE_HOME/network/admin/tnsnames.ora ]"

# Test listener status
LISTENER_STATUS=$(sudo -u oracle bash -c "
    export ORACLE_HOME=$ORACLE_HOME
    export PATH=\$ORACLE_HOME/bin:\$PATH
    \$ORACLE_HOME/bin/lsnrctl status 2>&1 | grep -c 'The command completed successfully'
")
check "Listener responding" "[ '$LISTENER_STATUS' -gt 0 ]"
echo ""

echo "5. Database Status Checks"
echo "--------------------------------------------"

# Test database connection and get status
DB_STATUS=$(sudo -u oracle bash -c "
    export ORACLE_HOME=$ORACLE_HOME
    export ORACLE_SID=$ORACLE_SID
    export PATH=\$ORACLE_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$ORACLE_HOME/lib
    echo 'SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
    SELECT status FROM v\$instance;
    EXIT;' | \$ORACLE_HOME/bin/sqlplus -s / as sysdba 2>&1 | grep -v '^$' | tail -1
")

check "Database status is OPEN" "[ '$DB_STATUS' = 'OPEN' ]"

# Check database name
DB_NAME=$(sudo -u oracle bash -c "
    export ORACLE_HOME=$ORACLE_HOME
    export ORACLE_SID=$ORACLE_SID
    export PATH=\$ORACLE_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$ORACLE_HOME/lib
    echo 'SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
    SELECT name FROM v\$database;
    EXIT;' | \$ORACLE_HOME/bin/sqlplus -s / as sysdba 2>&1 | grep -v '^$' | tail -1
")

check "Database name is FREE" "[ '$DB_NAME' = 'FREE' ]"

# Check PDB status
PDB_COUNT=$(sudo -u oracle bash -c "
    export ORACLE_HOME=$ORACLE_HOME
    export ORACLE_SID=$ORACLE_SID
    export PATH=\$ORACLE_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$ORACLE_HOME/lib
    echo 'SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
    SELECT COUNT(*) FROM v\$pdbs WHERE name='\''FREEPDB1'\'' AND open_mode='\''READ WRITE'\'';
    EXIT;' | \$ORACLE_HOME/bin/sqlplus -s / as sysdba 2>&1 | grep -v '^$' | tail -1
")

check "FREEPDB1 is open in READ WRITE mode" "[ '$PDB_COUNT' -eq 1 ]"

# Check archivelog mode
ARCHIVE_MODE=$(sudo -u oracle bash -c "
    export ORACLE_HOME=$ORACLE_HOME
    export ORACLE_SID=$ORACLE_SID
    export PATH=\$ORACLE_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$ORACLE_HOME/lib
    echo 'SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
    SELECT log_mode FROM v\$database;
    EXIT;' | \$ORACLE_HOME/bin/sqlplus -s / as sysdba 2>&1 | grep -v '^$' | tail -1
")

check "Database in ARCHIVELOG mode" "[ '$ARCHIVE_MODE' = 'ARCHIVELOG' ]"
echo ""

echo "6. Password Verification"
echo "--------------------------------------------"

# Test SYS password
SYS_LOGIN=$(sudo -u oracle bash -c "
    export ORACLE_HOME=$ORACLE_HOME
    export ORACLE_SID=$ORACLE_SID
    export PATH=\$ORACLE_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$ORACLE_HOME/lib
    echo 'EXIT;' | \$ORACLE_HOME/bin/sqlplus -s sys/'CockroachDB_123'@localhost:1521/FREE as sysdba 2>&1 | grep -c 'Connected to'
")

check "SYS password works (CockroachDB_123)" "[ '$SYS_LOGIN' -gt 0 ]"
echo ""

echo "7. Auto-start Configuration"
echo "--------------------------------------------"
check "Systemd service file exists" "[ -f /etc/systemd/system/oracle-free.service ]"
check "Systemd service enabled" "systemctl is-enabled oracle-free.service &>/dev/null || [ -L /etc/systemd/system/multi-user.target.wants/oracle-free.service ]"
echo ""

echo "============================================"
echo "Verification Summary"
echo "============================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "✅ ALL CHECKS PASSED!"
    echo ""
    echo "Your Oracle host image is ready:"
    echo "  • Database: FREE (CDB)"
    echo "  • PDB: FREEPDB1"
    echo "  • Port: 1521"
    echo "  • Password: CockroachDB_123"
    echo "  • Auto-start: Enabled"
    echo ""
    echo "🎉 You can now SAVE this VM as your Instruqt host image!"
    echo ""
    exit 0
else
    echo "❌ SOME CHECKS FAILED!"
    echo ""
    echo "Please review the failed checks above and fix them before saving the host image."
    echo ""
    exit 1
fi
