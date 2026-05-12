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

# Label K8s nodes with topology labels so the operator can map the region.
# Cloud providers (GKE/EKS/AKS) set these automatically, but K3s does not.
echo "[INFO] Labeling nodes with topology region=${REGION_CODE}..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl label node "$node" \
        topology.kubernetes.io/region="${REGION_CODE}" \
        topology.kubernetes.io/zone="${REGION_CODE}-a" \
        --overwrite
done

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
        topologySpreadConstraints:
          - maxSkew: 1
            topologyKey: topology.kubernetes.io/zone
            whenUnsatisfiable: ScheduleAnyway
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
# Uses upgrade --install for idempotent retries (plain "helm install" fails
# with "cannot re-use a name" if a previous attempt left a failed release).
echo "[INFO] Installing CockroachDB cluster via Helm..."
set +e
for attempt in $(seq 1 30); do
    if helm upgrade --install cockroachdb "${HELM_CHARTS_DIR}/cockroachdb-parent/charts/cockroachdb" \
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
# Retry the wait — on single-node K3s, cluster formation can be slow under resource pressure.
# The operator initializes pods sequentially (certs, init, join) so later pods take longer.
set +e
for wait_attempt in $(seq 1 3); do
    if kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=cockroachdb \
      -n "${NAMESPACE}" --timeout=300s 2>&1; then
        echo "[INFO] All CockroachDB pods are ready"
        break
    fi
    echo "[INFO] Not all pods ready yet (attempt $wait_attempt/3), current status:"
    kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=cockroachdb
    if [ "$wait_attempt" -eq 3 ]; then
        echo "[ERROR] CockroachDB pods did not become ready within 900s"
        kubectl describe pods -n "${NAMESPACE}" -l app.kubernetes.io/name=cockroachdb | tail -30
        exit 1
    fi
    sleep 10
done
set -e

echo "=========================================="
echo "[INFO] CockroachDB cluster deployed successfully"
echo "=========================================="
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=cockroachdb
echo ""
helm status cockroachdb -n "${NAMESPACE}"
