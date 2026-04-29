import psycopg2
from embeddings import get_embeddings, get_connection_string

def search_by_source(query_text, tenant_id, source_filter):
    """Search within a specific tenant AND source document."""
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
          AND d.source = %s
        ORDER BY distance ASC
        LIMIT 3
    """, (vec_str, tenant_id, source_filter))

    results = cur.fetchall()
    conn.close()

    print(f"\nQuery: 'backup recovery strategy'")
    print(f"Tenant: {tenant_id}, Source: {source_filter}")
    print(f"{'─' * 60}")
    for i, (content, title, distance) in enumerate(results, 1):
        print(f"\n{i}. [{title}] (distance: {distance:.4f})")
        print(f"   {content[:120]}...")

search_by_source("backup recovery strategy", "acme", "operations-guide")
