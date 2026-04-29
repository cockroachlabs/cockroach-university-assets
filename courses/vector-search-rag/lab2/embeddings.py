"""
Embedding provider with three-tier fallback:
1. OpenAI (if OPENAI_API_KEY is set)
2. Ollama with nomic-embed-text (default)
3. Mock embeddings (deterministic, last resort)
"""
import os
import math
import hashlib


def get_embeddings():
    """Return the best available embedding provider."""

    # Tier 1: OpenAI
    if os.environ.get("OPENAI_API_KEY"):
        print("Using OpenAI embeddings (text-embedding-3-small)")
        from langchain_openai import OpenAIEmbeddings
        return OpenAIEmbeddings(model="text-embedding-3-small")

    # Tier 2: Ollama (default)
    try:
        from langchain_ollama import OllamaEmbeddings
        embeddings = OllamaEmbeddings(model="nomic-embed-text")
        embeddings.embed_query("test")
        print("Using Ollama embeddings (nomic-embed-text, 768-dim)")
        return embeddings
    except Exception as e:
        print(f"Ollama not available ({e}), falling back to mock embeddings")

    # Tier 3: Mock embeddings
    print("Using mock embeddings (deterministic, 768-dim)")
    from langchain.embeddings.base import Embeddings

    class MockEmbeddings(Embeddings):
        def embed_documents(self, texts):
            return [self.embed_query(t) for t in texts]

        def embed_query(self, text):
            h = hashlib.sha256(text.encode()).hexdigest()
            vec = []
            for i in range(0, min(len(h), 768 * 2), 2):
                val = int(h[i:i + 2], 16) / 255.0 * 2 - 1
                vec.append(val)
            while len(vec) < 768:
                idx = len(vec)
                val = int(hashlib.sha256(f"{text}{idx}".encode()).hexdigest()[:2], 16) / 255.0 * 2 - 1
                vec.append(val)
            norm = math.sqrt(sum(x * x for x in vec))
            vec = [x / norm for x in vec]
            return vec

    return MockEmbeddings()


def get_connection_string():
    """Return the CockroachDB connection string."""
    return "cockroachdb://root@localhost:26257/raglab?sslmode=verify-full&sslrootcert=/root/certs/ca.crt&sslcert=/root/certs/client.root.crt&sslkey=/root/certs/client.root.key"
