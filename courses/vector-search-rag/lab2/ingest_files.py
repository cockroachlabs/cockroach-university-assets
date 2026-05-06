"""
Ingest real documents (PDF, Word, Markdown) into the RAG pipeline.

Pipeline: Load file -> Extract text -> Chunk -> Embed -> Store in CockroachDB
Each document is ingested in a single ACID transaction.
"""
import os
import sys
import psycopg2
from langchain_text_splitters import RecursiveCharacterTextSplitter
from embeddings import get_embeddings, get_connection_string

DOCS_DIR = "/root/lab/docs"

LOADERS = {
    ".pdf": ("langchain_community.document_loaders", "PyPDFLoader"),
    ".docx": ("langchain_community.document_loaders", "Docx2txtLoader"),
    ".md": ("langchain_community.document_loaders", "TextLoader"),
    ".txt": ("langchain_community.document_loaders", "TextLoader"),
}


def load_file(filepath):
    """Load a file using the appropriate LangChain document loader."""
    ext = os.path.splitext(filepath)[1].lower()
    if ext not in LOADERS:
        print(f"  Skipping unsupported format: {ext}")
        return []
    module_name, class_name = LOADERS[ext]
    module = __import__(module_name, fromlist=[class_name])
    loader_cls = getattr(module, class_name)
    loader = loader_cls(filepath)
    return loader.load()


def ingest_directory(docs_dir, tenant_id):
    """Load, chunk, embed, and store all documents from a directory."""
    embeddings = get_embeddings()
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=500,
        chunk_overlap=50,
        separators=["\n\n", "\n", ". ", " ", ""],
    )

    conn = psycopg2.connect(get_connection_string())
    conn.autocommit = True

    files = sorted(f for f in os.listdir(docs_dir) if not f.startswith("."))
    print(f"\nFound {len(files)} files in {docs_dir}/")
    print(f"{'=' * 60}")

    total_chunks = 0

    for filename in files:
        filepath = os.path.join(docs_dir, filename)
        ext = os.path.splitext(filename)[1].lower()

        print(f"\n--- {filename} ({ext.upper().strip('.')}) ---")

        # Step 1: Load
        print(f"  Loading with {LOADERS.get(ext, ('?','?'))[1]}...")
        pages = load_file(filepath)
        if not pages:
            continue
        full_text = "\n\n".join(page.page_content for page in pages)
        print(f"  Extracted {len(full_text):,} characters from {len(pages)} page(s)")

        # Step 2: Chunk
        chunks = splitter.split_text(full_text)
        print(f"  Split into {len(chunks)} chunks (500 chars, 50 overlap)")

        # Step 3 & 4: Embed + Store (in a single transaction)
        try:
            cur = conn.cursor()
            cur.execute("BEGIN")

            source = os.path.splitext(filename)[0]
            cur.execute(
                "INSERT INTO documents (title, source, tenant_id) VALUES (%s, %s, %s) RETURNING id",
                (filename, source, tenant_id),
            )
            doc_id = cur.fetchone()[0]

            for i, chunk_text in enumerate(chunks):
                vec = embeddings.embed_query(chunk_text)
                vec_str = "[" + ",".join(str(v) for v in vec) + "]"
                cur.execute(
                    "INSERT INTO chunks (document_id, chunk_index, content, embedding, tenant_id) "
                    "VALUES (%s, %s, %s, %s, %s)",
                    (doc_id, i, chunk_text, vec_str, tenant_id),
                )

            cur.execute("COMMIT")
            total_chunks += len(chunks)
            print(f"  Stored {len(chunks)} chunks with embeddings (COMMITTED)")

        except Exception as e:
            conn.rollback()
            print(f"  FAILED — rolled back: {e}")

    conn.close()

    print(f"\n{'=' * 60}")
    print(f"Ingestion complete: {len(files)} files, {total_chunks} total chunks")


if __name__ == "__main__":
    tenant = sys.argv[1] if len(sys.argv) > 1 else "acme"
    docs_dir = sys.argv[2] if len(sys.argv) > 2 else DOCS_DIR

    print(f"RAG File Ingestion Pipeline")
    print(f"Tenant: {tenant}")
    print(f"Source:  {docs_dir}/")
    ingest_directory(docs_dir, tenant)
