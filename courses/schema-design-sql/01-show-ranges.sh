#!/bin/bash

echo "[Show Ranges Challenge] in setup"

# Load bookdb workload

cockroach sql --insecure --execute="
CREATE DATABASE bookly;
USE bookly;

CREATE TABLE book (
    book_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title STRING NOT NULL,
    author STRING NOT NULL,
    price FLOAT NOT NULL,
    format STRING NOT NULL,
    publish_date DATE NOT NULL
);"

# Import data into the Books table
cockroach sql --insecure --execute="
IMPORT INTO bookly.book (book_id, title, author, price, format, publish_date)
CSV DATA ('https://cockroach-university-public.s3.amazonaws.com/1000000_books.csv')
WITH skip = '1';
ALTER TABLE bookly.book CONFIGURE ZONE USING range_min_bytes = 0, range_max_bytes = 67108864;
CREATE INDEX ON bookly.book (publish_date);"

exit 0