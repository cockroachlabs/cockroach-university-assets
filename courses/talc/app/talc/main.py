"""Talc web app: a FastAPI backend plus a one-page chat UI."""

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID

import psycopg
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from . import repository as repo
from .db import close_pool, get_pool

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
STATIC = Path(__file__).parent / "static"


@asynccontextmanager
async def lifespan(_: FastAPI):
    get_pool()  # fail fast if DATABASE_URL is wrong
    yield
    close_pool()


app = FastAPI(title="Talc", lifespan=lifespan)


class UserIn(BaseModel):
    email: str
    display_name: str


class ConversationIn(BaseModel):
    user_id: UUID
    title: str | None = None


class MessageIn(BaseModel):
    text: str


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC / "index.html")


@app.get("/api/health")
def health() -> dict:
    with get_pool().connection() as conn:
        version = conn.execute("SELECT version()").fetchone()[0]
    return {"ok": True, "database": version}


@app.get("/api/users")
def users() -> list[dict]:
    return repo.list_users()


@app.post("/api/users")
def create_user(body: UserIn) -> dict:
    return repo.upsert_user(body.email.strip().lower(), body.display_name.strip())


@app.get("/api/users/{user_id}/conversations")
def conversations(user_id: UUID) -> list[dict]:
    return repo.list_conversations(user_id)


@app.post("/api/conversations")
def create_conversation(body: ConversationIn) -> dict:
    try:
        return repo.create_conversation(body.user_id, body.title)
    except psycopg.errors.ForeignKeyViolation:
        raise HTTPException(404, "unknown user")


@app.get("/api/conversations/{conversation_id}/messages")
def messages(conversation_id: UUID, cursor: str | None = None) -> dict:
    return repo.list_messages(conversation_id, cursor)


@app.post("/api/conversations/{conversation_id}/messages")
def send(conversation_id: UUID, body: MessageIn) -> dict:
    try:
        return repo.send_message(conversation_id, body.text)
    except psycopg.errors.ForeignKeyViolation:
        raise HTTPException(404, "unknown conversation")
    except RuntimeError as err:
        raise HTTPException(500, str(err))
