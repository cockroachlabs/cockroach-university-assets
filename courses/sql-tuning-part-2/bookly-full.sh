#!/bin/bash
#
# This script runs when the platform setup the challenge.
#
# The platform determines if the script was successful using the exit code of this
# script. If the exit code is not 0, the script fails. 
#

# Drop the bookly database if it exists
cockroach sql --insecure --execute="
DROP DATABASE IF EXISTS bookly CASCADE;"

# Create the bookly database
cockroach sql --insecure --execute="
CREATE DATABASE bookly;"
echo "OPT-SQL-EXERCISE: Successfully created the bookly database."

# Create the book table
cockroach sql --insecure --execute="
CREATE TABLE bookly.book (
    book_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title STRING NOT NULL,
    author STRING NOT NULL,
    price FLOAT NOT NULL,
    format STRING NOT NULL,
    publish_date DATE NOT NULL
);"
echo "OPT-SQL-EXERCISE: Successfully created the books table"

# Import 10 million rows of data into the book table
echo "OPT-SQL-EXERCISE:  Starting to import 10,000,000 rows of data into the book table."
cockroach sql --insecure --execute="
IMPORT INTO bookly.book (book_id, title, author, price, format, publish_date)
CSV DATA ('https://cockroach-university-public.s3.amazonaws.com/10000000_books.csv')
WITH skip = '1';"
echo "OPT-SQL-EXERCISE: Finish the import of 10,000,000 rows of data into the book table."

# Verify that 100,000 rows were imported
row_count=$(cockroach sql --insecure --execute="SELECT count(*) FROM bookly.book;" --format=csv | tail -n 1)

if [ "$row_count" -eq 10000000 ]; then
    echo "OPT-SQL-EXERCISE: Successfully imported 10,000,000 rows."
    echo "OPT-SQL-EXERCISE: Using exit 0 in if row_count 10000000 to finish setup."
else
    echo "Failed to import 10,000,000 rows. Row count is $row_count."
    exit 1
fi

cockroach sql --insecure --execute="ALTER TABLE bookly.book CONFIGURE ZONE USING gc.ttlseconds = 30;"

# Create the tunings table
cockroach sql --insecure --execute="
CREATE TABLE bookly.tunings (
  id SERIAL PRIMARY KEY,
  query STRING,
  execution_time FLOAT,
  intervention STRING
);"
echo "OPT-SQL-EXERCISE: Successfully created the tunings table."


echo "OPT-SQL-EXERCISE: Finishing ilt-lab-vm setup."
exit 0