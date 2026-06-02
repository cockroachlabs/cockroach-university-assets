---
name: configure-haproxy-health-checks-and-backend-servers
description: Configure HAProxy health checks, backend servers, load balancing algorithms, and connection limits for CockroachDB
metadata:
  domain: Cluster Management
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Configure HAProxy Health Checks and Backend Servers

**Domain**: Cluster Management
**Bloom's Level**: Apply

## What This Skill Teaches

This skill teaches you how to configure HAProxy health checks and backend server pools for CockroachDB clusters. You'll learn to use CockroachDB health endpoints (`/health?ready=1`), configure health check intervals and timeouts, select appropriate load balancing algorithms (roundrobin, leastconn), set connection limits, and manage backend server states.

## Prerequisites

- HAProxy installed and basic deployment complete
- Understanding of CockroachDB health endpoints
- Access to edit `/etc/haproxy/haproxy.cfg`
- Knowledge of TCP and HTTP load balancing concepts

## Core Concepts

### CockroachDB Health Endpoints

**Available Endpoints**:
1. **`/health`**: Node is live (process running)
2. **`/health?ready=1`**: Node is ready (can serve SQL queries)
3. **`/health/ready`**: Alternative ready endpoint (v21.1+)

**Recommended**: Use `/health?ready=1` to ensure nodes can serve traffic.

**Endpoint Returns**:
- HTTP 200 if healthy/ready
- HTTP 503 if unhealthy/not ready
- HTTP 500 if node is draining

### Health Check Parameters

```haproxy
server node1 10.0.1.10:26257 check port 8080 inter 5s fall 3 rise 2 maxconn 1000
```

- **check**: Enable health checks
- **port 8080**: Check HTTP port (not SQL port 26257)
- **inter 5s**: Check interval (default 2s)
- **fall 3**: Mark DOWN after 3 failed checks
- **rise 2**: Mark UP after 2 successful checks
- **maxconn 1000**: Maximum connections per server

## Health Check Configuration

### Basic Configuration

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance roundrobin
    option httpchk GET /health?ready=1
    http-check expect status 200

    server node1 10.0.1.10:26257 check port 8080
    server node2 10.0.1.11:26257 check port 8080
    server node3 10.0.1.12:26257 check port 8080
```

### Advanced Configuration with Tuning

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance leastconn
    option httpchk GET /health?ready=1
    http-check expect status 200
    timeout server 30m
    timeout connect 10s
    maxconn 3000

    server node1 10.0.1.10:26257 check port 8080 inter 5s fall 3 rise 2 maxconn 1000 weight 100
    server node2 10.0.1.11:26257 check port 8080 inter 5s fall 3 rise 2 maxconn 1000 weight 100
    server node3 10.0.1.12:26257 check port 8080 inter 5s fall 3 rise 2 maxconn 1000 weight 100
```

### Advanced Parameters

```haproxy
# Detailed health check tuning
server node1 10.0.1.10:26257 check port 8080 inter 5s fall 3 rise 2 fastinter 2s downinter 10s
```

- **fastinter 2s**: Fast interval when transitioning state
- **downinter 10s**: Check interval when server is DOWN

### Custom Headers

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    option httpchk GET /health?ready=1 HTTP/1.1
    http-check send hdr Host cockroachdb-cluster
    http-check expect status 200
```

## Load Balancing Algorithms

### Algorithm Selection

| Algorithm | Use Case | Best For |
|-----------|----------|----------|
| `roundrobin` | General purpose | Short-lived connections, uniform load |
| `leastconn` | Long-lived connections | Connection pooling, variable query duration |
| `source` | Session affinity | Same client to same server (rare for CockroachDB) |
| `first` | Active/standby | First available server, failover to next |

### Roundrobin (Even Distribution)

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance roundrobin
    server node1 10.0.1.10:26257 check port 8080
    server node2 10.0.1.11:26257 check port 8080
    server node3 10.0.1.12:26257 check port 8080
```

### Leastconn (Recommended for CockroachDB)

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance leastconn  # Routes to server with fewest connections
    server node1 10.0.1.10:26257 check port 8080
    server node2 10.0.1.11:26257 check port 8080
    server node3 10.0.1.12:26257 check port 8080
```

### Source Affinity

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance source
    hash-type consistent
    server node1 10.0.1.10:26257 check port 8080
```

## Backend Server Configuration

### Server Weights (Different Capacities)

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance roundrobin
    server node1 10.0.1.10:26257 check port 8080 weight 100  # Full capacity
    server node2 10.0.1.11:26257 check port 8080 weight 100  # Full capacity
    server node3 10.0.1.12:26257 check port 8080 weight 50   # Half capacity
```

### Backup Servers

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance roundrobin
    server node1 10.0.1.10:26257 check port 8080
    server node2 10.0.1.11:26257 check port 8080
    server node3 10.0.1.12:26257 check port 8080
    server node4 10.0.1.13:26257 check port 8080 backup  # Only used if all primary DOWN
```

### Initial Server States

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance roundrobin
    server node1 10.0.1.10:26257 check port 8080           # Normal (enabled)
    server node2 10.0.1.11:26257 check port 8080 disabled  # Maintenance mode
    server node3 10.0.1.12:26257 check port 8080 drain     # Existing connections only
```

## Connection Limits and Timeouts

### Global Limits

```haproxy
global
    maxconn 4096              # Maximum total connections

defaults
    maxconn 2000              # Default per frontend/backend
    timeout connect 10s       # Backend connection timeout
    timeout client 30m        # Client inactivity timeout
    timeout server 30m        # Server inactivity timeout
    timeout queue 30s         # Queue timeout
```

### Per-Backend Limits

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance leastconn
    maxconn 3000              # Total for this backend

    server node1 10.0.1.10:26257 check port 8080 maxconn 1000
    server node2 10.0.1.11:26257 check port 8080 maxconn 1000
    server node3 10.0.1.12:26257 check port 8080 maxconn 1000
```

### Queue Configuration

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance leastconn
    timeout queue 30s  # Max time in queue before rejection

    server node1 10.0.1.10:26257 check port 8080 maxconn 1000 maxqueue 100
```

## Multi-Region Configuration

### Region-Aware Load Balancing

```haproxy
backend cockroachdb_sql_nodes
    mode tcp
    balance leastconn
    option httpchk GET /health?ready=1
    http-check expect status 200

    # Preferred local region
    server us-east-1 10.0.1.10:26257 check port 8080 weight 100
    server us-east-2 10.0.1.11:26257 check port 8080 weight 100

    # Cross-region backup
    server us-west-1 10.0.2.10:26257 check port 8080 weight 50 backup
    server us-west-2 10.0.2.11:26257 check port 8080 weight 50 backup
```

## Complete Configuration Example

```haproxy
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    retries 3
    timeout connect 10s
    timeout client  30m
    timeout server  30m
    timeout queue   30s

frontend cockroachdb_sql
    bind *:26257
    mode tcp
    maxconn 3000
    default_backend cockroachdb_sql_nodes

backend cockroachdb_sql_nodes
    mode tcp
    balance leastconn
    option httpchk GET /health?ready=1
    http-check expect status 200
    maxconn 3000

    server node1 10.0.1.10:26257 check port 8080 inter 5s fall 3 rise 2 maxconn 1000
    server node2 10.0.1.11:26257 check port 8080 inter 5s fall 3 rise 2 maxconn 1000
    server node3 10.0.1.12:26257 check port 8080 inter 5s fall 3 rise 2 maxconn 1000

frontend cockroachdb_admin
    bind *:8080
    mode http
    default_backend cockroachdb_admin_nodes

backend cockroachdb_admin_nodes
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server node1 10.0.1.10:8080 check inter 10s
    server node2 10.0.1.11:8080 check inter 10s
    server node3 10.0.1.12:8080 check inter 10s

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
```

## Verify Configuration

### View Backend Status

```bash
# Check statistics page
http://<haproxy-ip>:8404/stats

# Status colors:
# Green = UP, Red = DOWN, Orange = Draining/Transitioning
```

### Test Health Endpoint Manually

```bash
# Test from HAProxy server
curl -v http://10.0.1.10:8080/health?ready=1

# Expected: HTTP/1.1 200 OK with {"status": "ok"}
```

### Monitor Health Check Events

```bash
# View logs
sudo journalctl -u haproxy -f

# Look for: "Server cockroachdb_sql_nodes/node1 is UP, reason: Layer7 check passed"
```

## Common Mistakes

### 1. Health Check on Wrong Port

```haproxy
# WRONG: Checks SQL port
server node1 10.0.1.10:26257 check

# CORRECT: Checks HTTP port
server node1 10.0.1.10:26257 check port 8080
```

### 2. Using Wrong Health Endpoint

```haproxy
# WRONG: Only checks liveness
option httpchk GET /health

# CORRECT: Checks readiness
option httpchk GET /health?ready=1
```

### 3. Too Aggressive Intervals

```haproxy
# Too aggressive
server node1 10.0.1.10:26257 check port 8080 inter 1s

# Better
server node1 10.0.1.10:26257 check port 8080 inter 5s
```

### 4. Insufficient maxconn

```haproxy
# Calculate: (expected concurrent connections) / (number of backends)
# Example: 3000 total / 3 nodes = 1000 per node
server node1 10.0.1.10:26257 check port 8080 maxconn 1000
```

## Best Practices

1. **Use `/health?ready=1`**: Ensures nodes are ready to serve queries
2. **Set 5-10s Check Intervals**: Balance responsiveness and overhead
3. **Configure fall 3, rise 2**: Prevents flapping between UP/DOWN
4. **Use leastconn**: Better for long-lived database connections
5. **Calculate maxconn**: Based on expected concurrent connections
6. **Configure Weights**: Adjust for different instance sizes
7. **Use Backup Servers**: Cross-region failover configuration
8. **Monitor Stats Page**: Regularly check backend health
9. **Test Failover**: Verify HAProxy routes around failed nodes
10. **Document Servers**: Comment backend configs with location/purpose

## Troubleshooting

### All Backends DOWN

```bash
# Test health endpoint
curl -v http://10.0.1.10:8080/health?ready=1

# Check connectivity
telnet 10.0.1.10 8080

# Verify config
sudo grep -A 5 "option httpchk" /etc/haproxy/haproxy.cfg
```

### Backends Flapping

```bash
# Increase stability thresholds
server node1 10.0.1.10:26257 check port 8080 rise 5 inter 10s
```

### Connection Limits Reached

```bash
# View stats page for current connections
http://<haproxy-ip>:8404/stats

# Increase if needed
server node1 10.0.1.10:26257 check port 8080 maxconn 2000
```

## Related Skills

- `deploy-haproxy-load-balancer-for-cluster`: Initial HAProxy deployment
- `manage-haproxy-service-lifecycle`: Start, stop, reload HAProxy
- `remove-nodes-from-load-balancer-configuration`: Remove nodes from pool
- `restore-nodes-to-load-balancer-after-maintenance`: Add nodes back
- `monitor-cluster-health-metrics`: Monitor CockroachDB health endpoints

## References

- [CockroachDB Documentation: Health Endpoints](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html#health-endpoints)
- [HAProxy Documentation: Health Checks](https://www.haproxy.com/documentation/haproxy-configuration-tutorials/health-checks/)
- [HAProxy Documentation: Load Balancing](https://www.haproxy.com/documentation/haproxy-configuration-tutorials/load-balancing/)
- [HAProxy Configuration Manual](https://www.haproxy.org/download/2.8/doc/configuration.txt)
