---
name: understand-and-avoid-index-join-operations
description: Understands index-join occurs when index scan finds matching keys but must look up full rows from primary index to get non-indexed columns. Shows in EXPLAIN as 'index join'. Expensive for large result sets - two lookups per row. Solution is create covering index with STORING clause. Use when user says "index join", "slow query", "two lookups", or EXPLAIN shows index join operations.
metadata:
  domain: SQL
  tags: sql, indexing, performance
  blooms_level: Analyze
  version: 1.0.0
---

# Understand and Avoid Index-Join Operations

Explains what index-join operations are, why they're expensive, and how to eliminate them using covering indexes with STORING clause.

## Why Index-Joins Are Expensive

**Index-join = Two lookups per row**:
1. **Scan secondary index** to find matching keys
2. **Look up full row** from primary index to get non-indexed columns

**Performance impact**: 2x slower than covering index (no second lookup needed).

**When it happens**: Query selects columns not in the index.

## How to Identify Index-Joins

### Method 1: EXPLAIN Shows "index join"

```sql
EXPLAIN SELECT id, name, email, created_at
FROM users
WHERE status = 'active';
```

**Bad output** (index join present):
```
• index join
│ table: users@users_pkey
│
└── • scan
      table: users@idx_users_status
      spans: [/'active' - /'active']
```

**Key indicator**: `index join` in EXPLAIN output.

### Method 2: DB Console Insights

**Steps**:
1. Navigate to DB Console → Insights
2. Look for "High Index-Join Count" recommendations
3. Click recommendation to see affected queries

## Understanding the Problem

**Example**:
```sql
-- Table structure
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email STRING,
    name STRING,
    status STRING,
    created_at TIMESTAMPTZ
);

-- Index on status only
CREATE INDEX idx_users_status ON users(status);

-- Query selects columns NOT in index
SELECT id, name, email, created_at
FROM users
WHERE status = 'active';
```

**What happens**:
1. Scan `idx_users_status` finds 1000 matching IDs
2. For EACH ID, look up full row from primary index (1000 lookups!)
3. Return name, email, created_at from those rows

**Performance**: 2x slower than if index contained all columns.

## Solution: Covering Index with STORING

**Create covering index** (includes all SELECT columns):
```sql
CREATE INDEX idx_users_status_covering
ON users(status)
STORING (name, email, created_at);
```

**Now the query**:
```sql
SELECT id, name, email, created_at
FROM users
WHERE status = 'active';
```

**EXPLAIN output** (NO index join):
```
• scan
  table: users@idx_users_status_covering
  spans: [/'active' - /'active']
```

**Performance**: Single lookup, 2x faster!

## When to Use Covering Indexes

**Use covering index when**:
- Query runs frequently (high QPS)
- Query selects same columns consistently
- Result set is large (index-join expensive for 1000+ rows)
- Performance critical

**Don't use covering index when**:
- Query runs rarely
- SELECT columns vary widely
- Index would be too large (STORING adds size)
- Write performance more important (covering indexes slower to update)

## Trade-offs

**Benefits**:
- ✅ Eliminate index-join (2x faster queries)
- ✅ Single lookup instead of two
- ✅ Lower CPU usage

**Costs**:
- ❌ Larger index size (STORING columns consume space)
- ❌ Slower writes (more columns to update in index)
- ❌ More disk space used

**Decision**: Use covering index when read performance > write performance priority.

## Common Patterns

### Pattern 1: Email Lookup with User Details

**Query**:
```sql
SELECT id, name, email, created_at
FROM users
WHERE email = 'alice@example.com';
```

**Without covering index** (index join):
```sql
CREATE INDEX idx_users_email ON users(email);
-- EXPLAIN shows: index join
```

**With covering index** (no index join):
```sql
CREATE INDEX idx_users_email_covering
ON users(email)
STORING (name, created_at);
-- EXPLAIN shows: scan (no index join)
```

### Pattern 2: Status Filter with Details

**Query**:
```sql
SELECT id, total, customer_id, created_at
FROM orders
WHERE status = 'pending';
```

**Covering index**:
```sql
CREATE INDEX idx_orders_status_covering
ON orders(status)
STORING (total, customer_id, created_at);
```

### Pattern 3: Multi-Column Filter with Details

**Query**:
```sql
SELECT id, name, price, stock
FROM products
WHERE category = 'electronics' AND status = 'active';
```

**Covering index**:
```sql
CREATE INDEX idx_products_cat_status_covering
ON products(category, status)
STORING (name, price, stock);
```

### Pattern 4: User Activity Query

**Query**:
```sql
SELECT user_id, event_type, data, created_at
FROM events
WHERE user_id = 'user-123'
ORDER BY created_at DESC
LIMIT 20;
```

**Covering index**:
```sql
CREATE INDEX idx_events_user_time_covering
ON events(user_id, created_at DESC)
STORING (event_type, data);
```

## Identifying Index-Join Queries

### Method 1: DB Console Statements Page

**Steps**:
1. Navigate to DB Console → SQL Activity → Statements
2. Click on a statement
3. Look at EXPLAIN plan
4. Search for "index join"

### Method 2: Query crdb_internal

**Find queries with index-joins**:
```sql
SELECT
    metadata->>'query' as query,
    statistics->>'cnt' as execution_count
FROM crdb_internal.statement_statistics
WHERE metadata->>'query' LIKE '%index join%'
ORDER BY (statistics->>'cnt')::INT DESC
LIMIT 10;
```

### Method 3: EXPLAIN for Specific Query

```sql
EXPLAIN (VERBOSE) SELECT ...;
-- Look for "index join" in output
```

## Fixing Index-Joins: Step-by-Step

**Step 1**: Identify slow query
```sql
-- Query takes 500ms
SELECT id, name, email FROM users WHERE status = 'active';
```

**Step 2**: Run EXPLAIN
```sql
EXPLAIN SELECT id, name, email FROM users WHERE status = 'active';
```

**Step 3**: Check for "index join"
```
• index join  ← Found it!
│ table: users@users_pkey
│
└── • scan
      table: users@idx_users_status
```

**Step 4**: Identify SELECT columns
- Query needs: id, name, email
- Index has: status
- Missing from index: name, email

**Step 5**: Create covering index
```sql
CREATE INDEX idx_users_status_covering
ON users(status)
STORING (name, email);
```

**Step 6**: Verify with EXPLAIN
```sql
EXPLAIN SELECT id, name, email FROM users WHERE status = 'active';
-- Should show: scan (NO index join)
```

**Step 7**: Measure improvement
- Before: 500ms (with index join)
- After: 250ms (no index join)
- Improvement: 2x faster

## Index-Join vs Full Table Scan

**Question**: Which is worse?

**Index-join** (1000 matching rows):
- Scan index: 1 lookup
- Fetch rows: 1000 lookups
- Total: 1001 lookups

**Full table scan** (10,000 total rows):
- Scan all rows: 10,000 rows read
- Total: 10,000 rows

**Answer**: Depends on selectivity!
- If < 10% of rows match: Index-join better
- If > 50% of rows match: Full scan better
- CockroachDB optimizer chooses automatically

## Verification Checklist

To eliminate index-joins:
- ✅ Run EXPLAIN on slow queries
- ✅ Look for "index join" in output
- ✅ Identify SELECT columns not in index
- ✅ Create covering index with STORING clause
- ✅ Verify EXPLAIN shows no index join
- ✅ Measure query performance improvement
- ✅ Monitor index size (covering indexes larger)

## Related Skills

- `create-covering-indexes-with-storing-clause` - How to create covering indexes
- `create-secondary-indexes-on-single-columns` - Basic indexing
- `create-composite-indexes-for-multi-column-queries` - Multi-column indexes
- `apply-index-best-practices` - Overall indexing strategy

## Documentation

- Index Selection: https://www.cockroachlabs.com/docs/stable/indexes.html#selection
- Covering Indexes: https://www.cockroachlabs.com/docs/stable/schema-design-indexes.html#storing-columns
- EXPLAIN: https://www.cockroachlabs.com/docs/stable/explain.html
- DB Console Insights: https://www.cockroachlabs.com/docs/stable/ui-insights-page.html
