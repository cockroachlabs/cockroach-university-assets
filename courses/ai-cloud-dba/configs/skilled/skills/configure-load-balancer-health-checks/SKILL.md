---
name: configure-load-balancer-health-checks
description: Configure load balancer health checks using CockroachDB /health?ready=1 endpoint to route traffic only to healthy, ready nodes and avoid routing to failed or draining nodes.
domain: Resilience and Failure Handling
bloom_level: Apply
tags: resilience, load-balancing, health-checks, haproxy, high-availability, infrastructure
version: 1.0.0
cockroachdb_version: v26.1.0+
---

# Configure Load Balancer Health Checks

Route traffic to healthy nodes only: configure load balancers to use CockroachDB's `/health?ready=1` endpoint on port 8080, distinguish between live and ready states, prevent traffic routing to draining nodes, configure health check intervals and thresholds, and implement failover strategies.

## Instructions

This skill teaches you to configure load balancer health checks that ensure application traffic only reaches nodes capable of serving requests.

### Step 1: Understand CockroachDB Health Endpoints

**Health check endpoints:**

| Endpoint | Port | Purpose | Returns 200 When |
|----------|------|---------|------------------|
| `/health` | 8080 | Basic liveness | Process is running |
| `/health?ready=1` | 8080 | Readiness check | Node ready to serve traffic |

**Key difference:**

- **`/health`**: Returns 200 if CockroachDB process is alive (even if draining or not ready)
- **`/health?ready=1`**: Returns 200 only if node is ready to accept SQL connections

**Test endpoints manually:**

```bash
# Check if node is alive
curl http://localhost:8080/health
# Output: {"status":"ok"}

# Check if node is ready
curl http://localhost:8080/health?ready=1
# Output: {"status":"ok"}  (if ready)
# Output: HTTP 503 (if draining or not ready)

# Check specific node
curl http://node1.example.com:8080/health?ready=1
curl http://node2.example.com:8080/health?ready=1
curl http://node3.example.com:8080/health?ready=1
```

**Health endpoint behavior during drain:**

```sql
-- Start draining a node
SHOW node_status;

-- On draining node:
curl http://localhost:8080/health
# Returns: 200 OK (node still alive)

curl http://localhost:8080/health?ready=1
# Returns: 503 Service Unavailable (not ready for traffic)
```

### Step 2: Configure HAProxy Health Checks

**Generate HAProxy configuration:**

```bash
# Auto-generate HAProxy config for cluster
cockroach gen haproxy \
  --host=localhost \
  --port=26257 \
  --out=haproxy.cfg

# Review generated configuration
cat haproxy.cfg
```

**HAProxy configuration for CockroachDB:**

```haproxy
global
  maxconn 4096
  log stdout local0

defaults
  log global
  mode tcp
  option tcplog
  timeout connect 10s
  timeout client 1m
  timeout server 1m

listen psql
  bind :26257
  mode tcp
  balance roundrobin
  option httpchk GET /health?ready=1
  server cockroach1 node1.example.com:26257 check port 8080
  server cockroach2 node2.example.com:26257 check port 8080
  server cockroach3 node3.example.com:26257 check port 8080

listen stats
  bind :8404
  mode http
  stats enable
  stats uri /stats
  stats refresh 10s
```

**Key HAProxy directives:**

| Directive | Value | Purpose |
|-----------|-------|---------|
| `option httpchk` | `GET /health?ready=1` | Health check method |
| `check port 8080` | `8080` | Health check on HTTP port (not SQL port) |
| `mode tcp` | `tcp` | Passthrough mode for PostgreSQL protocol |
| `balance roundrobin` | `roundrobin` | Load balancing algorithm |
| `timeout connect` | `10s` | Connection timeout |
| `timeout client` | `1m` | Client idle timeout |
| `timeout server` | `1m` | Server idle timeout |

**Advanced HAProxy health check options:**

```haproxy
listen psql
  bind :26257
  mode tcp
  balance roundrobin

  # Health check configuration
  option httpchk GET /health?ready=1
  http-check expect status 200

  # Health check intervals
  default-server inter 3s    # Check every 3 seconds
  default-server fall 2      # Mark down after 2 failures
  default-server rise 2      # Mark up after 2 successes

  # Server definitions
  server cockroach1 node1.example.com:26257 check port 8080
  server cockroach2 node2.example.com:26257 check port 8080 backup
  server cockroach3 node3.example.com:26257 check port 8080
```

**Start HAProxy:**

```bash
# Test configuration
haproxy -c -f haproxy.cfg

# Start HAProxy
haproxy -f haproxy.cfg

# Run in daemon mode
haproxy -f haproxy.cfg -D

# Reload configuration without downtime
haproxy -f haproxy.cfg -D -sf $(cat /var/run/haproxy.pid)
```

### Step 3: Configure NGINX Health Checks

**NGINX configuration for CockroachDB:**

```nginx
# upstream block defines CockroachDB backend servers
upstream cockroachdb {
    least_conn;  # Least connections load balancing

    # Backend servers
    server node1.example.com:26257 max_fails=2 fail_timeout=10s;
    server node2.example.com:26257 max_fails=2 fail_timeout=10s;
    server node3.example.com:26257 max_fails=2 fail_timeout=10s;
}

# TCP proxy to CockroachDB
stream {
    server {
        listen 26257;
        proxy_pass cockroachdb;
        proxy_connect_timeout 10s;
    }
}
```

**NGINX Plus with active health checks:**

```nginx
upstream cockroachdb {
    zone cockroach 64k;

    server node1.example.com:26257;
    server node2.example.com:26257;
    server node3.example.com:26257;
}

stream {
    server {
        listen 26257;
        proxy_pass cockroachdb;

        # Active health checks (NGINX Plus only)
        health_check interval=5s
                     fails=2
                     passes=2
                     uri=/health?ready=1
                     port=8080;
    }
}
```

### Step 4: Configure AWS Application Load Balancer

**Create target group for CockroachDB:**

```bash
# Create target group
aws elbv2 create-target-group \
  --name cockroachdb-tg \
  --protocol TCP \
  --port 26257 \
  --vpc-id vpc-12345678 \
  --health-check-enabled \
  --health-check-protocol HTTP \
  --health-check-path /health?ready=1 \
  --health-check-port 8080 \
  --health-check-interval-seconds 10 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2

# Register targets
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets \
    Id=i-node1 \
    Id=i-node2 \
    Id=i-node3
```

**ALB health check parameters:**

| Parameter | Recommended Value | Purpose |
|-----------|-------------------|---------|
| Protocol | `HTTP` | Health check protocol |
| Port | `8080` | HTTP status port |
| Path | `/health?ready=1` | Readiness endpoint |
| Interval | `10` seconds | Check frequency |
| Timeout | `5` seconds | Health check timeout |
| Healthy threshold | `2` | Consecutive successes to mark healthy |
| Unhealthy threshold | `2` | Consecutive failures to mark unhealthy |

**AWS Console configuration:**

1. Navigate to EC2 > Load Balancers
2. Create Network Load Balancer
3. Add listener on port 26257
4. Create target group:
   - **Target type**: Instance
   - **Protocol**: TCP
   - **Port**: 26257
   - **Health check protocol**: HTTP
   - **Health check path**: `/health?ready=1`
   - **Health check port**: `8080`
5. Register CockroachDB instances
6. Associate target group with listener

### Step 5: Configure Google Cloud Load Balancer

**Create health check:**

```bash
# Create HTTP health check
gcloud compute health-checks create http cockroachdb-health-check \
  --port=8080 \
  --request-path=/health?ready=1 \
  --check-interval=10s \
  --timeout=5s \
  --healthy-threshold=2 \
  --unhealthy-threshold=2

# Create TCP load balancer backend service
gcloud compute backend-services create cockroachdb-backend \
  --protocol=TCP \
  --health-checks=cockroachdb-health-check \
  --global

# Add instances to backend service
gcloud compute backend-services add-backend cockroachdb-backend \
  --instance-group=cockroach-ig \
  --instance-group-zone=us-central1-a \
  --global
```

**GCP health check settings:**

| Setting | Value | Purpose |
|---------|-------|---------|
| Check type | `HTTP` | Protocol for health check |
| Port | `8080` | HTTP status port |
| Request path | `/health?ready=1` | Readiness check |
| Check interval | `10` seconds | Frequency |
| Timeout | `5` seconds | Response timeout |
| Healthy threshold | `2` | Successes to mark healthy |
| Unhealthy threshold | `2` | Failures to mark unhealthy |

### Step 6: Monitor Health Check Status

**HAProxy stats page:**

```bash
# Access HAProxy stats (configured at :8404/stats)
curl http://localhost:8404/stats

# Or open in browser
open http://localhost:8404/stats
```

**HAProxy command line interface:**

```bash
# Install socat for HAProxy stats socket
apt-get install socat

# Add to haproxy.cfg global section:
# stats socket /var/run/haproxy.sock mode 600 level admin

# Check backend server status
echo "show stat" | socat stdio /var/run/haproxy.sock

# Show backend servers
echo "show servers state" | socat stdio /var/run/haproxy.sock
```

**Monitor CockroachDB health endpoint:**

```bash
# Monitor health checks continuously
watch -n 1 'curl -s http://localhost:8080/health?ready=1 | jq .'

# Check all nodes
for node in node1 node2 node3; do
  echo "$node:"
  curl -s http://$node:8080/health?ready=1 | jq .
done
```

**SQL monitoring:**

```sql
-- View cluster nodes
SELECT
  node_id,
  address,
  is_live,
  is_available
FROM crdb_internal.gossip_liveness
ORDER BY node_id;

-- View draining nodes
SELECT
  node_id,
  is_draining
FROM crdb_internal.kv_node_status
WHERE is_draining = true;
```

## Common Patterns

**Pattern 1: Multi-region load balancing**

```haproxy
# Regional load balancers with health checks
frontend us-east
  bind :26257
  mode tcp
  default_backend us-east-nodes

backend us-east-nodes
  mode tcp
  balance roundrobin
  option httpchk GET /health?ready=1
  server node1 us-east-1.example.com:26257 check port 8080
  server node2 us-east-2.example.com:26257 check port 8080
  server node3 us-east-3.example.com:26257 check port 8080

frontend us-west
  bind :26258
  mode tcp
  default_backend us-west-nodes

backend us-west-nodes
  mode tcp
  balance roundrobin
  option httpchk GET /health?ready=1
  server node4 us-west-1.example.com:26257 check port 8080
  server node5 us-west-2.example.com:26257 check port 8080
  server node6 us-west-3.example.com:26257 check port 8080
```

**Pattern 2: Weighted load balancing**

```haproxy
# Route more traffic to larger nodes
backend cockroachdb
  mode tcp
  balance roundrobin
  option httpchk GET /health?ready=1

  # Large node - 2x weight
  server node1 large-node.example.com:26257 check port 8080 weight 200

  # Standard nodes - 1x weight
  server node2 node2.example.com:26257 check port 8080 weight 100
  server node3 node3.example.com:26257 check port 8080 weight 100
```

**Pattern 3: Backup servers**

```haproxy
# Primary servers with backup failover
backend cockroachdb
  mode tcp
  balance roundrobin
  option httpchk GET /health?ready=1

  # Primary servers
  server node1 primary1.example.com:26257 check port 8080
  server node2 primary2.example.com:26257 check port 8080
  server node3 primary3.example.com:26257 check port 8080

  # Backup server (only used if all primaries down)
  server backup1 backup.example.com:26257 check port 8080 backup
```

**Pattern 4: Health check with custom timeout**

```haproxy
backend cockroachdb
  mode tcp
  balance roundrobin

  # Custom health check settings per server
  option httpchk GET /health?ready=1

  server node1 fast-node.example.com:26257 \
    check port 8080 inter 2s fall 2 rise 2

  server node2 slow-node.example.com:26257 \
    check port 8080 inter 5s fall 3 rise 3
```

## Common Issues

**Issue 1: Health checks hitting wrong port**

**Problem:** Load balancer checks SQL port (26257) instead of HTTP port (8080).

```haproxy
# BAD: Health check on SQL port
server cockroach1 node1:26257 check
# HAProxy tries HTTP GET on 26257, which speaks PostgreSQL protocol
```

**Solution:** Explicitly check port 8080.

```haproxy
# GOOD: Health check on HTTP port
server cockroach1 node1:26257 check port 8080
```

**Issue 2: Using /health instead of /health?ready=1**

**Problem:** Load balancer routes traffic to draining nodes.

```haproxy
# BAD: Only checks if process is alive
option httpchk GET /health
# Node continues receiving traffic while draining
```

**Solution:** Use readiness check.

```haproxy
# GOOD: Checks if node is ready
option httpchk GET /health?ready=1
# Traffic stops when node starts draining
```

**Issue 3: Health check interval too aggressive**

**Problem:** Excessive health check load on cluster.

```haproxy
# BAD: Check every 500ms
default-server inter 500ms
# With 3 nodes, 6 checks/second per load balancer
```

**Solution:** Use reasonable interval.

```haproxy
# GOOD: Check every 3-10 seconds
default-server inter 5s fall 2 rise 2
# Balances responsiveness vs load
```

**Issue 4: Firewall blocking port 8080**

**Problem:** Health checks fail even though nodes are healthy.

```bash
# Symptoms
curl http://node1:8080/health?ready=1
# Connection timeout or refused
```

**Solution:** Open port 8080 for health checks.

```bash
# Allow HTTP health checks from load balancer
iptables -A INPUT -p tcp --dport 8080 -s 10.0.1.0/24 -j ACCEPT

# Or configure security group (AWS)
aws ec2 authorize-security-group-ingress \
  --group-id sg-12345678 \
  --protocol tcp \
  --port 8080 \
  --source-group sg-lb
```

**Issue 5: All nodes marked unhealthy**

**Problem:** Load balancer marks all backends down.

**Troubleshooting:**

```bash
# Check health endpoint directly
curl -v http://node1:8080/health?ready=1

# Check from load balancer server
ssh loadbalancer
curl http://node1:8080/health?ready=1

# Check HAProxy logs
tail -f /var/log/haproxy.log

# Check CockroachDB logs
cockroach debug zip /tmp/debug.zip --host=node1:26257
```

## Best Practices

1. **Use /health?ready=1** - Don't route traffic to draining nodes
2. **Check port 8080** - HTTP health port, not SQL port 26257
3. **Set reasonable intervals** - 3-10 seconds balances responsiveness and load
4. **Configure fall/rise thresholds** - Require 2+ consecutive checks before state change
5. **Monitor health check failures** - Alert on repeated failures
6. **Use TCP mode** - HAProxy should passthrough PostgreSQL wire protocol
7. **Configure timeouts** - Set connect/client/server timeouts appropriately
8. **Test drain behavior** - Verify traffic stops when draining
9. **Document load balancer config** - Include in cluster documentation
10. **Automate configuration** - Use `cockroach gen haproxy` as starting point

## Related Skills

**Load balancer management:**
- deploy-haproxy-load-balancer-for-cluster
- configure-haproxy-health-checks-and-backend-servers
- manage-haproxy-service-lifecycle

**Node maintenance:**
- drain-nodes-gracefully-for-maintenance
- remove-nodes-from-load-balancer-configuration
- restore-nodes-to-load-balancer-after-maintenance

**Health monitoring:**
- use-health-check-endpoints
- use-health-check-endpoints-for-availability-monitoring
- monitor-node-liveness-and-health

## References

- [CockroachDB Docs: Deploy CockroachDB On-Premises](https://www.cockroachlabs.com/docs/stable/deploy-cockroachdb-on-premises)
- [CockroachDB Docs: Production Checklist](https://www.cockroachlabs.com/docs/stable/recommended-production-settings)
- [CockroachDB Docs: cockroach gen haproxy](https://www.cockroachlabs.com/docs/stable/cockroach-gen)
- [CockroachDB Docs: Monitoring and Alerting](https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting)
