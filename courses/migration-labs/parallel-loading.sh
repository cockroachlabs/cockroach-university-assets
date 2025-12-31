#!/bin/bash
set -euxo pipefail

# Create database
sudo -u postgres psql -c "CREATE DATABASE warehouse_db;"

echo "=================================================="
echo "Lab 3: Parallel MOLT Jobs - Setup Script"
echo "=================================================="

echo "Creating PostgreSQL schema..."
sudo -u postgres psql -d warehouse_db << 'EOF'
-- Create Tables
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    price DECIMAL(10,2) NOT NULL,
    cost DECIMAL(10,2) NOT NULL,
    weight_kg DECIMAL(8,2),
    dimensions VARCHAR(50),
    supplier_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    company_name VARCHAR(255),
    phone VARCHAR(20),
    customer_type VARCHAR(20) DEFAULT 'retail',
    credit_limit DECIMAL(12,2),
    registration_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE suppliers (
    supplier_id SERIAL PRIMARY KEY,
    supplier_name VARCHAR(255) NOT NULL,
    contact_name VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(100),
    country VARCHAR(50),
    payment_terms VARCHAR(100),
    rating DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE warehouses (
    warehouse_id SERIAL PRIMARY KEY,
    warehouse_code VARCHAR(20) UNIQUE NOT NULL,
    warehouse_name VARCHAR(255) NOT NULL,
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    capacity_sqm DECIMAL(10,2),
    manager_name VARCHAR(255),
    phone VARCHAR(20),
    operating_hours VARCHAR(100)
);

CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    employee_code VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    department VARCHAR(100),
    position VARCHAR(100),
    hire_date DATE NOT NULL,
    salary DECIMAL(10,2),
    manager_id INTEGER,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE inventory_transactions (
    transaction_id BIGSERIAL PRIMARY KEY,
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    transaction_type VARCHAR(20) NOT NULL,
    product_sku VARCHAR(50) NOT NULL,
    warehouse_code VARCHAR(20) NOT NULL,
    quantity INTEGER NOT NULL,
    unit_cost DECIMAL(10,2),
    total_value DECIMAL(12,2),
    reference_number VARCHAR(50),
    notes TEXT,
    created_by VARCHAR(100)
);

CREATE TABLE sales_transactions (
    sale_id BIGSERIAL PRIMARY KEY,
    sale_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    customer_email VARCHAR(255) NOT NULL,
    product_sku VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    discount_percent DECIMAL(5,2) DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL,
    payment_method VARCHAR(50),
    status VARCHAR(20) DEFAULT 'completed',
    invoice_number VARCHAR(50)
);

CREATE TABLE audit_logs (
    log_id BIGSERIAL PRIMARY KEY,
    log_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_id VARCHAR(100),
    action VARCHAR(100) NOT NULL,
    table_name VARCHAR(100),
    record_id VARCHAR(50),
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT
);

-- Create indexes for better query performance
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_type ON customers(customer_type);
CREATE INDEX idx_inventory_date ON inventory_transactions(transaction_date);
CREATE INDEX idx_inventory_product ON inventory_transactions(product_sku);
CREATE INDEX idx_sales_date ON sales_transactions(sale_date);
CREATE INDEX idx_sales_customer ON sales_transactions(customer_email);
CREATE INDEX idx_audit_timestamp ON audit_logs(log_timestamp);
CREATE INDEX idx_audit_table ON audit_logs(table_name);

EOF

echo "PostgreSQL schema created successfully."
echo ""

echo "Generating PostgreSQL dataset..."
echo "This may take 2-3 minutes for large tables..."
echo ""

# Insert small tables first (fast)
echo "Inserting warehouses (50 rows)..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO warehouses (warehouse_code, warehouse_name, address, city, state, country, postal_code, capacity_sqm, manager_name, phone, operating_hours)
SELECT
    'WH-' || LPAD(i::TEXT, 4, '0'),
    'Warehouse ' || i,
    i || ' Industrial Parkway',
    'City' || (i % 20 + 1),
    'State' || (i % 10 + 1),
    CASE (i % 5) WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'Mexico' WHEN 3 THEN 'UK' ELSE 'Germany' END,
    LPAD((10000 + i)::TEXT, 5, '0'),
    (random() * 50000 + 10000)::NUMERIC(10,2),
    'Manager' || i,
    '+1-555-' || LPAD((1000 + i)::TEXT, 4, '0'),
    '8AM-6PM'
FROM generate_series(1, 50) AS i;
EOF

echo "Inserting suppliers (1,000 rows)..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO suppliers (supplier_name, contact_name, email, phone, address, city, country, payment_terms, rating)
SELECT
    'Supplier Corp ' || i,
    'Contact' || i,
    'supplier' || i || '@example.com',
    '+1-555-' || LPAD((2000 + i)::TEXT, 4, '0'),
    i || ' Business Park',
    'City' || (i % 50 + 1),
    CASE (i % 5) WHEN 0 THEN 'USA' WHEN 1 THEN 'China' WHEN 2 THEN 'Japan' WHEN 3 THEN 'Germany' ELSE 'India' END,
    'Net ' || (i % 3 + 1) || '0',
    (random() * 2 + 3)::NUMERIC(3,2)
FROM generate_series(1, 1000) AS i;
EOF

echo "Inserting employees (5,000 rows)..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO employees (employee_code, first_name, last_name, email, phone, department, position, hire_date, salary, status)
SELECT
    'EMP-' || LPAD(i::TEXT, 6, '0'),
    'FirstName' || i,
    'LastName' || i,
    'employee' || i || '@company.com',
    '+1-555-' || LPAD((3000 + i)::TEXT, 4, '0'),
    CASE (i % 10)
        WHEN 0 THEN 'Sales'
        WHEN 1 THEN 'Operations'
        WHEN 2 THEN 'IT'
        WHEN 3 THEN 'HR'
        WHEN 4 THEN 'Finance'
        WHEN 5 THEN 'Marketing'
        WHEN 6 THEN 'Logistics'
        WHEN 7 THEN 'Customer Service'
        WHEN 8 THEN 'Procurement'
        ELSE 'Management'
    END,
    CASE (i % 5)
        WHEN 0 THEN 'Manager'
        WHEN 1 THEN 'Supervisor'
        WHEN 2 THEN 'Senior'
        WHEN 3 THEN 'Associate'
        ELSE 'Junior'
    END,
    CURRENT_DATE - (random() * 3650)::INTEGER,
    (random() * 100000 + 30000)::NUMERIC(10,2),
    CASE WHEN random() < 0.95 THEN 'active' ELSE 'inactive' END
FROM generate_series(1, 5000) AS i;
EOF

echo "Inserting products (100,000 rows) - this will take ~1 minute..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO products (sku, product_name, description, category, price, cost, weight_kg, dimensions, supplier_id)
SELECT
    'SKU-' || LPAD(i::TEXT, 8, '0'),
    'Product ' || i,
    'Description for product ' || i,
    'Category' || ((i % 20) + 1),
    (random() * 1000 + 10)::NUMERIC(10,2),
    (random() * 500 + 5)::NUMERIC(10,2),
    (random() * 50 + 0.5)::NUMERIC(8,2),
    ROUND(random() * 100) || 'x' || ROUND(random() * 100) || 'x' || ROUND(random() * 100),
    (random() * 999 + 1)::INTEGER
FROM generate_series(1, 100000) AS i;
EOF

echo "Inserting customers (50,000 rows) - this will take ~30 seconds..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO customers (email, first_name, last_name, company_name, phone, customer_type, credit_limit, status)
SELECT
    'customer' || i || '@example.com',
    'FirstName' || i,
    'LastName' || i,
    CASE WHEN random() < 0.3 THEN 'Company ' || i ELSE NULL END,
    '+1-555-' || LPAD((i % 9999)::TEXT, 4, '0'),
    CASE (random() * 3)::INTEGER
        WHEN 0 THEN 'retail'
        WHEN 1 THEN 'wholesale'
        ELSE 'enterprise'
    END,
    (random() * 100000 + 1000)::NUMERIC(12,2),
    CASE WHEN random() < 0.9 THEN 'active' ELSE 'inactive' END
FROM generate_series(1, 50000) AS i;
EOF

echo "Inserting inventory_transactions (500,000 rows) - this will take ~1 minute..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO inventory_transactions (transaction_date, transaction_type, product_sku, warehouse_code, quantity, unit_cost, total_value, reference_number, notes, created_by)
SELECT
    CURRENT_TIMESTAMP - (random() * interval '365 days'),
    CASE (random() * 3)::INTEGER
        WHEN 0 THEN 'IN'
        WHEN 1 THEN 'OUT'
        ELSE 'ADJUSTMENT'
    END,
    'SKU-' || LPAD(((random() * 99999)::INTEGER + 1)::TEXT, 8, '0'),
    'WH-' || LPAD(((random() * 49)::INTEGER + 1)::TEXT, 4, '0'),
    (random() * 100 + 1)::INTEGER,
    (random() * 100 + 5)::NUMERIC(10,2),
    (random() * 10000 + 500)::NUMERIC(12,2),
    'REF-' || LPAD(i::TEXT, 10, '0'),
    'Automated transaction',
    'system'
FROM generate_series(1, 500000) AS i;
EOF

echo "Inserting sales_transactions (200,000 rows) - this will take ~45 seconds..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO sales_transactions (sale_date, customer_email, product_sku, quantity, unit_price, discount_percent, tax_amount, total_amount, payment_method, status, invoice_number)
SELECT
    CURRENT_TIMESTAMP - (random() * interval '730 days'),
    'customer' || ((random() * 49999)::INTEGER + 1) || '@example.com',
    'SKU-' || LPAD(((random() * 99999)::INTEGER + 1)::TEXT, 8, '0'),
    (random() * 10 + 1)::INTEGER,
    (random() * 500 + 10)::NUMERIC(10,2),
    (random() * 20)::NUMERIC(5,2),
    (random() * 50)::NUMERIC(10,2),
    (random() * 5000 + 50)::NUMERIC(12,2),
    CASE (random() * 4)::INTEGER
        WHEN 0 THEN 'Credit Card'
        WHEN 1 THEN 'PayPal'
        WHEN 2 THEN 'Bank Transfer'
        ELSE 'Cash'
    END,
    CASE (random() * 5)::INTEGER
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'processing'
        ELSE 'completed'
    END,
    'INV-' || LPAD(i::TEXT, 10, '0')
FROM generate_series(1, 200000) AS i;
EOF

echo "Inserting audit_logs (1,000,000 rows) - this will take ~2 minutes..."
sudo -u postgres psql -d warehouse_db << 'EOF'
INSERT INTO audit_logs (log_timestamp, user_id, action, table_name, record_id, ip_address, user_agent)
SELECT
    CURRENT_TIMESTAMP - (random() * interval '365 days'),
    'user' || ((random() * 4999)::INTEGER + 1),
    CASE (random() * 4)::INTEGER
        WHEN 0 THEN 'INSERT'
        WHEN 1 THEN 'UPDATE'
        WHEN 2 THEN 'DELETE'
        ELSE 'SELECT'
    END,
    CASE (random() * 8)::INTEGER
        WHEN 0 THEN 'products'
        WHEN 1 THEN 'customers'
        WHEN 2 THEN 'orders'
        WHEN 3 THEN 'inventory'
        WHEN 4 THEN 'sales'
        WHEN 5 THEN 'employees'
        WHEN 6 THEN 'suppliers'
        ELSE 'warehouses'
    END,
    i::TEXT,
    ('192.168.' || (random() * 255)::INTEGER || '.' || (random() * 255)::INTEGER)::INET,
    'Mozilla/5.0 (compatible; Bot/1.0)'
FROM generate_series(1, 1000000) AS i;
EOF

echo ""
echo "PostgreSQL dataset generation completed."
echo ""

# Display final counts
echo "Verifying PostgreSQL data counts..."
sudo -u postgres psql -d warehouse_db << 'EOF'
SELECT 'warehouses' AS table_name, COUNT(*) AS row_count,
       pg_size_pretty(pg_total_relation_size('warehouses')) AS size FROM warehouses
UNION ALL
SELECT 'suppliers', COUNT(*), pg_size_pretty(pg_total_relation_size('suppliers')) FROM suppliers
UNION ALL
SELECT 'employees', COUNT(*), pg_size_pretty(pg_total_relation_size('employees')) FROM employees
UNION ALL
SELECT 'products', COUNT(*), pg_size_pretty(pg_total_relation_size('products')) FROM products
UNION ALL
SELECT 'customers', COUNT(*), pg_size_pretty(pg_total_relation_size('customers')) FROM customers
UNION ALL
SELECT 'inventory_transactions', COUNT(*),
       pg_size_pretty(pg_total_relation_size('inventory_transactions')) FROM inventory_transactions
UNION ALL
SELECT 'sales_transactions', COUNT(*),
       pg_size_pretty(pg_total_relation_size('sales_transactions')) FROM sales_transactions
UNION ALL
SELECT 'audit_logs', COUNT(*), pg_size_pretty(pg_total_relation_size('audit_logs')) FROM audit_logs
ORDER BY row_count;

-- Total database size
SELECT pg_size_pretty(pg_database_size('warehouse_db')) AS total_database_size;
EOF

echo ""
echo "Setting up CockroachDB target schema..."

# Create target database
cockroach sql --insecure -e "CREATE DATABASE warehouse_db;"

# Create Target Schema (simplified, mirroring source)
cockroach sql --insecure -d warehouse_db << 'EOF'
CREATE TABLE products (
    product_id BIGINT PRIMARY KEY,
    sku STRING UNIQUE NOT NULL,
    product_name STRING NOT NULL,
    description STRING,
    category STRING,
    price DECIMAL(10,2) NOT NULL,
    cost DECIMAL(10,2) NOT NULL,
    weight_kg DECIMAL(8,2),
    dimensions STRING,
    supplier_id INT,
    created_at TIMESTAMP DEFAULT current_timestamp(),
    updated_at TIMESTAMP DEFAULT current_timestamp()
);

CREATE TABLE customers (
    customer_id BIGINT PRIMARY KEY,
    email STRING UNIQUE NOT NULL,
    first_name STRING NOT NULL,
    last_name STRING NOT NULL,
    company_name STRING,
    phone STRING,
    customer_type STRING DEFAULT 'retail',
    credit_limit DECIMAL(12,2),
    registration_date TIMESTAMP DEFAULT current_timestamp(),
    last_login TIMESTAMP,
    status STRING DEFAULT 'active'
);

CREATE TABLE suppliers (
    supplier_id BIGINT PRIMARY KEY,
    supplier_name STRING NOT NULL,
    contact_name STRING,
    email STRING,
    phone STRING,
    address STRING,
    city STRING,
    country STRING,
    payment_terms STRING,
    rating DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT current_timestamp()
);

CREATE TABLE warehouses (
    warehouse_id BIGINT PRIMARY KEY,
    warehouse_code STRING UNIQUE NOT NULL,
    warehouse_name STRING NOT NULL,
    address STRING,
    city STRING,
    state STRING,
    country STRING,
    postal_code STRING,
    capacity_sqm DECIMAL(10,2),
    manager_name STRING,
    phone STRING,
    operating_hours STRING
);

CREATE TABLE employees (
    employee_id BIGINT PRIMARY KEY,
    employee_code STRING UNIQUE NOT NULL,
    first_name STRING NOT NULL,
    last_name STRING NOT NULL,
    email STRING UNIQUE NOT NULL,
    phone STRING,
    department STRING,
    position STRING,
    hire_date DATE NOT NULL,
    salary DECIMAL(10,2),
    manager_id INT,
    status STRING DEFAULT 'active'
);

CREATE TABLE inventory_transactions (
    transaction_id BIGINT PRIMARY KEY,
    transaction_date TIMESTAMP DEFAULT current_timestamp(),
    transaction_type STRING NOT NULL,
    product_sku STRING NOT NULL,
    warehouse_code STRING NOT NULL,
    quantity INT NOT NULL,
    unit_cost DECIMAL(10,2),
    total_value DECIMAL(12,2),
    reference_number STRING,
    notes STRING,
    created_by STRING
);

CREATE TABLE sales_transactions (
    sale_id BIGINT PRIMARY KEY,
    sale_date TIMESTAMP DEFAULT current_timestamp(),
    customer_email STRING NOT NULL,
    product_sku STRING NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    discount_percent DECIMAL(5,2) DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL,
    payment_method STRING,
    status STRING DEFAULT 'completed',
    invoice_number STRING
);

CREATE TABLE audit_logs (
    log_id BIGINT PRIMARY KEY,
    log_timestamp TIMESTAMP DEFAULT current_timestamp(),
    user_id STRING,
    action STRING NOT NULL,
    table_name STRING,
    record_id STRING,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent STRING
);

-- Create indexes matching source database
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_type ON customers(customer_type);
CREATE INDEX idx_inventory_date ON inventory_transactions(transaction_date);
CREATE INDEX idx_inventory_product ON inventory_transactions(product_sku);
CREATE INDEX idx_sales_date ON sales_transactions(sale_date);
CREATE INDEX idx_sales_customer ON sales_transactions(customer_email);
CREATE INDEX idx_audit_timestamp ON audit_logs(log_timestamp);
CREATE INDEX idx_audit_table ON audit_logs(table_name);

SHOW TABLES;
EOF

echo "CockroachDB target schema setup completed."
echo ""
echo "=================================================="
echo "Lab 3 Setup Complete!"
echo "=================================================="
echo ""
echo "Summary:"
echo "  - PostgreSQL source database: warehouse_db (8 tables populated)"
echo "  - CockroachDB target database: warehouse_db (8 tables ready)"
echo "  - Total rows to migrate: 1,856,050"
echo ""
echo "You can now proceed with the parallel migration exercise."
