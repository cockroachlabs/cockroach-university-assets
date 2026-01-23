#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Creating Kubernetes Lab Directory Structure"
echo "[INFO] ============================================"

# Create lab directories
echo "[INFO] Creating directories in /root/k8s-labs/..."
mkdir -p /root/k8s-labs/{manifests,pods,deployments,services,configs,storage,stateful}

# Create a README in the lab directory
cat > /root/k8s-labs/README.md << 'EOF'
# Kubernetes Fundamentals Lab Resources

This directory contains resources for the Kubernetes Fundamentals track.

## Directory Structure

- `manifests/` - Example YAML manifests downloaded from GitHub
- `pods/` - Working directory for pod exercises
- `deployments/` - Working directory for deployment exercises
- `services/` - Working directory for service exercises
- `configs/` - Working directory for ConfigMap and Secret exercises
- `storage/` - Working directory for storage exercises
- `stateful/` - Working directory for StatefulSet exercises

## Quick Tips

Use `kubectl apply -f <file>` to create resources from YAML manifests.
Use `kubectl get all` to see all resources in the current namespace.
Use `kubectl describe <resource> <name>` to get detailed information.

Happy learning!
EOF

echo "[INFO] ============================================"
echo "[INFO] ✅ Lab directory structure created!"
echo "[INFO] ============================================"
tree /root/k8s-labs/ -L 1 2>/dev/null || ls -la /root/k8s-labs/
echo "[INFO] ============================================"
