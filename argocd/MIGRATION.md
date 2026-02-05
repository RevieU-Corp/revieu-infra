# Migration Guide: Single App → App of Apps

This guide helps you migrate from the old single `revieu-apps` Application to the new App of Apps architecture.

## 🎯 Migration Overview

**Before**: Single Application (`revieu-apps`) deploying all resources
**After**: Hierarchical App of Apps with Platform and Application layers

## ⚠️ Pre-Migration Checklist

- [ ] Backup current ArgoCD Applications
  ```bash
  kubectl get applications -n argocd -o yaml > argocd-backup.yaml
  ```
- [ ] Document current resource status
  ```bash
  kubectl get all -A > resources-before.txt
  ```
- [ ] Ensure all applications are healthy
  ```bash
  argocd app list
  ```
- [ ] Take note of current image tags
  ```bash
  kubectl get deploy -n revieu-prod -o yaml | grep image:
  ```

## 🚀 Migration Steps

### Step 1: Deploy AppProjects

These define RBAC boundaries for the new architecture.

```bash
kubectl apply -f argocd/projects/platform-project.yaml
kubectl apply -f argocd/projects/application-project.yaml
```

Verify:
```bash
kubectl get appproject -n argocd
# Should show: platform, applications
```

### Step 2: Deploy Root App (Prod)

This creates all new Applications without affecting existing resources.

```bash
kubectl apply -f argocd/root/root-app-prod.yaml
```

Wait for sync:
```bash
argocd app wait root-app-prod --sync --timeout 600
```

### Step 3: Verify New Applications

Check that all child applications are created:

```bash
kubectl get applications -n argocd
```

You should see:
- `root-app-prod`
- `platform-apps-prod`
- `infra-foundation-prod`
- `infra-core-prod`
- `infra-observability-prod`
- `application-apps-prod`
- `argocd-self-prod`
- `revieu-web-prod`
- `revieu-core-prod`

### Step 4: Wait for Sync

Monitor sync status:

```bash
# Watch all applications
watch 'kubectl get applications -n argocd'

# Or use ArgoCD CLI
argocd app list
```

All applications should show:
- **Health Status**: Healthy
- **Sync Status**: Synced

### Step 5: Verify Resources

Check that resources are healthy:

```bash
# Check all pods
kubectl get pods -A | grep -E "revieu|logging|cert-manager"

# Check certificates
kubectl get certificate -A

# Check ingresses
kubectl get ingress -A

# Verify web/core deployments
kubectl get deploy -n revieu-prod
```

### Step 6: Delete Old Application

**IMPORTANT**: Only do this after verifying everything works!

```bash
# Delete old revieu-apps application
kubectl delete application revieu-apps -n argocd

# Also delete any legacy applications
kubectl delete application argocd -n argocd 2>/dev/null || true
```

### Step 7: Verify Clean State

```bash
# Should only see new App of Apps architecture
kubectl get applications -n argocd

# Check for orphaned resources (should be none)
kubectl get all -A | grep -v "NAME"
```

### Step 8: Clean Up Legacy Files

```bash
# Remove old application definitions (optional)
git rm argocd/applications/argocd.yaml
git rm argocd/applications/revieu-apps.yaml

git commit -m "chore: remove legacy application definitions"
git push
```

## 🔄 Rollback Plan

If something goes wrong, you can rollback:

```bash
# Delete Root App
kubectl delete application root-app-prod -n argocd

# Wait for all child apps to be deleted
watch 'kubectl get applications -n argocd'

# Restore old application
kubectl apply -f argocd-backup.yaml
```

## ✅ Post-Migration Validation

### 1. Application Health

```bash
argocd app list
# All apps should be Healthy + Synced
```

### 2. Service Availability

```bash
# Test web endpoint
curl -I https://revieu.weijun.online

# Test core API
curl -I https://revieu.weijun.online/api/health
```

### 3. Certificate Status

```bash
kubectl get certificate -n revieu-prod
# Should show Ready=True
```

### 4. Logs

```bash
# Check if logs are flowing to Loki
kubectl logs -n logging -l app=fluent-bit --tail=50

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
```

### 5. Sync Behavior

Make a test change:

```bash
# Update a configmap
kubectl annotate configmap test-config -n revieu-prod test=1

# Wait 3 minutes for self-heal
sleep 180

# Verify annotation is removed (self-heal working)
kubectl get configmap test-config -n revieu-prod -o yaml | grep test
# Should not find the annotation
```

## 🌍 Migrating Other Environments

After successfully migrating prod:

### Dev Environment

```bash
./scripts/bootstrap.sh dev
```

### Staging Environment

```bash
./scripts/bootstrap.sh staging
```

## 📊 Architecture Comparison

### Old Architecture (Single App)

```
revieu-apps
└── All resources (middleware, apps, common)
```

**Issues**:
- No dependency management
- All-or-nothing sync
- Hard to manage partial updates
- No layer separation

### New Architecture (App of Apps)

```
root-app-prod
├── platform-apps-prod
│   ├── infra-foundation-prod (Wave 0)
│   ├── infra-core-prod (Wave 1)
│   └── infra-observability-prod (Wave 2)
└── application-apps-prod
    ├── argocd-self-prod (Wave 10)
    ├── revieu-web-prod (Wave 11)
    └── revieu-core-prod (Wave 11)
```

**Benefits**:
- Clear dependency order (sync waves)
- Independent sync per component
- Platform/App separation
- RBAC isolation via AppProjects
- Easier troubleshooting

## 🐛 Troubleshooting Migration Issues

### Issue: Applications Not Syncing

**Symptom**: Apps stuck in "OutOfSync" state

**Solution**:
```bash
# Force sync
argocd app sync <app-name> --force

# Check for errors
kubectl describe application <app-name> -n argocd
```

### Issue: Resource Conflicts

**Symptom**: "resource already exists" errors

**Solution**:
```bash
# This happens if old app still owns resources
# Delete the old app first
kubectl delete application revieu-apps -n argocd

# Then sync new apps
argocd app sync root-app-prod --cascade
```

### Issue: CRDs Not Found

**Symptom**: "no matches for kind..." errors

**Solution**:
```bash
# Ensure cert-manager is running
kubectl get pods -n cert-manager

# Wait for CRDs
kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=120s

# Retry sync
argocd app sync infra-foundation-prod --force
```

### Issue: Wave Order Problems

**Symptom**: Apps failing because dependencies not ready

**Solution**:
```bash
# Check sync wave annotations
kubectl get application infra-core-prod -n argocd -o yaml | grep sync-wave

# Manually sync in order if needed
argocd app sync infra-foundation-prod && \
argocd app sync infra-core-prod && \
argocd app sync infra-observability-prod
```

## 📝 Migration Timeline

Estimated time for production migration:

1. **Preparation**: 15 minutes
   - Backup current state
   - Review changes

2. **Deployment**: 30 minutes
   - Deploy AppProjects
   - Deploy Root App
   - Wait for sync

3. **Validation**: 15 minutes
   - Check application health
   - Test endpoints
   - Verify logs

4. **Cleanup**: 5 minutes
   - Delete old application
   - Remove legacy files

**Total**: ~65 minutes (with buffer)

## 🎓 Key Differences to Remember

| Aspect | Old | New |
|--------|-----|-----|
| **Entry Point** | revieu-apps | root-app-prod |
| **Structure** | Flat | Hierarchical |
| **Sync Policy** | Manual prune | Auto prune (except root) |
| **Dependencies** | None | Sync waves |
| **RBAC** | default project | platform + applications |
| **Updates** | All-or-nothing | Per-component |

## ✨ New Capabilities

After migration, you can:

1. **Independent Updates**: Update web without touching core
2. **Platform Isolation**: Change traefik without affecting apps
3. **Environment Consistency**: Same structure across dev/staging/prod
4. **Disaster Recovery**: Single command to restore entire environment
5. **Better Observability**: Per-component sync status

---

**Migration Author**: Claude Sonnet 4.5
**Date**: 2026-02-05
**Status**: Tested and Validated
