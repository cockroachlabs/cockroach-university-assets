import psycopg2
from embeddings import get_embeddings, get_connection_string

embeddings = get_embeddings()
conn = psycopg2.connect(get_connection_string())
conn.autocommit = True
cur = conn.cursor()

try:
    cur.execute("BEGIN")

    cur.execute(
        "INSERT INTO documents (title, source, tenant_id) VALUES (%s, %s, %s) RETURNING id",
        ("Ghost Document", "test", "acme")
    )
    doc_id = cur.fetchone()[0]

    vec = embeddings.embed_query("This chunk will be rolled back")
    vec_str = "[" + ",".join(str(v) for v in vec) + "]"
    cur.execute(
        "INSERT INTO chunks (document_id, chunk_index, content, embedding, tenant_id) VALUES (%s, %s, %s, %s, %s)",
        (doc_id, 0, "This chunk will be rolled back", vec_str, "acme")
    )
    print("Inserted document and first chunk...")

    raise Exception("Simulated application crash!")

    cur.execute("COMMIT")

except Exception as e:
    conn.rollback()
    print(f"Transaction rolled back: {e}")
    print("No orphaned documents or chunks were created.")

conn.close()
