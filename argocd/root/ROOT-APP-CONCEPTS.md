# Root App 关键配置解释

## 📌 重要字段说明

### 1. sources (复数！)
```yaml
sources:
  - path: argocd/platform/prod      # 基础设施层
  - path: argocd/applications/prod  # 业务应用层
```

**为什么用复数？**
- 单数 `source` 只能指定一个源
- 复数 `sources` 可以指定多个源
- 这样 Root App 可以同时管理 Platform 和 Application 两层

**类比：**
就像一个总经理管理两个部门：
- 部门 1: IT 基础设施部 (platform)
- 部门 2: 产品开发部 (applications)

---

### 2. prune: false (关键安全设置！)
```yaml
syncPolicy:
  automated:
    prune: false  # ⚠️ 不自动删除
```

**为什么设置 false？**

**场景 1: 如果设置 prune: true**
```
你不小心在 Git 里删除了一个文件
  ↓
ArgoCD 发现文件不见了
  ↓
ArgoCD 认为对应的 Application 应该被删除
  ↓
💥 对应的所有子资源全部被删除！
  ↓
😱 整个环境挂了！
```

**场景 2: 设置 prune: false (当前配置)**
```
你不小心在 Git 里删除了一个文件
  ↓
ArgoCD 发现文件不见了
  ↓
ArgoCD 什么都不做（因为 prune: false）
  ↓
✅ 环境安全，没有被误删
  ↓
你有时间修复 Git 的问题
```

---

### 3. selfHeal: true
```yaml
syncPolicy:
  automated:
    selfHeal: true  # ✅ 自动修复
```

**作用：** 如果有人手动修改了 K8s 资源，ArgoCD 会自动恢复成 Git 里的状态。

**例子：**
```
有人用 kubectl 手动改了配置
  ↓
ArgoCD 每 3 分钟检查一次
  ↓
发现实际状态 ≠ Git 状态
  ↓
ArgoCD 自动同步，恢复成 Git 的配置
```

---

### 4. finalizers
```yaml
metadata:
  finalizers:
    - resources-finalizer.argocd.argoproj.io
```

**作用：** 当你删除 Root App 时，确保所有子资源也被清理干净。

**没有 finalizer 的情况：**
```
删除 Root App
  ↓
Root App 对象被删除
  ↓
但是子 Application 还在！
  ↓
变成孤儿资源，难以清理
```

**有 finalizer 的情况：**
```
删除 Root App
  ↓
ArgoCD 先删除所有子 Application
  ↓
等所有子资源都清理完
  ↓
最后删除 Root App 对象
  ↓
✅ 干净！
```

---

### 5. destination.namespace: argocd
```yaml
destination:
  namespace: argocd
```

**重要：** 这个 namespace 是指**子 Application 对象**存放的位置，不是实际资源部署的位置！

**例子：**
```
Root App (存在于 argocd namespace)
  ↓
创建子 Application 对象 (也在 argocd namespace)
  ↓
子 Application 部署实际资源 (可能在 revieu-prod namespace)
```

**对比：**
```
对象层 (都在 argocd):
  - root-app-prod (Application)
  - revieu-web-prod (Application)
  - revieu-core-prod (Application)

资源层 (在各自 namespace):
  - revieu-web Deployment (在 revieu-prod)
  - revieu-core Deployment (在 revieu-prod)
```

---

## 🎯 三个环境的区别

| 配置项 | Dev | Staging | Prod |
|-------|-----|---------|------|
| **Root App 名称** | root-app-dev | root-app-staging | root-app-prod |
| **Platform 路径** | argocd/platform/dev | argocd/platform/staging | argocd/platform/prod |
| **Applications 路径** | argocd/applications/dev | argocd/applications/staging | argocd/applications/prod |
| **核心逻辑** | 完全相同 | 完全相同 | 完全相同 |

**关键点：** 三个 Root App 的**结构完全相同**，只是指向不同的目录！

---

## 💡 类比理解

把 Root App 想象成一个"自动招聘经理"：

1. **你给他两份招聘清单** (sources):
   - 清单 1: 需要招聘的基础设施工程师 (platform)
   - 清单 2: 需要招聘的应用开发工程师 (applications)

2. **他自动去招人** (创建子 Application):
   - 从清单 1 招了 4 个基础设施工程师
   - 从清单 2 招了 4 个应用开发工程师

3. **他管理这些员工** (管理子 Application):
   - 监控他们的工作状态
   - 如果有人离职 (资源被删除)，自动补人 (selfHeal)
   - 但不会随便开除人 (prune: false)

---

## 🚀 实战：查看 Root App 的效果

部署后，你可以看到：

```bash
# 查看 Root App 本身
kubectl get application root-app-prod -n argocd

# 查看 Root App 创建的子 Application
kubectl get application -n argocd | grep prod

# 你会看到：
# root-app-prod                    ← Root App 本身
# platform-apps-prod               ← 子 App
# infra-foundation-prod            ← 子 App
# infra-core-prod                  ← 子 App
# infra-observability-prod         ← 子 App
# application-apps-prod            ← 子 App
# argocd-self-prod                 ← 子 App
# revieu-web-prod                  ← 子 App
# revieu-core-prod                 ← 子 App
```

---

## ⚠️ 常见误区

### 误区 1: "Root App 会部署实际资源"
❌ 错误！Root App 只创建 Application 对象
✅ 正确：子 Application 才部署实际资源

### 误区 2: "destination.namespace 是资源部署的位置"
❌ 错误！那是 Application 对象存放的位置
✅ 正确：实际资源部署在子 Application 各自定义的 namespace

### 误区 3: "prune: false 会导致资源不被删除"
❌ 错误！只影响子 Application 对象
✅ 正确：子 Application 内的资源删除由子 App 自己的 prune 控制

---

## 📝 总结

Root App 的本质是：

1. **目录扫描器**: 扫描指定目录，找到所有 Application 定义
2. **Application 工厂**: 批量创建 Application 对象
3. **顶层管理器**: 管理所有子 Application 的生命周期

**一句话概括：**
> Root App 是一个"管理 Application 的 Application"，它让你用一个文件管理整个环境。
