#!/bin/bash
set -euxo pipefail

## Local Cluster Setup
echo "CockroachDB install check"

# Check if the command "cockroach" exists and both geos files are present
if command -v cockroach &> /dev/null && \
   [ -f "/usr/local/lib/cockroach/libgeos.so" ] && \
   [ -f "/usr/local/lib/cockroach/libgeos_c.so" ]; then
    echo "Good job, you have installed CockroachDB correctly"
else
    echo "CockroachDB is not installed"
    exit 1
fi

# Wipe out any traces prior attempts
if [ "$(pgrep -c cockroach)" -ge 1 ]; then 
    pkill -9 cockroach
fi
rm -rf ~/node*

# Start CockroachDB instances
# Without the nohup, file redirection and the background flags, instruqt hangs
nohup cockroach start --insecure --store=node1 --listen-addr=localhost:26257 \
   --http-addr=0.0.0.0:8081 --join=localhost:26257,localhost:26258,localhost:26259 \
   --locality=host=localhost,node=node1 --background > foo.out 2> foo.err < /dev/null
nohup cockroach start --insecure --store=node2 --listen-addr=localhost:26258 \
   --http-addr=0.0.0.0:8082 --join=localhost:26257,localhost:26258,localhost:26259 \
   --locality=host=localhost,node=node2 --background > foo.out 2> foo.err < /dev/null
nohup cockroach start --insecure --store=node3 --listen-addr=localhost:26259 \
   --http-addr=0.0.0.0:8083 --join=localhost:26257,localhost:26258,localhost:26259 \
   --locality=host=localhost,node=node3 --background > foo.out 2> foo.err < /dev/null

# Initialize the cluster 
cockroach init --insecure --host=localhost:26257

## setup port forwarding for the db console 1
# COCKROACHDB UI
nohup socat tcp-listen:3080,reuseaddr,fork tcp:localhost:8080 > /var/log/listen-3080.out 2> /var/log/listen-3080.err < /dev/null &

echo "Done cluster setup"