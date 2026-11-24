"""Database access: connection pool and transaction retries.

Course 1, Lab 1 solution.
"""

import logging
import os
import random
import time
from collections.abc import Callable
from typing import TypeVar

import psycopg
from psycopg_pool import ConnectionPool

log = logging.getLogger("talc.db")

T = TypeVar("T")

# Read the connection string from the environment so no credentials live in code.
# Example: postgresql://talc_app:...@localhost:26257/talc?sslmode=verify-full&sslrootcert=/root/certs/ca.crt
DATABASE_URL = os.environ.get("DATABASE_URL", "")

_pool: ConnectionPool | None = None


def get_pool() -> ConnectionPool:
    """Return the process-wide connection pool, creating it on first use."""
    global _pool
    if _pool is None:
        if not DATABASE_URL:
            raise RuntimeError("DATABASE_URL is not set")
        _pool = ConnectionPool(
            conninfo=DATABASE_URL,
            min_size=2,
            max_size=10,
            # autocommit=True lets conn.transaction() issue an explicit BEGIN/COMMIT.
            kwargs={"autocommit": True, "application_name": "talc"},
            open=True,
        )
        _pool.wait(timeout=10)
    return _pool


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def run_transaction(op: Callable[[psycopg.Connection], T], max_retries: int = 5) -> T:
    """Run op(conn) inside a transaction, retrying on serialization errors.

    CockroachDB runs transactions at SERIALIZABLE isolation by default. When two
    transactions conflict, one of them fails with SQLSTATE 40001 and the client
    must retry the whole transaction. op must therefore be safe to run more than once.
    """
    pool = get_pool()
    for attempt in range(1, max_retries + 1):
        with pool.connection() as conn:
            try:
                with conn.transaction():
                    return op(conn)
            except psycopg.errors.SerializationFailure as err:
                if attempt == max_retries:
                    raise
                # Exponential backoff with jitter: about 50ms, 100ms, 200ms, ... capped at 2s.
                delay = min(2.0, 0.05 * 2 ** (attempt - 1)) * (0.5 + random.random())
                log.warning("40001 on attempt %d, retrying in %.0f ms: %s", attempt, delay * 1000, err.diag.message_primary)
                time.sleep(delay)
    raise AssertionError("unreachable")
