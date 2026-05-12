#!/bin/bash
set -euxo pipefail

# Deploy a CockroachDB cluster using the CockroachDB Operator (Preview) + Helm
# Usage: ./02-crdb-cluster-deploy.sh [cockroach-version] [nodes]
# Default: v26.1.3 with 3 nodes

COCKROACH_VER=${1:-${COCKROACH_VER:-v26.1.3}}
CRDB_NODES=${2:-${CRDB_NODES:-3}}
NAMESPACE=${NAMESPACE:-cockroachdb}
HELM_CHARTS_DIR=${HELM_CHARTS_DIR:-/tmp/helm-charts}
REGION_CODE=${REGION_CODE:-us-east1}
CLOUD_PROVIDER=${CLOUD_PROVIDER:-k3d}

# Ensure KUBECONFIG is set (may not be inherited from parent process)
if [ -z "${KUBECONFIG:-}" ]; then
    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    elif [ -f ~/.kube/config ]; then
        export KUBECONFIG=~/.kube/config
    fi
fi

echo "=========================================="
echo "[INFO] Deploying CockroachDB ${COCKROACH_VER} (${CRDB_NODES} nodes)"
echo "=========================================="

# Generate values.yaml
cat <<EOF > /tmp/values.yaml
cockroachdb:
  crdbCluster:
    image:
      name: cockroachdb/cockroach:${COCKROACH_VER}
    dataStore:
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
    regions:
      - code: "${REGION_CODE}"
        nodes: ${CRDB_NODES}
        namespace: ${NAMESPACE}
        cloudProvider: ${CLOUD_PROVIDER}
    podTemplate:
      spec:
        resources:
          requests:
            cpu: "500m"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
    additionalArgs:
      - --cache=25%
      - --max-sql-memory=25%
EOF

echo "[INFO] Generated values.yaml:"
cat /tmp/values.yaml

# Install the CockroachDB cluster via Helm
echo "[INFO] Installing CockroachDB cluster via Helm..."
set +e
for attempt in $(seq 1 30); do
    if helm install cockroachdb "${HELM_CHARTS_DIR}/cockroachdb-parent/charts/cockroachdb" \
      --namespace "${NAMESPACE}" --create-namespace \
      -f /tmp/values.yaml 2>&1; then
        echo "[INFO] Helm install succeeded"
        break
    fi
    echo "[INFO] Waiting for operator to be ready (attempt $attempt/30)..."
    sleep 5
done
set -e

# Wait for all CockroachDB pods to be ready
echo "[INFO] Waiting for CockroachDB pods to be created..."
until kubectl get pods -l app.kubernetes.io/name=cockroachdb -n "${NAMESPACE}" 2>/dev/null | grep -q cockroachdb; do sleep 3; done
echo "[INFO] Waiting for CockroachDB pods to be ready (this may take a few minutes)..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=cockroachdb \
  -n "${NAMESPACE}" --timeout=600s

echo "=========================================="
echo "[INFO] CockroachDB cluster deployed successfully"
echo "=========================================="
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=cockroachdb
echo ""
helm status cockroachdb -n "${NAMESPACE}"
