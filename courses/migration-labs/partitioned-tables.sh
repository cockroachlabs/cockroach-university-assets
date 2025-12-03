#!/bin/bash
set -euxo pipefail

# Create database
sudo -u postgres psql -c "CREATE DATABASE sales_db;"

# 5. Create Source Schema and Data
echo "Populating PostgreSQL source..."
sudo -u postgres psql -d sales_db << 'EOF'
-- Create parent partitioned table
CREATE TABLE sales_transactions (
    transaction_id BIGSERIAL,
    transaction_date DATE NOT NULL,
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    region VARCHAR(50) NOT NULL,
    legacy_system_id VARCHAR(100), -- Column to be excluded
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (transaction_id, transaction_date)
) PARTITION BY RANGE (transaction_date);

-- Create partitions for different quarters
CREATE TABLE sales_transactions_q1_2023 PARTITION OF sales_transactions
    FOR VALUES FROM ('2023-01-01') TO ('2023-04-01');
CREATE TABLE sales_transactions_q2_2023 PARTITION OF sales_transactions
    FOR VALUES FROM ('2023-04-01') TO ('2023-07-01');
CREATE TABLE sales_transactions_q3_2023 PARTITION OF sales_transactions
    FOR VALUES FROM ('2023-07-01') TO ('2023-10-01');
CREATE TABLE sales_transactions_q4_2023 PARTITION OF sales_transactions
    FOR VALUES FROM ('2023-10-01') TO ('2024-01-01');

-- Create indexes on partitioned table
CREATE INDEX idx_customer_id ON sales_transactions(customer_id);
CREATE INDEX idx_transaction_date ON sales_transactions(transaction_date);

-- Insert sample data across partitions
INSERT INTO sales_transactions (transaction_date, customer_id, product_id, amount, region, legacy_system_id)
SELECT
    DATE '2023-01-01' + (random() * 364)::INTEGER,
    (random() * 1000)::INTEGER + 1,
    (random() * 100)::INTEGER + 1,
    (random() * 1000)::NUMERIC(10,2) + 10,
    CASE (random() * 4)::INTEGER
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        ELSE 'West'
    END,
    'LEGACY-' || generate_series(1, 10000)
FROM generate_series(1, 10000);
EOF

cockroach sql --insecure -e "CREATE DATABASE sales_db;"

echo "Lab 1 Setup Complete."