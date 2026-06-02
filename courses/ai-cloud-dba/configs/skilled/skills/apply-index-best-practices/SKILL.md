---
name: apply-index-best-practices
description: Comprehensive guide to index best practices in CockroachDB. Covers when to create indexes, naming conventions, composite vs single-column indexes, covering indexes with STORING clause, avoiding redundant indexes, monitoring index usage, and dropping unused indexes. Use when user says "index best practices", "index guidelines", "index strategy", "how to index", or needs comprehensive indexing advice.
metadata:
  domain: SQL
  tags: sql, indexing, best-practices, performance
  blooms_level: Apply
  version: 1.0.0
  tested_against: v26.1.0
  status: complete
---

# Apply Index Best Practices

Comprehensive guide to creating and managing indexes effectively in CockroachDB. Covers when to create indexes, naming conventions, types of indexes, and ongoing maintenance.

## What This Skill Teaches

You will learn:
- When (and when not) to create indexes
- Index naming conventions
- Choosing between single-column and composite indexes
- Using covering indexes with STORING clause
- Identifying and avoiding redundant indexes
- Monitoring index usage
- Dropping unused indexes safely

## When to Create Indexes

### Rule 1: Index Columns Used in WHERE Clauses

**Create index when**:
- Query filters on specific columns frequently
- Selectivity is good (< 20% of rows returned)

```sql
-- Frequent query
SELECT * FROM orders WHERE status = 'pending';

-- Create index
CREATE INDEX idx_orders_status ON orders(status);
```

**Don't index when**:
- Column has very few distinct values (low cardinality)
- Query returns > 50% of rows (full scan faster)

```sql
-- Bad: status has only 2 values ('active', 'inactive')
-- 50% of rows are 'active' - full scan better than index
CREATE INDEX idx_users_status ON users(status);  -- Don't create this
```

### Rule 2: Index Columns Used in ORDER BY

**Create index when**:
- Query sorts frequently on specific columns
- Combined with WHERE clause for same query

```sql
-- Frequent query with sort
SELECT * FROM events
WHERE user_id = 'user-123'
ORDER BY created_at DESC
LIMIT 10;

-- Create composite index: WHERE column first, ORDER BY second
CREATE INDEX idx_events_user_time ON events(user_id, created_at DESC);
```

### Rule 3: Index JOIN Columns

**Create index on foreign key columns**:
```sql
-- Tables with relationship
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    customer_id UUID,
    total DECIMAL
);

CREATE TABLE customers (
    id UUID PRIMARY KEY,
    name STRING
);

-- Frequent join query
SELECT o.*, c.name
FROM orders o
JOIN customers c ON o.customer_id = c.id;

-- Create index on join column
CREATE INDEX idx_orders_customer ON orders(customer_id);
```

### Rule 4: Don't Index Low-Cardinality Columns Alone

**Bad** - boolean or enum with few values:
```sql
-- Boolean column: only 2 possible values
CREATE INDEX idx_users_active ON users(is_active);  -- Don't create

-- Status with 3 values: 'pending', 'approved', 'rejected'
CREATE INDEX idx_requests_status ON requests(status);  -- Questionable
```

**Better** - use composite index or don't index:
```sql
-- If must query by boolean, combine with another column
CREATE INDEX idx_users_active_created ON users(is_active, created_at);

-- Or use partial index
CREATE INDEX idx_users_active ON users(id) WHERE is_active = true;
```

## Index Naming Conventions

**Standard format**: `idx_<table>_<columns>_[suffix]`

### Single-Column Index
```sql
-- Format: idx_<table>_<column>
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_products_sku ON products(sku);
```

### Composite Index
```sql
-- Format: idx_<table>_<col1>_<col2>_<col3>
CREATE INDEX idx_orders_customer_status ON orders(customer_id, status);
CREATE INDEX idx_events_user_type_time ON events(user_id, event_type, created_at);
```

### Covering Index
```sql
-- Format: idx_<table>_<cols>_covering or idx_<table>_<cols>_inc
CREATE INDEX idx_users_email_covering ON users(email) STORING (name, created_at);
CREATE INDEX idx_orders_customer_inc ON orders(customer_id) STORING (total, status);
```

### Partial Index
```sql
-- Format: idx_<table>_<cols>_partial or idx_<table>_<cols>_<condition>
CREATE INDEX idx_orders_pending ON orders(created_at) WHERE status = 'pending';
CREATE INDEX idx_users_active ON users(email) WHERE is_active = true;
```

### Descending Index
```sql
-- Format: idx_<table>_<cols>_desc
CREATE INDEX idx_events_time_desc ON events(created_at DESC);
CREATE INDEX idx_orders_user_date_desc ON orders(user_id, created_at DESC);
```

**Key principles**:
- Use lowercase with underscores
- Start with `idx_`
- Include table name
- Include indexed columns (abbreviated if needed)
- Add suffix for special types (covering, partial, desc)
- Keep it under 63 characters (PostgreSQL limit)

## Composite vs Single-Column Indexes

### Use Single-Column Index When

**Pattern**: Query filters on one column only.

```sql
-- Query always filters on email alone
SELECT * FROM users WHERE email = 'alice@example.com';

-- Single-column index sufficient
CREATE INDEX idx_users_email ON users(email);
```

### Use Composite Index When

**Pattern 1**: Query filters on multiple columns.

```sql
-- Query filters on category AND status
SELECT * FROM products
WHERE category = 'electronics' AND status = 'active';

-- Composite index needed
CREATE INDEX idx_products_cat_status ON products(category, status);
```

**Pattern 2**: Query filters on one column and sorts on another.

```sql
-- Filter by user, sort by date
SELECT * FROM orders
WHERE customer_id = 'cust-123'
ORDER BY created_at DESC
LIMIT 10;

-- Composite index: filter column first, sort column second
CREATE INDEX idx_orders_customer_date ON orders(customer_id, created_at DESC);
```

**Pattern 3**: Query has WHERE + ORDER BY on different columns.

```sql
-- Filter and sort on different columns
SELECT * FROM events
WHERE user_id = 'user-123'
ORDER BY event_time DESC;

-- Composite index covers both
CREATE INDEX idx_events_user_time ON events(user_id, event_time DESC);
```

### Column Ordering in Composite Indexes

**Rule**: Most selective column first, then by query pattern.

**Example 1**: Filter then sort.
```sql
-- WHERE user_id = ? ORDER BY created_at
-- user_id first (filter), created_at second (sort)
CREATE INDEX idx_orders_user_date ON orders(user_id, created_at DESC);
```

**Example 2**: Multiple filters.
```sql
-- WHERE customer_id = ? AND status = ?
-- Most selective first: customer_id (UUID, unique-ish) before status (few values)
CREATE INDEX idx_orders_customer_status ON orders(customer_id, status);
```

**Example 3**: Range queries.
```sql
-- WHERE category = ? AND price BETWEEN ? AND ?
-- Equality first (category), range second (price)
CREATE INDEX idx_products_cat_price ON products(category, price);
```

## Covering Indexes with STORING Clause

**Purpose**: Avoid index-join by storing additional columns in index.

### When to Use STORING

**Use when**:
- Query always selects same columns
- Query executed frequently (high QPS)
- EXPLAIN shows "index join"
- Stored columns are small

```sql
-- Query pattern
SELECT id, name, email FROM users WHERE status = 'active';

-- Without STORING (has index join)
CREATE INDEX idx_users_status ON users(status);
-- EXPLAIN shows: index join (slow)

-- With STORING (no index join)
CREATE INDEX idx_users_status_covering
ON users(status)
STORING (name, email);
-- EXPLAIN shows: scan only (fast)
```

### What to Store

**Store columns that are**:
- Frequently selected together
- Small (strings, numbers, timestamps - not large TEXT/JSONB)
- Relatively stable (don't change often)

```sql
-- Good: Store small, frequently-accessed columns
CREATE INDEX idx_orders_customer_details
ON orders(customer_id)
STORING (total, status, created_at);

-- Bad: Don't store large columns
CREATE INDEX idx_products_sku
ON products(sku)
STORING (description, specifications, reviews);  -- Too large!
```

### STORING Trade-offs

**Benefits**:
- Eliminate index joins (2-5x faster queries)
- Consistent performance
- Lower CPU usage

**Costs**:
- Larger index size (+50-200% depending on stored columns)
- Slower writes (more data to update)
- More disk space

## Avoiding Redundant Indexes

**Redundant index**: Index that provides no benefit because another index covers the same queries.

### Pattern 1: Subset Indexes

**Redundant** - second index is prefix of first:
```sql
-- First index
CREATE INDEX idx_orders_customer_status_date
ON orders(customer_id, status, created_at);

-- Redundant: customer_id already covered by first index
CREATE INDEX idx_orders_customer ON orders(customer_id);  -- Redundant!

-- Redundant: (customer_id, status) covered by first index
CREATE INDEX idx_orders_customer_status ON orders(customer_id, status);  -- Redundant!
```

**Rule**: Index on (A, B, C) makes indexes on (A) and (A, B) redundant.

**Exception**: Sometimes smaller index is faster for specific queries.
```sql
-- If query ONLY filters on customer_id (no status/date)
-- and table is huge, dedicated index on customer_id may be worthwhile
-- But usually composite index is sufficient
```

### Pattern 2: Different Column Order

**Not redundant** - different column order = different use case:
```sql
-- For: WHERE customer_id = ? ORDER BY created_at
CREATE INDEX idx_orders_customer_date ON orders(customer_id, created_at);

-- For: WHERE created_at > ? ORDER BY customer_id
CREATE INDEX idx_orders_date_customer ON orders(created_at, customer_id);
-- NOT redundant - serves different query pattern
```

### Pattern 3: Overlapping Covering Indexes

**Redundant** - same indexed columns, different STORING:
```sql
CREATE INDEX idx1 ON users(email) STORING (name);
CREATE INDEX idx2 ON users(email) STORING (name, created_at);  -- Possibly redundant

-- Better: Single covering index with all needed columns
CREATE INDEX idx_users_email_details
ON users(email)
STORING (name, created_at);
```

### Finding Redundant Indexes

**Check index definitions**:
```sql
-- View all indexes on table
SHOW INDEXES FROM orders;

-- Look for indexes that share common prefix
-- Example output:
-- idx_orders_customer          (customer_id)
-- idx_orders_customer_status   (customer_id, status)
-- idx_orders_customer_date     (customer_id, created_at)
-- First index is redundant (covered by second and third)
```

## Monitoring Index Usage

### Method 1: Index Usage Statistics

```sql
-- View index usage statistics (v22.1+)
SELECT
    index_name,
    total_reads,
    last_read
FROM crdb_internal.index_usage_statistics
WHERE table_name = 'orders'
ORDER BY total_reads DESC;
```

**Indicators**:
- `total_reads = 0` - Unused index, candidate for removal
- `last_read IS NULL` - Never used
- Low total_reads - Rarely used, evaluate if needed

### Method 2: DB Console Index Recommendations

**Steps**:
1. Navigate to DB Console → Insights → Schema Insights
2. Look for "Unused Index" recommendations
3. Review suggested indexes to drop

### Method 3: EXPLAIN Analysis

**Test if index is used**:
```sql
-- Check if query uses specific index
EXPLAIN SELECT * FROM orders WHERE customer_id = 'cust-123';

-- Look for index name in output:
-- • scan
--   table: orders@idx_orders_customer  ← Uses this index
```

### Method 4: Statement Statistics

```sql
-- Find queries that don't use indexes (full scans)
SELECT
    metadata->>'query' as query,
    statistics->>'cnt' as execution_count,
    statistics->>'mean_exec_time' as avg_time
FROM crdb_internal.statement_statistics
WHERE metadata->>'query' LIKE '%orders%'
    AND statistics->>'scan_type' = 'full'
ORDER BY (statistics->>'cnt')::INT DESC;
```

## Dropping Unused Indexes

### Before Dropping: Verify Index is Unused

**Check 1**: Zero reads in last 30 days.
```sql
SELECT
    index_name,
    total_reads,
    last_read
FROM crdb_internal.index_usage_statistics
WHERE table_name = 'orders'
    AND (total_reads = 0 OR last_read < now() - INTERVAL '30 days');
```

**Check 2**: No queries in statement stats use the index.
```sql
-- Run EXPLAIN on common queries to verify they don't use index
EXPLAIN SELECT * FROM orders WHERE status = 'pending';
-- If output doesn't mention idx_orders_status, it's not used
```

**Check 3**: Review index definition.
```sql
SHOW CREATE TABLE orders;
-- Verify index is not enforcing uniqueness or constraint
```

### Dropping an Index

```sql
-- Drop index
DROP INDEX idx_orders_status;

-- Drop multiple indexes
DROP INDEX idx_orders_old1, idx_orders_old2;

-- Drop with CASCADE (if referenced)
DROP INDEX idx_orders_status CASCADE;
```

**Important**: Index drops are non-blocking in CockroachDB (v22.1+).

### Monitoring After Drop

```sql
-- Monitor query performance after drop
SELECT
    metadata->>'query' as query,
    statistics->>'mean_exec_time' as avg_time,
    statistics->>'cnt' as executions
FROM crdb_internal.statement_statistics
WHERE metadata->>'query' LIKE '%orders%'
ORDER BY (statistics->>'mean_exec_time')::FLOAT DESC
LIMIT 10;
```

**Watch for**: Sudden increase in query time after index drop.

## Best Practices Checklist

### Index Creation
- ✅ Create indexes on columns in WHERE clauses (high selectivity)
- ✅ Create indexes on columns in ORDER BY clauses
- ✅ Create indexes on foreign key columns (JOIN columns)
- ✅ Use composite indexes for multi-column filters
- ✅ Use covering indexes (STORING) for frequently-selected columns
- ✅ Follow naming conventions: `idx_<table>_<cols>`
- ❌ Don't index low-cardinality columns alone
- ❌ Don't create redundant indexes

### Index Maintenance
- ✅ Monitor index usage regularly (monthly)
- ✅ Drop unused indexes (zero reads for 30+ days)
- ✅ Review index size vs table size
- ✅ Check for redundant indexes after schema changes
- ✅ Use DB Console insights for recommendations
- ❌ Don't keep "just in case" indexes
- ❌ Don't create indexes without measuring query performance

### Index Limits
- ✅ Aim for < 10 indexes per table (general guideline)
- ✅ Larger tables can have more indexes (if needed)
- ❌ Avoid > 20 indexes per table (write performance suffers)
- ❌ Avoid very large covering indexes (> 1GB per index)

## Common Scenarios

### Scenario 1: E-Commerce Orders Table

```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    customer_id UUID,
    status STRING,
    total DECIMAL,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- Query patterns
-- 1. List customer orders by date
SELECT * FROM orders WHERE customer_id = ? ORDER BY created_at DESC;

-- 2. Find pending orders
SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at;

-- 3. Admin dashboard: recent orders
SELECT id, customer_id, total, status FROM orders ORDER BY created_at DESC LIMIT 50;

-- Recommended indexes
CREATE INDEX idx_orders_customer_date
ON orders(customer_id, created_at DESC);

CREATE INDEX idx_orders_status_date
ON orders(status, created_at)
STORING (customer_id, total);  -- Covering for query 2

CREATE INDEX idx_orders_date_desc
ON orders(created_at DESC)
STORING (customer_id, total, status);  -- Covering for query 3
```

### Scenario 2: User Lookup Table

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email STRING UNIQUE,
    username STRING,
    name STRING,
    status STRING,
    created_at TIMESTAMPTZ
);

-- Query patterns
-- 1. Login by email
SELECT id, name, status FROM users WHERE email = ?;

-- 2. Search by username
SELECT id, name FROM users WHERE username = ?;

-- 3. List active users
SELECT id, email, name FROM users WHERE status = 'active' ORDER BY created_at DESC;

-- Recommended indexes
-- Email already has unique index (from UNIQUE constraint)

CREATE INDEX idx_users_username
ON users(username)
STORING (name);  -- Covering for query 2

CREATE INDEX idx_users_status_created
ON users(status, created_at DESC)
STORING (email, name);  -- Covering for query 3
```

### Scenario 3: Event Log Table

```sql
CREATE TABLE events (
    id UUID PRIMARY KEY,
    user_id UUID,
    event_type STRING,
    data JSONB,
    created_at TIMESTAMPTZ
);

-- Query patterns
-- 1. User activity (last 100 events)
SELECT * FROM events WHERE user_id = ? ORDER BY created_at DESC LIMIT 100;

-- 2. Event type analysis
SELECT event_type, count(*) FROM events WHERE created_at > ? GROUP BY event_type;

-- Recommended indexes
CREATE INDEX idx_events_user_time
ON events(user_id, created_at DESC);  -- For query 1

CREATE INDEX idx_events_time_type
ON events(created_at DESC, event_type);  -- For query 2

-- Don't create: idx_events_user (redundant - covered by idx_events_user_time)
-- Don't create: idx_events_type (low cardinality, rarely filtered alone)
```

## Common Mistakes to Avoid

### Mistake 1: Over-Indexing

**Problem**: Creating index for every column.
```sql
-- Too many indexes!
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_name ON users(name);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created ON users(created_at);
-- 5 indexes on a simple table = write performance penalty
```

**Solution**: Only index columns actually used in WHERE/ORDER BY.

### Mistake 2: Wrong Column Order

**Problem**: Composite index with wrong column order.
```sql
-- Query: WHERE customer_id = ? ORDER BY created_at
-- Wrong order: sort column first
CREATE INDEX idx_orders_date_customer ON orders(created_at, customer_id);  -- Wrong!

-- Right order: filter column first
CREATE INDEX idx_orders_customer_date ON orders(customer_id, created_at DESC);  -- Right!
```

### Mistake 3: Creating Subset Indexes

**Problem**: Creating smaller indexes when composite exists.
```sql
-- Already have this
CREATE INDEX idx_orders_customer_status_date
ON orders(customer_id, status, created_at);

-- Don't create these (redundant)
CREATE INDEX idx_orders_customer ON orders(customer_id);  -- Redundant!
CREATE INDEX idx_orders_customer_status ON orders(customer_id, status);  -- Redundant!
```

### Mistake 4: Not Using Covering Indexes

**Problem**: Query has index-join when it could use covering index.
```sql
-- Query always selects same columns
SELECT id, name FROM users WHERE email = ?;

-- Non-covering index (has index-join)
CREATE INDEX idx_users_email ON users(email);

-- Should use covering index instead
CREATE INDEX idx_users_email_name ON users(email) STORING (name);
```

### Mistake 5: Keeping Unused Indexes

**Problem**: Indexes created months ago, never used.
```sql
-- Created 6 months ago, zero reads
CREATE INDEX idx_orders_old_status ON orders(old_status_column);

-- Should drop
DROP INDEX idx_orders_old_status;
```

## Related Skills

- `create-secondary-indexes-on-single-columns` - Creating basic indexes
- `create-composite-indexes-for-multi-column-queries` - Multi-column indexes
- `create-covering-indexes-with-storing-clause` - Covering indexes
- `create-partial-indexes-with-where-clauses` - Partial indexes
- `optimize-composite-index-column-ordering` - Column ordering strategies
- `avoid-over-indexing-tables` - Managing index count
- `monitor-index-usage-statistics` - Tracking index usage
- `understand-mvcc-impact-on-indexes` - MVCC effects on indexes

## Documentation

- Index Best Practices: https://www.cockroachlabs.com/docs/v26.1/schema-design-indexes
- CREATE INDEX: https://www.cockroachlabs.com/docs/v26.1/create-index
- DROP INDEX: https://www.cockroachlabs.com/docs/v26.1/drop-index
- Index Usage Statistics: https://www.cockroachlabs.com/docs/v26.1/ui-databases-page#index-stats
- Performance Tuning: https://www.cockroachlabs.com/docs/v26.1/performance-best-practices-overview
