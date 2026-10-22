#!/bin/bash
set -euxo pipefail

# Per-language setup for the "CockroachDB for Python Developers" labs.
# Usage: python.sh [connect|resilient]
# Pulls the CockroachDB Python library from its public Pages package index.

LAB=${1:-connect}

# The library requires Python >= 3.11; the base image ships 3.10, so install 3.11
# into a venv and make `python3`/`python` resolve to it for the lab.
DEBIAN_FRONTEND=noninteractive apt -y install software-properties-common
add-apt-repository -y ppa:deadsnakes/ppa
apt -y update
DEBIAN_FRONTEND=noninteractive apt -y install python3.11 python3.11-venv
python3.11 -m venv /opt/crdbvenv
# Make `python3`/`python` resolve to the venv (3.11 + the library) everywhere,
# including non-interactive check/solve scripts. A wrapper (not a symlink) is
# required — symlink resolution lands on the real python3.11 and bypasses the venv.
cat > /usr/local/bin/python3 <<'SH'
#!/bin/sh
exec /opt/crdbvenv/bin/python "$@"
SH
chmod +x /usr/local/bin/python3
cp /usr/local/bin/python3 /usr/local/bin/python

# --- CockroachDB Python library: install from the public git repo ------------
# NOT the Pages simple index: the package name `cockroachdb` collides with an
# unrelated PyPI project (versions 0.1.0-0.3.5, incl. 0.1.1), so pip's
# --extra-index-url resolves the wrong package. Installing straight from the
# public repo bypasses index name-resolution and is deterministic. No token.
/opt/crdbvenv/bin/pip install --quiet "psycopg[binary]"
/opt/crdbvenv/bin/pip install --quiet \
  "git+https://github.com/cockroachlabs/cockroachdb-python-library.git#subdirectory=packages/cockroachdb" \
  "git+https://github.com/cockroachlabs/cockroachdb-python-library.git#subdirectory=packages/cockroachdb-core"

mkdir -p /root/app

if [ "$LAB" = "resilient" ]; then
    cockroach sql --insecure --host=localhost:26257 -d defaultdb -e \
      "CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, balance INT); UPSERT INTO accounts VALUES (1, 1000), (2, 1000);" || true
    cat > /root/app/resilient.py <<'PY'
import time
import psycopg
from cockroachdb import crdb_retry

# All three nodes are listed, so the driver fails over if one goes down.
DSN = ("postgresql://root@localhost:26257,localhost:26258,localhost:26259"
       "/defaultdb?sslmode=disable")

@crdb_retry(max_retries=10, base_delay=0.1)
def transfer(a, b):
    with psycopg.connect(DSN) as conn, conn.transaction():
        conn.execute("UPDATE accounts SET balance = balance - 1 WHERE id = %s", (a,))
        conn.execute("UPDATE accounts SET balance = balance + 1 WHERE id = %s", (b,))

n = 0
while True:
    try:
        transfer(1, 2)
        n += 1
        if n % 20 == 0:
            print(f"ok: {n} transfers (app still serving)", flush=True)
    except Exception as e:
        print(f"ERROR (not retried away): {e}", flush=True)
    time.sleep(0.1)
PY
else
    cat > /root/app/first_query.py <<'PY'
import psycopg

DSN = "postgresql://root@localhost:26257/defaultdb?sslmode=disable"

# You'll fill this in during the challenges.
PY
fi

echo "[INFO] Python lab assets ready (${LAB})"
