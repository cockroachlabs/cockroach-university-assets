#!/bin/bash

FILES=(
  "bookly/jmeter/bookly_book_main_test_plan_tuned_1.jmx"
  "bookly/jmeter/bookly_book_main_test_plan.jmx"
  "bookly/jmeter/bookly_book_warm_up_plan.jmx"
)

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/"
DEST_DIR="/root/workload"

# Create the destination directory if it doesn't exist
mkdir -p "$DEST_DIR"
# Download the JMeter test plans

echo "[JMETER] Downloading JMeter test plans..."

for SCRIPT_PATH in "${FILES[@]}"; do
  FILE_NAME=$(basename "$SCRIPT_PATH")
  FULL_URL="${BASE_URL}${SCRIPT_PATH}"
  curl -sSL "$FULL_URL" -o "${DEST_DIR}/${FILE_NAME}"
done

echo "[JMETER] JMeter test plans downloaded successfully."
