#!/bin/bash

echo "[Insert speed challenge] in setup"

cockroach sql --insecure --execute="
DROP DATABASE IF EXISTS bookly CASCADE;
CREATE DATABASE bookly;

CREATE TABLE bookly.unspecified_pk (
    book_id UUID DEFAULT gen_random_uuid(),
    title STRING NOT NULL,
    author STRING NOT NULL,
    price FLOAT NOT NULL,
    format STRING NOT NULL,
    publish_date DATE NOT NULL
);"

# Import data into the Books table
cockroach sql --insecure --execute="
IMPORT INTO bookly.unspecified_pk (book_id, title, author, price, format, publish_date)
CSV DATA ('https://cockroach-university-public.s3.amazonaws.com/1000000_books.csv')
WITH skip = '1';

ALTER TABLE bookly.unspecified_pk CONFIGURE ZONE USING range_min_bytes = 320000, range_max_bytes = 67108864;
"

echo "[Insert speed challenge] finished importing data into unspecified_pk"

cockroach sql --insecure --execute="
CREATE TABLE bookly.uuid_pk (
    book_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title STRING NOT NULL,
    author STRING NOT NULL,
    price FLOAT NOT NULL,
    format STRING NOT NULL,
    publish_date DATE NOT NULL
);"

# Import data into the Books table
cockroach sql --insecure --execute="
IMPORT INTO bookly.uuid_pk (book_id, title, author, price, format, publish_date)
CSV DATA ('https://cockroach-university-public.s3.amazonaws.com/1000000_books.csv')
WITH skip = '1';

ALTER TABLE bookly.uuid_pk CONFIGURE ZONE USING range_min_bytes = 320000, range_max_bytes = 67108864;
"

echo "[Insert speed challenge] finished set up"

exit 0