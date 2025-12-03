#!/bin/bash
set -e

echo "Setting up Lab 2 Environment (VM-based)..."


# Create database
sudo -u postgres psql -c "CREATE DATABASE ecommerce_db;"

# 5. Create Source Schema and Data
echo "Populating PostgreSQL source..."
sudo -u postgres psql -d ecommerce_db << 'EOF'
-- Create customers table (parent table 1)
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create products table (parent table 2)
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    category VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create addresses table (child of customers)
CREATE TABLE addresses (
    address_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    address_type VARCHAR(20) CHECK (address_type IN ('billing', 'shipping')),
    street_address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(100) NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table (child of customers)
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'pending',
    total_amount DECIMAL(10,2) NOT NULL,
    shipping_address_id INTEGER REFERENCES addresses(address_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create order_items table (child of orders and products - junction table)
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create reviews table (child of customers and products)
CREATE TABLE reviews (
    review_id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review_text TEXT,
    review_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(product_id, customer_id)
);

-- Insert Sample Data
-- Customers
INSERT INTO customers (email, first_name, last_name, phone)
SELECT 'customer' || i || '@example.com', 'First' || i, 'Last' || i, '+1-555-' || LPAD(i::TEXT, 7, '0')
FROM generate_series(1, 1000) AS i;

-- Products
INSERT INTO products (product_name, description, price, stock_quantity, category)
SELECT 'Product ' || i, 'Description for product ' || i, (random() * 500 + 10)::NUMERIC(10,2), (random() * 1000)::INTEGER,
CASE (random() * 5)::INTEGER WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Clothing' ELSE 'Books' END
FROM generate_series(1, 500) AS i;

-- Addresses
INSERT INTO addresses (customer_id, address_type, street_address, city, state, postal_code, country)
SELECT c.customer_id, CASE WHEN random() < 0.5 THEN 'billing' ELSE 'shipping' END,
(random() * 9999)::INTEGER || ' Main St', 'City' || (random() * 100)::INTEGER, 'State', '12345', 'USA'
FROM customers c CROSS JOIN generate_series(1, 2);

-- Orders
INSERT INTO orders (customer_id, order_date, status, total_amount, shipping_address_id)
SELECT c.customer_id, CURRENT_TIMESTAMP - (random() * INTERVAL '365 days'),
'delivered', (random() * 1000 + 50)::NUMERIC(10,2),
(SELECT address_id FROM addresses WHERE customer_id = c.customer_id LIMIT 1)
FROM customers c CROSS JOIN generate_series(1, 2);

-- Order Items
INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal)
SELECT o.order_id, p.product_id, (random() * 5 + 1)::INTEGER, p.price, p.price
FROM orders o CROSS JOIN LATERAL (SELECT product_id, price FROM products ORDER BY random() LIMIT 2) p;

-- Reviews
INSERT INTO reviews (product_id, customer_id, rating, review_text)
SELECT DISTINCT oi.product_id, o.customer_id, (random() * 5)::INTEGER + 1, 'Review text'
FROM order_items oi JOIN orders o ON oi.order_id = o.order_id
WHERE random() < 0.3 ON CONFLICT DO NOTHING;
EOF


# Create target database
cockroach sql --insecure -e "CREATE DATABASE ecommerce_db;"

# Create Mapping Tables (Pre-requisite for migration)
echo "Creating mapping tables..."
sudo -u postgres psql -d ecommerce_db << 'EOF'
CREATE SCHEMA IF NOT EXISTS migration_mapping;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE migration_mapping.customer_id_map (old_id INTEGER PRIMARY KEY, new_uuid UUID NOT NULL UNIQUE);
CREATE TABLE migration_mapping.product_id_map (old_id INTEGER PRIMARY KEY, new_uuid UUID NOT NULL UNIQUE);
CREATE TABLE migration_mapping.address_id_map (old_id INTEGER PRIMARY KEY, new_uuid UUID NOT NULL UNIQUE);
CREATE TABLE migration_mapping.order_id_map (old_id INTEGER PRIMARY KEY, new_uuid UUID NOT NULL UNIQUE);
CREATE TABLE migration_mapping.order_item_id_map (old_id INTEGER PRIMARY KEY, new_uuid UUID NOT NULL UNIQUE);
CREATE TABLE migration_mapping.review_id_map (old_id INTEGER PRIMARY KEY, new_uuid UUID NOT NULL UNIQUE);

-- Generate UUIDs
INSERT INTO migration_mapping.customer_id_map (old_id, new_uuid) SELECT customer_id, uuid_generate_v4() FROM customers;
INSERT INTO migration_mapping.product_id_map (old_id, new_uuid) SELECT product_id, uuid_generate_v4() FROM products;
INSERT INTO migration_mapping.address_id_map (old_id, new_uuid) SELECT address_id, uuid_generate_v4() FROM addresses;
INSERT INTO migration_mapping.order_id_map (old_id, new_uuid) SELECT order_id, uuid_generate_v4() FROM orders;
INSERT INTO migration_mapping.order_item_id_map (old_id, new_uuid) SELECT order_item_id, uuid_generate_v4() FROM order_items;
INSERT INTO migration_mapping.review_id_map (old_id, new_uuid) SELECT review_id, uuid_generate_v4() FROM reviews;
EOF

echo "Lab 2 Setup Complete."