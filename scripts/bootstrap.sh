#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main"
ENVIRONMENT="${1:-prod}"  # 默认 prod，可传参 dev/staging/prod

echo "==> Bootstrapping environment: $ENVIRONMENT"

# 1. 安装 cert-manager (前置依赖)
echo "==> Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml

echo "==> Waiting for cert-manager CRDs..."
kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=120s
kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=120s

echo "==> Waiting for cert-manager webhook..."
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=300s

# 2. 安装 ArgoCD
echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for ArgoCD CRDs..."
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=120s

echo "==> Patching ArgoCD NetworkPolicies to allow egress traffic..."
# 修复：ArgoCD默认NetworkPolicy只定义Ingress，会阻止所有Egress（DNS、API访问等）
for np in argocd-application-controller-network-policy \
           argocd-applicationset-controller-network-policy \
           argocd-dex-server-network-policy \
           argocd-notifications-controller-network-policy \
           argocd-redis-network-policy \
           argocd-repo-server-network-policy \
           argocd-server-network-policy; do
  kubectl patch networkpolicy "$np" -n argocd --type=json -p='[
    {"op": "add", "path": "/spec/policyTypes/-", "value": "Egress"},
    {"op": "add", "path": "/spec/egress", "value": [{}]}
  ]' 2>/dev/null || echo "NetworkPolicy $np not found, skipping..."
done

echo "==> Waiting for ArgoCD server..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

# 3. 创建 AppProjects
echo "==> Creating AppProjects..."
kubectl apply -f $REPO_URL/argocd/projects/platform-project.yaml
kubectl apply -f $REPO_URL/argocd/projects/application-project.yaml

# 4. 部署 Root Application
echo "==> Deploying Root Application for $ENVIRONMENT..."
kubectl apply -f $REPO_URL/argocd/root/root-app-$ENVIRONMENT.yaml

echo "==> Bootstrap complete for $ENVIRONMENT!"
echo ""
echo "To get the initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
