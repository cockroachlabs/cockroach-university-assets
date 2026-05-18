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

# Ensure KUBECONFIG is set (may not be inherited from parent process)
if [ -z "${KUBECONFIG:-}" ]; then
    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    elif [ -f ~/.kube/config ]; then
        export KUBECONFIG=~/.kube/config
    fi
fi

REGION_CODE=${REGION_CODE:-us-east1}

echo "=========================================="
echo "[INFO] Installing CockroachDB Operator (Preview)"
echo "=========================================="

# Wait for Kubernetes API to be reachable
echo "[INFO] Waiting for Kubernetes API..."
for i in $(seq 1 30); do
    if kubectl cluster-info &>/dev/null; then
        echo "[INFO] Kubernetes API is ready."
        break
    fi
    echo "[INFO] Attempt $i/30 - API not ready, waiting 5s..."
    sleep 5
done
kubectl cluster-info || { echo "[ERROR] Kubernetes API unreachable after 150s"; exit 1; }

# Label K8s nodes with topology labels BEFORE installing the operator.
# The operator's admission webhook reads node labels at startup to build
# its valid regions map. Without labels, the webhook rejects all region codes.
echo "[INFO] Labeling nodes with topology region=${REGION_CODE}..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl label node "$node" \
        topology.kubernetes.io/region="${REGION_CODE}" \
        topology.kubernetes.io/zone="${REGION_CODE}-a" \
        --overwrite
done

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
helm install cockroach-operator "${HELM_CHARTS_DIR}/cockroachdb-parent/charts/operator" \
  --namespace cockroach-operator-system --create-namespace \
  --set numReplicas=1

# Wait for the operator deployment to be available
echo "[INFO] Waiting for CockroachDB Operator deployment to be available..."
kubectl wait --for=condition=Available deployment --all \
  -n cockroach-operator-system --timeout=180s

# The Deployment Available condition can pass before the pod object exists.
# Wait for at least one pod to appear, then wait for it to be Ready.
echo "[INFO] Waiting for operator pod to exist..."
until kubectl get pods -l app=cockroach-operator -n cockroach-operator-system --no-headers 2>/dev/null | grep -q .; do
    sleep 2
done
echo "[INFO] Waiting for operator pod to be ready..."
kubectl wait --for=condition=Ready pods -l app=cockroach-operator \
  -n cockroach-operator-system --timeout=300s

# Verify the CRD is registered (the operator registers it at startup)
echo "[INFO] Waiting for CrdbCluster CRD to be registered..."
for crd_attempt in $(seq 1 40); do
    if kubectl get crd crdbclusters.crdb.cockroachlabs.com &>/dev/null; then
        echo "[INFO] CrdbCluster CRD is available"
        break
    fi
    if [ "$crd_attempt" -eq 40 ]; then
        echo "[ERROR] CrdbCluster CRD not registered after 120s"
        exit 1
    fi
    sleep 3
done

echo "=========================================="
echo "[INFO] CockroachDB Operator installed successfully"
echo "=========================================="
kubectl get pods -n cockroach-operator-system
