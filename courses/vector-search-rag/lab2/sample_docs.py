"""Sample document corpus for the RAG lab."""

TENANT_ACME_DOCS = [
    {
        "title": "CockroachDB Architecture Overview",
        "source": "architecture-guide",
        "chunks": [
            "CockroachDB is a distributed SQL database that provides horizontal scalability, strong consistency, and survivability. It distributes data across nodes using a sorted key-value map divided into ranges of approximately 512MB each.",
            "Each range is replicated to at least three nodes using the Raft consensus protocol. This ensures that data remains available even if one or more nodes fail. The replication factor is configurable per zone.",
            "CockroachDB uses a layered architecture: SQL layer parses and optimizes queries, Transaction layer manages ACID transactions, Distribution layer routes operations to the correct range, Replication layer handles Raft consensus, and Storage layer persists data using Pebble.",
        ]
    },
    {
        "title": "SQL Performance Tuning",
        "source": "performance-guide",
        "chunks": [
            "Use EXPLAIN ANALYZE to understand query execution plans and identify bottlenecks. Look for full table scans, which indicate missing indexes. The number of rows scanned versus rows returned reveals index efficiency.",
            "Secondary indexes speed up queries but add write overhead. Each index is stored as a separate sorted map of key-value pairs, distributed and replicated just like table data. Choose indexes based on your query patterns.",
            "Connection pooling reduces the overhead of establishing new database connections. Use a pool size of 2-4 connections per CPU core. CockroachDB works well with pgBouncer and most application-level connection pools.",
        ]
    },
    {
        "title": "Backup and Restore Operations",
        "source": "operations-guide",
        "chunks": [
            "CockroachDB supports full and incremental backups to cloud storage (S3, GCS, Azure). Backup schedules automate recurring backups with configurable retention policies. Use BACKUP DATABASE to capture a consistent snapshot.",
            "Incremental backups capture only changes since the last full backup, reducing storage and time. Create a schedule that combines daily full backups with hourly incrementals for optimal recovery point objectives.",
            "RESTORE operations can target a specific point in time using AS OF SYSTEM TIME. This enables recovery to any moment within the GC TTL window, which defaults to 4 hours but is configurable.",
        ]
    },
]

TENANT_GLOBEX_DOCS = [
    {
        "title": "Multi-Region Deployment Guide",
        "source": "multi-region-guide",
        "chunks": [
            "CockroachDB multi-region capabilities allow you to control where data is stored and how it is accessed across geographic regions. Configure survival goals to survive zone failures or entire region failures.",
            "REGIONAL BY ROW tables place each row in the region specified by its crdb_region column. This ensures data locality - reads and writes for a row are fast in the rows home region. Cross-region access incurs latency.",
            "GLOBAL tables are optimized for low-latency reads from any region. They achieve this through non-blocking transactions that avoid cross-region coordination on reads. Writes to GLOBAL tables are slower as they must replicate globally.",
        ]
    },
    {
        "title": "Transaction Handling Best Practices",
        "source": "transactions-guide",
        "chunks": [
            "CockroachDB uses serializable isolation by default, the strongest level in SQL. This prevents all transaction anomalies including dirty reads, non-repeatable reads, phantom reads, and write skew.",
            "Transaction retry errors (SQLSTATE 40001) occur when concurrent transactions conflict under serializable isolation. Applications must implement retry logic with exponential backoff. This is the cost of guaranteed consistency.",
            "Use SELECT FOR UPDATE to explicitly lock rows you intend to modify. This reduces retry errors by declaring intent early in the transaction. The lock is released when the transaction commits or rolls back.",
        ]
    },
    {
        "title": "Changefeed Configuration",
        "source": "cdc-guide",
        "chunks": [
            "Changefeeds stream row-level changes from CockroachDB tables to external sinks like Kafka, cloud storage, or webhooks. They enable real-time data pipelines and event-driven architectures.",
            "Enterprise changefeeds support schema change handling, filtering with WHERE clauses, and multiple output formats including JSON and Avro. Configure the min_checkpoint_frequency to control how often progress is saved.",
            "Use changefeeds to trigger re-embedding workflows: when document content changes, the changefeed fires a webhook to your embedding service, which computes new vectors and atomically updates them in CockroachDB.",
        ]
    },
]
