#!/bin/bash
set -euxo pipefail

# Create database
sudo -u postgres psql -c "CREATE DATABASE production_db;"

# 5. Create Source Schema
echo "Populating PostgreSQL source..."
sudo -u postgres psql -d production_db << 'EOF'
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    status VARCHAR(20) DEFAULT 'active',
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(12,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    shipping_address TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE order_items (
    item_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);

CREATE TABLE inventory (
    inventory_id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    reserved_quantity INTEGER NOT NULL DEFAULT 0,
    last_restocked TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(product_id, warehouse_id)
);

CREATE TABLE audit_trail (
    audit_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    record_id INTEGER,
    user_id INTEGER,
    changes JSONB,
    ip_address INET,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create Publication
CREATE PUBLICATION molt_publication FOR ALL TABLES;
EOF

# 6. Insert Initial Dataset
sudo -u postgres psql -d production_db << 'EOF'
INSERT INTO users (username, email, full_name) SELECT 'user'||i, 'user'||i||'@test.com', 'User '||i FROM generate_series(1, 1000) i;
INSERT INTO orders (user_id, order_number, total_amount) SELECT (i%1000)+1, 'ORD-'||i, 100.00 FROM generate_series(1, 5000) i;
INSERT INTO inventory (product_id, warehouse_id, quantity) SELECT i, 1, 100 FROM generate_series(1, 1000) i;
EOF


# Create target database
cockroach sql --insecure -e "CREATE DATABASE production_db;"

# 8. Create Target Schema
cockroach sql --insecure -d production_db << 'EOF'
CREATE TABLE users (user_id INT PRIMARY KEY, username STRING, email STRING, full_name STRING, status STRING, last_login TIMESTAMP, created_at TIMESTAMP, updated_at TIMESTAMP);
CREATE TABLE orders (order_id INT PRIMARY KEY, user_id INT, order_number STRING, order_date TIMESTAMP, total_amount DECIMAL(12,2), status STRING, shipping_address STRING, created_at TIMESTAMP, updated_at TIMESTAMP);
CREATE TABLE order_items (item_id INT PRIMARY KEY, order_id INT, product_id INT, quantity INT, unit_price DECIMAL(10,2), subtotal DECIMAL(12,2), created_at TIMESTAMP);
CREATE TABLE inventory (inventory_id INT PRIMARY KEY, product_id INT, warehouse_id INT, quantity INT, reserved_quantity INT, last_restocked TIMESTAMP, updated_at TIMESTAMP);
CREATE TABLE audit_trail (audit_id INT PRIMARY KEY, table_name STRING, operation STRING, record_id INT, user_id INT, changes JSONB, ip_address INET, created_at TIMESTAMP);
EOF

echo "Lab 4 Setup Complete."