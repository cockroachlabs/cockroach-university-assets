#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Downloading Kubernetes YAML Manifests"
echo "[INFO] ============================================"

BASE_URL="https://raw.githubusercontent.com/cockroachlabs/cockroach-university-assets/refs/heads/main/courses/k8s/fundamentals/manifests"
DEST_DIR="/root/k8s-labs/manifests"

# Create manifest directories
mkdir -p "$DEST_DIR"/{01-pods,02-deployments,03-services,04-configs,05-storage,06-stateful}

# Function to download a file
download_manifest() {
    local file_path=$1
    local dest_path="$DEST_DIR/$file_path"
    local url="$BASE_URL/$file_path"

    echo "[INFO] Downloading: $file_path"
    if curl -fsSL "$url" -o "$dest_path"; then
        echo "[INFO] ✅ Downloaded: $file_path"
    else
        echo "[WARN] ⚠️  Failed to download: $file_path (may not exist yet)"
    fi
}

# Challenge 01: Pods
echo "[INFO] Downloading Challenge 01 manifests (Pods)..."
download_manifest "01-pods/simple-pod.yaml"
download_manifest "01-pods/multi-container-pod.yaml"
download_manifest "01-pods/broken-pod.yaml"

# Challenge 02: Deployments
echo "[INFO] Downloading Challenge 02 manifests (Deployments)..."
download_manifest "02-deployments/webapp-deployment.yaml"
download_manifest "02-deployments/deployment-v2.yaml"
download_manifest "02-deployments/deployment-resources.yaml"

# Challenge 03: Services
echo "[INFO] Downloading Challenge 03 manifests (Services)..."
download_manifest "03-services/clusterip-service.yaml"
download_manifest "03-services/nodeport-service.yaml"
download_manifest "03-services/headless-service.yaml"

# Challenge 04: ConfigMaps and Secrets
echo "[INFO] Downloading Challenge 04 manifests (Configs)..."
download_manifest "04-configs/configmap-literals.yaml"
download_manifest "04-configs/configmap-file.yaml"
download_manifest "04-configs/secret-generic.yaml"
download_manifest "04-configs/pod-with-config.yaml"

# Challenge 05: Storage
echo "[INFO] Downloading Challenge 05 manifests (Storage)..."
download_manifest "05-storage/pv-hostpath.yaml"
download_manifest "05-storage/pvc.yaml"
download_manifest "05-storage/pod-with-pvc.yaml"

# Challenge 06: StatefulSets
echo "[INFO] Downloading Challenge 06 manifests (StatefulSets)..."
download_manifest "06-stateful/headless-svc.yaml"
download_manifest "06-stateful/statefulset.yaml"
download_manifest "06-stateful/statefulset-nginx.yaml"

echo "[INFO] ============================================"
echo "[INFO] ✅ Manifest download complete!"
echo "[INFO] ============================================"
echo "[INFO] Manifests location: $DEST_DIR"
echo "[INFO] ============================================"
tree "$DEST_DIR" -L 2 2>/dev/null || ls -laR "$DEST_DIR"
echo "[INFO] ============================================"
