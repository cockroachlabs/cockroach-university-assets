-- Vector schema for the RAG platform (KubeCon WS3).
-- Requires CockroachDB v26.2+ where vector indexing is generally available.

-- 1. Enable vector indexing (a feature flag, not a preview flag).
SET CLUSTER SETTING feature.vector_index.enabled = true;

CREATE DATABASE IF NOT EXISTS ragdb;
SET DATABASE = ragdb;

-- 2. System of record: the documents themselves.
CREATE TABLE IF NOT EXISTS document (
  id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title STRING NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. One row per chunk: the embedding lives on the same row as its text,
--    with a foreign key back to the document (relational context).
--    384 dimensions = BAAI/bge-small-en-v1.5 (the app's embedding model).
CREATE TABLE IF NOT EXISTS doc_chunk (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_id    UUID NOT NULL REFERENCES document(id),
  chunk     STRING NOT NULL,
  embedding VECTOR(384) NOT NULL,
  VECTOR INDEX (embedding vector_cosine_ops)
);
