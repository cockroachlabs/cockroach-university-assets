"""Force a serialization conflict and show whether run_transaction() survives it.

Two "browser tabs" rename the same conversation at the same moment. Each one
reads the row, waits until the other has read it too, then writes. Under
SERIALIZABLE isolation one of the two must fail with SQLSTATE 40001, and
the app has to retry it.

Usage:  python -m tools.retry_demo
"""

import sys
import threading

import psycopg

from talc import repository as repo
from talc.db import close_pool, run_transaction

user = repo.upsert_user("retry-demo@example.com", "Retry Demo")
conv = repo.create_conversation(user["id"], "Retry demo")
barrier = threading.Barrier(2, timeout=5)
attempts = {"tab-1": 0, "tab-2": 0}
results: dict[str, str] = {}


def rename(tab: str) -> None:
    def op(conn: psycopg.Connection) -> None:
        attempts[tab] += 1
        title = conn.execute("SELECT title FROM conversations WHERE id = %s", (conv["id"],)).fetchone()[0]
        if attempts[tab] == 1:
            barrier.wait()  # first attempt only: make both tabs read before either writes
        conn.execute(
            "UPDATE conversations SET title = %s, updated_at = now() WHERE id = %s",
            (f"{title} + {tab}", conv["id"]),
        )

    try:
        run_transaction(op)
        results[tab] = "committed"
    except psycopg.errors.SerializationFailure as err:
        results[tab] = f"FAILED with 40001: {err.diag.message_primary}"
    except threading.BrokenBarrierError:
        results[tab] = "barrier broken"


threads = [threading.Thread(target=rename, args=(t,)) for t in attempts]
for t in threads:
    t.start()
for t in threads:
    t.join()

final = repo.list_conversations(user["id"], limit=50)
title = next(c["title"] for c in final if c["id"] == conv["id"])
for tab in attempts:
    print(f"{tab}: {results[tab]} after {attempts[tab]} attempt(s)")
print(f"final title: {title!r}")
close_pool()

ok = all(r == "committed" for r in results.values())
print("\nRESULT:", "both renames committed; the retry worked" if ok else "a transaction was lost; add retry logic to run_transaction()")
sys.exit(0 if ok else 1)
