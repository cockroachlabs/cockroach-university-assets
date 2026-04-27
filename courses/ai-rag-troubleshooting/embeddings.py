#!/usr/bin/env python3
"""
Embedding helper using sentence-transformers.

Provides a simple interface to generate 384-dimensional embeddings
using the all-MiniLM-L6-v2 model. Falls back to deterministic mock
embeddings if sentence-transformers is not available.
"""

import sys
import hashlib
import struct

# Global model reference (lazy-loaded)
_model = None
_use_real = None


def _load_model():
    """Lazy-load the sentence-transformers model."""
    global _model, _use_real
    if _use_real is not None:
        return

    try:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer("all-MiniLM-L6-v2")
        _use_real = True
        print("[embeddings] Loaded all-MiniLM-L6-v2 model (384-dim)", file=sys.stderr)
    except ImportError:
        _use_real = False
        print("[embeddings] WARNING: sentence-transformers not available, using mock embeddings", file=sys.stderr)


def _mock_embed(text):
    """Generate deterministic pseudo-random 384-dim unit vector from text."""
    h = hashlib.sha512(text.encode()).digest()
    extended = h
    while len(extended) < 384 * 4:
        extended += hashlib.sha512(extended).digest()
    vals = []
    for i in range(384):
        raw = struct.unpack_from(">I", extended, i * 4)[0]
        vals.append((raw / 2**32) * 2 - 1)
    norm = sum(v**2 for v in vals) ** 0.5
    return [v / norm for v in vals]


def embed(text):
    """
    Generate a 384-dimensional embedding vector for the given text.

    Uses all-MiniLM-L6-v2 if available, otherwise falls back to
    deterministic mock embeddings.

    Args:
        text: The text to embed (string)

    Returns:
        List of 384 floats representing the embedding vector
    """
    _load_model()
    if _use_real:
        return _model.encode(text).tolist()
    else:
        return _mock_embed(text)


def embed_batch(texts):
    """
    Generate embeddings for a batch of texts.

    Args:
        texts: List of strings to embed

    Returns:
        List of embedding vectors (each a list of 384 floats)
    """
    _load_model()
    if _use_real:
        return [vec.tolist() for vec in _model.encode(texts)]
    else:
        return [_mock_embed(t) for t in texts]


def vector_to_sql(vec):
    """Format an embedding vector as a SQL VECTOR literal."""
    return "'[" + ",".join(f"{v:.6f}" for v in vec) + "]'"


if __name__ == "__main__":
    # Self-test
    test_text = "CockroachDB node is unresponsive after maintenance"
    vec = embed(test_text)
    print(f"Embedding dimension: {len(vec)}")
    print(f"First 5 values: {vec[:5]}")
    print(f"Using real model: {_use_real}")
