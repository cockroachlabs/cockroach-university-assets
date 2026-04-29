#!/usr/bin/env python3
"""Insert synthetic vector embeddings into vectorlab.documents."""
import subprocess
import math
import random

random.seed(42)

documents = [
    ("CockroachDB automatically rebalances data across nodes when new nodes are added.", "architecture", "acme"),
    ("Ranges are the unit of replication in CockroachDB, typically 512MB in size.", "architecture", "acme"),
    ("The Raft consensus protocol ensures data consistency across replicas.", "architecture", "acme"),
    ("CockroachDB uses MVCC to handle concurrent transactions without blocking.", "architecture", "globex"),
    ("Leaseholders coordinate all reads and writes for a given range.", "architecture", "globex"),
    ("CREATE TABLE uses standard SQL syntax with CockroachDB-specific extensions.", "sql", "acme"),
    ("Secondary indexes are automatically distributed and replicated like table data.", "sql", "acme"),
    ("CockroachDB supports JSON columns with inverted indexes for efficient querying.", "sql", "globex"),
    ("Use AS OF SYSTEM TIME to perform historical reads without blocking writes.", "sql", "globex"),
    ("The EXPLAIN ANALYZE statement shows actual execution statistics for a query.", "sql", "acme"),
    ("Backup schedules automate recurring full and incremental backups.", "operations", "acme"),
    ("Rolling restarts allow zero-downtime upgrades of CockroachDB clusters.", "operations", "globex"),
    ("Node decommissioning safely moves data off a node before removal.", "operations", "globex"),
    ("CockroachDB changefeeds stream row-level changes to external sinks.", "operations", "acme"),
    ("Zone configurations control data placement for compliance and performance.", "operations", "acme"),
    ("Serializable isolation prevents all transaction anomalies including phantom reads.", "transactions", "acme"),
    ("Transaction retry errors (40001) occur when serializable conflicts are detected.", "transactions", "globex"),
    ("CockroachDB uses hybrid logical clocks for global transaction ordering.", "transactions", "globex"),
    ("Follower reads can serve historical data from any replica, reducing latency.", "transactions", "acme"),
    ("Multi-region tables use REGIONAL BY ROW to place data near its users.", "multi-region", "acme"),
    ("GLOBAL tables provide low-latency reads from any region at the cost of write latency.", "multi-region", "globex"),
    ("Survival goals determine whether a database can survive zone or region failures.", "multi-region", "globex"),
    ("Super regions restrict data to a subset of regions for compliance requirements.", "multi-region", "acme"),
    ("The gateway region is where the SQL query enters the cluster.", "multi-region", "acme"),
    ("Vector search in CockroachDB uses the VECTOR(n) data type for embeddings.", "vectors", "acme"),
    ("The cosine distance operator <=> is ideal for normalized embeddings like OpenAI.", "vectors", "globex"),
    ("C-SPANN indexes partition vector data aligned with CockroachDB ranges.", "vectors", "acme"),
    ("Hybrid queries combine vector similarity with SQL predicates for filtered search.", "vectors", "globex"),
    ("Predicate pushdown on vector queries filters data before the ANN search.", "vectors", "acme"),
    ("Embedding dimensions affect storage: VECTOR(1536) uses about 6KB per row.", "vectors", "globex"),
]


def make_embedding(text, dims=8):
    vec = []
    for i in range(dims):
        h = hash(text + str(i)) % 10000
        vec.append(round((h / 10000.0) * 2 - 1, 6))
    norm = math.sqrt(sum(x * x for x in vec))
    if norm > 0:
        vec = [round(x / norm, 6) for x in vec]
    return vec


sql_parts = []
for doc_text, category, tenant in documents:
    emb = make_embedding(doc_text)
    vec_str = "[" + ",".join(str(x) for x in emb) + "]"
    escaped = doc_text.replace("'", "''")
    sql_parts.append(f"('{escaped}', '{category}', '{tenant}', '{vec_str}')")

sql = f"""
CREATE TABLE vectorlab.documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content STRING NOT NULL,
    category STRING NOT NULL,
    tenant_id STRING NOT NULL,
    embedding VECTOR(8) NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    INDEX idx_category (category),
    INDEX idx_tenant (tenant_id)
);

INSERT INTO vectorlab.documents (content, category, tenant_id, embedding) VALUES
{','.join(sql_parts)};
"""

subprocess.run(
    [
        "cockroach", "sql",
        "--certs-dir=/root/certs",
        "--host=localhost:26257",
        "--execute", sql,
    ],
    check=True,
)
