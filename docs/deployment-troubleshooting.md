# RevieU Infrastructure 部署故障排查指南

本文档记录了在远程服务器部署 RevieU Infrastructure 过程中遇到的问题、解决方案和注意事项。

## 部署日期
2026-02-01

## 环境信息
- **服务器**: rd.liweijun.com
- **K3s 版本**: v1.34.3+k3s1
- **部署方式**: GitOps (ArgoCD)
- **仓库**: https://github.com/RevieU-Corp/revieu-infra.git

---

## 遇到的问题及解决方案

### 1. Sealed Secret 无法解密

**问题描述**:
```
revieu-auth pod 状态: CreateContainerConfigError
错误信息: secret "revieu-auth-secret" not found
```

查看 SealedSecret 资源状态：
```bash
kubectl describe sealedsecret auth-secrets -n revieu-prod
```

发现错误：
```
Message: no key could decrypt secret (GOOGLE_CLIENT_ID, POSTGRES_DB, ...)
Status: False
Type: Synced
```

**根本原因**:
- SealedSecret 使用公钥加密，只能被对应的 sealed-secrets-controller 私钥解密
- 当前集群的 sealed-secrets-controller 与加密时使用的 controller 不是同一个实例
- 可能原因：集群重建、controller 重新安装、或 secrets 是为其他集群创建的

**解决方案**:
1. **方案 A - 重新加密 secrets（推荐）**:
   ```bash
   # 获取当前 controller 的公钥
   kubeseal --fetch-cert --controller-name=sealed-secrets-controller \
     --controller-namespace=kube-system > pub-cert.pem

   # 使用新公钥重新加密 secrets
   kubectl create secret generic auth-secrets \
     --from-env-file=secrets.env \
     --dry-run=client -o yaml | \
     kubeseal --cert=pub-cert.pem --format=yaml > sealed-auth-secrets.yaml
   ```

2. **方案 B - 恢复原始私钥**:
   如果有原始 controller 的私钥备份，可以恢复到当前集群

**注意事项**:
- ⚠️ 永远不要将未加密的 secrets 提交到 Git
- ⚠️ 每个集群的 sealed-secrets-controller 都有唯一的密钥对
- ⚠️ 重建集群或重装 controller 会导致所有 sealed secrets 失效

---

### 2. Elasticsearch OOMKilled

**问题描述**:
```
elasticsearch-0 状态: CrashLoopBackOff (257 次重启)
Last State: Terminated (Reason: OOMKilled, Exit Code: 137)
```

**根本原因**:
配置不匹配：
- Java heap 配置: `-Xms1g -Xmx1g` (需要 1GB 内存)
- Container 内存限制: `512Mi` (只有 512MB)

**解决方案**:
由于项目已迁移到 Loki，不需要修复。如果需要使用 Elasticsearch：
```yaml
# 方案 1: 减少 Java heap
env:
  - name: ES_JAVA_OPTS
    value: "-Xms256m -Xmx256m"

# 方案 2: 增加容器内存限制
resources:
  limits:
    memory: 2Gi
  requests:
    memory: 1Gi
```

**注意事项**:
- ⚠️ Elasticsearch 至少需要 1GB 内存才能正常运行
- ⚠️ Java heap 大小不应超过容器内存限制的 75%
- ⚠️ 生产环境建议至少 2GB 内存

---

### 3. 缺失 Loki Overlay Kustomization

**问题描述**:
ArgoCD 同步失败，错误信息：
```
ComparisonError: Failed to load target state
Error: accumulating resources from './middleware':
  '<path>/apps/overlays/prod/middleware/loki': no such file or directory
```

**根本原因**:
- `apps/overlays/prod/middleware/kustomization.yaml` 引用了 `loki/`
- 但 `apps/overlays/prod/middleware/loki/` 目录不存在
- Base 层有 loki 定义，但 prod overlay 层缺失

**解决方案**:
创建 overlay kustomization 文件：
```bash
mkdir -p apps/overlays/prod/middleware/loki
```

创建 `apps/overlays/prod/middleware/loki/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../../base/middleware/loki
```

提交并推送：
```bash
git add apps/overlays/prod/middleware/loki/kustomization.yaml
git commit --no-gpg-sign -m "fix: add loki overlay kustomization for prod"
git push origin main
```

**注意事项**:
- ⚠️ Kustomize overlay 必须有对应的目录结构
- ⚠️ 即使不需要 overlay 特定配置，也需要创建引用 base 的 kustomization.yaml
- ⚠️ 在本地测试 kustomize build 确保配置正确

---

### 4. ArgoCD 自动同步未启用

**问题描述**:
- ArgoCD Application 状态显示 `OutOfSync`
- 但没有自动触发同步操作
- 手动刷新也不会触发同步

**根本原因**:
集群中的 Application 资源缺少 `automated` 配置：
```bash
kubectl -n argocd get application revieu-apps -o jsonpath='{.spec.syncPolicy}'
# 输出只有: {"syncOptions": ["CreateNamespace=true"]}
# 缺少: {"automated": {"prune": true, "selfHeal": true}}
```

Git 仓库中的定义是正确的，但集群中的资源与 Git 不同步。

**解决方案**:
从 Git 仓库重新应用 Application 定义：
```bash
cd /root/workspace/repos/revieu-infra
kubectl apply -f argocd/applications/revieu-apps.yaml
```

验证配置已更新：
```bash
kubectl -n argocd get application revieu-apps -o jsonpath='{.spec.syncPolicy}' | jq .
# 应该包含 automated 配置
```

**注意事项**:
- ⚠️ ArgoCD Application 资源本身不由 ArgoCD 管理（除非使用 App of Apps 模式）
- ⚠️ 修改 Application 定义后需要手动 kubectl apply
- ⚠️ 建议使用 `argocd-self-managed` Application 来管理 ArgoCD 自身
- ⚠️ `automated.prune: true` 会自动删除 Git 中不存在的资源

---

## 部署流程总结

### 前置条件
1. K3s 已安装并运行
2. kubectl 已配置
3. Git 仓库已克隆到服务器

### 标准部署步骤

1. **同步仓库**:
   ```bash
   cd /root/workspace/repos/revieu-infra
   git pull origin main
   ```

2. **应用 ArgoCD Applications**:
   ```bash
   kubectl apply -f argocd/applications/
   ```

3. **验证自动同步配置**:
   ```bash
   kubectl -n argocd get application revieu-apps -o jsonpath='{.spec.syncPolicy}' | jq .
   ```

4. **等待自动同步**:
   ```bash
   watch kubectl get applications -n argocd
   ```

5. **检查部署状态**:
   ```bash
   kubectl get pods -n revieu-prod
   kubectl get pods -n logging
   ```

### 验证清单

- [ ] ArgoCD Application 状态为 `Synced`
- [ ] 所有 Pod 状态为 `Running` (除了已知的失败 Pod)
- [ ] Ingress 已创建并有 ADDRESS
- [ ] Certificate 状态为 `Ready`
- [ ] 可以通过域名访问服务

---

## 重要注意事项

### GitOps 原则
✅ **DO**:
- 所有配置变更通过 Git 提交
- 使用 ArgoCD 自动同步
- 在 Git 中记录所有基础设施状态

❌ **DON'T**:
- 不要直接 kubectl edit 修改资源
- 不要手动创建不在 Git 中的资源
- 不要绕过 ArgoCD 直接 kubectl apply

### 故障排查技巧

1. **查看 ArgoCD Application 状态**:
   ```bash
   kubectl -n argocd get application revieu-apps -o yaml
   ```

2. **查看 ArgoCD 同步错误**:
   ```bash
   kubectl -n argocd get application revieu-apps \
     -o jsonpath='{.status.operationState.message}'
   ```

3. **查看 ArgoCD Controller 日志**:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller \
     --tail=100 | grep revieu-apps
   ```

4. **手动触发同步**:
   ```bash
   kubectl -n argocd annotate application revieu-apps \
     argocd.argoproj.io/refresh=normal --overwrite
   ```

5. **查看资源差异**:
   ```bash
   kubectl -n argocd get application revieu-apps \
     -o jsonpath='{.status.sync.comparisonResult}'
   ```

### 常见问题

**Q: 为什么 ArgoCD 显示 OutOfSync 但不自动同步？**
A: 检查 `spec.syncPolicy.automated` 是否配置。如果缺失，重新 apply Application 定义。

**Q: 如何强制 ArgoCD 重新同步？**
A: 添加 refresh annotation 或在 ArgoCD UI 中点击 "Refresh"。

**Q: Pod 一直 Pending 怎么办？**
A: 检查 PVC 是否正常创建，节点资源是否充足。

**Q: Certificate 一直不 Ready？**
A: 检查域名 DNS 解析，确保 80/443 端口开放，查看 cert-manager 日志。

---

## 参考资源

- [ArgoCD 官方文档](https://argo-cd.readthedocs.io/)
- [Sealed Secrets 文档](https://github.com/bitnami-labs/sealed-secrets)
- [Kustomize 文档](https://kustomize.io/)
- [K3s 文档](https://docs.k3s.io/)

---

## 更新日志

- 2026-02-01: 初始版本，记录首次部署遇到的问题和解决方案
