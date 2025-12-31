#!/bin/bash
set -euxo pipefail

# Create database
sudo -u postgres psql -c "CREATE DATABASE warehouse_db;"

echo "Generating PostgreSQL dataset..."
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

-- Insert Data
INSERT INTO warehouses SELECT generate_series(1,50), 'WH-'||generate_series, 'Warehouse '||generate_series, 'Address', 'City', 'State', 'Country', '12345', 1000, 'Manager', '555-1234', '9-5';
INSERT INTO suppliers SELECT generate_series(1,1000), 'Supplier '||generate_series, 'Contact', 'email@test.com', '555-5555', 'Address', 'City', 'Country', 'Net30', 4.5;
INSERT INTO employees SELECT generate_series(1,5000), 'EMP-'||generate_series, 'First', 'Last', 'emp'||generate_series||'@test.com', '555-0000', 'Dept', 'Pos', '2020-01-01', 50000, 1, 'active';
INSERT INTO products SELECT generate_series(1,100000), 'SKU-'||generate_series, 'Product '||generate_series, 'Desc', 'Cat', 10.00, 5.00, 1.0, '10x10', 1;
INSERT INTO customers SELECT generate_series(1,50000), 'cust'||generate_series||'@test.com', 'First', 'Last', 'Company', '555-1111', 'retail', 1000, '2020-01-01', '2023-01-01', 'active';
INSERT INTO inventory_transactions SELECT generate_series(1,200000), NOW(), 'IN', 'SKU-1', 'WH-1', 10, 5.00, 50.00, 'REF', 'Note', 'User';
INSERT INTO sales_transactions SELECT generate_series(1,100000), NOW(), 'cust1@test.com', 'SKU-1', 1, 10.00, 0, 0, 10.00, 'Card', 'completed', 'INV-1';
INSERT INTO audit_logs SELECT generate_series(1,500000), NOW(), 'user1', 'INSERT', 'products', '1', '{}', '{}', '127.0.0.1', 'Agent';
EOF

echo "PostgreSQL dataset generation completed."

echo "Setting up CockroachDB target schema..."

# Create target database
cockroach sql --insecure -e "CREATE DATABASE warehouse_db;"

# 7. Create Target Schema (simplified, mirroring source)
cockroach sql --insecure -d warehouse_db << 'EOF'
CREATE TABLE products (product_id INT PRIMARY KEY, sku STRING, product_name STRING, description STRING, category STRING, price DECIMAL(10,2), cost DECIMAL(10,2), weight_kg DECIMAL(8,2), dimensions STRING, supplier_id INT, created_at TIMESTAMP, updated_at TIMESTAMP);
CREATE TABLE customers (customer_id INT PRIMARY KEY, email STRING, first_name STRING, last_name STRING, company_name STRING, phone STRING, customer_type STRING, credit_limit DECIMAL(12,2), registration_date TIMESTAMP, last_login TIMESTAMP, status STRING);
CREATE TABLE suppliers (supplier_id INT PRIMARY KEY, supplier_name STRING, contact_name STRING, email STRING, phone STRING, address STRING, city STRING, country STRING, payment_terms STRING, rating DECIMAL(3,2), created_at TIMESTAMP);
CREATE TABLE warehouses (warehouse_id INT PRIMARY KEY, warehouse_code STRING, warehouse_name STRING, address STRING, city STRING, state STRING, country STRING, postal_code STRING, capacity_sqm DECIMAL(10,2), manager_name STRING, phone STRING, operating_hours STRING);
CREATE TABLE employees (employee_id INT PRIMARY KEY, employee_code STRING, first_name STRING, last_name STRING, email STRING, phone STRING, department STRING, position STRING, hire_date DATE, salary DECIMAL(10,2), manager_id INT, status STRING);
CREATE TABLE inventory_transactions (transaction_id INT PRIMARY KEY, transaction_date TIMESTAMP, transaction_type STRING, product_sku STRING, warehouse_code STRING, quantity INT, unit_cost DECIMAL(10,2), total_value DECIMAL(12,2), reference_number STRING, notes STRING, created_by STRING);
CREATE TABLE sales_transactions (sale_id INT PRIMARY KEY, sale_date TIMESTAMP, customer_email STRING, product_sku STRING, quantity INT, unit_price DECIMAL(10,2), discount_percent DECIMAL(5,2), tax_amount DECIMAL(10,2), total_amount DECIMAL(12,2), payment_method STRING, status STRING, invoice_number STRING);
CREATE TABLE audit_logs (log_id INT PRIMARY KEY, log_timestamp TIMESTAMP, user_id STRING, action STRING, table_name STRING, record_id STRING, old_values JSONB, new_values JSONB, ip_address INET, user_agent STRING);
EOF

echo "CockroachDB target schema setup completed."

echo "Lab 3 Setup Complete."