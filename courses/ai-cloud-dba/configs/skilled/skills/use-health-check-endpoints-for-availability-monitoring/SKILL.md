---
name: use-health-check-endpoints-for-availability-monitoring
description: Use CockroachDB health check endpoints (/health, /health?ready=1) for availability monitoring with load balancers and orchestrators. Monitor HTTP status codes and integrate with infrastructure.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: complete
---

# Use Health Check Endpoints for Availability Monitoring

## What This Skill Teaches

CockroachDB exposes HTTP health check endpoints for monitoring node availability and readiness. Use `/health` for liveness checks and `/health?ready=1` for readiness checks, integrating with load balancers, Kubernetes, and monitoring systems.

**Use cases:**
- Automated failure detection and recovery
- Load balancer traffic routing
- Kubernetes pod health management
- Graceful node draining without downtime
- Infrastructure automation

---

## Health Check Endpoints Overview

CockroachDB provides two HTTP endpoints on **port 8080** (HTTP admin port, not SQL port 26257):

| Endpoint | Purpose | Returns | Use For |
|----------|---------|---------|---------|
| `/health` | Liveness check | 200 OK or connection refused | Process alive? Kubernetes liveness |
| `/health?ready=1` | Readiness check | 200 OK or 503 unavailable | Ready for traffic? Load balancers, K8s readiness |

---

## Endpoint 1: /health (Liveness Check)

**Purpose:** Check if the CockroachDB process is alive and responsive.

### Example Request

```bash
# Healthy node
curl http://localhost:8080/health
# HTTP/1.1 200 OK
# {"status":"ok"}

# Dead node
curl http://localhost:8080/health
# curl: (7) Failed to connect: Connection refused
```

### What It Checks

- ✅ HTTP server running
- ✅ Process can handle requests
- ❌ Does NOT check database availability, cluster connectivity, or drain status

### When to Use

- **Kubernetes liveness probes** - Detect crashed/hung processes
- **Basic process monitoring** - "Is the daemon running?"

---

## Endpoint 2: /health?ready=1 (Readiness Check)

**Purpose:** Check if the node is ready to accept SQL traffic.

### Example Request

```bash
# Ready node
curl 'http://localhost:8080/health?ready=1'
# HTTP/1.1 200 OK
# {"status":"ok"}

# Draining node
curl 'http://localhost:8080/health?ready=1'
# HTTP/1.1 503 Service Unavailable
# {"error":"node is draining"}

# Starting node
curl 'http://localhost:8080/health?ready=1'
# HTTP/1.1 503 Service Unavailable
# {"error":"node is not ready"}
```

### Node States and Responses

| Node State | /health | /health?ready=1 | Description |
|------------|---------|-----------------|-------------|
| **Healthy** | 200 OK | 200 OK | Fully operational |
| **Starting** | 200 OK | 503 Unavailable | Process alive but initializing |
| **Draining** | 200 OK | 503 Unavailable | Graceful shutdown in progress |
| **Stopped** | Connection refused | Connection refused | Process terminated |

### What It Checks

- ✅ Cluster membership established
- ✅ Gossip network connected
- ✅ Not in drain mode
- ✅ Ready to accept SQL connections

### When to Use

- **Load balancer health checks** - Route traffic to ready nodes only
- **Kubernetes readiness probes** - Control pod service registration
- **Graceful draining** - Automatic traffic removal
- **Rolling deployments** - Wait for node readiness

**⭐ Use `/health?ready=1` for all traffic routing decisions**

---

## Kubernetes Integration

### Liveness Probe (Detect Process Crashes)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cockroachdb-0
spec:
  containers:
  - name: cockroachdb
    image: cockroachdb/cockroach:v26.1.0
    ports:
    - containerPort: 26257
      name: grpc
    - containerPort: 8080
      name: http
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      failureThreshold: 3
```

**Behavior:** Kubernetes restarts pod after 3 consecutive failures (30 seconds).

### Readiness Probe (Control Traffic Routing)

```yaml
    readinessProbe:
      httpGet:
        path: /health?ready=1
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 5
      failureThreshold: 2
```

**Behavior:**
- Returns 200 OK → Pod added to Service
- Returns 503 (draining) → Pod removed from Service
- After 2 failures → Removed from endpoints

### Complete Configuration

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cockroachdb-0
spec:
  containers:
  - name: cockroachdb
    image: cockroachdb/cockroach:v26.1.0
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /health?ready=1
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 5
      failureThreshold: 2
```

---

## Load Balancer Integration

### HAProxy Configuration

```
backend cockroach
    balance roundrobin
    option httpchk GET /health?ready=1
    http-check expect status 200

    server node1 10.0.1.10:26257 check inter 3000ms fall 2 rise 2 port 8080
    server node2 10.0.1.11:26257 check inter 3000ms fall 2 rise 2 port 8080
    server node3 10.0.1.12:26257 check inter 3000ms fall 2 rise 2 port 8080
```

**Parameters:**
- `option httpchk GET /health?ready=1` - Health check endpoint
- `http-check expect status 200` - Only 200 is healthy
- `inter 3000ms` - Check every 3 seconds
- `fall 2` - Mark down after 2 failures (6s detection time)
- `rise 2` - Mark up after 2 successes
- `port 8080` - Check on HTTP port (not SQL port 26257)

### AWS Network Load Balancer

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

**Detection time:** 10s × 2 = 20 seconds

### Google Cloud Load Balancer

```bash
gcloud compute health-checks create http cockroach-health \
  --port=8080 \
  --request-path="/health?ready=1" \
  --check-interval=10s \
  --unhealthy-threshold=2 \
  --healthy-threshold=2
```

---

## Monitoring Integration

### Prometheus Monitoring

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'cockroachdb-health'
    metrics_path: /health
    static_configs:
      - targets: ['node1:8080', 'node2:8080', 'node3:8080']

# Alert rule
groups:
  - name: cockroachdb_health
    rules:
      - alert: CockroachDBNodeDown
        expr: up{job="cockroachdb-health"} == 0
        for: 1m
```

### Custom Health Check Script

```bash
#!/bin/bash
# health-check.sh

NODES=("node1:8080" "node2:8080" "node3:8080")
ERRORS=0

for node in "${NODES[@]}"; do
    # Readiness check
    status=$(curl -s -o /dev/null -w "%{http_code}" 'http://'"$node"'/health?ready=1')

    if [ "$status" = "200" ]; then
        echo "✓ $node is healthy and ready"
    elif [ "$status" = "503" ]; then
        echo "⚠ $node is alive but not ready (draining or initializing)"
    else
        echo "ERROR: $node returned unexpected status: $status"
        ERRORS=$((ERRORS + 1))
    fi
done

exit $ERRORS
```

---

## Graceful Drain Detection

### How /health?ready=1 Responds to Drain

```bash
# Before drain
curl 'http://localhost:8080/health?ready=1'
# HTTP/1.1 200 OK

# Start drain
cockroach node drain 1 --host=localhost:26257 --certs-dir=certs

# Immediately check (returns 503 instantly)
curl 'http://localhost:8080/health?ready=1'
# HTTP/1.1 503 Service Unavailable
# {"error":"node is draining"}
```

### Timeline

```
t=0s    Drain command issued
t=0s    /health?ready=1 returns 503 (immediate)
t=0-6s  Load balancer detects failure
t=6s    Load balancer removes node from pool
t=10s   server.shutdown.initial_wait expires
t=10s   New connections rejected
t=30s   Drain completes
```

### Critical Setting Coordination

```
server.shutdown.initial_wait ≥ (health_check_interval × failure_threshold)
```

**Example:**

```sql
-- Load balancer: 3s interval × 2 failures = 6s detection time
-- Set initial_wait to 10s (6s + 4s buffer)
SET CLUSTER SETTING server.shutdown.initial_wait = '10s';
```

**Why this matters:**
- If `initial_wait` is too short, load balancer hasn't detected drain yet
- New connections still routed to draining node
- Results in connection errors

---

## Testing Health Checks

### Test 1: Verify Endpoint Access

```bash
# Test liveness
curl -v http://localhost:8080/health
# Expected: HTTP/1.1 200 OK

# Test readiness
curl -v 'http://localhost:8080/health?ready=1'
# Expected: HTTP/1.1 200 OK
```

### Test 2: Verify Drain Detection

```bash
# Terminal 1: Monitor health endpoint
watch -n 1 'curl -s '\''http://localhost:8080/health?ready=1'\'''

# Terminal 2: Start drain
cockroach node drain 1 --host=localhost:26257 --certs-dir=certs

# Expected: Status changes from 200 to 503 immediately
```

### Test 3: Load Balancer Integration

```bash
# Check HAProxy stats before drain
curl http://localhost:8404/stats | grep node1
# Expected: node1: UP

# Drain node1
cockroach node drain 1 --host=localhost:26257 --certs-dir=certs

# Wait for detection
sleep 6

# Check HAProxy stats after drain
curl http://localhost:8404/stats | grep node1
# Expected: node1: DOWN
```

---

## Best Practices

1. **Use /health?ready=1 for traffic routing** - Not /health (liveness only)
2. **Separate liveness and readiness** - Different purposes, different thresholds
3. **Coordinate timeouts** - Ensure `initial_wait` ≥ load balancer detection time
4. **Check on port 8080** - HTTP admin port, not SQL port 26257
5. **Test in staging** - Validate drain removes node from rotation

---

## Troubleshooting

### Issue: Connection Refused

**Symptoms:**
```bash
curl http://localhost:8080/health
# curl: (7) Failed to connect: Connection refused
```

**Causes & Solutions:**

```bash
# Process not running
ps aux | grep cockroach
# Solution: Start CockroachDB

# Port not listening
netstat -tlnp | grep 8080
# Solution: Check --http-addr flag (default: :8080)

# Firewall blocking
sudo iptables -L -n | grep 8080
# Solution: Allow port 8080
```

### Issue: Always Returns 503

**Symptoms:**
```bash
curl 'http://localhost:8080/health?ready=1'
# HTTP/1.1 503 Service Unavailable
```

**Diagnosis:**

```bash
# Check if draining
cockroach node status --decommission --certs-dir=certs

# Check logs
tail -f cockroach-data/logs/cockroach.log | grep -i "drain\|ready"

# Check cluster membership
cockroach node status --certs-dir=certs
```

**Common causes:**
- Node still initializing (wait 30-60s)
- Node in drain mode (cancel drain or wait for completion)
- Clock skew (sync clocks with NTP)

### Issue: Load Balancer Not Detecting Drain

**Diagnosis:**

```bash
# Verify health endpoint returns 503
curl 'http://<draining-node>:8080/health?ready=1'
# Should return: 503

# Check load balancer config uses correct endpoint
# HAProxy: option httpchk GET /health?ready=1
# AWS NLB: health-check-path "/health?ready=1"
```

**Common mistakes:**
- Using `/health` instead of `/health?ready=1`
- Checking wrong port (26257 instead of 8080)
- Health check interval too long

---

## Verification Checklist

✅ `/health` returns 200 OK on healthy nodes
✅ `/health?ready=1` returns 200 OK on ready nodes
✅ `/health?ready=1` returns 503 when draining
✅ Load balancer uses `/health?ready=1` (not `/health`)
✅ Health checks target port 8080 (not 26257)
✅ Drain removes node from load balancer within detection time
✅ `server.shutdown.initial_wait` ≥ load balancer detection time
✅ Kubernetes liveness uses `/health`
✅ Kubernetes readiness uses `/health?ready=1`
✅ No connection errors during graceful drain

---

## Related Skills

- `configure-load-balancer-health-checks-for-node-maintenance` - Load balancer configuration
- `execute-a-graceful-node-shutdown-in-a-cockroachdb-cluster` - Graceful shutdown
- `monitor-node-liveness-and-health` - Node status monitoring
- `configure-cluster-settings-for-graceful-shutdown` - Drain timeout settings
