"""
RAG application for the KubeCon WS3 Cloud-Native AI Platform workshop.

A stateless FastAPI service that uses CockroachDB as both the vector store and
the system of record. Embeddings are produced locally with fastembed (ONNX,
384-dim) so the retrieval path needs no external API key. The /chat generation
step uses an OpenAI-compatible LLM if configured, else an extractive fallback.
"""
from __future__ import annotations

import os
import signal
import time
import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel
from psycopg_pool import ConnectionPool
from psycopg import errors as pg_errors
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("rag-app")

# --- Config (ConfigMap / Secret via env) ---
DB_URL = os.environ["DB_URL"]
DB_POOL_MIN = int(os.getenv("DB_POOL_MIN", "2"))
DB_POOL_MAX = int(os.getenv("DB_POOL_MAX", "10"))
EMBED_MODEL = os.getenv("EMBED_MODEL", "BAAI/bge-small-en-v1.5")
EMBED_DIM = int(os.getenv("EMBED_DIM", "384"))
TOP_K = int(os.getenv("TOP_K", "5"))
LLM_API_BASE = os.getenv("LLM_API_BASE", "").rstrip("/")
LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-4o-mini")

# --- Metrics ---
REQS = Counter("http_requests_total", "HTTP requests", ["endpoint", "status"])
STAGE_LAT = Histogram("rag_stage_seconds", "Per-stage latency", ["stage"])

pool: ConnectionPool | None = None
embedder = None  # fastembed.TextEmbedding, loaded at startup


def embed(text: str) -> list[float]:
    """Embed a single string into a 384-dim vector."""
    with STAGE_LAT.labels("embed").time():
        return list(next(iter(embedder.embed([text]))))


def vec_literal(v: list[float]) -> str:
    """Render a Python list as a CockroachDB VECTOR literal: '[1,2,3]'."""
    return "[" + ",".join(f"{x:.6f}" for x in v) + "]"


def retry_tx(fn, attempts: int = 5):
    """Run fn(conn) inside a retry loop that handles serialization errors."""
    assert pool is not None
    last = None
    for i in range(attempts):
        try:
            with pool.connection() as conn:
                return fn(conn)
        except pg_errors.SerializationFailure as e:  # 40001 — expected, retry
            last = e
            time.sleep(0.1 * (2 ** i))
        except pg_errors.OperationalError as e:  # dead/stale connection — retry on a fresh one
            last = e
            time.sleep(0.1 * (2 ** i))
    raise HTTPException(status_code=503, detail=f"database unavailable: {last}")


@asynccontextmanager
async def lifespan(_: FastAPI):
    global pool, embedder
    from fastembed import TextEmbedding
    log.info("loading embedding model %s", EMBED_MODEL)
    embedder = TextEmbedding(model_name=EMBED_MODEL)
    log.info("opening connection pool (%d-%d)", DB_POOL_MIN, DB_POOL_MAX)
    pool = ConnectionPool(DB_URL, min_size=DB_POOL_MIN, max_size=DB_POOL_MAX, open=True)

    # Graceful shutdown: drain in-flight work, then close the pool cleanly.
    def _term(*_a):
        log.info("SIGTERM received; closing connection pool")
        if pool is not None:
            pool.close()
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, _term)

    yield
    if pool is not None:
        pool.close()


app = FastAPI(title="RAG Platform", lifespan=lifespan)


class IngestIn(BaseModel):
    doc_id: str
    title: str
    chunk: str


class SearchIn(BaseModel):
    query: str
    k: int | None = None


class ChatIn(BaseModel):
    query: str
    k: int | None = None


@app.get("/livez", response_class=PlainTextResponse)
def livez():
    """Liveness: the process is up. Does NOT touch the database."""
    return "ok"


@app.get("/readyz", response_class=PlainTextResponse)
def readyz():
    """Readiness: only ready if CockroachDB is reachable."""
    try:
        retry_tx(lambda c: c.execute("SELECT 1").fetchone(), attempts=1)
        return "ready"
    except Exception:
        raise HTTPException(status_code=503, detail="not ready")


@app.get("/metrics")
def metrics():
    return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/ingest")
def ingest(body: IngestIn):
    v = vec_literal(embed(body.chunk))

    def _do(conn):
        conn.execute(
            "INSERT INTO document (id, title) VALUES (%s, %s) ON CONFLICT (id) DO NOTHING",
            (body.doc_id, body.title),
        )
        conn.execute(
            "INSERT INTO doc_chunk (doc_id, chunk, embedding) VALUES (%s, %s, %s::VECTOR)",
            (body.doc_id, body.chunk, v),
        )
    retry_tx(_do)
    REQS.labels("ingest", "200").inc()
    return {"status": "stored"}


def _search(query: str, k: int) -> list[dict]:
    v = vec_literal(embed(query))

    def _do(conn):
        with STAGE_LAT.labels("retrieve").time():
            rows = conn.execute(
                """
                SELECT c.chunk, d.title, c.embedding <=> %s::VECTOR AS distance
                FROM doc_chunk AS c
                JOIN document AS d ON d.id = c.doc_id
                ORDER BY c.embedding <=> %s::VECTOR
                LIMIT %s
                """,
                (v, v, k),
            ).fetchall()
        return [{"chunk": r[0], "title": r[1], "distance": float(r[2])} for r in rows]
    return retry_tx(_do)


@app.post("/search")
def search(body: SearchIn):
    hits = _search(body.query, body.k or TOP_K)
    REQS.labels("search", "200").inc()
    return {"results": hits}


@app.post("/chat")
def chat(body: ChatIn):
    hits = _search(body.query, body.k or TOP_K)
    context = "\n\n".join(f"- {h['chunk']}" for h in hits)
    answer = _generate(body.query, context)
    REQS.labels("chat", "200").inc()
    return {"answer": answer, "sources": [h["title"] for h in hits]}


def _generate(query: str, context: str) -> str:
    """Generate an answer. Uses an OpenAI-compatible LLM if configured, else
    returns an honest extractive answer from the retrieved context."""
    if not (LLM_API_BASE and LLM_API_KEY):
        return (
            "Based on the retrieved context:\n" + context +
            "\n\n(No LLM configured — this is an extractive answer. Set "
            "LLM_API_BASE and LLM_API_KEY to enable generation.)"
        )
    with STAGE_LAT.labels("generate").time():
        prompt = (
            "Answer the question using ONLY the context. If the context does not "
            f"contain the answer, say so.\n\nContext:\n{context}\n\nQuestion: {query}"
        )
        resp = httpx.post(
            f"{LLM_API_BASE}/chat/completions",
            headers={"Authorization": f"Bearer {LLM_API_KEY}"},
            json={"model": LLM_MODEL, "messages": [{"role": "user", "content": prompt}]},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]
