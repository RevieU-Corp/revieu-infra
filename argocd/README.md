# RevieU-Infra App of Apps Architecture

This repository implements an **App of Apps** pattern for ArgoCD on a single cluster, with shared platform components and separate dev/staging/prod application roots.

## 🏗️ Architecture Overview

```
Root App (shared platform)
└── Platform Apps
    ├── infra-foundation-shared (Wave 0: cert-manager)
    ├── infra-sealed-secrets-shared (Wave 0: sealed-secrets)
    ├── infra-core-shared (Wave 1: shared DNS secret)
    ├── infra-observability-shared (Wave 2: loki/grafana/fluent-bit)
    └── argocd-self-shared (Wave 10: ArgoCD self-management)

Root App (per environment)
└── Application Apps (business + env common)
    ├── revieu-common-<env> (Wave 9: namespace/cert/issuer)
    ├── revieu-web-<env> (Wave 11)
    └── revieu-core-<env> (Wave 11)
```

## 📂 Directory Structure

```
revieu-infra/
├── argocd/
│   ├── root/                          # Root applications (entry points)
│   │   ├── root-app-platform.yaml
│   │   ├── root-app-dev.yaml
│   │   ├── root-app-staging.yaml
│   │   └── root-app-prod.yaml
│   │
│   ├── platform/                      # Platform infrastructure apps
│   │   └── shared/
│   │
│   ├── applications/                  # Business applications
│   │   ├── dev/
│   │   │   ├── common.yaml            # Wave 9
│   │   │   ├── web.yaml               # Wave 11
│   │   │   └── core.yaml              # Wave 11
│   │   ├── staging/
│   │   └── prod/
│   │
│   └── projects/                      # AppProject RBAC definitions
│       ├── platform-project.yaml
│       └── application-project.yaml
│
├── apps/
│   ├── base/                          # Base Kubernetes manifests
│   │   ├── common/                    # Namespace, ClusterIssuer, Certificate
│   │   ├── infrastructure/            # cert-manager, sealed-secrets, logging, traefik middleware
│   │   └── applications/              # ArgoCD, web, core
│   │
│   └── overlays/                      # Environment-specific configs
│       ├── dev/
│       │   ├── common/
│       │   ├── infrastructure/
│       │   └── applications/{web,core,argocd}/
│       ├── staging/
│       ├── prod/
│       └── shared/
│
└── scripts/
    └── bootstrap.sh                   # Multi-environment bootstrap script
```

## 🚀 Deployment

### Bootstrap a New Environment

```bash
# Deploy production environment
curl -sfL https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/scripts/bootstrap.sh | bash -s prod

# Deploy staging environment
curl -sfL https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/scripts/bootstrap.sh | bash -s staging

# Deploy development environment
curl -sfL https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/scripts/bootstrap.sh | bash -s dev
```

The bootstrap script will:
1. Install cert-manager
2. Install ArgoCD
3. Create AppProjects (platform and applications)
4. Deploy the shared platform root app
5. Deploy the root app for the specified environment
6. ArgoCD will automatically deploy all child applications

### Access ArgoCD UI

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser to https://localhost:8080
```

## 🔄 Sync Waves

Applications deploy in the following order:

- **Wave 0**: Shared foundation (cert-manager, sealed-secrets)
- **Wave 1**: Shared core secrets
- **Wave 2**: Shared observability
- **Wave 9**: Environment common resources (namespace, ClusterIssuer, Certificate)
- **Wave 10**: ArgoCD self-management
- **Wave 11**: Environment applications (web, core)

## 🌍 Environment Configuration

| Configuration | Dev | Staging | Prod |
|--------------|-----|---------|------|
| **Namespace** | revieu-dev | revieu-staging | revieu-prod |
| **Domain** | dev.revieu.weijun.online | staging.revieu.weijun.online | revieu.weijun.online |
| **Cert Issuer** | Let's Encrypt Staging | Let's Encrypt Staging | Let's Encrypt Prod |
| **Web Replicas** | 1 | 2 | 3 |
| **Core Replicas** | 1 | 2 | 3 |
| **Image Tag** | dev-latest | staging-latest | sha-\<commit\> |
| **Memory (Web)** | 256Mi | 512Mi | 1Gi |
| **Memory (Core)** | 512Mi | 1Gi | 2Gi |

## 📦 AppProjects

Two AppProjects provide RBAC isolation:

### Platform Project
- **Scope**: Infrastructure components
- **Permissions**: Full cluster access
- **Components**: cert-manager, loki, grafana, sealed-secrets, env common

### Applications Project
- **Scope**: Business applications
- **Permissions**: Limited to revieu-* namespaces
- **Components**: web, core

## 🔐 Sync Policies

### Root Apps
- `automated.prune: false` - Prevents accidental deletion of all child apps
- `automated.selfHeal: true` - Auto-corrects drift

### Child Apps (Platform & Applications)
- `automated.prune: true` - Removes resources not in Git
- `automated.selfHeal: true` - Auto-corrects drift
- Retry backoff for transient failures

## 🎯 Key Features

✅ **GitOps First**: All changes via Git commits
✅ **Multi-Environment**: Dev, Staging, Prod support
✅ **Layered Architecture**: Clear separation of Platform vs Applications
✅ **Sync Waves**: Ordered deployment with dependency management
✅ **Self-Healing**: Automatic drift correction
✅ **RBAC Isolation**: AppProjects enforce least privilege
✅ **Disaster Recovery**: Shared platform root + env root can restore the full stack

## 🔧 Managing the Stack

### View All Applications
```bash
kubectl get applications -n argocd
```

### Sync All Applications
```bash
argocd app sync root-app-platform --cascade
argocd app sync root-app-prod --cascade
```

### Delete an Environment
```bash
# WARNING: This deletes everything
kubectl delete -f argocd/root/root-app-prod.yaml
```

### Update Application Image
```bash
# Edit the kustomization.yaml in the appropriate overlay
cd apps/overlays/prod/applications/web
# Edit kustomization.yaml to change newTag
git commit -m "Update web image to new-tag"
git push
# ArgoCD will automatically detect and deploy
```

## 🛡️ Best Practices

1. **Never modify resources directly**: Always use Git
2. **Test in dev first**: Validate changes before promoting to prod
3. **Use sync waves**: Ensure proper deployment order
4. **Monitor ArgoCD UI**: Check for sync errors
5. **Review diffs**: Before syncing, review what will change

## 📚 References

- [ArgoCD App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Kustomize Overlays](https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#overlay)

## 🚨 Troubleshooting

### Application Stuck Syncing
```bash
# Check application status
argocd app get <app-name>

# View sync status
kubectl describe application <app-name> -n argocd

# Force refresh
argocd app sync <app-name> --force
```

### CRD Issues
```bash
# Ensure cert-manager CRDs exist
kubectl get crd | grep cert-manager

# Ensure ArgoCD CRDs exist
kubectl get crd | grep argoproj
```

### Certificate Not Ready
```bash
# Check certificate status
kubectl get certificate -A

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

---

**Implementation Date**: 2026-02-05
**Architecture Pattern**: App of Apps (3-tier)
**Environments**: dev, staging, prod
