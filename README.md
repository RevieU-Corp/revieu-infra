# RevieU-Infra

GitOps infrastructure for RevieU platform using ArgoCD, K3s, and Kustomize.

## Architecture

- **K3s**: Lightweight Kubernetes distribution
- **ArgoCD**: GitOps continuous deployment
- **Cert-Manager**: Automatic TLS certificate management
- **Traefik**: Ingress controller
- **Sealed Secrets**: Encrypted secrets management
- **Multi-environment**: dev/staging/prod

## ⚠️ Important: Multi-Node Setup

If you have a multi-node cluster with nodes connected via VPN (e.g., WireGuard), you **MUST** configure K3s properly **before** installation, or pods on different nodes won't be able to communicate.

**See [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md) for complete setup instructions.**

## Quick Start

### Prerequisites

1. **K3s cluster** with proper network configuration
2. **WireGuard VPN** (for multi-node setups)
3. **PostgreSQL database**
4. **kubectl** with cluster access

### Network Validation (Multi-Node Only)

**Before bootstrapping**, verify your network configuration:

```bash
./scripts/check-network.sh
```

This checks:
- ✓ Flannel is using VPN interface (not public interface)
- ✓ Cross-node pod communication works
- ✓ No networking issues

### Bootstrap

Deploy the infrastructure:

```bash
# For production
./scripts/bootstrap.sh prod

# For dev/staging
./scripts/bootstrap.sh dev
./scripts/bootstrap.sh staging
```

### Access ArgoCD UI

```bash
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open: https://localhost:8080
# Username: admin
```

## Repository Structure

```
revieu-infra/
├── apps/
│   ├── base/                    # Base manifests
│   │   ├── common/             # Namespace, ClusterIssuer, Certificate
│   │   ├── middleware/         # Traefik, Loki, Grafana, etc.
│   │   └── apps/               # Web, Core applications
│   └── overlays/               # Environment-specific configs
│       ├── dev/
│       ├── staging/
│       └── prod/
│
├── argocd/
│   ├── root/                   # Root Applications
│   ├── platform/               # Infrastructure apps (per environment)
│   ├── applications/           # Business apps (per environment)
│   └── projects/               # AppProjects (RBAC)
│
├── scripts/
│   ├── bootstrap.sh            # Main bootstrap script
│   └── check-network.sh        # Network validation
│
└── docs/
    └── DEPLOYMENT.md           # Complete deployment guide
```

## Common Issues & Solutions

### Gateway Timeout accessing backend

**Symptom**: API returns Gateway Timeout

**Cause**: Cross-node pod communication failure (flannel using wrong interface)

**Fix**:
```bash
# Check flannel configuration
ip -d link show flannel.1

# If it shows "dev eth0" instead of "dev wg0":

# 1. Update K3s config on each node
echo "flannel-iface: wg0" | sudo tee /etc/rancher/k3s/config.yaml

# 2. Delete old flannel interface
sudo ip link delete flannel.1

# 3. Restart K3s
sudo systemctl restart k3s          # control plane
sudo systemctl restart k3s-agent    # workers

# 4. Verify
ip -d link show flannel.1  # Should show "local 10.0.0.x dev wg0"
```

### ArgoCD stuck syncing

**Cause**: NetworkPolicy blocking egress

**Fix**: Bootstrap script auto-patches this. If issues persist:
```bash
kubectl patch networkpolicy argocd-server-network-policy -n argocd \
  --type=json -p='[
    {"op": "add", "path": "/spec/policyTypes/-", "value": "Egress"},
    {"op": "add", "path": "/spec/egress", "value": [{}]}
  ]'
```

### Certificate not ready

```bash
kubectl describe certificate -n revieu-prod revieu-cert
kubectl logs -n cert-manager -l app=cert-manager
```

## Documentation

- **[DEPLOYMENT.md](./docs/DEPLOYMENT.md)** - Complete deployment guide with all prerequisites
- **[MEMORY.md](./.claude/projects/-home-wayne-workspace-repos-revieu-infra/memory/MEMORY.md)** - Lessons learned and troubleshooting

## Sealed Secrets

Sensitive data is encrypted using Sealed Secrets:

**Backend secrets workflow**:
```bash
cd revieu-backend

# 1. Edit plaintext secrets (gitignored)
vim apps/core/configs/secrets.yaml

# 2. Encrypt
./scripts/seal-secrets.sh

# 3. Commit encrypted version
git add apps/core/configs/sealed-secrets.yaml
git commit -m "Update secrets"

# 4. Update infra repo reference
cd revieu-infra
# Edit apps/overlays/prod/apps/core/kustomization.yaml
# Update sealed-secrets URL to new commit SHA
```

## CI/CD Workflow

1. **Build** new image: `ghcr.io/revieu-corp/revieu-core:sha-<commit>`
2. **Update** `apps/overlays/ENV/apps/*/kustomization.yaml` with new tag
3. **Commit** and push
4. **ArgoCD** auto-deploys

## Multi-Environment Strategy

| Environment | Namespace | Domain | Certificates | Replicas |
|------------|-----------|--------|--------------|----------|
| dev | revieu-dev | dev.revieu.weijun.online | LE Staging | 1 |
| staging | revieu-staging | staging.revieu.weijun.online | LE Staging | 2 |
| prod | revieu-prod | revieu.weijun.online | LE Production | 3 |

## Architecture Decisions

See [MEMORY.md](./.claude/projects/-home-wayne-workspace-repos-revieu-infra/memory/MEMORY.md):
- Why flannel needs VPN interface configuration
- NetworkPolicy egress requirements
- Sealed Secrets workflow
- GitOps principles

## Contributing

1. Create feature branch
2. Test in dev environment
3. PR to main
4. Auto-deploy to staging/prod after merge

## License

Proprietary - RevieU Corp
