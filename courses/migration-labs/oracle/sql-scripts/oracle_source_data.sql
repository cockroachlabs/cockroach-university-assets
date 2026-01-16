-- Oracle Source Data Population Script
-- Inserts initial 100 rows into orders and order_fills tables

ALTER SESSION SET CONTAINER = FREEPDB1;

-- Insert initial data into orders table (100 rows)
INSERT INTO APP_USER.orders (
    account_id, symbol, order_started,
    order_completed, total_shares_purchased, total_cost_of_order)
    SELECT
        1,
        'ORCL',
        SYSTIMESTAMP,
        NULL,
        100,
        238.98
    FROM all_objects WHERE ROWNUM <= 100;

-- Insert corresponding data into order_fills table
INSERT INTO APP_USER.order_fills (
    order_id, account_id, symbol, fill_time,
    shares_filled, total_cost_of_fill, price_at_time_of_fill)
    SELECT
        order_id,
        account_id,
        symbol,
        SYSTIMESTAMP,
        100,
        238.98,
        2.38
    FROM APP_USER.orders;

COMMIT;

-- Display row counts
SELECT 'Orders table' AS table_name, COUNT(*) AS row_count FROM APP_USER.orders
UNION ALL
SELECT 'Order fills table' AS table_name, COUNT(*) AS row_count FROM APP_USER.order_fills;

EXIT;
