# AppProject 如何生效？

## 🔑 关键点：AppProject 不是被 Root App "引用"的，而是被子 Application "引用"的！

---

## 📊 完整的部署顺序和引用关系

### 部署顺序（从 bootstrap.sh）

```bash
第 1 步：安装 cert-manager
  kubectl apply -f https://...cert-manager.yaml

第 2 步：安装 ArgoCD
  kubectl apply -f https://...argocd/install.yaml

  # 等待 ArgoCD CRD 就绪
  # 包括：applications.argoproj.io 和 appprojects.argoproj.io

第 3 步：创建 AppProject（重要！）
  kubectl apply -f argocd/projects/platform-project.yaml
  kubectl apply -f argocd/projects/application-project.yaml

第 4 步：部署 Root Application
  kubectl apply -f argocd/root/root-app-prod.yaml
```

**关键：AppProject 必须在 Root App 之前部署！**

---

## 🔗 引用关系图

```
┌─────────────────────────────────────────────────────────────┐
│  第 1 层：AppProject (被直接部署到 K8s)                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐        ┌──────────────────┐         │
│  │ Platform Project │        │ Applications     │         │
│  │                  │        │ Project          │         │
│  └──────────────────┘        └──────────────────┘         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                    ▲                      ▲
                    │                      │
                    │ 引用 (project: xxx)   │
                    │                      │
┌─────────────────────────────────────────────────────────────┐
│  第 2 层：Root Application                                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────────────────────────────────┐                │
│  │ root-app-prod                          │                │
│  │ project: default  ←──────┐             │                │
│  └────────────────────────────────────────┘                │
│                                    │                        │
│                          (不引用自定义 Project)              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ 创建
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  第 3 层：子 Application (由 Root App 创建)                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────┐    ┌──────────────────────┐     │
│  │ infra-foundation-prod│    │ revieu-web-prod      │     │
│  │ project: platform ───┼───→│ project: applications│─┐   │
│  └──────────────────────┘    └──────────────────────┘ │   │
│           │                            │               │   │
│           │                            │               │   │
│  引用 Platform Project       引用 Applications Project  │   │
│           │                            │               │   │
│           ▼                            ▼               ▼   │
│     检查权限白名单              检查权限白名单         检查权限 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 实际引用示例

### Root App 不引用自定义 Project

```yaml
# argocd/root/root-app-prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app-prod
spec:
  project: default  # ← 使用 ArgoCD 内置的 default project
                    #    不是我们创建的 platform 或 applications
```

**为什么用 default？**
- Root App 只需要创建 Application 对象
- default project 有足够权限做这件事
- 不需要额外限制

---

### Platform Apps 引用 platform project

```yaml
# argocd/platform/prod/infra-foundation.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-foundation-prod
spec:
  project: platform  # ← 引用我们创建的 platform project
                     #    获得高权限
```

**ArgoCD 的检查流程：**
```
1. infra-foundation-prod 说：我要使用 platform project
2. ArgoCD 查找：是否存在名为 "platform" 的 AppProject？
3. 找到了：platform-project.yaml 创建的 AppProject
4. 应用权限：使用 platform project 的白名单规则
```

---

### Application Apps 引用 applications project

```yaml
# argocd/applications/prod/web.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: revieu-web-prod
spec:
  project: applications  # ← 引用我们创建的 applications project
                         #    获得受限权限
```

**ArgoCD 的检查流程：**
```
1. revieu-web-prod 说：我要使用 applications project
2. ArgoCD 查找：是否存在名为 "applications" 的 AppProject？
3. 找到了：application-project.yaml 创建的 AppProject
4. 应用权限：使用 applications project 的白名单规则
```

---

## 🔍 AppProject 如何生效？

### 机制：通过名称匹配

```yaml
# Step 1: 创建 AppProject
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform  # ← 定义名称为 "platform"
  namespace: argocd

# Step 2: Application 引用这个名称
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  project: platform  # ← 通过名称引用
```

**ArgoCD 的工作方式：**
1. 当 Application 尝试执行操作时（部署、同步等）
2. ArgoCD 查找 `spec.project` 字段指定的 AppProject
3. 检查操作是否符合 AppProject 的白名单
4. 如果符合 → 允许操作
5. 如果不符合 → 拒绝操作

---

## 📋 完整的初始化流程

```
时间轴：从零到完整环境

T0: 空集群
├─ 没有 ArgoCD
├─ 没有 AppProject
└─ 没有 Application

T1: 安装 cert-manager
└─ kubectl apply -f cert-manager.yaml

T2: 安装 ArgoCD
└─ kubectl apply -f argocd/install.yaml
   创建：
   ├─ argocd namespace
   ├─ ArgoCD CRDs (包括 AppProject CRD)
   ├─ ArgoCD Deployment
   └─ ArgoCD Service

T3: 创建 AppProject 对象 ★ 关键步骤
└─ kubectl apply -f argocd/projects/
   创建：
   ├─ AppProject: platform
   └─ AppProject: applications

   此时 K8s 中存在：
   argocd namespace:
   ├─ AppProject/platform      ← 权限规则已就绪
   └─ AppProject/applications  ← 权限规则已就绪

T4: 部署 Root App
└─ kubectl apply -f argocd/root/root-app-prod.yaml
   创建：
   └─ Application: root-app-prod (project: default)

T5: Root App 创建子 Application
ArgoCD 检测到 root-app-prod，开始同步
├─ 读取 argocd/platform/prod/*.yaml
├─ 创建 Application: infra-foundation-prod
│  └─ spec.project: platform  ← 引用已存在的 AppProject
│     ArgoCD 检查：
│     ├─ AppProject "platform" 是否存在？ ✅ 存在
│     ├─ sourceRepos 是否允许？ ✅ 允许
│     ├─ destination 是否允许？ ✅ 允许
│     └─ 资源类型是否允许？ ✅ 允许
│
└─ 创建 Application: revieu-web-prod
   └─ spec.project: applications  ← 引用已存在的 AppProject
      ArgoCD 检查：
      ├─ AppProject "applications" 是否存在？ ✅ 存在
      ├─ sourceRepos 是否允许？ ✅ 允许
      ├─ destination 是否允许？ ✅ 允许
      └─ 资源类型是否允许？ ✅ 允许

T6: 子 Application 部署资源
每个 Application 根据其 project 的权限规则部署资源
```

---

## ❓ 常见问题

### Q1: 如果先部署 Root App，后部署 AppProject 会怎样？

```bash
# 错误的顺序
kubectl apply -f argocd/root/root-app-prod.yaml
kubectl apply -f argocd/projects/platform-project.yaml

# 结果：
❌ 子 Application 创建失败
Error: AppProject "platform" does not exist
```

**原因：** Application 引用不存在的 Project

---

### Q2: 如果不创建 AppProject 会怎样？

```bash
# 跳过 AppProject 创建
kubectl apply -f argocd/root/root-app-prod.yaml

# 结果：
❌ 所有引用 "platform" 或 "applications" 的 Application 创建失败
✅ Root App 本身可以创建（因为用的是 default project）
```

---

### Q3: default project 是什么？

ArgoCD 安装时自动创建的内置 project：

```bash
kubectl get appproject -n argocd
NAME         AGE
default      10m    ← ArgoCD 自带的

# 查看详情
kubectl get appproject default -n argocd -o yaml
```

**default project 的特点：**
- ArgoCD 自动创建，无需手动部署
- 权限较宽松（适合管理型任务）
- Root App 使用它

---

### Q4: 可以在 Root App 中创建 AppProject 吗？

**技术上可以，但不推荐：**

```yaml
# 不推荐的方式
# argocd/root/root-app-prod.yaml
sources:
  - path: argocd/projects    # 包含 AppProject
  - path: argocd/platform    # 包含 Application (引用 platform project)
  - path: argocd/applications
```

**问题：**
- 创建顺序不确定（可能 Application 先于 Project 创建）
- 失败时难以排查
- 违反"基础设施优先"原则

**推荐方式（当前实现）：**
- 在 bootstrap.sh 中先创建 AppProject
- 确保 Project 先于 Application 存在

---

## 🎓 总结

### AppProject 生效的三个关键

1. **独立部署**
   - AppProject 不通过 Root App 部署
   - 在 bootstrap.sh 中直接 kubectl apply

2. **名称引用**
   - Application 通过 `spec.project: platform` 引用
   - ArgoCD 通过名称匹配找到对应的 AppProject

3. **部署顺序**
   - 必须先创建 AppProject
   - 后创建引用它的 Application

### 引用关系总结

```
AppProject (独立部署)
    ↑
    │ 名称引用 (spec.project: xxx)
    │
Application (被 Root App 创建)
```

### 记忆口诀

```
Project 是规则书，要先放在图书馆
Application 是学生，来了才能去翻看
Root 是教务处，负责招收学生
但规则书得提前准备好，不然学生来了没规矩
```

---

## 🔧 验证 AppProject 是否生效

```bash
# 1. 检查 AppProject 是否存在
kubectl get appproject -n argocd

# 2. 查看某个 Application 使用的 Project
kubectl get application revieu-web-prod -n argocd -o yaml | grep project

# 3. 测试权限限制（尝试创建越权 Application）
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-app
  namespace: argocd
spec:
  project: applications
  destination:
    namespace: kube-system  # ← 不在白名单
    server: https://kubernetes.default.svc
  source:
    repoURL: https://github.com/RevieU-Corp/revieu-infra.git
    path: test
EOF

# 预期结果：
# Error: application destination namespace "kube-system" is not permitted
```

现在你理解了吗？AppProject 是独立部署的，Application 通过名称引用它！
