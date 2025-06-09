#!/bin/bash

echo "[Hash Sharding] in Setup"

# Delete if bookly exists
cockroach sql --insecure --execute="DROP DATABASE IF EXISTS bookly CASCADE;"

# Load bookdb workload

cockroach sql --insecure --execute="CREATE DATABASE bookly;"

cockroach sql --insecure --execute="
 CREATE TABLE bookly.book (
     book_id UUID DEFAULT gen_random_uuid(),
     title STRING NOT NULL,
     author STRING NOT NULL,
     price FLOAT NOT NULL,
     format STRING NOT NULL,
     publish_date DATE NOT NULL,
     PRIMARY KEY (publish_date, title, author)
  );"

cockroach sql --insecure --execute="
  IMPORT INTO bookly.book (book_id, title, author, price, format, publish_date)
  CSV DATA ('https://cockroach-university-public.s3.amazonaws.com/1000000_books.csv')
  WITH skip = '1';"


## setup port forwarding for the db console 2 because we will kill node 1
nohup socat tcp-listen:36299,reuseaddr,fork tcp:localhost:8080 > foo.out 2> foo.err < /dev/null &

exit 0