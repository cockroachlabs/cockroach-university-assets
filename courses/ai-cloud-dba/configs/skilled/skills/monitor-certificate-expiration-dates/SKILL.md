---
name: monitor-certificate-expiration-dates
description: Check certificate expiration using cockroach cert list. Monitor node, client, and CA certificates. Alert when certificates expire within 30 days. Automate rotation procedures.
metadata:
  domain: Monitoring and Alerting
  bloom_level: Apply
  version: 1.1.0
  cockroachdb_version: v26.1.0+
  status: active
---

# Monitor Certificate Expiration Dates

**Domain**: Monitoring and Alerting
**Bloom's Level**: Apply
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

You will learn to monitor certificate expiration dates in CockroachDB clusters, create automated alerting systems, and implement certificate rotation procedures. This skill covers checking node, client, and CA certificates using the `cockroach cert list` command, establishing 30-day alert thresholds, and automating monitoring workflows.

Certificate expiration is critical. Expired certificates cause cluster outages, failed connections, and authentication errors that proper monitoring prevents.

## Prerequisites

- Access to CockroachDB certificate directory (typically `/certs`)
- `cockroach` binary installed
- Basic understanding of TLS/SSL certificates
- Ability to run shell scripts

## Core Concepts

**CA Certificate (ca.crt)** - Root authority signing all certificates. Expiration causes complete cluster failure.

**Node Certificates (node.crt)** - Enable inter-node communication. Expiration causes node isolation.

**Client Certificates (client.*.crt)** - User authentication. Expiration prevents connections.

**Lifecycle**: Creation → Active → Warning (30d) → Expiration → Disruption

## Instructions

### Step 1: Check Certificate Expiration Manually

**List all certificates:**

```bash
cockroach cert list --certs-dir=/certs

# Output shows:
# Usage  | Certificate File |    Key File    |  Expires   |  Notes
# -------+------------------+----------------+------------+----------
# CA     | ca.crt           |                | 2027/01/15 |
# Node   | node.crt         | node.key       | 2026/04/20 | expires in 45 days
# Client | client.root.crt  | client.root.key| 2026/03/25 | expires in 19 days
```

**Check specific directory:**

```bash
cockroach cert list --certs-dir=/var/lib/cockroach/certs
```

### Step 2: Parse Certificate Expiration Programmatically

**Check specific certificate with openssl:**

```bash
# Check CA certificate expiration
openssl x509 -in /certs/ca.crt -noout -enddate
# Output: notAfter=Jan 15 10:23:45 2027 GMT

# Check node certificate
openssl x509 -in /certs/node.crt -noout -enddate

# Check client certificate
openssl x509 -in /certs/client.root.crt -noout -enddate
```

**Calculate days until expiration:**

```bash
#!/bin/bash
CERT_FILE="/certs/node.crt"
EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_REMAINING=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

echo "Certificate expires in $DAYS_REMAINING days"
```

### Step 3: Create Automated Monitoring Script

**Complete monitoring script (monitor_certs.sh):**

```bash
#!/bin/bash
# CockroachDB Certificate Expiration Monitor

set -euo pipefail

CERTS_DIR="${CERTS_DIR:-/certs}"
ALERT_THRESHOLD_DAYS="${ALERT_THRESHOLD_DAYS:-30}"
ALERT_EMAIL="${ALERT_EMAIL:-ops@example.com}"
LOG_FILE="${LOG_FILE:-/var/log/cockroach/cert-monitor.log}"

get_days_remaining() {
    local cert_file="$1"
    [[ ! -f "$cert_file" ]] && echo "0" && return 1

    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    echo $(( ($expiry_epoch - $current_epoch) / 86400 ))
}

check_certificate() {
    local cert_name="$1"
    local cert_file="$2"
    local days_remaining=$(get_days_remaining "$cert_file")

    echo "$(date -Iseconds) INFO: $cert_name expires in $days_remaining days" | tee -a "$LOG_FILE"

    if [[ $days_remaining -le 0 ]]; then
        echo "$(date -Iseconds) CRITICAL: $cert_name EXPIRED!" | tee -a "$LOG_FILE"
        echo "CRITICAL: $cert_name has expired!" | mail -s "CERT EXPIRED: $cert_name" "$ALERT_EMAIL"
        return 2
    elif [[ $days_remaining -le $ALERT_THRESHOLD_DAYS ]]; then
        echo "$(date -Iseconds) WARNING: $cert_name expires in $days_remaining days" | tee -a "$LOG_FILE"
        echo "Certificate $cert_name expires in $days_remaining days" | mail -s "CERT EXPIRING: $cert_name" "$ALERT_EMAIL"
        return 1
    fi
    return 0
}

main() {
    echo "$(date -Iseconds) INFO: Starting certificate check (threshold: $ALERT_THRESHOLD_DAYS days)" | tee -a "$LOG_FILE"

    local exit_code=0

    # Check CA certificate
    [[ -f "$CERTS_DIR/ca.crt" ]] && check_certificate "ca.crt" "$CERTS_DIR/ca.crt" || exit_code=$?

    # Check node certificate
    [[ -f "$CERTS_DIR/node.crt" ]] && check_certificate "node.crt" "$CERTS_DIR/node.crt" || exit_code=$?

    # Check client certificates
    for cert in "$CERTS_DIR"/client.*.crt; do
        [[ -f "$cert" ]] && check_certificate "$(basename "$cert")" "$cert" || exit_code=$?
    done

    echo "$(date -Iseconds) INFO: Certificate check complete" | tee -a "$LOG_FILE"
    return $exit_code
}

main
```

**Make executable and run:**

```bash
chmod +x monitor_certs.sh

# Run with defaults
./monitor_certs.sh

# Run with custom settings
CERTS_DIR=/var/lib/cockroach/certs ALERT_THRESHOLD_DAYS=45 ./monitor_certs.sh
```

### Step 4: Schedule Automated Monitoring

**Add to crontab for daily checks:**

```bash
crontab -e

# Check daily at 9 AM
0 9 * * * /usr/local/bin/monitor_certs.sh

# Or check every 6 hours
0 */6 * * * CERTS_DIR=/certs /usr/local/bin/monitor_certs.sh
```

**Using systemd timer (alternative):**

Create `/etc/systemd/system/cockroach-cert-monitor.service`:

```ini
[Unit]
Description=CockroachDB Certificate Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor_certs.sh
Environment="CERTS_DIR=/certs"
Environment="ALERT_THRESHOLD_DAYS=30"
User=cockroach
```

Create `/etc/systemd/system/cockroach-cert-monitor.timer`:

```ini
[Unit]
Description=Run CockroachDB Certificate Monitor Daily

[Timer]
OnCalendar=daily
OnCalendar=09:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cockroach-cert-monitor.timer
sudo systemctl list-timers cockroach-cert-monitor.timer
```

### Step 5: Export Metrics for Monitoring Systems

**Prometheus metrics exporter:**

```bash
#!/bin/bash
# Export certificate expiration metrics

CERTS_DIR="${CERTS_DIR:-/certs}"
METRICS_FILE="/var/lib/node_exporter/textfile_collector/cockroach_certs.prom"

get_days_remaining() {
    local cert_file="$1"
    [[ ! -f "$cert_file" ]] && echo "-1" && return
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    echo $(( ($expiry_epoch - $current_epoch) / 86400 ))
}

cat > "$METRICS_FILE.tmp" <<EOF
# HELP cockroachdb_cert_expiry_days Days until certificate expiration
# TYPE cockroachdb_cert_expiry_days gauge
EOF

# Export metrics for each certificate
[[ -f "$CERTS_DIR/ca.crt" ]] && \
    echo "cockroachdb_cert_expiry_days{cert=\"ca\",type=\"CA\"} $(get_days_remaining "$CERTS_DIR/ca.crt")" >> "$METRICS_FILE.tmp"

[[ -f "$CERTS_DIR/node.crt" ]] && \
    echo "cockroachdb_cert_expiry_days{cert=\"node\",type=\"node\"} $(get_days_remaining "$CERTS_DIR/node.crt")" >> "$METRICS_FILE.tmp"

for cert in "$CERTS_DIR"/client.*.crt; do
    [[ -f "$cert" ]] && {
        cert_name=$(basename "$cert" .crt | sed 's/client\.//')
        echo "cockroachdb_cert_expiry_days{cert=\"$cert_name\",type=\"client\"} $(get_days_remaining "$cert")" >> "$METRICS_FILE.tmp"
    }
done

mv "$METRICS_FILE.tmp" "$METRICS_FILE"
```

**Prometheus alert rules:**

```yaml
# /etc/prometheus/rules/cockroachdb_certs.yml
groups:
  - name: cockroachdb_certificates
    interval: 1h
    rules:
      - alert: CertificateExpiringSoon
        expr: cockroachdb_cert_expiry_days < 30
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Certificate {{ $labels.cert }} expiring soon"
          description: "{{ $labels.cert }} ({{ $labels.type }}) expires in {{ $value }} days"

      - alert: CertificateExpiryCritical
        expr: cockroachdb_cert_expiry_days < 7
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Certificate {{ $labels.cert }} expiring very soon"
          description: "{{ $labels.cert }} expires in {{ $value }} days - rotate immediately"

      - alert: CertificateExpired
        expr: cockroachdb_cert_expiry_days <= 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Certificate {{ $labels.cert }} EXPIRED"
          description: "{{ $labels.cert }} has expired - service disruption likely"
```

### Step 6: Certificate Rotation Procedures

**Generate new certificates:**

```bash
# CA cert (10 years)
cockroach cert create-ca --certs-dir=/certs/new --ca-key=/certs/new/ca.key --lifetime=87600h

# Node cert (1 year)
cockroach cert create-node localhost $(hostname) --certs-dir=/certs/new --ca-key=/certs/ca.key --lifetime=8760h

# Client cert (1 year)
cockroach cert create-client root --certs-dir=/certs/new --ca-key=/certs/ca.key --lifetime=8760h

# Backup old certs
cp /certs/*.crt /certs/backup/
```

**Rolling rotation script:**

```bash
#!/bin/bash
NODES=("node1" "node2" "node3")
for node in "${NODES[@]}"; do
    scp /certs/new/* "$node:/certs/new/"
    ssh "$node" "sudo mv /certs/new/* /certs/ && sudo systemctl restart cockroach"
    sleep 30
    cockroach node status --certs-dir=/certs --host="$node:26257"
done
```

## Common Patterns

**Multi-Threshold Alerts**: Escalate based on days remaining (30d: info, 14d: warning, 7d: critical, 3d: emergency).

**Multi-Cluster Monitoring**: Loop through cluster directories, run monitoring script for each.

**Inventory Reports**: Generate periodic reports with expiration dates for all certificates.

## Troubleshooting

### Permission Denied Errors

**Issue**: Cannot read certificate directory.

**Solution**: Run with appropriate user or fix permissions.

```bash
# Run as cockroach user
sudo -u cockroach cockroach cert list --certs-dir=/certs

# Fix permissions
sudo chmod 755 /certs
sudo chmod 644 /certs/*.crt
```

### Incorrect Days Remaining Calculation

**Issue**: Date parsing differs between Linux/macOS.

**Solution**: Use portable date handling.

```bash
# Portable date parsing
if date --version >/dev/null 2>&1; then
    # GNU date (Linux)
    expiry_epoch=$(date -d "$expiry_date" +%s)
else
    # BSD date (macOS)
    expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s)
fi
```

### Alerts Not Sending

**Issue**: Mail command not configured.

**Solution**: Test alert mechanism and add logging.

```bash
# Test email
echo "Test" | mail -s "Test" ops@example.com

# Add debug logging
alert_expiring() {
    echo "DEBUG: Sending alert for $1" >&2
    # ... alert code
}
```

### Connection Failures After Rotation

**Issue**: Certificate mismatch after replacement.

**Solution**: Verify certificates before deployment.

```bash
# Verify new cert is signed by CA
openssl verify -CAfile /certs/new/ca.crt /certs/new/node.crt

# Test before deployment
cockroach cert list --certs-dir=/certs/new

# Perform rolling restart one node at a time
```

## Best Practices

**Set Multiple Alert Thresholds**
- 30 days: Initial warning, plan rotation
- 14 days: Schedule maintenance window
- 7 days: Critical alert, execute rotation
- 3 days: Emergency page

**Automate Certificate Generation**
- Use consistent lifetimes (1 year for node/client, 10 years for CA)
- Include all DNS names and IPs in node certificates
- Store CA key securely offline

**Maintain Certificate Inventory**
- Document all certificates and locations
- Track generation and rotation history
- Keep backups of all certificates

**Test Rotation Procedures**
- Practice in non-production first
- Document step-by-step procedures
- Verify monitoring detects test expirations

**Monitor Continuously**
- Check certificates at least daily
- Export metrics to monitoring system
- Create expiration timeline dashboards

**Secure Certificate Storage**
- Restrict directory access (chmod 700)
- Encrypt private keys at rest
- Use HSM for CA keys in production

## Related Skills

- **generate-node-certificates-for-cluster-nodes**: Create node certificates
- **create-certificate-authority-ca-for-cluster**: Set up CA
- **manage-certificate-lifecycle-and-rotation**: Full rotation procedures
- **configure-tls-encryption**: Initial TLS setup
- **set-up-alerting-rules-for-critical-conditions**: Alert configuration

## Summary

Monitor certificate expiration using `cockroach cert list` for manual checks and automated scripts for continuous monitoring. Implement 30-day alert thresholds with escalating notifications. Use Prometheus metrics and systemd timers for production monitoring. Practice certificate rotation procedures regularly to prevent unexpected outages. Expired certificates cause complete cluster failures - proactive monitoring is essential.
