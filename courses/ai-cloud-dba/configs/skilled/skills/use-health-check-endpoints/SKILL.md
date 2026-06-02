---
name: use-health-check-endpoints
description: Can use /health endpoint for basic node availability and /health?ready=1 for readiness checks (node can serve traffic). Use in load balancers, Kubernetes probes, and external monitoring systems. Use when user says "health check", "health endpoint", "readiness probe".
metadata:
  domain: Monitoring and Alerting
  tags: schema-design, monitoring
  blooms_level: Apply
  version: 1.0.0
---

# Use Health Check Endpoints for Availability Monitoring

Uses HTTP health check endpoints to monitor node availability and readiness. Essential for load balancers, Kubernetes probes, and external monitoring systems.

## Available Health Endpoints

CockroachDB provides two HTTP health check endpoints:

### 1. `/health` - Liveness Check

**Purpose**: Basic node availability
**Returns**: 200 OK if node process is running
**Use for**: Determining if node is alive

**URL:**
```
http://<node-address>:8080/health
```

**Success Response:**
```json
Status: 200 OK
{
  "ok": true
}
```

**Failure Response:**
```
Status: 503 Service Unavailable
Connection refused (if node is down)
```

### 2. `/health?ready=1` - Readiness Check

**Purpose**: Node can serve traffic
**Returns**: 200 OK if node is ready to accept connections
**Use for**: Load balancer backend health, traffic routing

**URL:**
```
http://<node-address>:8080/health?ready=1
```

**Success Response:**
```json
Status: 200 OK
{
  "ok": true
}
```

**Failure Response:**
```
Status: 503 Service Unavailable
{
  "error": "node is not ready"
}
```

**Node is NOT ready when:**
- Still starting up
- Draining for maintenance
- Decommissioning
- Experiencing severe performance issues

## Instructions

### Method 1: Command Line (curl)

**Check liveness:**
```bash
curl http://localhost:8080/health
```

**Check readiness:**
```bash
curl http://localhost:8080/health?ready=1
```

**With secure cluster (HTTPS):**
```bash
curl --cacert certs/ca.crt https://localhost:8080/health

curl --cacert certs/ca.crt https://localhost:8080/health?ready=1
```

**Check specific node:**
```bash
# Node 1
curl http://localhost:8080/health?ready=1

# Node 2
curl http://localhost:8081/health?ready=1

# Node 3
curl http://localhost:8082/health?ready=1
```

### Method 2: Load Balancer Configuration

**HAProxy Example:**
```
backend cockroachdb
    option httpchk GET /health?ready=1
    server node1 node1:26257 check port 8080
    server node2 node2:26257 check port 8080
    server node3 node3:26257 check port 8080
```

**Key parameters:**
- `option httpchk GET /health?ready=1` - Use readiness check
- `check port 8080` - Check HTTP port, not SQL port
- Server marked DOWN if health check fails

### Method 3: Kubernetes Probes

**Liveness Probe** (restarts pod if fails):
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Readiness Probe** (removes from service if fails):
```yaml
readinessProbe:
  httpGet:
    path: /health?ready=1
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 2
```

### Method 4: Monitoring Systems

**Prometheus Blackbox Exporter:**
```yaml
- job_name: 'cockroachdb_health'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
        - http://node1:8080/health?ready=1
        - http://node2:8080/health?ready=1
        - http://node3:8080/health?ready=1
```

**Nagios/Icinga:**
```bash
check_http -H node1 -p 8080 -u /health?ready=1 -s "ok"
```

## Example: Check All Nodes

```bash
#!/bin/bash
# Check health of all nodes

NODES=("localhost:8080" "localhost:8081" "localhost:8082")

for node in "${NODES[@]}"; do
  echo "Checking $node..."

  # Liveness
  if curl -s -f http://$node/health > /dev/null; then
    echo "  ✅ Liveness: OK"
  else
    echo "  ❌ Liveness: FAILED"
  fi

  # Readiness
  if curl -s -f http://$node/health?ready=1 > /dev/null; then
    echo "  ✅ Readiness: OK"
  else
    echo "  ⚠️  Readiness: NOT READY"
  fi

  echo ""
done
```

## Understanding Health Check Responses

### Liveness Check (`/health`)

| Status Code | Meaning | Action |
|-------------|---------|--------|
| **200 OK** | Node is alive | ✅ No action |
| **503** | Node is dead/stopped | ❌ Restart node |
| **Connection refused** | Process not running | ❌ Start process |

### Readiness Check (`/health?ready=1`)

| Status Code | Meaning | Action |
|-------------|---------|--------|
| **200 OK** | Node ready for traffic | ✅ No action |
| **503** | Node not ready | ⚠️ Investigate |

**Reasons for 503 (not ready):**
1. **Node draining** - Planned maintenance
2. **Node decommissioning** - Being removed
3. **Startup incomplete** - Still initializing
4. **Performance issues** - Overloaded

## Use Cases

### 1. Load Balancer Backend Health

**Scenario:** HAProxy routing SQL connections

**Configuration:**
```
backend cockroachdb_sql
    mode tcp
    balance roundrobin
    option httpchk GET /health?ready=1
    http-check expect status 200
    server node1 10.0.1.10:26257 check port 8080 inter 5s
    server node2 10.0.1.11:26257 check port 8080 inter 5s
    server node3 10.0.1.12:26257 check port 8080 inter 5s
```

**Behavior:**
- Checks `/health?ready=1` every 5 seconds
- Removes node from pool if unhealthy
- Re-adds when healthy again
- No client connection errors during maintenance

### 2. Kubernetes Pod Health

**Scenario:** CockroachDB StatefulSet

**Benefits:**
- **Liveness**: Kubernetes restarts crashed pods
- **Readiness**: Pods not added to Service until ready
- **Graceful draining**: Pods marked not-ready before termination

### 3. External Monitoring

**Scenario:** Datadog/Prometheus monitoring

**Setup:**
```python
# Python example
import requests

def check_cluster_health(nodes):
    for node in nodes:
        try:
            response = requests.get(f"http://{node}:8080/health?ready=1")
            if response.status_code == 200:
                print(f"✅ {node}: Ready")
            else:
                print(f"⚠️ {node}: Not Ready")
        except requests.ConnectionError:
            print(f"❌ {node}: Down")
```

### 4. Pre-Deployment Validation

**Scenario:** CI/CD pipeline

**Check before deploying application:**
```bash
# Wait for cluster to be ready
until curl -s -f http://localhost:8080/health?ready=1; do
  echo "Waiting for CockroachDB to be ready..."
  sleep 5
done

echo "Cluster ready! Deploying application..."
```

## Advanced: Draining Nodes Gracefully

**Before maintenance, drain node:**
```bash
cockroach node drain <node-id> --certs-dir=certs
```

**What happens:**
1. `/health?ready=1` returns 503
2. Load balancer stops sending new connections
3. Existing connections finish gracefully
4. Node can be safely restarted

**Verify draining:**
```bash
curl http://localhost:8080/health?ready=1
# Should return 503 during drain
```

**After maintenance, node automatically becomes ready:**
```bash
curl http://localhost:8080/health?ready=1
# Returns 200 when ready for traffic again
```

## Monitoring Best Practices

### 1. Check Frequency

- **Liveness**: Every 30-60 seconds
- **Readiness**: Every 5-10 seconds

**Rationale:**
- Frequent checks detect issues quickly
- Not too frequent to avoid overhead
- Readiness checked more often (affects traffic routing)

### 2. Timeout Values

- **Connect timeout**: 3 seconds
- **Read timeout**: 5 seconds

**Why:**
- Health checks should be fast
- Slow responses indicate problems
- Prevent hanging checks

### 3. Failure Thresholds

- **Mark unhealthy after**: 2-3 consecutive failures
- **Mark healthy after**: 1-2 consecutive successes

**Prevents:**
- Flapping (rapid healthy/unhealthy transitions)
- False positives from transient network issues

## Common Issues

**Issue: Health check returns 503 but node seems fine**

**Possible Causes:**
- Node is draining
- Node is decommissioning
- Severe resource pressure

**Check:**
```bash
cockroach node status --certs-dir=certs --host=localhost:26258

# Look for:
# - is_draining column
# - is_decommissioning column
# - is_available column
```

**Issue: Health check times out**

**Possible Causes:**
- Firewall blocking port 8080
- Node process crashed
- Network issues

**Check:**
```bash
# Check if port is open
telnet localhost 8080

# Check if process is running
ps aux | grep cockroach
```

**Issue: Health check succeeds but queries fail**

**Possible Causes:**
- Health check uses HTTP port (8080)
- SQL connections use different port (26257/26258)
- Firewall allows 8080 but blocks 26257

**Check:**
```bash
# Test SQL connectivity
cockroach sql --certs-dir=certs --host=localhost:26258 --execute="SELECT 1"
```

## Verification Checklist

Healthy cluster shows:
- ✅ All nodes return 200 on `/health`
- ✅ All nodes return 200 on `/health?ready=1`
- ✅ Health checks respond in < 1 second
- ✅ Load balancer shows all backends healthy
- ✅ No draining or decommissioning nodes (unless planned)

## Related Skills

- `monitor-node-liveness-and-health` - Node status checking
- `monitor-gossip-network-health` - Cluster communication
- `configure-load-balancer-health-checks-for-node-maintenance` - HAProxy setup
- `deploy-haproxy-load-balancer-for-cluster` - Load balancer deployment

## Documentation

- Health Endpoints: https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting.html#health-endpoints
- Node Draining: https://www.cockroachlabs.com/docs/stable/node-shutdown.html
- Load Balancing: https://www.cockroachlabs.com/docs/stable/recommended-production-settings.html#load-balancing
