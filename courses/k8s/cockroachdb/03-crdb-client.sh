#!/bin/bash
set -euxo pipefail

# Deploy a CockroachDB SQL client pod with TLS certificates
# Usage: ./03-crdb-client.sh [namespace]

NAMESPACE=${1:-${NAMESPACE:-default}}

echo "=========================================="
echo "[INFO] Deploying CockroachDB SQL client pod"
echo "=========================================="

# Create the client pod that mounts the TLS client secret
echo "[INFO] Creating SQL client pod..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: Pod
metadata:
  name: cockroachdb-client
  labels:
    app: cockroachdb-client
spec:
  containers:
    - name: cockroachdb-client
      image: cockroachdb/cockroach:v24.3.5
      command:
        - sleep
        - "infinity"
      volumeMounts:
        - name: client-certs
          mountPath: /cockroach/cockroach-certs
          readOnly: true
  terminationGracePeriodSeconds: 0
  volumes:
    - name: client-certs
      projected:
        sources:
          - secret:
              name: cockroachdb-node
              items:
                - key: ca.crt
                  path: ca.crt
          - secret:
              name: cockroachdb-root
              items:
                - key: tls.crt
                  path: client.root.crt
                - key: tls.key
                  path: client.root.key
        defaultMode: 0400
EOF

# Wait for client pod to be ready
echo "[INFO] Waiting for client pod to be ready..."
kubectl wait --for=condition=Ready pod/cockroachdb-client -n "${NAMESPACE}" --timeout=120s

echo "=========================================="
echo "[INFO] SQL client pod is ready"
echo "[INFO] Connect with:"
echo "  kubectl exec -it cockroachdb-client -- cockroach sql --certs-dir=/cockroach/cockroach-certs --host=cockroachdb-public"
echo "=========================================="
