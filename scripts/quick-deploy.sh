#!/bin/bash
# RevieU Infrastructure Quick Deploy Script
# 可以直接从网络运行: curl -fsSL <url> | bash

set -e

REPO_URL="https://github.com/RevieU-Corp/revieu-infra.git"
TEMP_DIR="/tmp/revieu-infra-deploy-$$"

echo "======================================"
echo "RevieU Infrastructure Quick Deploy"
echo "======================================"
echo ""

# 检查是否已安装 kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install K3s first:"
    echo "   curl -sfL https://get.k3s.io | sh -"
    echo "   mkdir -p ~/.kube"
    echo "   sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config"
    echo "   sudo chown \$(id -u):\$(id -g) ~/.kube/config"
    exit 1
fi

echo "✓ kubectl found"

# 检查集群连接
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    echo "   Please check your kubeconfig"
    exit 1
fi

echo "✓ Connected to Kubernetes cluster"
echo ""

# 克隆仓库到临时目录
echo "==> Cloning repository..."
git clone --depth 1 "$REPO_URL" "$TEMP_DIR"
cd "$TEMP_DIR"

echo ""
echo "==> Installing cert-manager..."
kubectl apply -k "$TEMP_DIR/apps/overlays/prod/middleware/cert-manager"

echo ""
echo "==> Waiting for cert-manager CRDs to be established..."
kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=120s
kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=120s

echo ""
echo "==> Waiting for cert-manager webhook to be ready..."
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=300s

echo ""
echo "==> Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Installing ArgoCD..."
kubectl apply -k "$TEMP_DIR/apps/overlays/prod/apps/argocd"

echo ""
echo "==> Waiting for ArgoCD CRDs to be established..."
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=60s

echo ""
echo "==> Waiting for ArgoCD server to be ready..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

echo ""
echo "==> Applying ArgoCD Applications..."
kubectl apply -f "$TEMP_DIR/argocd/applications/"

echo ""
echo "==> Cleaning up temporary files..."
cd ~
rm -rf "$TEMP_DIR"

echo ""
echo "======================================"
echo "✅ Bootstrap complete!"
echo "======================================"
echo ""
echo "ArgoCD will now automatically sync all resources from GitHub."
echo ""
echo "To check deployment status:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -A"
echo ""
echo "To get the ArgoCD admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "To access ArgoCD UI (port-forward):"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then visit: https://localhost:8080"
echo ""
