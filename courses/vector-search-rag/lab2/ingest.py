import sys
import psycopg2
from embeddings import get_embeddings, get_connection_string
from sample_docs import TENANT_ACME_DOCS, TENANT_GLOBEX_DOCS

def ingest_documents(docs, tenant_id):
    """Ingest documents with atomic transactions — all chunks succeed or none do."""
    embeddings = get_embeddings()
    conn = psycopg2.connect(get_connection_string())
    conn.autocommit = True

    for doc in docs:
        try:
            cur = conn.cursor()
            cur.execute("BEGIN")

            cur.execute(
                "INSERT INTO documents (title, source, tenant_id) VALUES (%s, %s, %s) RETURNING id",
                (doc["title"], doc["source"], tenant_id)
            )
            doc_id = cur.fetchone()[0]

            for i, chunk_text in enumerate(doc["chunks"]):
                vec = embeddings.embed_query(chunk_text)
                vec_str = "[" + ",".join(str(v) for v in vec) + "]"
                cur.execute(
                    "INSERT INTO chunks (document_id, chunk_index, content, embedding, tenant_id) VALUES (%s, %s, %s, %s, %s)",
                    (doc_id, i, chunk_text, vec_str, tenant_id)
                )

            cur.execute("COMMIT")
            print(f"  Ingested: {doc['title']} ({len(doc['chunks'])} chunks)")

        except Exception as e:
            conn.rollback()
            print(f"  FAILED: {doc['title']} - {e}")

    conn.close()

if __name__ == "__main__":
    tenant = sys.argv[1] if len(sys.argv) > 1 else "acme"
    docs = TENANT_ACME_DOCS if tenant == "acme" else TENANT_GLOBEX_DOCS

    print(f"\nIngesting documents for tenant '{tenant}'...")
    ingest_documents(docs, tenant)
    print("Done!")
