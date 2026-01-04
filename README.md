# RevieU Infrastructure (K3s + Traefik + SSL)

本项目基于 **K3s** 构建，使用 **Kustomize** 进行资源管理，集成了 **Traefik** 作为 Ingress Controller，并通过 **cert-manager** 实现了基于 ACME (Let's Encrypt) 的自动化 SSL 证书签发。

## 🏗️ 架构概览

- **网关层**: K3s 内置 Traefik，负责 HTTPS 卸载和路由转发。
- **证书管理**: `cert-manager` 配合 `ClusterIssuer` 使用 HTTP-01 挑战自动申请证书。
- **鉴权层**: 采用 Traefik 的 `ForwardAuth` 中间件模式，流量在到达业务前先由 `auth-service` 验证。
- **配置管理**: `base/` 存放通用模板，`overlays/prod/` 存放生产环境特有的镜像 Tag、副本数和邮箱配置。

## 📂 目录结构

```text
revieu-infra/
├── base/                   # 基础配置
│   ├── auth/               # Auth 后端服务 (Deployment, Service)
│   ├── web/                # Web 前端服务 (Deployment, Service, Ingress, Certificate)
│   ├── namespace.yaml      # 命名空间定义
│   ├── cluster-issuer.yaml # SSL 签发机构模板
│   └── traefik-auth-middleware.yaml # 鉴权中间件定义
└── overlays/               # 环境差异化配置
    └── prod/               # 生产环境
        └── kustomization.yaml # 包含生产环境的 Patch (邮箱、镜像 Tag)
```

## �️ 安装环境与组件

### 1. 安装 K3s (基础底座)
在干净的 Linux 机器上执行标准安装：
```bash
# 标准安装
curl -sfL https://get.k3s.io | sh -

# 中国大陆镜像加速安装 (可选)
# curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -
```

配置 `kubectl` 权限：
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
source ~/.bashrc
```

### 2. 安装 Helm (客户端)
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 3. 安装 cert-manager (SSL 自动化)
```bash
# 添加并更新仓库
helm repo add jetstack https://charts.jetstack.io
helm repo update

# 安装 cert-manager (包含 CRD)
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --set installCRDs=true
```

---

## �🚀 部署指南 (Project Deployment)

### 1. 准备工作 (Secrets)
在应用配置前，需手动在集群中创建以下 Secret（出于安全考虑未放入 Git）：

```bash
# 1. GitHub 私有镜像拉取密钥
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<GITHUB_USER> \
  --docker-password=<PAT_TOKEN> \
  -n revieu-prod

# 2. 数据库连接密钥 (Using secrets.env)
配置 `overlays/prod/apps/auth/secrets.env` 文件。
**注意**：请勿在值两边添加引号，Kustomize 会将其作为值的一部分读取，导致认证失败。

```env
JWT_SECRET_KEY=my_super_secret_key
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_password
...
```
```

### 2. 执行部署
```bash
# 进入生产目录
cd overlays/prod/

# 应用所有配置
kubectl apply -k .
```

## 🔐 SSL 证书说明
本项目使用 **Let's Encrypt HTTP-01** 验证：
- **配置文件**: `base/cluster-issuer.yaml`
- **Prod 覆盖**: 在 `overlays/prod/kustomization.yaml` 中通过 Patch 覆盖 `email` 字段。
- **注意**: 必须确保域名解析正确，且服务器 80/443 端口对公网开放。

## 🛠️ 故障排查 (Cheat Sheet)

### 1. 证书状态
```bash
kubectl get cert -n revieu-prod         # 查看证书是否 READY
kubectl describe cert revieu-cert -n revieu-prod # 查看具体签发报错
kubectl get challenge -n revieu-prod   # 查看 ACME 挑战进度
```

### 2. 网关日志
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50
```

### 3. 服务调试
如果遇到 **500 Error**，通常是 `ForwardAuth` 无法连接到 `auth-service` 导致的：
1. 检查 Auth Pod 状态：`kubectl get pods -n revieu-prod`。
2. 查看 Auth 日志：`kubectl logs -l app=revieu-auth -n revieu-prod`。
3. **临时绕过**: 在 `base/web/ingress.yaml` 中注释掉 `middlewares` 注解，重新 `apply` 即可。

## ⚠️ 避坑指南 (Lessons Learned)

在本项目部署过程中，我们总结了以下高频错误及解决方法：

### 1. SSL 签发失败: "forbidden domain example.com"
*   **现象**: `kubectl describe clusterissuer` 显示 `ErrRegisterACMEAccount`。
*   **原因**: Let's Encrypt 不允许使用 `example.com` 等测试域名作为联系邮箱。
*   **对策**: 务必在 `overlays/prod/kustomization.yaml` 中通过 Patch 替换为真实的个人/企业邮箱。

### 2. 访问 500 错误: ForwardAuth 依赖
*   **现象**: 浏览器访问报错 500，Traefik 日志显示无法连接鉴权服务。
*   **原因**: 开启了 `ForwardAuth` 中间件，但 `revieu-auth` 服务未就绪（如镜像无法拉取、数据库连接失败）。
*   **对策**: 
    1.  确认 Auth Pod 正常运行。
    2.  调试期间可临时在 `ingress.yaml` 中注释掉 `middlewares` 逻辑以排除网关干扰。

### 3. Namespace 粘滞性
*   **注意**: 我们的 Ingress 和 Middleware 都在 `revieu-prod` 命名空间下。如果在 Ingress 注解中引用中间件，格式必须是 `NAMESPACE-NAME@kubernetescrd`，缺一不可。

### 4. 数据库认证失败: password authentication failed
*   **现象**: `revieu-auth` 日志显示 `password authentication failed for user ""postgres""`。
*   **原因**: `secrets.env` 或 `kustomization.yaml` 中的变量值被双引号包裹（如 `USER="postgres"`）。
*   **对策**: 移除所有配置文件中不必要的双引号。

## 🛡️ 生产环境建议 (Best Practices)

1.  **资源限制 (Resources)**: 建议在各 Deployment 中显式指定 `cpu/memory` 的 `requests` 和 `limits`，避免 K3s 节点因资源耗尽崩溃。
2.  **健康检查 (Liveness/Readiness)**: 为应用添加 `probes`，确保 Traefik 只把流量转给真正“活”着的容器。
3.  **HPA 扩容**: 针对 `web` 前端，建议配置 `HorizontalPodAutoscaler` 以应对突发流量。
4.  **证书监控**: 建议配置 Prometheus 监控 `cert-manager` 状态，确保证书续期进度正常。
