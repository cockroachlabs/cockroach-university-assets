---
name: configure-load-balancer-health-checks-for-node-maintenance
description: Configure load balancer health checks using CockroachDB health endpoints to automatically remove draining nodes from rotation during maintenance. Use when user asks "load balancer health check", "HAProxy health endpoint", "/health?ready=1", or "automatic node removal".
metadata:
  domain: Cluster Maintenance
  bloom_level: Apply
  version: 1.0.0
  cockroachdb_version: v26.1.0+
---

# Configure Load Balancer Health Checks for Node Maintenance

## What This Skill Teaches

Proper load balancer health check configuration is essential for graceful node maintenance. This skill covers configuring HAProxy, Nginx, and cloud load balancers to use CockroachDB's health endpoints for automatic node removal during drains.

## Why Health Checks Matter

### Without Health Checks

When a node drains without health checks:
- ❌ Load balancer continues sending traffic to draining node
- ❌ New connections fail (connection refused)
- ❌ Application errors spike
- ❌ Manual load balancer reconfiguration required

### With Health Checks

When properly configured:
- ✅ Load balancer automatically detects draining node
- ✅ Node removed from rotation within seconds
- ✅ Traffic redirected to healthy nodes
- ✅ Zero client-visible errors
- ✅ Fully automated (no manual intervention)

---

## CockroachDB Health Endpoints

CockroachDB exposes two HTTP health endpoints:

### Endpoint 1: /health (Liveness Check)

**URL**: `http://<node>:8080/health`

**Purpose**: Check if node process is alive

**Returns**:
- `200 OK` - Node process running
- Connection refused - Node dead

**Use case**: Basic aliveness check

**Example**:
```bash
curl http://localhost:8080/health
# Response: {"status":"ok"}
```

---

### Endpoint 2: /health?ready=1 (Readiness Check)

**URL**: `http://<node>:8080/health?ready=1`

**Purpose**: Check if node ready to accept traffic

**Returns**:
- `200 OK` - Node ready (not draining, healthy)
- `503 Service Unavailable` - Node draining or not ready

**Use case**: Load balancer health checks (RECOMMENDED)

**Example**:
```bash
# Healthy node
curl http://localhost:8080/health?ready=1
# Response: 200 OK
# Body: {"status":"ok"}

# Draining node
curl http://localhost:8080/health?ready=1
# Response: 503 Service Unavailable
# Body: {"error":"node is draining"}
```

**Behavior during drain**:
```
Before drain: 200 OK
Drain starts: 503 Service Unavailable (immediately)
During drain: 503 Service Unavailable
After drain: 503 Service Unavailable
Node stopped: Connection refused
```

**⭐ Use `/health?ready=1` for load balancer health checks**

---

## Health Check Timing

### Critical Timing Relationship

For graceful maintenance, coordinate:

```
server.shutdown.initial_wait (CockroachDB)
         ≥
health_check_interval × fall_threshold (Load Balancer)
```

**Example**:
```
Load balancer:
  health_check_interval = 3s
  fall_threshold = 2 failures

Time to detect failure: 3s × 2 = 6s

CockroachDB setting:
  server.shutdown.initial_wait = 8s (6s + 2s buffer)
```

**Why this matters**:
- Node starts draining
- Health endpoint returns 503
- Load balancer needs time to detect failure
- `initial_wait` provides that time
- After initial wait, new connections stopped

---

## HAProxy Configuration

### Basic HAProxy Backend

```
backend cockroach
    balance roundrobin
    option httpchk GET /health?ready=1
    http-check expect status 200

    server node1 10.0.1.10:26257 check inter 3000ms fall 2 rise 2 port 8080
    server node2 10.0.1.11:26257 check inter 3000ms fall 2 rise 2 port 8080
    server node3 10.0.1.12:26257 check inter 3000ms fall 2 rise 2 port 8080
```

### Parameter Breakdown

**option httpchk GET /health?ready=1**:
- Perform HTTP GET to `/health?ready=1`
- On CockroachDB's HTTP port (8080)

**http-check expect status 200**:
- Consider node healthy only if returns 200
- 503 = unhealthy, remove from pool

**check**: Enable health checks

**inter 3000ms**: Check every 3 seconds

**fall 2**: Mark down after 2 consecutive failures

**rise 2**: Mark up after 2 consecutive successes

**port 8080**: Health check port (CockroachDB HTTP port)

---

### Complete HAProxy Configuration

```
global
    log /dev/log local0
    maxconn 4096

defaults
    log global
    mode tcp
    timeout connect 10s
    timeout client 10m
    timeout server 10m

frontend cockroach_sql
    bind *:26257
    default_backend cockroach

backend cockroach
    balance roundrobin
    option httpchk GET /health?ready=1
    http-check expect status 200

    # Health check configuration
    default-server inter 3000ms fall 2 rise 2 port 8080 check

    # Backend servers
    server node1 10.0.1.10:26257
    server node2 10.0.1.11:26257
    server node3 10.0.1.12:26257

# Admin interface (optional)
listen stats
    bind *:8404
    stats enable
    stats uri /
    stats refresh 10s
```

### Advanced HAProxy Options

```
backend cockroach
    balance roundrobin
    option httpchk GET /health?ready=1
    http-check expect status 200

    # Advanced health check tuning
    default-server \
        inter 2000ms \      # Check every 2s (faster detection)
        fastinter 1000ms \  # Check every 1s when transitioning states
        downinter 5000ms \  # Check every 5s when down
        fall 3 \            # 3 failures before marking down
        rise 2 \            # 2 successes before marking up
        port 8080 \         # Health check port
        check               # Enable checks

    server node1 10.0.1.10:26257 weight 100
    server node2 10.0.1.11:26257 weight 100
    server node3 10.0.1.12:26257 weight 100 backup  # Backup server
```

---

## Nginx Configuration

### Nginx with ngx_http_upstream_hc_module

```nginx
http {
    upstream cockroach {
        least_conn;

        server 10.0.1.10:26257 max_fails=2 fail_timeout=10s;
        server 10.0.1.11:26257 max_fails=2 fail_timeout=10s;
        server 10.0.1.12:26257 max_fails=2 fail_timeout=10s;
    }

    server {
        listen 26257;

        location / {
            proxy_pass http://cockroach;

            # Health check (Nginx Plus)
            health_check uri=/health?ready=1 interval=3s fails=2 passes=2 port=8080;
        }
    }
}
```

**Note**: Active health checks require Nginx Plus (commercial). Open-source Nginx uses passive checks only.

### Nginx Stream Module (TCP Load Balancing)

```nginx
stream {
    upstream cockroach_backend {
        least_conn;

        server 10.0.1.10:26257 max_fails=2 fail_timeout=10s;
        server 10.0.1.11:26257 max_fails=2 fail_timeout=10s;
        server 10.0.1.12:26257 max_fails=2 fail_timeout=10s;
    }

    server {
        listen 26257;
        proxy_pass cockroach_backend;
        proxy_connect_timeout 10s;
    }
}
```

**Limitation**: Nginx Open Source performs passive health checks only (based on connection failures).

**Recommendation**: Use HAProxy for active health checks, or upgrade to Nginx Plus.

---

## AWS Elastic Load Balancer (ELB)

### Application Load Balancer (ALB)

**Target Group Configuration**:

```yaml
Health Check Protocol: HTTP
Health Check Path: /health?ready=1
Health Check Port: 8080
Healthy Threshold: 2 checks
Unhealthy Threshold: 2 checks
Timeout: 5 seconds
Interval: 10 seconds
Success Codes: 200
```

**Via AWS CLI**:
```bash
aws elbv2 create-target-group \
  --name cockroach-targets \
  --protocol TCP \
  --port 26257 \
  --vpc-id vpc-12345678 \
  --health-check-enabled \
  --health-check-protocol HTTP \
  --health-check-path "/health?ready=1" \
  --health-check-port 8080 \
  --health-check-interval-seconds 10 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2
```

---

### Network Load Balancer (NLB)

NLB supports HTTP health checks:

```bash
aws elbv2 create-target-group \
  --name cockroach-nlb-targets \
  --protocol TCP \
  --port 26257 \
  --vpc-id vpc-12345678 \
  --health-check-enabled \
  --health-check-protocol HTTP \
  --health-check-path "/health?ready=1" \
  --health-check-port 8080 \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2
```

**Register targets**:
```bash
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets Id=i-node1 Id=i-node2 Id=i-node3
```

---

## Google Cloud Load Balancer

### GCP Health Check Configuration

```bash
# Create health check
gcloud compute health-checks create http cockroach-health \
  --port=8080 \
  --request-path="/health?ready=1" \
  --check-interval=10s \
  --timeout=5s \
  --unhealthy-threshold=2 \
  --healthy-threshold=2

# Create backend service with health check
gcloud compute backend-services create cockroach-backend \
  --protocol=TCP \
  --health-checks=cockroach-health \
  --global

# Add instances to backend
gcloud compute backend-services add-backend cockroach-backend \
  --instance-group=cockroach-ig \
  --instance-group-zone=us-central1-a \
  --global
```

---

## Testing Health Check Configuration

### Test 1: Verify Endpoint Accessibility

```bash
# Test health endpoint from load balancer
curl -v http://10.0.1.10:8080/health?ready=1

# Expected: HTTP/1.1 200 OK
# Body: {"status":"ok"}
```

### Test 2: Simulate Node Drain

```bash
# Drain a node
cockroach node drain 1 --host=localhost:26257 --certs-dir=certs

# Immediately test health endpoint
curl http://10.0.1.10:8080/health?ready=1

# Expected: HTTP/1.1 503 Service Unavailable
# Body: {"error":"node is draining"}
```

### Test 3: Verify Load Balancer Detects Failure

```bash
# Monitor load balancer stats (HAProxy example)
watch -n 1 'curl -s http://localhost:8404/stats | grep cockroach'

# Expected:
# node1: DOWN (draining)
# node2: UP
# node3: UP
```

### Test 4: Verify Traffic Redirected

```bash
# Before drain: connections distributed
# After drain: connections only to healthy nodes

# Check active connections per node
cockroach sql --execute="
  SELECT node_id, count(*) AS connection_count
  FROM crdb_internal.cluster_sessions
  GROUP BY node_id;
"

# Draining node should have 0 new connections
```

---

## Coordinating Settings

### CockroachDB Settings

```sql
-- Set initial wait to allow load balancer detection
SET CLUSTER SETTING server.shutdown.initial_wait = '10s';

-- Connection drain timeout
SET CLUSTER SETTING server.shutdown.connections.timeout = '15s';

-- Transaction timeout
SET CLUSTER SETTING server.shutdown.transactions.timeout = '30s';
```

### Load Balancer Settings (HAProxy Example)

```
Health check interval: 3s
Fall threshold: 2 failures
Rise threshold: 2 successes

Time to detect failure: 3s × 2 = 6s
Time to detect recovery: 3s × 2 = 6s

server.shutdown.initial_wait: 10s (>6s)
```

### Calculation

```
Minimum initial_wait = (health_check_interval × fall_threshold) + safety_buffer

Example:
  health_check_interval = 3s
  fall_threshold = 2
  safety_buffer = 2s

  Minimum initial_wait = (3s × 2) + 2s = 8s
  Recommended: 10s
```

---

## Troubleshooting

### Issue 1: Load Balancer Still Sending Traffic to Draining Node

**Symptoms**:
- Node draining but still receiving connections
- Client errors during drain

**Diagnosis**:
```bash
# Check health endpoint
curl http://<draining-node>:8080/health?ready=1
# Should return 503

# Check load balancer sees node as down
# HAProxy: curl http://localhost:8404/stats
# Check node status shows "DOWN"
```

**Causes**:
- Health check not configured
- Health check using wrong endpoint (/ instead of /health?ready=1)
- Health check port wrong
- Firewall blocking health checks

**Solutions**:
```bash
# Verify load balancer health check configuration
# Ensure using /health?ready=1 on port 8080

# Test health check from load balancer host
curl http://<node>:8080/health?ready=1

# Check firewall rules
sudo iptables -L | grep 8080
```

---

### Issue 2: Node Marked Down Too Quickly

**Symptoms**:
- Temporary network blip causes node removal
- Flapping (node up/down repeatedly)

**Solution**:
```
# Increase fall threshold (HAProxy)
server node1 10.0.1.10:26257 check fall 3 rise 2

# Increase health check interval
inter 5000ms

# Both reduce sensitivity to transient failures
```

---

### Issue 3: Node Takes Too Long to Return to Service

**Symptoms**:
- Node restarted but load balancer slow to add back

**Diagnosis**:
```bash
# Check health endpoint
curl http://<node>:8080/health?ready=1
# Should return 200 OK

# Check load balancer rise threshold
# High rise threshold = slow recovery
```

**Solution**:
```
# Reduce rise threshold (HAProxy)
server node1 10.0.1.10:26257 check fall 2 rise 2

# Reduce health check interval during recovery
fastinter 1000ms
```

---

## Best Practices

1. **Always use /health?ready=1** - Not /health (liveness only)
2. **Check on HTTP port** - Port 8080 (not SQL port 26257)
3. **Set appropriate timeouts** - Balance sensitivity vs stability
4. **Coordinate with initial_wait** - Ensure CockroachDB waits long enough
5. **Test in staging** - Validate drain removes node from rotation
6. **Monitor health check metrics** - Track up/down transitions
7. **Document configuration** - Record settings for troubleshooting

---

## Configuration Examples Summary

| Load Balancer | Health Check Config | Detection Time |
|---------------|---------------------|----------------|
| HAProxy | `option httpchk GET /health?ready=1`<br>`inter 3000ms fall 2` | 6 seconds |
| Nginx Plus | `health_check uri=/health?ready=1`<br>`interval=3s fails=2` | 6 seconds |
| AWS ALB/NLB | Path: `/health?ready=1`<br>Port: 8080<br>Interval: 10s | 20 seconds |
| GCP LB | `--request-path="/health?ready=1"`<br>`--check-interval=10s` | 20 seconds |

---

## Key Takeaways

1. **Use `/health?ready=1` endpoint** - Returns 503 when draining
2. **Health check on port 8080** - HTTP port, not SQL port
3. **Coordinate timeouts** - `initial_wait` ≥ detection time
4. **Test configuration** - Verify drain removes node
5. **Balance sensitivity** - Not too aggressive, not too slow
6. **Automatic removal** - No manual intervention needed
7. **Zero-downtime maintenance** - When properly configured

---

## Related Skills

- `drain-nodes-for-maintenance` - Drain command usage
- `execute-a-graceful-node-shutdown-in-a-cockroachdb-cluster` - Full shutdown workflow
- `configure-cluster-settings-for-graceful-shutdown` - Shutdown timeout configuration
- `perform-rolling-restarts` - Rolling restart procedure
- `verify-connection-draining-completion` - Drain validation
