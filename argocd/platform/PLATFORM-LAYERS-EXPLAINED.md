# Platform 层文件详解

## 📚 Platform 目录结构

```
argocd/platform/prod/
├── platform-apps.yaml           # 聚合器（管理下面 3 个）
├── infra-foundation.yaml        # Wave 0: 基础层
├── infra-core.yaml              # Wave 1: 核心层
└── infra-observability.yaml     # Wave 2: 可观测性层
```

---

## 🎯 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    Root App                             │
│                 (总入口)                                 │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
┌───────────────┐         ┌───────────────┐
│ Platform Apps │         │ Application   │
│               │         │ Apps          │
└───────┬───────┘         └───────────────┘
        │
        │ 包含（通过 directory include）
        │
    ┌───┴────┬──────────┬──────────┐
    │        │          │          │
    ▼        ▼          ▼          ▼
┌────────┐ ┌────┐ ┌────────┐ ┌────────────┐
│platform│ │foun│ │core    │ │observabil- │
│-apps   │ │dati│ │        │ │ity         │
│(聚合器)│ │on  │ │        │ │            │
└────────┘ └────┘ └────────┘ └────────────┘
    Wave 0  Wave 0  Wave 1    Wave 2
```

---

## 1️⃣ platform-apps.yaml - 聚合器

### 作用：管理其他 3 个 infra-* Application

```yaml
metadata:
  name: platform-apps-prod
  annotations:
    argocd.argoproj.io/sync-wave: "0"

spec:
  source:
    path: argocd/platform/prod    # ← 指向当前目录
    directory:
      include: 'infra-*.yaml'     # ← 只包含 infra- 开头的文件
```

**工作原理：**
```
platform-apps.yaml 说：
"去 argocd/platform/prod 目录"
"找到所有 infra-*.yaml 文件"
"把它们都当作 Application 创建"

找到的文件：
  ✅ infra-foundation.yaml
  ✅ infra-core.yaml
  ✅ infra-observability.yaml
  ❌ platform-apps.yaml (自己，被排除)
```

**类比：**
- 就像一个"文件夹管理器"
- 它负责创建和管理下面 3 个子 Application
- 自己不部署任何实际资源

---

## 2️⃣ infra-foundation.yaml - 基础层 (Wave 0)

### 作用：部署最基础的依赖组件

```yaml
metadata:
  name: infra-foundation-prod
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # ← 第一批部署

spec:
  source:
    path: apps/overlays/prod/middleware
    directory:
      include: '{cert-manager,sealed-secrets}/**'  # ← 只部署这两个
```

### 部署的组件：

#### 1. cert-manager (证书管理器)
**用途：** 自动管理 TLS/SSL 证书

```
cert-manager 做什么？
├─ 自动向 Let's Encrypt 申请证书
├─ 自动续期快过期的证书
├─ 提供 Certificate CRD（自定义资源）
└─ 提供 ClusterIssuer CRD（证书签发者）

为什么是 Wave 0？
└─ 其他组件需要用到它的 CRD
   例如：infra-core 需要创建 Certificate 对象
```

**实际资源：**
```yaml
Namespace: cert-manager
Deployments:
  - cert-manager
  - cert-manager-webhook
  - cert-manager-cainjector
CRDs:
  - certificates.cert-manager.io
  - clusterissuers.cert-manager.io
  - issuers.cert-manager.io
```

#### 2. sealed-secrets (密钥加密工具)
**用途：** 让你可以安全地把密钥存在 Git 里

```
sealed-secrets 做什么？
├─ 加密 Secret，生成 SealedSecret
├─ SealedSecret 可以安全地存在 Git
├─ 部署到 K8s 后自动解密成 Secret
└─ 只有集群可以解密，别人看到的是密文

使用场景：
  你有数据库密码需要存 Git
  ├─ 普通做法：不能直接存明文 Secret
  ├─ Sealed Secrets：加密后存 SealedSecret
  └─ ArgoCD 部署后自动变成可用的 Secret
```

**实际资源：**
```yaml
Namespace: kube-system
Deployment:
  - sealed-secrets-controller
CRD:
  - sealedsecrets.bitnami.com
```

### 为什么叫 Foundation (基础层)？

```
Foundation = 地基

就像盖房子：
1. 先打地基（cert-manager, sealed-secrets）
2. 才能盖房子（其他组件）

如果没有 cert-manager：
  ❌ 无法创建 Certificate 对象
  ❌ 无法自动获取 HTTPS 证书
  ❌ 网站无法使用 HTTPS

如果没有 sealed-secrets：
  ❌ 密钥只能手动创建
  ❌ 无法通过 GitOps 管理密钥
  ❌ 违背 "一切皆代码" 原则
```

---

## 3️⃣ infra-core.yaml - 核心层 (Wave 1)

### 作用：部署核心基础设施配置

```yaml
metadata:
  name: infra-core-prod
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # ← 第二批部署

spec:
  source:
    path: apps/overlays/prod/common  # ← 部署 common 目录的内容
  destination:
    namespace: revieu-prod           # ← 部署到业务 namespace
```

### 部署的组件：

#### 查看实际内容

让我先看看 `apps/overlays/prod/common` 里有什么：

```bash
# 需要查看 apps/base/common 和 apps/overlays/prod/common
```

**典型内容（基于 common 的标准结构）：**

```yaml
1. Namespace
   - revieu-prod  ← 创建业务 namespace

2. ClusterIssuer
   - letsencrypt-prod  ← 证书签发器（使用 cert-manager）

   作用：定义如何获取证书
   ├─ 使用 Let's Encrypt 生产环境
   ├─ 通过 HTTP-01 或 DNS-01 验证
   └─ 自动续期

3. Certificate
   - revieu-cert  ← 证书资源（使用 cert-manager）

   作用：申请实际的 SSL 证书
   ├─ 域名：revieu.weijun.online
   ├─ 使用 letsencrypt-prod 签发
   └─ 存储为 Secret: revieu-tls
```

### 为什么是 Wave 1（在 Foundation 之后）？

```
依赖关系：
  infra-core 需要 cert-manager 的 CRD

  ❌ 如果没有 Wave 0 (cert-manager)：
     └─ 无法创建 ClusterIssuer（CRD 不存在）
     └─ 无法创建 Certificate（CRD 不存在）

  ✅ Wave 0 先部署 cert-manager：
     └─ CRD 就绪
     └─ Wave 1 可以创建 ClusterIssuer 和 Certificate
```

### 为什么叫 Core (核心层)？

```
Core = 核心配置

这些是业务应用运行的核心依赖：
├─ Namespace：应用部署的地方
├─ ClusterIssuer：如何获取证书的规则
└─ Certificate：应用需要的 HTTPS 证书

没有这些：
  ❌ 应用没地方部署（没 Namespace）
  ❌ 应用无法使用 HTTPS（没证书）
```

---

## 4️⃣ infra-observability.yaml - 可观测性层 (Wave 2)

### 作用：部署监控、日志、网络相关组件

```yaml
metadata:
  name: infra-observability-prod
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # ← 第三批部署

spec:
  source:
    path: apps/overlays/prod/middleware
    directory:
      include: '{loki,grafana,fluent-bit,traefik}/**'  # ← 包含这 4 个
      exclude: '{cert-manager,sealed-secrets}/**'     # ← 排除已部署的
```

### 部署的组件：

#### 1. Loki (日志聚合)
**用途：** 收集和存储日志

```
Loki 做什么？
├─ 收集所有 Pod 的日志
├─ 存储日志（不索引全文，节省资源）
├─ 提供查询接口
└─ 类似 Elasticsearch，但更轻量

为什么需要？
  Pod 重启后日志会丢失
  Loki 持久化存储所有日志
  可以查询历史日志
```

**实际资源：**
```yaml
Namespace: logging
StatefulSet:
  - loki
Service:
  - loki
PVC:
  - loki-storage
```

#### 2. Grafana (可视化面板)
**用途：** 展示监控和日志数据

```
Grafana 做什么？
├─ 连接到 Loki 查询日志
├─ 连接到 Prometheus 查询指标（如果有）
├─ 创建美观的监控面板
└─ 设置告警规则

使用场景：
  在浏览器打开 Grafana
  看到实时日志流
  看到资源使用图表
  CPU、内存、网络流量等
```

**实际资源：**
```yaml
Namespace: logging
Deployment:
  - grafana
Service:
  - grafana
ConfigMap:
  - grafana-datasources (连接 Loki)
PVC:
  - grafana-storage
```

#### 3. Fluent Bit (日志采集器)
**用途：** 从每个 Pod 采集日志，发送到 Loki

```
Fluent Bit 做什么？
├─ 作为 DaemonSet 运行在每个节点
├─ 读取所有容器的日志文件
├─ 解析日志格式
├─ 发送到 Loki 存储

工作流程：
  Pod 写日志 → Fluent Bit 采集 → 发送到 Loki → Grafana 查询
```

**实际资源：**
```yaml
Namespace: logging
DaemonSet:
  - fluent-bit (每个节点一个 Pod)
ConfigMap:
  - fluent-bit-config (配置如何采集和转发)
```

#### 4. Traefik (Ingress Controller / 反向代理)
**用途：** 管理外部流量进入集群

```
Traefik 做什么？
├─ 接收外部 HTTP/HTTPS 请求
├─ 根据域名路由到不同的 Service
├─ 自动配置 SSL/TLS（使用 cert-manager 的证书）
└─ 提供负载均衡

例子：
  用户访问 revieu.weijun.online
    ↓
  Traefik 接收请求
    ↓
  查看域名对应的 Ingress 规则
    ↓
  转发到 revieu-web Service
    ↓
  请求到达 Web Pod
```

**实际资源：**
```yaml
Namespace: kube-system (或 traefik)
Deployment:
  - traefik
Service:
  - traefik (LoadBalancer 类型，获取外部 IP)
IngressRoute:
  - traefik-dashboard (Traefik 自己的管理界面)
Middleware:
  - 各种中间件（认证、限流等）
```

### 为什么是 Wave 2（最后部署）？

```
依赖关系：

Traefik 需要：
  ✅ cert-manager (Wave 0)：自动获取 SSL 证书
  ✅ Certificate (Wave 1)：具体的证书资源

Grafana 需要：
  ✅ Loki：数据源
  ✅ Namespace (Wave 1)：部署位置

这些组件不紧急：
  - 应用可以先启动（Wave 11）
  - 监控和日志是"锦上添花"
  - 如果它们失败，不影响业务应用
```

### 为什么叫 Observability (可观测性层)？

```
Observability = 可观测性

三大支柱：
1. Logs (日志) → Loki + Fluent Bit
2. Metrics (指标) → (可以加 Prometheus)
3. Traces (追踪) → (可以加 Jaeger)

作用：
  出问题时能快速定位
  ├─ 查日志：发生了什么
  ├─ 查指标：资源使用情况
  └─ 查追踪：请求链路

Traefik 虽然是网络组件，但也在这层，因为：
  - 它不是核心依赖
  - 业务应用可以直接用 Service (NodePort)
  - Traefik 是为了更好的访问体验
```

---

## 📊 完整的部署流程

```
时间轴：

T0: Root App 开始同步
    └─ 读取 argocd/platform/prod 目录

T1: 创建 platform-apps-prod
    └─ platform-apps 扫描目录，发现 3 个 infra-* 文件

T2: Wave 0 开始部署
    ├─ infra-foundation-prod 开始同步
    │   ├─ 部署 cert-manager
    │   │   ├─ 创建 cert-manager namespace
    │   │   ├─ 创建 CRD (Certificate, ClusterIssuer...)
    │   │   ├─ 部署 cert-manager Pod
    │   │   └─ 等待 Webhook 就绪
    │   │
    │   └─ 部署 sealed-secrets
    │       ├─ 创建 Controller
    │       └─ 创建 CRD (SealedSecret)
    │
    └─ 等待所有 Wave 0 的 Application 同步完成

T3: Wave 1 开始部署
    ├─ infra-core-prod 开始同步
    │   ├─ 创建 revieu-prod namespace
    │   ├─ 创建 ClusterIssuer (使用 cert-manager CRD)
    │   └─ 创建 Certificate (使用 cert-manager CRD)
    │       └─ cert-manager 自动申请 Let's Encrypt 证书
    │
    └─ 等待所有 Wave 1 的 Application 同步完成

T4: Wave 2 开始部署
    ├─ infra-observability-prod 开始同步
    │   ├─ 部署 Loki
    │   │   └─ 创建 logging namespace
    │   │   └─ 创建 StatefulSet 和 PVC
    │   │
    │   ├─ 部署 Fluent Bit
    │   │   └─ 创建 DaemonSet (每节点一个)
    │   │
    │   ├─ 部署 Grafana
    │   │   └─ 连接到 Loki
    │   │   └─ 创建 Deployment
    │   │
    │   └─ 部署 Traefik
    │       └─ 创建 LoadBalancer Service
    │       └─ 配置自动使用 cert-manager 证书
    │
    └─ Platform 层部署完成！

T5: 继续部署 Application 层 (Wave 10+)
```

---

## 🎯 总结对比表

| 文件 | Wave | 作用 | 部署组件 | 为什么这个顺序 |
|------|------|------|---------|---------------|
| **platform-apps.yaml** | 0 | 聚合器 | 管理下面 3 个 Application | 需要先创建才能管理子 App |
| **infra-foundation.yaml** | 0 | 基础层 | cert-manager, sealed-secrets | 提供 CRD，其他组件依赖 |
| **infra-core.yaml** | 1 | 核心层 | Namespace, ClusterIssuer, Certificate | 需要 cert-manager 的 CRD |
| **infra-observability.yaml** | 2 | 可观测性 | Loki, Grafana, Fluent Bit, Traefik | 需要 Namespace 和证书 |

---

## 💡 类比理解

### 盖房子的顺序

```
Wave 0 - Foundation (地基):
  └─ 打地基，安装水电管道
     = cert-manager (证书管道)
     = sealed-secrets (密钥管道)

Wave 1 - Core (主体结构):
  └─ 建墙、建屋顶
     = Namespace (房间)
     = Certificate (门锁钥匙)

Wave 2 - Observability (装修和设施):
  └─ 装修、安装监控摄像头、wifi
     = Loki (监控录像)
     = Grafana (监控屏幕)
     = Fluent Bit (摄像头)
     = Traefik (大门)
```

### 开餐厅的顺序

```
Wave 0 - Foundation:
  └─ 申请营业执照、消防许可
     = cert-manager (自动办证)
     = sealed-secrets (保管重要文件)

Wave 1 - Core:
  └─ 租店面、装修厨房
     = Namespace (店面)
     = Certificate (营业执照)

Wave 2 - Observability:
  └─ 安装监控、装wifi、做广告牌
     = Loki + Fluent Bit (监控系统)
     = Grafana (查看监控)
     = Traefik (店面门牌和导航)
```

---

## 🔍 如何验证每层部署了什么

### 验证 Foundation 层

```bash
# 检查 cert-manager
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager

# 检查 sealed-secrets
kubectl get deployment -n kube-system sealed-secrets-controller
kubectl get crd sealedsecrets.bitnami.com
```

### 验证 Core 层

```bash
# 检查 namespace
kubectl get namespace revieu-prod

# 检查 ClusterIssuer
kubectl get clusterissuer

# 检查 Certificate
kubectl get certificate -n revieu-prod
```

### 验证 Observability 层

```bash
# 检查 Loki
kubectl get statefulset -n logging loki

# 检查 Grafana
kubectl get deployment -n logging grafana

# 检查 Fluent Bit
kubectl get daemonset -n logging fluent-bit

# 检查 Traefik
kubectl get deployment -n kube-system traefik
kubectl get svc -n kube-system traefik
```

现在你明白这 4 个文件各自的作用了吗？ 😊
