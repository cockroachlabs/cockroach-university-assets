# Talc app (Cockroach University)

Starter and reference code for the **Talc** course series: build a small,
self-hosted team AI assistant (chat, skills, tools, memory) on CockroachDB.

Stack: Python 3, FastAPI, psycopg 3 + psycopg-pool, CockroachDB v26.2.
The "agent" is a stub (`talc/agent.py`), so no LLM or API key is needed.

## Layout

| Path | What |
|---|---|
| `app/` | Reference app at the **end of Course 1** (Lab 1 and Lab 2 solutions) |
| `app/schema.sql` | Lab 1 solution schema |
| `app/migrations/lab2.sql` | Lab 2 inverted index |
| `app/tools/` | `retry_demo.py` (forces a 40001), `hotspot_demo.sql`, `seed.sql` (Lab 2 data) |
| `labN/start-overrides/` | Files copied over `app/` to create Lab N's starting point (TODO versions) |

Instruqt setup does `cp -r app /root/talc && cp -r labN/start-overrides/. /root/talc/`.
Solve scripts copy files back from `app/`.

Note: `lab1/start-overrides/talc/repository.py` is the same file as
`lab2/start-overrides/talc/repository.py`. Keep them in sync.

## Run locally

```bash
cd app
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
export DATABASE_URL="postgresql://talc_app:...@localhost:26257/talc?sslmode=verify-full&sslrootcert=certs/ca.crt"
cockroach sql ... -d talc -f schema.sql
./run.sh   # http://localhost:8000
```

Instruqt tracks: `cu-talc-lab1`, `cu-talc-lab2`.
