# AppProject 详解 - 什么是 AppProject？

## 🎯 一句话总结

**AppProject 是 ArgoCD 的"权限控制器"和"安全边界"**

就像你给不同的员工设置不同的权限一样：
- 基础设施团队可以操作所有系统资源
- 应用开发团队只能操作业务应用资源

## 🏢 类比理解

### 场景：公司办公楼的门禁系统

```
公司大楼有很多房间：
├── 服务器机房 (cert-manager namespace)
├── 网络设备间 (kube-system namespace)
├── 监控中心 (logging namespace)
└── 开发办公室 (revieu-* namespaces)

员工分两类：
1. 基础设施团队 (Platform Project)
   - 门禁卡：可以进入所有房间 🔑🔑🔑
   - 权限：可以操作所有设备

2. 应用开发团队 (Applications Project)
   - 门禁卡：只能进入开发办公室 🔑
   - 权限：只能操作开发相关设备
```

**AppProject 就是这个"门禁系统"！**

---

## 📋 AppProject 的三大功能

### 1️⃣ 控制 Git 仓库访问 (sourceRepos)

**问题：** 如果没有限制，Application 可以从任何 Git 仓库拉取代码，包括恶意仓库！

**解决：** AppProject 定义白名单

```yaml
# Platform Project - 只允许从官方仓库拉取
sourceRepos:
  - https://github.com/RevieU-Corp/revieu-infra.git

# 如果有人试图从其他仓库部署，ArgoCD 会拒绝：
# ❌ https://github.com/hacker/malware.git
```

---

### 2️⃣ 控制部署目标 (destinations)

**问题：** 如果没有限制，Application 可以部署到任何 namespace，可能破坏其他团队的资源！

**解决：** AppProject 定义允许的 namespace

```yaml
# Platform Project - 可以部署到基础设施相关的 namespace
destinations:
  - namespace: 'cert-manager'      # ✅ 允许
  - namespace: 'kube-system'       # ✅ 允许
  - namespace: 'logging'           # ✅ 允许
  - namespace: 'revieu-*'          # ✅ 允许 (通配符)

# 如果 Platform 团队试图部署到其他 namespace：
# ❌ namespace: 'hacker-space' - 会被拒绝
```

```yaml
# Applications Project - 只能部署到业务应用 namespace
destinations:
  - namespace: 'revieu-*'          # ✅ 只允许 revieu 开头的
  - namespace: 'argocd'            # ✅ 允许 (ArgoCD 自管理)

# 如果应用团队试图部署到系统 namespace：
# ❌ namespace: 'kube-system' - 会被拒绝
```

---

### 3️⃣ 控制资源类型 (Whitelist)

**问题：** 如果没有限制，Application 可以创建任何类型的资源，包括危险的集群级别资源！

**解决：** AppProject 定义允许的资源类型

#### Platform Project - 完全权限

```yaml
clusterResourceWhitelist:    # 集群级别资源（不属于任何 namespace）
  - group: '*'               # 所有 API group
    kind: '*'                # 所有资源类型

namespaceResourceWhitelist:  # Namespace 级别资源
  - group: '*'
    kind: '*'
```

**含义：** 基础设施团队可以创建任何资源（他们需要管理整个集群）

#### Applications Project - 受限权限

```yaml
clusterResourceWhitelist:
  - group: ''                # 只允许创建 Namespace
    kind: Namespace          # ✅ 可以创建 namespace

namespaceResourceWhitelist:
  - group: 'apps'
    kind: Deployment         # ✅ 可以创建 Deployment
  - group: 'apps'
    kind: StatefulSet        # ✅ 可以创建 StatefulSet
  - group: ''
    kind: Service            # ✅ 可以创建 Service
  - group: 'networking.k8s.io'
    kind: Ingress            # ✅ 可以创建 Ingress
  # ... 其他业务需要的资源
```

**含义：** 应用团队只能创建业务相关的资源

**如果应用团队试图创建不在白名单的资源：**
```yaml
# ❌ 试图创建 ClusterRole (集群级别权限)
kind: ClusterRole
# ArgoCD 会拒绝：不在 clusterResourceWhitelist 中

# ❌ 试图创建 PersistentVolume (集群级别存储)
kind: PersistentVolume
# ArgoCD 会拒绝：不在 clusterResourceWhitelist 中
```

---

## 🔍 两个 Project 的详细对比

### Platform Project (基础设施项目)

```yaml
name: platform
description: Platform infrastructure components

权限等级：⭐⭐⭐⭐⭐ (最高权限)

允许的 Git 仓库：
  ✅ https://github.com/RevieU-Corp/revieu-infra.git

允许的 Namespace：
  ✅ cert-manager        (证书管理)
  ✅ kube-system         (K8s 系统组件)
  ✅ logging             (日志监控)
  ✅ revieu-*            (业务 namespace)
  ✅ argocd              (ArgoCD 自身)

允许的资源类型：
  ✅ 所有集群资源 (ClusterRole, ClusterRoleBinding, CustomResourceDefinition...)
  ✅ 所有 Namespace 资源 (Deployment, Service, ConfigMap...)

典型应用：
  - cert-manager (需要创建 CRD)
  - traefik (需要 ClusterRole)
  - loki (需要跨 namespace 访问)
  - sealed-secrets (需要集群级别权限)
```

### Applications Project (业务应用项目)

```yaml
name: applications
description: Business applications

权限等级：⭐⭐ (受限权限)

允许的 Git 仓库：
  ✅ https://github.com/RevieU-Corp/revieu-infra.git
  ✅ https://raw.githubusercontent.com/RevieU-Corp/* (用于 sealed-secrets)

允许的 Namespace：
  ✅ revieu-*            (只能操作业务 namespace)
  ✅ argocd              (ArgoCD 自管理)
  ❌ cert-manager        (禁止！)
  ❌ kube-system         (禁止！)
  ❌ logging             (禁止！)

允许的资源类型：
  ✅ Namespace (可以创建业务 namespace)
  ✅ Deployment, StatefulSet (应用部署)
  ✅ Service, Ingress (网络服务)
  ✅ ConfigMap, Secret (配置和密钥)
  ✅ Certificate (业务证书)
  ❌ ClusterRole (禁止！集群级别权限)
  ❌ CustomResourceDefinition (禁止！不能创建 CRD)
  ❌ PersistentVolume (禁止！集群级别存储)

典型应用：
  - revieu-web (前端应用)
  - revieu-core (后端 API)
  - argocd-self (ArgoCD 配置)
```

---

## 🛡️ 安全机制示例

### 场景 1：应用团队试图提权

```yaml
# 应用开发在 Git 里加了这个文件：
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
❌ ArgoCD 拒绝部署
错误信息：resource "ClusterRole" is not permitted in project "applications"

原因：ClusterRole 不在 applications project 的白名单中
```

### 场景 2：应用团队试图访问其他 namespace

```yaml
# 应用开发试图部署到 kube-system：
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: kube-system  # ← 试图部署到系统 namespace
```

**结果：**
```
❌ ArgoCD 拒绝部署
错误信息：namespace "kube-system" is not permitted in project "applications"

原因：kube-system 不在 applications project 的 destinations 中
```

### 场景 3：基础设施团队正常部署

```yaml
# 基础设施团队部署 cert-manager CRD：
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: certificates.cert-manager.io
```

**结果：**
```
✅ 部署成功
原因：platform project 有完全权限，可以创建任何资源
```

---

## 🔗 Application 如何使用 Project

### 在 Application 中指定 Project

```yaml
# argocd/platform/prod/infra-foundation.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-foundation-prod
spec:
  project: platform  # ← 使用 platform project 的权限
  source:
    repoURL: https://github.com/RevieU-Corp/revieu-infra.git
    path: apps/overlays/prod/middleware
```

```yaml
# argocd/applications/prod/web.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: revieu-web-prod
spec:
  project: applications  # ← 使用 applications project 的权限
  source:
    repoURL: https://github.com/RevieU-Corp/revieu-infra.git
    path: apps/overlays/prod/apps/web
```

---

## 📊 权限矩阵

| 操作 | Platform Project | Applications Project |
|------|------------------|---------------------|
| 创建 CRD | ✅ 允许 | ❌ 禁止 |
| 创建 ClusterRole | ✅ 允许 | ❌ 禁止 |
| 部署到 kube-system | ✅ 允许 | ❌ 禁止 |
| 部署到 cert-manager | ✅ 允许 | ❌ 禁止 |
| 部署到 revieu-prod | ✅ 允许 | ✅ 允许 |
| 创建 Deployment | ✅ 允许 | ✅ 允许 |
| 创建 Service | ✅ 允许 | ✅ 允许 |
| 创建 Namespace | ✅ 允许 | ✅ 允许 |
| 创建 PV | ✅ 允许 | ❌ 禁止 |

---

## 💡 为什么需要 AppProject？

### 1. **安全隔离**
```
没有 AppProject：
  所有 Application 都有相同权限
  任何人都可以部署到任何地方
  一个错误配置可能破坏整个集群
  ❌ 危险！

有 AppProject：
  不同团队有不同权限
  每个团队只能操作自己的资源
  最小权限原则
  ✅ 安全！
```

### 2. **职责分离**
```
Platform 团队：
  负责基础设施
  需要集群级别权限
  使用 platform project

Application 团队：
  负责业务应用
  只需要应用级别权限
  使用 applications project
```

### 3. **防止误操作**
```
场景：开发不小心写错了 namespace
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: kube-system  # ← 错误！本来想写 revieu-prod

没有 AppProject：
  ❌ 部署到 kube-system，可能破坏系统组件

有 AppProject：
  ✅ ArgoCD 拒绝部署，提示错误
```

---

## 🎓 实际例子

### 查看 Project 限制

```bash
# 查看所有 AppProject
kubectl get appproject -n argocd

# 查看 platform project 详情
kubectl get appproject platform -n argocd -o yaml

# 查看哪些 Application 使用了某个 project
kubectl get application -n argocd -o json | \
  jq -r '.items[] | select(.spec.project=="platform") | .metadata.name'
```

### 测试权限限制

```bash
# 尝试创建一个使用 applications project 但部署到 kube-system 的 App
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-app
  namespace: argocd
spec:
  project: applications
  destination:
    namespace: kube-system  # ← 这会失败！
    server: https://kubernetes.default.svc
  source:
    repoURL: https://github.com/RevieU-Corp/revieu-infra.git
    path: test
EOF

# 结果：
# Error: application destination namespace "kube-system" is not permitted
```

---

## 📝 总结

### AppProject 的本质

1. **权限控制器**: 定义 Application 可以做什么
2. **安全边界**: 隔离不同团队/应用的权限
3. **白名单机制**: 只允许明确许可的操作

### 三个关键问题

| 问题 | 配置项 | 作用 |
|------|--------|------|
| 从哪拉代码？ | `sourceRepos` | 限制 Git 仓库 |
| 部署到哪里？ | `destinations` | 限制 Namespace |
| 能创建什么？ | `*Whitelist` | 限制资源类型 |

### 记忆口诀

```
AppProject 是门禁卡
管你能去哪个家
Platform 是万能钥匙
Applications 只能回自己家
```

---

## 🔄 与 Root App 的关系

```
Root App (使用 default project)
  ↓
创建子 Application 时，指定它们的 project
  ↓
├─ Platform Apps (使用 platform project)
│  └─ 获得高权限，可以管理基础设施
│
└─ Application Apps (使用 applications project)
   └─ 获得受限权限，只能管理业务应用
```

**Root App 为什么用 default project？**
- Root App 只创建 Application 对象，不创建实际资源
- 它需要在 argocd namespace 创建子 Application
- default project 有足够权限做这件事

---

现在你理解 AppProject 了吗？它就是 ArgoCD 的"权限管理系统"！
