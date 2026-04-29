import sys
import psycopg2
from embeddings import get_embeddings, get_connection_string

def search(query_text, tenant_id, top_k=5):
    """Search for similar chunks within a specific tenant."""
    embeddings = get_embeddings()
    query_vec = embeddings.embed_query(query_text)
    vec_str = "[" + ",".join(str(v) for v in query_vec) + "]"

    conn = psycopg2.connect(get_connection_string())
    cur = conn.cursor()

    cur.execute("""
        SELECT
            c.content,
            d.title,
            c.embedding <=> %s::VECTOR(768) AS distance
        FROM chunks c
        JOIN documents d ON d.id = c.document_id
        WHERE c.tenant_id = %s
        ORDER BY distance ASC
        LIMIT %s
    """, (vec_str, tenant_id, top_k))

    results = cur.fetchall()
    conn.close()
    return results

if __name__ == "__main__":
    query = sys.argv[1] if len(sys.argv) > 1 else "How does CockroachDB handle node failures?"
    tenant = sys.argv[2] if len(sys.argv) > 2 else "acme"

    print(f"\nQuery: '{query}'")
    print(f"Tenant: {tenant}")
    print(f"{'─' * 60}")

    results = search(query, tenant)
    for i, (content, title, distance) in enumerate(results, 1):
        print(f"\n{i}. [{title}] (distance: {distance:.4f})")
        print(f"   {content[:120]}...")
