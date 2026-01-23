#!/bin/bash
set -euxo pipefail

echo "[INFO] ============================================"
echo "[INFO] Setting up kubectl aliases and completion"
echo "[INFO] ============================================"

# Add kubectl aliases to bashrc
if ! grep -q "alias k=kubectl" ~/.bashrc; then
    echo "[INFO] Adding kubectl aliases..."
    cat >> ~/.bashrc << 'EOF'

# Kubectl aliases
alias k=kubectl
alias kgp="kubectl get pods"
alias kgs="kubectl get services"
alias kgd="kubectl get deployments"
alias kgn="kubectl get nodes"
alias kga="kubectl get all"
alias kdp="kubectl describe pod"
alias kds="kubectl describe service"
alias kdd="kubectl describe deployment"
alias kl="kubectl logs"
alias kex="kubectl exec -it"
alias ka="kubectl apply -f"
alias kd="kubectl delete"
EOF
fi

# Add kubectl bash completion
echo "[INFO] Setting up kubectl bash completion..."
kubectl completion bash >> ~/.bashrc

echo "[INFO] ============================================"
echo "[INFO] ✅ kubectl aliases and completion configured!"
echo "[INFO] ============================================"
echo "[INFO] Available aliases:"
echo "[INFO]   k      = kubectl"
echo "[INFO]   kgp    = kubectl get pods"
echo "[INFO]   kgs    = kubectl get services"
echo "[INFO]   kgd    = kubectl get deployments"
echo "[INFO]   kgn    = kubectl get nodes"
echo "[INFO]   kga    = kubectl get all"
echo "[INFO]   kdp    = kubectl describe pod"
echo "[INFO]   kds    = kubectl describe service"
echo "[INFO]   kdd    = kubectl describe deployment"
echo "[INFO]   kl     = kubectl logs"
echo "[INFO]   kex    = kubectl exec -it"
echo "[INFO]   ka     = kubectl apply -f"
echo "[INFO]   kd     = kubectl delete"
echo "[INFO] ============================================"
