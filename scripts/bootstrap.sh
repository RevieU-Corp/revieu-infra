#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Installing cert-manager..."
kubectl apply -k "$REPO_ROOT/apps/overlays/prod/middleware/cert-manager"

echo "==> Waiting for cert-manager CRDs to be established..."
kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=120s
kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=120s

echo "==> Waiting for cert-manager webhook to be ready..."
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=300s

echo "==> Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD..."
kubectl apply -k "$REPO_ROOT/apps/overlays/prod/apps/argocd"

echo "==> Waiting for ArgoCD CRDs to be established..."
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=60s

echo "==> Waiting for ArgoCD server to be ready..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

echo "==> Applying ArgoCD Applications..."
kubectl apply -f "$REPO_ROOT/argocd/applications/"

echo "==> Bootstrap complete!"
echo ""
echo "To get the initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
