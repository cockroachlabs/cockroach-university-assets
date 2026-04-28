#!/bin/bash
set -euxo pipefail

# Deploy a CockroachDB cluster using the CockroachDB Operator
# Usage: ./02-crdb-cluster-deploy.sh [cockroach-version] [nodes]
# Default: v26.1.3 with 3 nodes

COCKROACH_VER=${1:-${COCKROACH_VER:-v26.1.3}}
CRDB_NODES=${2:-${CRDB_NODES:-3}}
NAMESPACE=${NAMESPACE:-default}

echo "=========================================="
echo "[INFO] Deploying CockroachDB ${COCKROACH_VER} (${CRDB_NODES} nodes)"
echo "=========================================="

# Wait for the CRD to be fully registered
echo "[INFO] Waiting for CrdbCluster CRD to be established..."
kubectl wait --for=condition=Established crd/crdbclusters.crdb.cockroachlabs.com --timeout=60s

# Write the CrdbCluster manifest to a temp file
cat <<EOF > /tmp/crdbcluster.yaml
apiVersion: crdb.cockroachlabs.com/v1alpha1
kind: CrdbCluster
metadata:
  name: cockroachdb
spec:
  dataStore:
    pvc:
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
        volumeMode: Filesystem
  resources:
    requests:
      cpu: "500m"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
  tlsEnabled: true
  image:
    name: cockroachdb/cockroach:${COCKROACH_VER}
  nodes: ${CRDB_NODES}
  additionalArgs:
    - --cache=25%
    - --max-sql-memory=25%
EOF

# Apply with retry — the operator webhook may need a few seconds after the pod is ready
echo "[INFO] Applying CrdbCluster resource..."
set +e
for attempt in $(seq 1 30); do
    if kubectl apply -n "${NAMESPACE}" -f /tmp/crdbcluster.yaml 2>&1; then
        echo "[INFO] CrdbCluster resource applied successfully"
        break
    fi
    echo "[INFO] Waiting for operator webhook to be ready (attempt $attempt/30)..."
    sleep 5
done
set -e
rm -f /tmp/crdbcluster.yaml

# Wait for all CockroachDB pods to be ready
echo "[INFO] Waiting for CockroachDB pods to be created..."
until kubectl get pods -l app.kubernetes.io/name=cockroachdb -n "${NAMESPACE}" 2>/dev/null | grep -q cockroachdb; do sleep 3; done
echo "[INFO] Waiting for CockroachDB pods to be ready (this may take a few minutes)..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=cockroachdb \
  -n "${NAMESPACE}" --timeout=600s

# Wait for the CrdbCluster to report initialized
echo "[INFO] Waiting for CrdbCluster to initialize..."
kubectl wait --for=condition=Initialized crdbcluster/cockroachdb \
  -n "${NAMESPACE}" --timeout=600s || true

echo "=========================================="
echo "[INFO] CockroachDB cluster deployed successfully"
echo "=========================================="
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=cockroachdb
echo ""
kubectl get crdbcluster -n "${NAMESPACE}"
