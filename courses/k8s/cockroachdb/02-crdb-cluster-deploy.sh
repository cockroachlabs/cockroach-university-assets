#!/bin/bash
set -euxo pipefail

# Deploy a CockroachDB cluster using the CockroachDB Operator
# Usage: ./02-crdb-cluster-deploy.sh [cockroach-version] [nodes]
# Default: v24.3.5 with 3 nodes

COCKROACH_VER=${1:-${COCKROACH_VER:-v24.3.5}}
CRDB_NODES=${2:-${CRDB_NODES:-3}}
NAMESPACE=${NAMESPACE:-default}

echo "=========================================="
echo "[INFO] Deploying CockroachDB ${COCKROACH_VER} (${CRDB_NODES} nodes)"
echo "=========================================="

# Wait for the CRD to be fully registered
echo "[INFO] Waiting for CrdbCluster CRD to be established..."
kubectl wait --for=condition=Established crd/crdbclusters.crdb.cockroachlabs.com --timeout=60s

# Apply the CrdbCluster manifest
echo "[INFO] Applying CrdbCluster resource..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
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
