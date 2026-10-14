#!/bin/bash
set -euxo pipefail

# Per-language setup for the "CockroachDB for Python Developers" labs.
# Usage: python.sh [connect|resilient]
#   connect   -> single-node lab: deploy the first_query starter
#   resilient -> 3-node lab: seed accounts + deploy the looping app
# Requires GH_USER / GH_PAT in the environment (Instruqt track variables)
# while the CockroachDB Python Library is pre-release.

LAB=${1:-connect}

DEBIAN_FRONTEND=noninteractive apt -y install python3 python3-pip python3-venv || true

# --- CockroachDB Python Library (pre-release, strategy B) --------------------
# PUBLIC-SWAP: after GA, replace the two git installs with:
#   pip3 install cockroachdb cockroachdb-core
pip3 install --quiet "psycopg[binary]"
pip3 install --quiet \
  "git+https://${GH_USER}:${GH_PAT}@github.com/felipeg48/cockroachdb-python-library.git#subdirectory=packages/cockroachdb" \
  "git+https://${GH_USER}:${GH_PAT}@github.com/felipeg48/cockroachdb-python-library.git#subdirectory=packages/cockroachdb-core"

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
