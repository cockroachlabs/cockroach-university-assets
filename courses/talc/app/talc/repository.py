"""SQL for users, conversations and messages.

Course 1, Lab 2 solution.
"""

from datetime import datetime
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from . import agent
from .db import get_pool, run_transaction

PAGE_SIZE = 20


# ---------------------------------------------------------------- users


def upsert_user(email: str, display_name: str) -> dict:
    def op(conn: psycopg.Connection) -> dict:
        cur = conn.cursor(row_factory=dict_row)
        cur.execute(
            """INSERT INTO users (email, display_name) VALUES (%s, %s)
               ON CONFLICT (email) DO UPDATE SET display_name = excluded.display_name
               RETURNING id, email, display_name""",
            (email, display_name),
        )
        return cur.fetchone()

    return run_transaction(op)


def list_users() -> list[dict]:
    with get_pool().connection() as conn:
        cur = conn.cursor(row_factory=dict_row)
        cur.execute("SELECT id, email, display_name FROM users ORDER BY email")
        return cur.fetchall()


# ---------------------------------------------------------------- conversations


def create_conversation(user_id: UUID, title: str | None = None) -> dict:
    def op(conn: psycopg.Connection) -> dict:
        cur = conn.cursor(row_factory=dict_row)
        cur.execute(
            """INSERT INTO conversations (user_id, title)
               VALUES (%s, COALESCE(%s, 'New conversation'))
               RETURNING id, title, updated_at""",
            (user_id, title),
        )
        return cur.fetchone()

    return run_transaction(op)


def list_conversations(user_id: UUID, limit: int = 50) -> list[dict]:
    # Served by conversations_user_recent_idx (user_id, updated_at DESC).
    with get_pool().connection() as conn:
        cur = conn.cursor(row_factory=dict_row)
        cur.execute(
            """SELECT id, title, updated_at FROM conversations
               WHERE user_id = %s ORDER BY updated_at DESC LIMIT %s""",
            (user_id, limit),
        )
        return cur.fetchall()


# ---------------------------------------------------------------- messages


def _encode_cursor(row: dict) -> str:
    return f"{row['created_at'].isoformat()}|{row['id']}"


def _decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    ts, msg_id = cursor.split("|")
    return datetime.fromisoformat(ts), UUID(msg_id)


def list_messages(conversation_id: UUID, cursor: str | None = None, limit: int = PAGE_SIZE) -> dict:
    """Return one page of messages, oldest first, plus a cursor for the next older page.

    Keyset pagination: seek straight to (created_at, id) < cursor using
    messages_conversation_idx, instead of reading and discarding every skipped row.
    """
    with get_pool().connection() as conn:
        cur = conn.cursor(row_factory=dict_row)
        if cursor is None:
            cur.execute(
                """SELECT id, role, content, created_at FROM messages
                   WHERE conversation_id = %s
                   ORDER BY created_at DESC, id DESC LIMIT %s""",
                (conversation_id, limit + 1),
            )
        else:
            before_ts, before_id = _decode_cursor(cursor)
            cur.execute(
                """SELECT id, role, content, created_at FROM messages
                   WHERE conversation_id = %s AND (created_at, id) < (%s, %s)
                   ORDER BY created_at DESC, id DESC LIMIT %s""",
                (conversation_id, before_ts, before_id, limit + 1),
            )
        rows = cur.fetchall()
    has_more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = _encode_cursor(rows[-1]) if has_more else None
    return {"messages": list(reversed(rows)), "next_cursor": next_cursor}


def send_message(conversation_id: UUID, text: str) -> dict:
    """Store the user's message and the assistant's reply atomically.

    The reply is generated first, outside the transaction: never hold a
    transaction open while waiting on a slow model call.
    """
    with get_pool().connection() as conn:
        history_len = conn.execute(
            "SELECT count(*) FROM messages WHERE conversation_id = %s", (conversation_id,)
        ).fetchone()[0]
    assistant = agent.reply(text, history_len)

    def op(conn: psycopg.Connection) -> dict:
        cur = conn.cursor(row_factory=dict_row)
        cur.execute(
            "INSERT INTO messages (conversation_id, role, content) VALUES (%s, 'user', %s)",
            (conversation_id, Jsonb({"text": text})),
        )
        if text.startswith("/crash"):
            raise RuntimeError("Simulated crash after saving the user message")
        cur.execute(
            """INSERT INTO messages (conversation_id, role, content) VALUES (%s, 'assistant', %s)
               RETURNING id, role, content, created_at""",
            (conversation_id, Jsonb(assistant)),
        )
        reply_row = cur.fetchone()
        # Bump the conversation to the top of the sidebar; name it after the first message.
        cur.execute(
            """UPDATE conversations
               SET updated_at = now(),
                   title = IF(title = 'New conversation', left(%s, 60), title)
               WHERE id = %s""",
            (text, conversation_id),
        )
        return reply_row

    return run_transaction(op)
