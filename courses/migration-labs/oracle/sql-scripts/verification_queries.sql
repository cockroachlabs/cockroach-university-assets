-- Verification Queries
-- Run these queries to verify data migration and consistency

-- ==================================
-- ORACLE QUERIES (Run in Oracle)
-- ==================================

-- Count rows in orders table
SELECT 'Oracle orders count' AS description, COUNT(*) AS row_count FROM APP_USER.orders;

-- Count rows in order_fills table
SELECT 'Oracle order_fills count' AS description, COUNT(*) AS row_count FROM APP_USER.order_fills;

-- Get aggregate statistics
SELECT
    'Oracle aggregates' AS description,
    COUNT(*) AS total_rows,
    SUM(total_cost_of_order) AS total_sales,
    AVG(total_cost_of_order) AS avg_sale,
    MIN(order_started) AS earliest_order,
    MAX(order_started) AS latest_order
FROM APP_USER.orders;

-- Check for NULL values
SELECT
    'Oracle NULL check' AS description,
    COUNT(CASE WHEN order_id IS NULL THEN 1 END) AS null_order_id,
    COUNT(CASE WHEN account_id IS NULL THEN 1 END) AS null_account_id,
    COUNT(CASE WHEN symbol IS NULL THEN 1 END) AS null_symbol
FROM APP_USER.orders;

-- ==================================
-- COCKROACHDB QUERIES (Run in CRDB)
-- ==================================

-- Count rows in orders table
SELECT 'CockroachDB orders count' AS description, COUNT(*) AS row_count FROM public.orders;

-- Count rows in order_fills table
SELECT 'CockroachDB order_fills count' AS description, COUNT(*) AS row_count FROM public.order_fills;

-- Get aggregate statistics
SELECT
    'CockroachDB aggregates' AS description,
    COUNT(*) AS total_rows,
    SUM(total_cost_of_order) AS total_sales,
    AVG(total_cost_of_order) AS avg_sale,
    MIN(order_started) AS earliest_order,
    MAX(order_started) AS latest_order
FROM public.orders;

-- Check for NULL values
SELECT
    'CockroachDB NULL check' AS description,
    COUNT(CASE WHEN order_id IS NULL THEN 1 END) AS null_order_id,
    COUNT(CASE WHEN account_id IS NULL THEN 1 END) AS null_account_id,
    COUNT(CASE WHEN symbol IS NULL THEN 1 END) AS null_symbol
FROM public.orders;

-- Check for duplicate primary keys
SELECT
    'Duplicate check' AS description,
    order_id,
    COUNT(*) AS count
FROM public.orders
GROUP BY order_id
HAVING COUNT(*) > 1;
