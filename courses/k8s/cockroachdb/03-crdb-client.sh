#!/bin/bash
set -euxo pipefail

# Deploy a CockroachDB SQL client pod with TLS certificates
# Uses the selfSigner-generated resources:
#   - cockroachdb-ca-secret-crt   (ConfigMap with CA certificate)
#   - cockroachdb-client-secret   (Secret with root client cert + key)
#
# Usage: ./03-crdb-client.sh [namespace]

NAMESPACE=${1:-${NAMESPACE:-cockroachdb}}

echo "=========================================="
echo "[INFO] Deploying CockroachDB SQL client pod"
echo "=========================================="

# Wait for the client Secret to exist
echo "[INFO] Waiting for client certificate Secret..."
until kubectl get secret cockroachdb-client-secret -n "${NAMESPACE}" &>/dev/null; do sleep 3; done

# Wait for the CA ConfigMap to exist
echo "[INFO] Waiting for CA certificate ConfigMap..."
until kubectl get configmap cockroachdb-ca-secret-crt -n "${NAMESPACE}" &>/dev/null; do sleep 3; done

# Create the client pod that mounts TLS certs from both ConfigMap and Secret
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
      image: us-docker.pkg.dev/cockroach-cloud-images/cockroachdb/cockroach:v26.1.3
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
          - configMap:
              name: cockroachdb-ca-secret-crt
              items:
                - key: ca.crt
                  path: ca.crt
          - secret:
              name: cockroachdb-client-secret
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
echo "  kubectl exec -it cockroachdb-client -n ${NAMESPACE} -- cockroach sql --certs-dir=/cockroach/cockroach-certs --host=cockroachdb-public"
echo "=========================================="
