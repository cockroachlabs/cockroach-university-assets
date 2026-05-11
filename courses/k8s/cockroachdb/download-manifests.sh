#!/bin/bash
set -euxo pipefail

# Download all CockroachDB on K8s course manifests from GitHub
# Usage: ./download-manifests.sh [destination-dir]

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/courses/k8s/cockroachdb/manifests"
DEST_DIR=${1:-/root/k8s-labs/cockroachdb}

echo "=========================================="
echo "[INFO] Downloading CockroachDB K8s manifests"
echo "[INFO] Destination: ${DEST_DIR}"
echo "=========================================="

# Create directory structure
mkdir -p "${DEST_DIR}"/{01-wrong-way,02-discovery,03-storage,04-operator,05-security,06-multi-region,07-performance,08-monitoring}

download_manifest() {
    local file_path=$1
    local dest_path="${DEST_DIR}/${file_path}"
    local url="${BASE_URL}/${file_path}"

    echo "[INFO] Downloading: ${file_path}"
    if curl -fsSL "${url}" -o "${dest_path}"; then
        echo "[INFO] Downloaded: ${file_path}"
    else
        echo "[WARN] Failed to download: ${file_path} (may not exist yet)"
    fi
}

# 01-wrong-way: Why Deployments don't work for CockroachDB
download_manifest "01-wrong-way/crdb-deployment.yaml"

# 02-discovery: Headless service and DNS discovery (manual Pods + PVCs)
download_manifest "02-discovery/crdb-headless-svc.yaml"
download_manifest "02-discovery/crdb-manual-pods.yaml"

# 03-storage: PVCs and StorageClasses
download_manifest "03-storage/storageclass.yaml"
download_manifest "03-storage/crdb-pvc.yaml"

# 04-operator: Helm values.yaml files (replaces old CrdbCluster CRD manifests)
download_manifest "04-operator/values.yaml"
download_manifest "04-operator/values-6node.yaml"

# 05-security: TLS, NetworkPolicies, secure client
download_manifest "05-security/network-policy.yaml"
download_manifest "05-security/client-pod-secure.yaml"

# 06-multi-region: Multi-region Helm values
download_manifest "06-multi-region/values-multi-region.yaml"

# 07-performance: Resource-tuned Helm values
download_manifest "07-performance/values-resources.yaml"

# 08-monitoring: Prometheus, Grafana, backup
download_manifest "08-monitoring/service-monitor.yaml"
download_manifest "08-monitoring/prometheus-rules.yaml"
download_manifest "08-monitoring/backup-cronjob.yaml"

echo "=========================================="
echo "[INFO] Download complete"
echo "=========================================="
tree "${DEST_DIR}" 2>/dev/null || ls -laR "${DEST_DIR}"
