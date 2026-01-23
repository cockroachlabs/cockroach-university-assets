#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Installing K3s Kubernetes Distribution"
echo "[INFO] ============================================"

# Install K3s with kubeconfig accessible to all users
echo "[INFO] Downloading and installing K3s..."
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Wait for K3s to be ready
echo "[INFO] Waiting for K3s to be ready..."
sleep 10

# Set kubeconfig for current session
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Add kubeconfig to bashrc for persistence
if ! grep -q "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ~/.bashrc; then
    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
fi

# Verify installation
echo "[INFO] Verifying K3s installation..."
kubectl version --short 2>/dev/null || kubectl version

# Wait for node to be ready
echo "[INFO] Waiting for node to be ready..."
kubectl wait --for=condition=Ready node --all --timeout=120s

# Display cluster info
echo "[INFO] ============================================"
echo "[INFO] K3s Installation Complete!"
echo "[INFO] ============================================"
kubectl get nodes
echo "[INFO] ============================================"
echo "[INFO] Cluster Components:"
kubectl get pods -A
echo "[INFO] ============================================"
echo "[INFO] ✅ K3s is ready for use!"
echo "[INFO] ============================================"
