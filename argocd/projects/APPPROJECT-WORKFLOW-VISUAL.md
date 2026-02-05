# AppProject 生效流程可视化

## 🎬 部署流程动画

```
═══════════════════════════════════════════════════════════════
第 1 步：安装 ArgoCD
═══════════════════════════════════════════════════════════════

$ kubectl apply -f argocd/install.yaml

Kubernetes Cluster:
┌────────────────────────────────────────────────────────┐
│ argocd namespace                                       │
│                                                        │
│ ✅ CRD: applications.argoproj.io                       │
│ ✅ CRD: appprojects.argoproj.io      ← 这是关键！     │
│ ✅ Deployment: argocd-server                           │
│ ✅ Deployment: argocd-repo-server                      │
│                                                        │
│ ✅ AppProject: default (自动创建)                      │
│                                                        │
└────────────────────────────────────────────────────────┘
```

```
═══════════════════════════════════════════════════════════════
第 2 步：创建自定义 AppProject（关键！）
═══════════════════════════════════════════════════════════════

$ kubectl apply -f argocd/projects/platform-project.yaml
$ kubectl apply -f argocd/projects/application-project.yaml

Kubernetes Cluster:
┌────────────────────────────────────────────────────────┐
│ argocd namespace                                       │
│                                                        │
│ AppProjects:                                           │
│ ┌────────────────────────────────────────────────┐    │
│ │ default (ArgoCD 自带)                          │    │
│ │ - 宽松权限                                      │    │
│ │ - 用于 Root App                                 │    │
│ └────────────────────────────────────────────────┘    │
│                                                        │
│ ┌────────────────────────────────────────────────┐    │
│ │ platform (我们创建的) ★                        │    │
│ │ - 高权限                                        │    │
│ │ - 可以创建集群资源                              │    │
│ │ - 可以部署到所有 namespace                      │    │
│ └────────────────────────────────────────────────┘    │
│                                                        │
│ ┌────────────────────────────────────────────────┐    │
│ │ applications (我们创建的) ★                    │    │
│ │ - 受限权限                                      │    │
│ │ - 只能创建应用资源                              │    │
│ │ - 只能部署到 revieu-* namespace                 │    │
│ └────────────────────────────────────────────────┘    │
│                                                        │
└────────────────────────────────────────────────────────┘

现在 AppProject "platform" 和 "applications" 已经存在！
可以被 Application 引用了！
```

```
═══════════════════════════════════════════════════════════════
第 3 步：部署 Root App
═══════════════════════════════════════════════════════════════

$ kubectl apply -f argocd/root/root-app-prod.yaml

Kubernetes Cluster:
┌────────────────────────────────────────────────────────┐
│ argocd namespace                                       │
│                                                        │
│ Applications:                                          │
│ ┌────────────────────────────────────────────────┐    │
│ │ Application: root-app-prod                     │    │
│ │   project: default  ──────┐                    │    │
│ │   status: Syncing...      │                    │    │
│ └───────────────────────────┼────────────────────┘    │
│                             │                         │
│                             ▼                         │
│                      查找 "default" AppProject        │
│                      ✅ 找到（ArgoCD 自带）            │
│                      ✅ 允许创建 Application 对象      │
│                                                        │
└────────────────────────────────────────────────────────┘
```

```
═══════════════════════════════════════════════════════════════
第 4 步：Root App 开始创建子 Application
═══════════════════════════════════════════════════════════════

ArgoCD 读取 Git 仓库：
  argocd/platform/prod/*.yaml
  argocd/applications/prod/*.yaml

发现 8 个 Application 定义文件

开始创建第 1 个子 Application：
┌────────────────────────────────────────────────────────┐
│ 从 Git 读取: argocd/platform/prod/infra-foundation.yaml│
│                                                        │
│ apiVersion: argoproj.io/v1alpha1                       │
│ kind: Application                                      │
│ metadata:                                              │
│   name: infra-foundation-prod                          │
│ spec:                                                  │
│   project: platform  ← 引用 "platform" AppProject     │
│                                                        │
└────────────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────┐
│ ArgoCD 验证流程：                                       │
│                                                        │
│ 1. 查找 AppProject "platform"                          │
│    └─ ✅ 找到了！(我们在第 2 步创建的)                 │
│                                                        │
│ 2. 检查 sourceRepos                                    │
│    └─ ✅ GitHub RevieU-Corp/revieu-infra 在白名单      │
│                                                        │
│ 3. 检查 destination                                    │
│    └─ ✅ 允许所有 namespace                            │
│                                                        │
│ 4. (稍后) 检查资源类型                                 │
│    └─ ✅ 允许所有资源类型                              │
│                                                        │
│ 结果: ✅ 创建 Application 成功！                        │
│                                                        │
└────────────────────────────────────────────────────────┘

继续创建第 2 个子 Application：
┌────────────────────────────────────────────────────────┐
│ 从 Git 读取: argocd/applications/prod/web.yaml         │
│                                                        │
│ apiVersion: argoproj.io/v1alpha1                       │
│ kind: Application                                      │
│ metadata:                                              │
│   name: revieu-web-prod                                │
│ spec:                                                  │
│   project: applications  ← 引用 "applications" Project │
│   destination:                                         │
│     namespace: revieu-prod                             │
│                                                        │
└────────────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────┐
│ ArgoCD 验证流程：                                       │
│                                                        │
│ 1. 查找 AppProject "applications"                      │
│    └─ ✅ 找到了！(我们在第 2 步创建的)                 │
│                                                        │
│ 2. 检查 sourceRepos                                    │
│    └─ ✅ GitHub RevieU-Corp/revieu-infra 在白名单      │
│                                                        │
│ 3. 检查 destination                                    │
│    └─ ✅ revieu-prod 匹配 'revieu-*' 模式              │
│                                                        │
│ 4. (稍后) 检查资源类型                                 │
│    └─ ✅ Deployment, Service 等在白名单                │
│                                                        │
│ 结果: ✅ 创建 Application 成功！                        │
│                                                        │
└────────────────────────────────────────────────────────┘
```

```
═══════════════════════════════════════════════════════════════
第 5 步：最终状态
═══════════════════════════════════════════════════════════════

Kubernetes Cluster:
┌────────────────────────────────────────────────────────┐
│ argocd namespace                                       │
│                                                        │
│ AppProjects:                                           │
│ ├─ default                                             │
│ ├─ platform          ← 权限规则                       │
│ └─ applications      ← 权限规则                       │
│                                                        │
│ Applications:                                          │
│ ├─ root-app-prod                (project: default)     │
│ │                                                      │
│ ├─ platform-apps-prod           (project: platform)    │
│ ├─ infra-foundation-prod        (project: platform)    │
│ ├─ infra-core-prod              (project: platform)    │
│ ├─ infra-observability-prod     (project: platform)    │
│ │                                                      │
│ ├─ application-apps-prod        (project: applications)│
│ ├─ argocd-self-prod             (project: applications)│
│ ├─ revieu-web-prod              (project: applications)│
│ └─ revieu-core-prod             (project: applications)│
│                                                        │
└────────────────────────────────────────────────────────┘

每个 Application 都通过 spec.project 引用对应的 AppProject
ArgoCD 根据 AppProject 的规则验证所有操作
```

---

## 🔍 权限检查时机

### 时机 1: Application 创建时

```
尝试创建 Application 对象
    ↓
ArgoCD 检查：
├─ AppProject 是否存在？
├─ sourceRepos 是否在白名单？
└─ destination 是否在白名单？
    ↓
如果都通过 → 创建 Application 对象
如果不通过 → 拒绝创建
```

### 时机 2: Application 同步时

```
Application 尝试同步（部署资源）
    ↓
ArgoCD 检查：
├─ 每个资源的 kind 是否在白名单？
├─ 集群资源是否在 clusterResourceWhitelist？
└─ Namespace 资源是否在 namespaceResourceWhitelist？
    ↓
如果都通过 → 允许部署
如果不通过 → 拒绝部署，显示错误
```

---

## ❌ 错误场景演示

### 场景 1: AppProject 不存在

```
$ kubectl apply -f argocd/root/root-app-prod.yaml
(没有先创建 AppProject)

ArgoCD 尝试创建 infra-foundation-prod:
├─ spec.project: platform
├─ 查找 AppProject "platform"
└─ ❌ 找不到！

Error:
  application spec is invalid: application references project "platform"
  which does not exist
```

### 场景 2: 尝试越权部署

```
Application: revieu-web-prod
├─ project: applications  ← 使用受限的 project
├─ 尝试创建 ClusterRole
└─ ArgoCD 检查 namespaceResourceWhitelist
    ├─ ClusterRole 不在列表中
    └─ ❌ 拒绝！

Error:
  resource ClusterRole is not permitted in project "applications"
```

---

## 🎯 关键要点

### 1. AppProject 的三个关键特性

```
① 独立性
  - AppProject 独立于 Root App 部署
  - 通过 kubectl 直接创建

② 引用机制
  - Application 通过名称引用
  - spec.project: "platform" / "applications"

③ 检查时机
  - Application 创建时检查
  - 资源部署时检查
```

### 2. 部署顺序很重要

```
✅ 正确顺序：
1. ArgoCD           (提供 CRD)
2. AppProject       (定义规则)
3. Root App         (创建 Application)
4. 子 Application   (引用 AppProject)

❌ 错误顺序：
1. ArgoCD
2. Root App         ← 错！此时 AppProject 还不存在
3. AppProject       ← 太晚了
```

### 3. 为什么不在 Root App 中创建 AppProject？

```
技术上可行：
  Root App sources:
  - argocd/projects
  - argocd/platform
  - argocd/applications

但有问题：
  ❌ 创建顺序不确定
  ❌ 可能 Application 先于 Project 创建
  ❌ 失败时难以排查

推荐做法：
  ✅ 在 bootstrap.sh 中先创建 AppProject
  ✅ 确保顺序正确
  ✅ 清晰明了
```

---

## 📝 总结

### AppProject 如何生效的完整答案

1. **不是被 Root App 引用**
   - AppProject 独立部署
   - 在 bootstrap.sh 第 3 步创建

2. **通过名称被 Application 引用**
   ```yaml
   Application:
     spec:
       project: platform  ← 名称引用
   ```

3. **ArgoCD 运行时检查**
   - Application 创建时检查权限
   - 资源部署时检查权限
   - 根据 AppProject 的白名单决定是否允许

### 记忆图

```
Bootstrap 脚本:
  Step 1: 安装 ArgoCD (提供基础设施)
  Step 2: 创建 AppProject (定义规则) ★
  Step 3: 部署 Root App (开始部署)

Application 引用:
  spec.project: "platform"
         ↓
  通过名称查找
         ↓
  AppProject: platform
         ↓
  应用权限规则
```

现在你完全理解 AppProject 如何生效了吧？ 😊
