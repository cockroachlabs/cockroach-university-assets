"""Database access: connection pool and transaction retries.

Course 1, Lab 1 starting point (see the TODOs).
"""

import logging
import os
import random  # noqa: F401  (you will need it for backoff jitter)
import time  # noqa: F401  (you will need it for backoff sleeps)
from collections.abc import Callable
from typing import TypeVar

import psycopg
from psycopg_pool import ConnectionPool  # noqa: F401

log = logging.getLogger("talc.db")

T = TypeVar("T")

# Read the connection string from the environment so no credentials live in code.
DATABASE_URL = os.environ.get("DATABASE_URL", "")

_pool: ConnectionPool | None = None


def get_pool() -> ConnectionPool:
    """Return the process-wide connection pool, creating it on first use."""
    global _pool
    if _pool is None:
        if not DATABASE_URL:
            raise RuntimeError("DATABASE_URL is not set")
        # TODO (Lab 1, step 3): create a psycopg_pool.ConnectionPool:
        #   conninfo=DATABASE_URL, min_size=2, max_size=10,
        #   kwargs={"autocommit": True, "application_name": "talc"}, open=True
        # then call _pool.wait(timeout=10) so a bad connection string fails fast.
        raise NotImplementedError("TODO: create the connection pool in talc/db.py")
    return _pool


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


def run_transaction(op: Callable[[psycopg.Connection], T], max_retries: int = 5) -> T:
    """Run op(conn) inside a transaction.

    TODO (Lab 1, step 4): CockroachDB runs transactions at SERIALIZABLE
    isolation. When two transactions conflict, one fails with SQLSTATE 40001
    (psycopg.errors.SerializationFailure) and must be retried from the start.
    Wrap the code below in a loop of up to max_retries attempts. On
    SerializationFailure, sleep with exponential backoff plus jitter and try
    again; on the last attempt, re-raise the error.
    """
    pool = get_pool()
    with pool.connection() as conn:
        with conn.transaction():
            return op(conn)
