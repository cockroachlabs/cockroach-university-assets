#!/bin/bash
set -euxo pipefail

# Install the CockroachDB Kubernetes Operator (v2)
# Usage: ./01-operator-install.sh [operator-version]
# Default operator version: 2.18.2

OPERATOR_VER=${1:-${OPERATOR_VER:-2.18.2}}

echo "=========================================="
echo "[INFO] Installing CockroachDB Operator v${OPERATOR_VER}"
echo "=========================================="

# Apply the CRDs
echo "[INFO] Applying CockroachDB Operator CRDs..."
kubectl apply -f "https://raw.githubusercontent.com/cockroachdb/cockroach-operator/v${OPERATOR_VER}/install/crds.yaml"

# Apply the operator deployment (includes ServiceAccount, ClusterRole, ClusterRoleBinding, Deployment)
echo "[INFO] Applying CockroachDB Operator deployment..."
kubectl apply -f "https://raw.githubusercontent.com/cockroachdb/cockroach-operator/v${OPERATOR_VER}/install/operator.yaml"

# Wait for the operator deployment to be available
echo "[INFO] Waiting for CockroachDB Operator to be available..."
kubectl wait --for=condition=Available deployment/cockroach-operator-manager \
  -n cockroach-operator-system --timeout=180s

echo "=========================================="
echo "[INFO] CockroachDB Operator v${OPERATOR_VER} installed successfully"
echo "=========================================="
kubectl get pods -n cockroach-operator-system
