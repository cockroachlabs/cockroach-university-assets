#!/bin/bash

# Drop bookly database if exists
echo "[INDEX CHALLENGE SETUP] drop any existing Bookly database and objects"
cockroach sql --insecure --execute="
DROP DATABASE IF EXISTS bookly CASCADE;"

# Create bookly database
echo "[INDEX CHALLENGE SETUP] create Bookly database"
cockroach sql --insecure --execute="
CREATE DATABASE bookly;"

# Create the Books table
echo "[INDEX CHALLENGE SETUP] create Book table"

cockroach sql -d bookly --insecure --execute="
CREATE TABLE Book (
    book_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title STRING NOT NULL,
    author STRING NOT NULL,
    price FLOAT NOT NULL,
    format STRING NOT NULL,
    publish_date DATE NOT NULL
);"

# Import data into the Books table
echo "[INDEX CHALLENGE SETUP] start import 10,000,000 books into Book table"

cockroach sql -d bookly --insecure --execute="
IMPORT INTO Book (book_id, title, author, price, format, publish_date)
CSV DATA ('https://cockroach-university-public.s3.amazonaws.com/10000000_books.csv')
WITH skip = '1';"

echo "[INDEX CHALLENGE SETUP] finished importing 10,000,000 books into Book table"

echo "[INDEX CHALLENGE SETUP] insert single book into Book table"
cockroach sql -d bookly --insecure --execute="
INSERT INTO bookly.Book (title, author, price, format, publish_date)
VALUES ('A Very Hungry Caterpillar' , 'Eric Carle', 17.99, 'hardback' , '1969-06-03' );"

# Import Books with same title table
echo "[INDEX CHALLENGE SETUP] start import 10,000 books with same title into Book table"

cockroach sql -d bookly --insecure --execute="
IMPORT INTO Book (book_id, title, author, price, format, publish_date)
CSV DATA ('https://cockroach-university-public.s3.amazonaws.com/10000_book_titles.csv')
WITH skip = '1';"

echo "[INDEX CHALLENGE SETUP] finished importing 10,000 books"

exit 0