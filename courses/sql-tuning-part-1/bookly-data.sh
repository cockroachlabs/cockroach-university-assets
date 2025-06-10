#!/bin/bash

FILES=(
  "bookly/data/20000_primary_keys_books.csv"
  "bookly/data/500000_book_id_prices.csv"
  "bookly/data/700000_title_authors_for_update.csv"
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"
DEST_DIR="/root/data"

# Create the destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

for SCRIPT_PATH in "${FILES[@]}"; do
  FILE_NAME=$(basename "$SCRIPT_PATH")
  FULL_URL="${BASE_URL}${SCRIPT_PATH}"
  curl -sSL "$FULL_URL" -o "${DEST_DIR}/${FILE_NAME}"
done