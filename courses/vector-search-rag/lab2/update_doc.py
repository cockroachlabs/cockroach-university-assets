import psycopg2
from embeddings import get_embeddings, get_connection_string

def update_document(doc_title, new_chunks, tenant_id):
    """
    Update a document's chunks atomically:
    1. Delete old chunks
    2. Embed new content
    3. Insert new chunks
    All in a single transaction.
    """
    embeddings = get_embeddings()
    conn = psycopg2.connect(get_connection_string())
    conn.autocommit = True
    cur = conn.cursor()

    try:
        cur.execute("BEGIN")

        cur.execute(
            "SELECT id FROM documents WHERE title = %s AND tenant_id = %s",
            (doc_title, tenant_id)
        )
        row = cur.fetchone()
        if not row:
            print(f"Document '{doc_title}' not found for tenant '{tenant_id}'")
            conn.rollback()
            return
        doc_id = row[0]

        cur.execute("DELETE FROM chunks WHERE document_id = %s", (doc_id,))
        print(f"Deleted old chunks for '{doc_title}'")

        for i, chunk_text in enumerate(new_chunks):
            vec = embeddings.embed_query(chunk_text)
            vec_str = "[" + ",".join(str(v) for v in vec) + "]"
            cur.execute(
                "INSERT INTO chunks (document_id, chunk_index, content, embedding, tenant_id) VALUES (%s, %s, %s, %s, %s)",
                (doc_id, i, chunk_text, vec_str, tenant_id)
            )

        cur.execute(
            "UPDATE documents SET updated_at = now() WHERE id = %s",
            (doc_id,)
        )

        cur.execute("COMMIT")
        print(f"Updated '{doc_title}' with {len(new_chunks)} new chunks")

    except Exception as e:
        conn.rollback()
        print(f"Update failed, rolled back: {e}")

    conn.close()

update_document(
    "SQL Performance Tuning",
    [
        "Use EXPLAIN ANALYZE to examine query execution plans. Look for full table scans and high row counts. CockroachDB 26.1 adds improved vectorized execution for analytical queries.",
        "Index selection should match your workload. Use partial indexes for filtered queries, expression indexes for computed values, and covering indexes to avoid table lookups entirely.",
        "Connection pooling is essential for production. Configure pool sizes at 3-4x CPU cores. CockroachDB 26.1 supports session-level variables for pool-friendly connection management.",
        "Query hints like @primary or @idx_name can force specific index usage when the optimizer makes suboptimal choices. Use sparingly — the optimizer usually picks correctly.",
    ],
    "acme"
)
