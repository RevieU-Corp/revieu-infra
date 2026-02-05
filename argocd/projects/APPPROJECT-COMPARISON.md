# AppProject 权限对比表

## 🎨 可视化对比

### 架构图：AppProject 如何控制 Application

```
┌─────────────────────────────────────────────────────────────────┐
│                         ArgoCD                                  │
│                                                                 │
│  ┌────────────────────┐              ┌────────────────────┐   │
│  │ Platform Project   │              │ Applications       │   │
│  │ (高权限)            │              │ Project (低权限)    │   │
│  │                    │              │                    │   │
│  │ ✅ 所有 namespace   │              │ ✅ revieu-*         │   │
│  │ ✅ 所有资源类型     │              │ ✅ 业务资源类型      │   │
│  │ ✅ 集群级别操作     │              │ ❌ 集群级别操作      │   │
│  └────────┬───────────┘              └────────┬───────────┘   │
│           │                                   │               │
│           │                                   │               │
│    ┌──────┴────────┐                   ┌──────┴────────┐     │
│    │               │                   │               │     │
│    ▼               ▼                   ▼               ▼     │
│  ┌──────┐      ┌──────┐            ┌──────┐      ┌──────┐   │
│  │ App1 │      │ App2 │            │ App3 │      │ App4 │   │
│  └──┬───┘      └──┬───┘            └──┬───┘      └──┬───┘   │
│     │             │                   │             │       │
└─────┼─────────────┼───────────────────┼─────────────┼───────┘
      │             │                   │             │
      ▼             ▼                   ▼             ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│                                                             │
│  cert-manager    kube-system    revieu-prod    argocd      │
│     (✅)            (✅)            (✅✅)         (✅✅)       │
│                                                             │
│  Platform Apps  Platform Apps  Platform+Apps  Platform+Apps│
│  可以访问        可以访问         都可以访问      都可以访问    │
└─────────────────────────────────────────────────────────────┘

图例：
✅ = 该 Project 可以访问
✅✅ = 两个 Project 都可以访问
```

---

## 📊 详细权限对比表

### Namespace 访问权限

| Namespace | Platform Project | Applications Project | 说明 |
|-----------|-----------------|---------------------|------|
| `cert-manager` | ✅ | ❌ | 证书管理器，只有基础设施团队能操作 |
| `kube-system` | ✅ | ❌ | K8s 核心组件，只有基础设施团队能操作 |
| `logging` | ✅ | ❌ | 日志系统，只有基础设施团队能操作 |
| `revieu-dev` | ✅ | ✅ | 开发环境，两个团队都能操作 |
| `revieu-staging` | ✅ | ✅ | 预发布环境，两个团队都能操作 |
| `revieu-prod` | ✅ | ✅ | 生产环境，两个团队都能操作 |
| `argocd` | ✅ | ✅ | ArgoCD 自身，两个团队都能操作 |
| `random-namespace` | ❌ | ❌ | 未定义的 namespace，都不能操作 |

---

### 集群级别资源权限

| 资源类型 | Platform | Applications | 用途 |
|---------|----------|--------------|------|
| `CustomResourceDefinition` | ✅ | ❌ | 自定义资源定义 (如 cert-manager 的 Certificate) |
| `ClusterRole` | ✅ | ❌ | 集群角色 (跨 namespace 权限) |
| `ClusterRoleBinding` | ✅ | ❌ | 集群角色绑定 |
| `PersistentVolume` | ✅ | ❌ | 持久化存储卷 (集群级别) |
| `StorageClass` | ✅ | ❌ | 存储类 |
| `IngressClass` | ✅ | ❌ | Ingress 类 |
| `Namespace` | ✅ | ✅ | Namespace 创建（业务也需要） |
| `ValidatingWebhookConfiguration` | ✅ | ❌ | Webhook 配置 |
| `MutatingWebhookConfiguration` | ✅ | ❌ | Webhook 配置 |

---

### Namespace 级别资源权限

| 资源类型 | Platform | Applications | 用途 |
|---------|----------|--------------|------|
| **计算资源** ||||
| `Deployment` | ✅ | ✅ | 无状态应用部署 |
| `StatefulSet` | ✅ | ✅ | 有状态应用部署 |
| `DaemonSet` | ✅ | ❌ | 守护进程 (通常是系统级别) |
| `Job` | ✅ | ❌ | 任务 |
| `CronJob` | ✅ | ❌ | 定时任务 |
| **网络资源** ||||
| `Service` | ✅ | ✅ | 服务 |
| `Ingress` | ✅ | ✅ | 入口规则 |
| `IngressRoute` (Traefik) | ✅ | ✅ | Traefik 路由 |
| `Middleware` (Traefik) | ✅ | ✅ | Traefik 中间件 |
| `NetworkPolicy` | ✅ | ❌ | 网络策略 |
| **存储资源** ||||
| `PersistentVolumeClaim` | ✅ | ❌ | 存储声明 |
| **配置资源** ||||
| `ConfigMap` | ✅ | ✅ | 配置映射 |
| `Secret` | ✅ | ✅ | 密钥 |
| `SealedSecret` | ✅ | ✅ | 加密密钥 |
| **证书资源** ||||
| `Certificate` | ✅ | ✅ | 证书 (cert-manager) |
| `ClusterIssuer` | ✅ | ❌ | 证书签发器 (集群级别) |
| `Issuer` | ✅ | ✅ | 证书签发器 (namespace 级别) |
| **RBAC 资源** ||||
| `Role` | ✅ | ❌ | 角色 (namespace 级别) |
| `RoleBinding` | ✅ | ❌ | 角色绑定 |
| `ServiceAccount` | ✅ | ❌ | 服务账号 |

---

## 🔍 实际场景分析

### 场景 1: 部署 cert-manager (基础设施)

**需要的资源：**
```yaml
1. CustomResourceDefinition (集群级别)
   - certificates.cert-manager.io
   - clusterissuers.cert-manager.io
   - issuers.cert-manager.io

2. Namespace
   - cert-manager

3. ClusterRole (集群级别)
   - cert-manager-controller
   - cert-manager-webhook

4. Deployment
   - cert-manager
   - cert-manager-webhook

5. Service
   - cert-manager
   - cert-manager-webhook
```

**哪个 Project 可以做？**
- ✅ **Platform Project** - 有所有需要的权限
- ❌ **Applications Project** - 无法创建 CRD 和 ClusterRole

---

### 场景 2: 部署 Web 应用 (业务应用)

**需要的资源：**
```yaml
1. Namespace
   - revieu-prod

2. Deployment
   - revieu-web

3. Service
   - revieu-web

4. Ingress
   - revieu-web-ingress

5. ConfigMap
   - revieu-web-config

6. Secret
   - revieu-web-secrets
```

**哪个 Project 可以做？**
- ✅ **Platform Project** - 有所有权限
- ✅ **Applications Project** - 有这些业务资源的权限

**最佳实践：** 使用 Applications Project（最小权限原则）

---

### 场景 3: 试图越权操作

#### 尝试 1: 应用团队想部署到 kube-system

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-evil-app
  namespace: argocd
spec:
  project: applications  # ← 使用 applications project
  destination:
    namespace: kube-system  # ← 试图部署到系统 namespace
  source:
    repoURL: https://github.com/RevieU-Corp/revieu-infra.git
    path: evil
```

**结果：**
```
❌ 创建失败
Error: application destination namespace "kube-system" is not permitted in project "applications"

destinations 白名单中没有 kube-system
```

#### 尝试 2: 应用团队想创建 ClusterRole

```yaml
# 在 Git 仓库中添加这个文件
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: super-admin
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
```

**结果：**
```
❌ 同步失败
Error: resource ClusterRole is not permitted in project "applications"

clusterResourceWhitelist 白名单中只有 Namespace
```

#### 尝试 3: 基础设施团队正常操作

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
spec:
  project: platform  # ← 使用 platform project
  destination:
    namespace: cert-manager
  source:
    repoURL: https://github.com/RevieU-Corp/revieu-infra.git
    path: apps/overlays/prod/middleware/cert-manager
```

**包含的资源：**
```yaml
- CustomResourceDefinition (CRD)
- ClusterRole
- ClusterRoleBinding
- Deployment
- Service
```

**结果：**
```
✅ 部署成功
platform project 有所有需要的权限
```

---

## 🎯 设计原则

### 1. 最小权限原则 (Principle of Least Privilege)

```
每个 Application 只获得完成任务所需的最小权限

Platform Apps:
  需要管理集群基础设施
  → 给予完全权限

Application Apps:
  只需要部署业务应用
  → 只给予业务相关权限
```

### 2. 职责分离 (Separation of Duties)

```
不同团队使用不同的 Project

基础设施团队 → Platform Project
  负责：cert-manager, traefik, monitoring
  权限：集群级别

应用开发团队 → Applications Project
  负责：web, core, business apps
  权限：应用级别
```

### 3. 纵深防御 (Defense in Depth)

```
多层安全机制：

第 1 层：Git 仓库访问控制
  只允许从可信仓库拉取

第 2 层：Namespace 隔离
  限制可以部署的 namespace

第 3 层：资源类型白名单
  限制可以创建的资源类型

第 4 层：K8s RBAC
  Kubernetes 本身的权限控制
```

---

## 📝 配置建议

### 生产环境 AppProject 配置

```yaml
# Platform Project - 基础设施团队
spec:
  sourceRepos:
    - https://github.com/YOUR-ORG/infra.git  # 只允许内部仓库

  destinations:
    - namespace: 'cert-manager'
    - namespace: 'kube-system'
    - namespace: 'logging'
    - namespace: 'monitoring'
    - namespace: '*-prod'  # 所有生产 namespace

  clusterResourceWhitelist:
    - group: '*'
      kind: '*'

  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
```

```yaml
# Applications Project - 开发团队
spec:
  sourceRepos:
    - https://github.com/YOUR-ORG/apps.git  # 应用仓库

  destinations:
    - namespace: 'app-*'  # 只允许 app 开头的 namespace
    - namespace: 'argocd'  # ArgoCD 自管理

  clusterResourceWhitelist:
    - group: ''
      kind: Namespace  # 只允许创建 Namespace

  namespaceResourceWhitelist:
    # 只列出应用需要的资源类型
    - group: 'apps'
      kind: Deployment
    - group: 'apps'
      kind: StatefulSet
    - group: ''
      kind: Service
    - group: 'networking.k8s.io'
      kind: Ingress
    - group: ''
      kind: ConfigMap
    - group: ''
      kind: Secret
```

---

## 💡 关键要点

1. **AppProject 是安全边界**
   - 不同团队使用不同的 Project
   - 实现权限隔离

2. **三重控制**
   - Git 仓库（从哪拉代码）
   - Namespace（部署到哪）
   - 资源类型（能创建什么）

3. **Platform vs Applications**
   - Platform: 高权限，管理基础设施
   - Applications: 低权限，管理业务应用

4. **白名单机制**
   - 默认拒绝所有
   - 只允许明确许可的操作

5. **最小权限原则**
   - 只给需要的权限
   - 不多给一分

---

## 🔗 相关资源

- **Root App**: 使用 default project，创建所有子 Application
- **Platform Apps**: 使用 platform project，部署基础设施
- **Application Apps**: 使用 applications project，部署业务应用

```
default project (Root)
  ├─ platform project (Infrastructure)
  └─ applications project (Business Apps)
```
