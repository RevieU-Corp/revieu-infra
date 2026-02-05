# Root App 工作流程可视化

## 🎬 完整部署流程

```
第 0 步：你的操作
═══════════════════════════════════════════════════════════════
$ kubectl apply -f argocd/root/root-app-prod.yaml
```

```
第 1 步：ArgoCD 创建 Root App 对象
═══════════════════════════════════════════════════════════════
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                          │
│                                                             │
│  argocd namespace:                                          │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Application: root-app-prod                         │    │
│  │ Status: Syncing...                                 │    │
│  └────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

```
第 2 步：Root App 扫描 Git 仓库
═══════════════════════════════════════════════════════════════
ArgoCD 去 GitHub 读取两个目录：

📁 argocd/platform/prod/
   ├── 📄 platform-apps.yaml         ← 找到！
   ├── 📄 infra-foundation.yaml      ← 找到！
   ├── 📄 infra-core.yaml            ← 找到！
   └── 📄 infra-observability.yaml   ← 找到！

📁 argocd/applications/prod/
   ├── 📄 application-apps.yaml      ← 找到！
   ├── 📄 argocd.yaml                ← 找到！
   ├── 📄 web.yaml                   ← 找到！
   └── 📄 core.yaml                  ← 找到！

总共找到 8 个 Application 定义文件
```

```
第 3 步：Root App 创建子 Application 对象
═══════════════════════════════════════════════════════════════
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                          │
│                                                             │
│  argocd namespace:                                          │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Application: root-app-prod                         │    │
│  │ Status: Healthy & Synced ✅                        │    │
│  └───────────────────┬────────────────────────────────┘    │
│                      │                                      │
│         ┌────────────┴────────────┐                        │
│         │                         │                        │
│         ▼                         ▼                        │
│  ┌──────────────┐          ┌──────────────┐               │
│  │ Platform     │          │ Application  │               │
│  │ 子 Apps (4个) │          │ 子 Apps (4个) │               │
│  └──────┬───────┘          └──────┬───────┘               │
│         │                         │                        │
│    ┌────┼────┐              ┌─────┼─────┐                 │
│    ▼    ▼    ▼              ▼     ▼     ▼                 │
│  [App] [App] [App] [App]  [App] [App] [App] [App]        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

```
第 4 步：子 Applications 部署实际资源
═══════════════════════════════════════════════════════════════
每个子 Application 根据自己的配置，部署实际的 K8s 资源：

┌─────────────────────────────────────────────────────────────┐
│ Platform Apps 开始部署                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Wave 0: infra-foundation-prod                               │
│   └─> 部署到各个 namespace                                   │
│       ├── cert-manager (namespace: cert-manager)            │
│       │   ├── Deployment: cert-manager                      │
│       │   ├── Deployment: cert-manager-webhook              │
│       │   └── Service: cert-manager                         │
│       └── sealed-secrets (namespace: kube-system)           │
│           └── Controller: sealed-secrets-controller         │
│                                                             │
│ Wave 1: infra-core-prod                                     │
│   └─> 部署到 revieu-prod namespace                          │
│       ├── Namespace: revieu-prod                            │
│       ├── ClusterIssuer: letsencrypt-prod                   │
│       └── Certificate: revieu-cert                          │
│                                                             │
│ Wave 2: infra-observability-prod                            │
│   └─> 部署到各个 namespace                                   │
│       ├── loki (namespace: logging)                         │
│       ├── grafana (namespace: logging)                      │
│       ├── fluent-bit (namespace: logging)                   │
│       └── traefik (namespace: kube-system)                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Application Apps 开始部署                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Wave 10: argocd-self-prod                                   │
│   └─> 部署到 argocd namespace                               │
│       └── ArgoCD 自身配置                                    │
│                                                             │
│ Wave 11: revieu-web-prod                                    │
│   └─> 部署到 revieu-prod namespace                          │
│       ├── Deployment: revieu-web                            │
│       ├── Service: revieu-web                               │
│       └── Ingress: revieu-web-ingress                       │
│                                                             │
│ Wave 11: revieu-core-prod                                   │
│   └─> 部署到 revieu-prod namespace                          │
│       ├── Deployment: revieu-core                           │
│       ├── Service: revieu-core                              │
│       └── Ingress: revieu-core-ingress                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

```
第 5 步：最终状态
═══════════════════════════════════════════════════════════════
┌─────────────────────────────────────────────────────────────┐
│ ArgoCD UI 显示                                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Applications (9 个)                                         │
│                                                             │
│ 🟢 root-app-prod              Healthy | Synced              │
│   └─ 🟢 platform-apps-prod    Healthy | Synced              │
│       └─ 🟢 infra-foundation-prod    Healthy | Synced       │
│       └─ 🟢 infra-core-prod          Healthy | Synced       │
│       └─ 🟢 infra-observability-prod Healthy | Synced       │
│   └─ 🟢 application-apps-prod       Healthy | Synced        │
│       └─ 🟢 argocd-self-prod         Healthy | Synced       │
│       └─ 🟢 revieu-web-prod          Healthy | Synced       │
│       └─ 🟢 revieu-core-prod         Healthy | Synced       │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Resources                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Namespaces:                                                 │
│   - argocd                (ArgoCD 本身)                     │
│   - cert-manager          (证书管理)                         │
│   - logging               (日志和监控)                       │
│   - revieu-prod           (业务应用)                         │
│                                                             │
│ Pods (总共约 20+ 个):                                       │
│   cert-manager-xxx          Running                         │
│   cert-manager-webhook-xxx  Running                         │
│   sealed-secrets-xxx        Running                         │
│   loki-xxx                  Running                         │
│   grafana-xxx               Running                         │
│   fluent-bit-xxx            Running                         │
│   traefik-xxx               Running                         │
│   argocd-server-xxx         Running                         │
│   argocd-repo-server-xxx    Running                         │
│   revieu-web-xxx            Running (3 replicas)            │
│   revieu-core-xxx           Running (3 replicas)            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 🔄 自愈流程示例

```
场景：有人手动删除了 revieu-web 的 Pod
═══════════════════════════════════════════════════════════════

时间轴：
00:00 - 某人运行: kubectl delete pod revieu-web-xxx
00:00 - Pod 被删除 ❌
00:01 - Deployment controller 发现 Pod 少了
00:01 - Deployment 自动创建新 Pod ✅
00:03 - ArgoCD 定期检查 (默认每 3 分钟)
00:03 - ArgoCD 发现状态一致 ✅
00:03 - 无需操作

═══════════════════════════════════════════════════════════════

场景：有人手动修改了 revieu-web 的副本数
═══════════════════════════════════════════════════════════════

时间轴：
00:00 - 某人运行: kubectl scale deployment revieu-web --replicas=10
00:00 - 副本数从 3 变成 10 ⚠️
00:03 - ArgoCD 定期检查
00:03 - ArgoCD 发现: 实际副本数(10) ≠ Git配置(3)
00:03 - ArgoCD 触发同步 (因为 selfHeal: true)
00:03 - 副本数恢复为 3 ✅
00:03 - ArgoCD 状态: Healthy & Synced

═══════════════════════════════════════════════════════════════
```

## 🗑️ 删除流程

```
如果你删除 Root App，会发生什么？
═══════════════════════════════════════════════════════════════

$ kubectl delete application root-app-prod -n argocd

因为有 finalizer，删除顺序是：

第 1 步：删除所有子 Application
  ├─ 删除 revieu-core-prod
  │  └─ 等待 revieu-core Deployment 被删除
  ├─ 删除 revieu-web-prod
  │  └─ 等待 revieu-web Deployment 被删除
  ├─ 删除 argocd-self-prod
  ├─ 删除 infra-observability-prod
  │  └─ 等待 loki, grafana, traefik 被删除
  ├─ 删除 infra-core-prod
  │  └─ 等待 ClusterIssuer, Certificate 被删除
  └─ 删除 infra-foundation-prod
     └─ 等待 cert-manager 被删除

第 2 步：确认所有资源清理完毕

第 3 步：最后删除 root-app-prod 本身

结果：整个环境被干净地删除 ✅

═══════════════════════════════════════════════════════════════
```

## 💡 关键要点

1. **Root App 不直接部署资源**
   - 它只创建和管理 Application 对象
   - 实际资源由子 Application 部署

2. **层次清晰**
   ```
   Root App (1 个)
     └─ 子 Applications (8 个)
          └─ 实际 K8s 资源 (几十个)
   ```

3. **安全机制**
   - `prune: false` 防止误删所有 App
   - `finalizer` 确保删除时级联清理
   - `selfHeal: true` 自动恢复配置

4. **一键部署**
   - 只需部署一个 Root App YAML
   - ArgoCD 自动处理剩余的一切

5. **环境隔离**
   - 三个 Root App 结构相同
   - 只是指向不同的配置目录
   - 互不干扰
