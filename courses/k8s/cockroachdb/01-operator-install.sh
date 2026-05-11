#!/bin/bash
set -euxo pipefail

# Install the CockroachDB Operator (Preview) using Helm
# Usage: ./01-operator-install.sh
#
# This script:
#   1. Installs Helm (if not present)
#   2. Clones the cockroachdb/helm-charts repository
#   3. Installs the cockroach-operator Helm chart

HELM_CHARTS_DIR=${HELM_CHARTS_DIR:-/tmp/helm-charts}

echo "=========================================="
echo "[INFO] Installing CockroachDB Operator (Preview)"
echo "=========================================="

# --- Install Helm if not present ---
if ! command -v helm &>/dev/null; then
    echo "[INFO] Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
echo "[INFO] Helm version: $(helm version --short)"

# --- Clone the helm-charts repository ---
if [ -d "${HELM_CHARTS_DIR}" ]; then
    echo "[INFO] helm-charts repo already exists at ${HELM_CHARTS_DIR}, pulling latest..."
    git -C "${HELM_CHARTS_DIR}" pull --ff-only 2>/dev/null || true
else
    echo "[INFO] Cloning cockroachdb/helm-charts..."
    git clone --depth 1 https://github.com/cockroachdb/helm-charts "${HELM_CHARTS_DIR}"
fi

# --- Install the CockroachDB Operator ---
echo "[INFO] Installing cockroach-operator Helm chart..."
helm install cockroach-operator "${HELM_CHARTS_DIR}/charts/cockroach-operator" \
  --namespace cockroach-operator-system --create-namespace

# Wait for the operator deployment to be available
echo "[INFO] Waiting for CockroachDB Operator to be ready..."
kubectl wait --for=condition=Available deployment -l app.kubernetes.io/name=cockroach-operator \
  -n cockroach-operator-system --timeout=180s

echo "=========================================="
echo "[INFO] CockroachDB Operator installed successfully"
echo "=========================================="
kubectl get pods -n cockroach-operator-system
