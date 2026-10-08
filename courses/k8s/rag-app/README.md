# RAG Application — Cloud-Native AI Platform (KubeCon WS3)

A thin, **stateless** FastAPI service that implements Retrieval-Augmented
Generation (RAG) on top of CockroachDB. CockroachDB is used as **both** the
vector store and the system of record — embeddings live in the same rows as the
data they describe.

## Why this design

- **Stateless**: all durable state is in CockroachDB, so Kubernetes can scale,
  kill, and reschedule pods freely.
- **Local embeddings**: uses [`fastembed`](https://github.com/qdrant/fastembed)
  (ONNX, CPU-friendly, no PyTorch) with `BAAI/bge-small-en-v1.5` → **384-dim**
  vectors. No external API key is required to do real vector search.
- **Optional LLM**: the `/chat` generation step calls an OpenAI-compatible
  endpoint if `LLM_API_BASE` + `LLM_API_KEY` are set; otherwise it returns an
  honest **extractive** answer stitched from the retrieved chunks. Either way the
  retrieval half runs fully self-contained.
- **Connection pool**: talks to CockroachDB through `psycopg_pool`, not one
  connection per request.
- **Probes**: `/livez` (process alive) vs `/readyz` (DB reachable) — distinct on
  purpose (see the course notes on liveness vs readiness).
- **Metrics**: Prometheus `/metrics`, with per-stage latency (embed / retrieve /
  generate).

## Endpoints

| Method | Path       | Purpose                                            |
|--------|------------|----------------------------------------------------|
| GET    | `/livez`   | Liveness — 200 while the process is up             |
| GET    | `/readyz`  | Readiness — 200 only when CockroachDB is reachable |
| GET    | `/metrics` | Prometheus metrics                                 |
| POST   | `/ingest`  | Embed + store a document chunk                     |
| POST   | `/search`  | Pure semantic (vector) search                      |
| POST   | `/chat`    | Full RAG: embed → retrieve → augment → generate    |

## Configuration (env)

| Var              | Default                         | Source     |
|------------------|---------------------------------|------------|
| `DB_URL`         | (required)                      | Secret     |
| `DB_POOL_MIN`    | `2`                             | ConfigMap  |
| `DB_POOL_MAX`    | `10`                            | ConfigMap  |
| `EMBED_MODEL`    | `BAAI/bge-small-en-v1.5`        | ConfigMap  |
| `EMBED_DIM`      | `384`                           | ConfigMap  |
| `TOP_K`          | `5`                             | ConfigMap  |
| `LLM_API_BASE`   | (unset → extractive fallback)   | ConfigMap  |
| `LLM_API_KEY`    | (unset)                         | Secret     |
| `LLM_MODEL`      | `gpt-4o-mini`                   | ConfigMap  |

> NOTE (asset gap): to run in the lab this source must be published to
> `cockroach-university-assets/courses/k8s/rag-app/` and/or built into a
> published image. See the track report.
