# Transaction Handling Best Practices

## CockroachDB University | Version 26.1

---

## Serializable Isolation

CockroachDB uses serializable isolation by default, the strongest isolation level defined by the SQL standard. Unlike most databases that default to read committed or repeatable read, CockroachDB guarantees that concurrent transactions produce results equivalent to some serial execution order.

This eliminates all concurrency anomalies:

- **Dirty reads**: Reading uncommitted data from another transaction
- **Non-repeatable reads**: Getting different results when re-reading the same row
- **Phantom reads**: New rows appearing in a repeated range query
- **Write skew**: Two transactions reading overlapping data and making conflicting writes

The cost of serializable isolation is that some transactions may need to be retried when conflicts are detected. This is a deliberate trade-off: CockroachDB prioritizes correctness over convenience.

## Transaction Retry Handling

When two transactions conflict under serializable isolation, CockroachDB aborts one of them with a retry error (SQLSTATE 40001). The application must catch this error and re-execute the entire transaction from the beginning.

Retry logic should use exponential backoff with jitter:

1. Catch the 40001 error
2. Wait for a random duration: base_delay * 2^attempt + random_jitter
3. Re-execute the entire transaction (not just the failed statement)
4. Give up after a maximum number of retries (typically 5-10)

Client libraries provide built-in retry helpers:
- **Go**: `crdb.ExecuteTx()`
- **Java**: `CockroachDBRetryHelper.retry()`
- **Python**: Use a decorator or context manager pattern

## Explicit Locking with SELECT FOR UPDATE

Use `SELECT FOR UPDATE` to explicitly lock rows you intend to modify later in the transaction. This declares intent early, reducing the window for conflicts and therefore reducing retry frequency.

Without explicit locking, two transactions can both read the same rows, compute new values, and then conflict when they try to write. With `SELECT FOR UPDATE`, the second transaction waits for the first to complete, serializing access naturally.

Best practices for `SELECT FOR UPDATE`:

- Lock rows as early as possible in the transaction
- Lock only the rows you will actually modify
- Keep transactions short to minimize lock hold time
- The lock is released automatically when the transaction commits or rolls back

## Atomic Document Operations in RAG Pipelines

In RAG (Retrieval-Augmented Generation) systems, document ingestion involves multiple related database operations: inserting a document record, creating chunk records, and storing embedding vectors. These operations must be atomic to prevent partial ingestion.

Without transactions, a crash between inserting the document and its chunks leaves orphaned records. With CockroachDB's ACID transactions, either all operations complete or none do:

```sql
BEGIN;
INSERT INTO documents (title, source, tenant_id) VALUES (...) RETURNING id;
INSERT INTO chunks (document_id, chunk_index, content, embedding, tenant_id) VALUES (...);
INSERT INTO chunks (document_id, chunk_index, content, embedding, tenant_id) VALUES (...);
COMMIT;
```

If any INSERT fails or the application crashes before COMMIT, the entire transaction is rolled back. No ghost documents, no orphaned chunks, no dangling embeddings.

## Savepoints and Nested Operations

CockroachDB supports savepoints for partial rollback within a transaction. This is useful when processing a batch of documents where you want to skip failures without aborting the entire batch:

```sql
BEGIN;
SAVEPOINT before_doc_1;
-- Try to ingest document 1
INSERT INTO documents ...;
INSERT INTO chunks ...;
RELEASE SAVEPOINT before_doc_1;

SAVEPOINT before_doc_2;
-- Try to ingest document 2 (might fail)
INSERT INTO documents ...;
-- Error occurs here
ROLLBACK TO SAVEPOINT before_doc_2;

-- Document 1 is still committed when we COMMIT
COMMIT;
```

This pattern enables resilient batch processing while maintaining transactional guarantees for each individual document.
