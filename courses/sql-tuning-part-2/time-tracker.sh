#!/bin/bash

# This set line ensures that all failures will cause the script to error and exit
set -euxo pipefail

echo "[TIME TRACKER] Starting time tracking..."

echo "Cloning the query-tuning repository..."
git clone https://github.com/cockroachlabs/cockroach-university-ilt-developer-fundamentals-exercises.git

# Navigate into the repository root folder
mv cockroach-university-ilt-developer-fundamentals-exercises/day2 /root/tracker

# Make sure the /root/tracker directory exists (with If-ELSE)
if [ ! -d /root/tracker ]; then
  echo "[TIME TRACKER] /root/tracker directory does not exist."
  exit 1
fi
# Install npm dependencies
cd /root/tracker
echo "Installing npm dependencies..."
npm install

# Start the Node.js server in the background on port 3000
echo "Starting Node.js server..."
nohup node ./server.js > server.log 2> server.err < /dev/null &

echo "[TIME TRACKER] Node.js server started successfully."