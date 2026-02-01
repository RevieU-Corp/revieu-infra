# RevieU Infrastructure 环境复现指南

本文档说明如何从零开始完整复现 RevieU 生产环境。

## 前置条件

- 一台干净的 Linux 服务器（Ubuntu/Debian/CentOS）
- Root 权限或 sudo 权限
- 服务器可以访问互联网
- 域名 DNS 已正确配置指向服务器 IP
- 80/443 端口对外开放（用于 Let's Encrypt 验证）

## 快速开始（一键部署）

```bash
curl -fsSL https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/scripts/quick-deploy.sh | bash
```

## 手动部署步骤

### 步骤 1: 安装 K3s

```bash
# 标准安装
curl -sfL https://get.k3s.io | sh -

# 或使用中国镜像（可选）
# curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -

# 配置 kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# 验证安装
kubectl get nodes
```

### 步骤 2: 运行 Bootstrap 脚本

```bash
# 临时克隆仓库
git clone --depth 1 https://github.com/RevieU-Corp/revieu-infra.git /tmp/revieu-infra

# 运行 bootstrap 脚本
cd /tmp/revieu-infra
bash scripts/bootstrap.sh

# 清理临时文件
cd ~
rm -rf /tmp/revieu-infra
```

### 步骤 3: 验证部署

```bash
# 检查 ArgoCD 应用状态
kubectl get applications -n argocd

# 应该看到：
# NAME                  SYNC STATUS   HEALTH STATUS
# argocd-self-managed   Synced        Healthy
# revieu-apps           Synced        Progressing/Healthy

# 检查所有 Pod 状态
kubectl get pods -n revieu-prod
kubectl get pods -n logging
kubectl get pods -n argocd

# 检查 Ingress 和证书
kubectl get ingress,certificate -A
```

### 步骤 4: 获取 ArgoCD 管理密码（可选）

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
```

访问 ArgoCD UI（如果配置了 Ingress）或使用端口转发：
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# 访问 https://localhost:8080
```

## 详细部署步骤（不使用 Bootstrap 脚本）

如果你想了解每一步的细节，或者 bootstrap 脚本失败，可以手动执行：

### 1. 安装 cert-manager

```bash
# 方法 A: 使用 Kustomize（需要临时克隆仓库）
git clone --depth 1 https://github.com/RevieU-Corp/revieu-infra.git /tmp/infra
kubectl apply -k /tmp/infra/apps/overlays/prod/middleware/cert-manager
rm -rf /tmp/infra

# 方法 B: 使用 Helm
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.0 \
  --set installCRDs=true

# 等待 cert-manager 就绪
kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=120s
kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=120s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=300s
```

### 2. 安装 ArgoCD

```bash
# 创建命名空间
kubectl create namespace argocd

# 方法 A: 使用仓库中的配置（需要临时克隆）
git clone --depth 1 https://github.com/RevieU-Corp/revieu-infra.git /tmp/infra
kubectl apply -k /tmp/infra/apps/overlays/prod/apps/argocd
rm -rf /tmp/infra

# 方法 B: 使用官方安装
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待 ArgoCD 就绪
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=60s
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
```

### 3. 应用 ArgoCD Applications

```bash
# 直接从 GitHub 应用
kubectl apply -f https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/argocd/applications/argocd.yaml
kubectl apply -f https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/argocd/applications/revieu-apps.yaml

# 或者临时克隆
git clone --depth 1 https://github.com/RevieU-Corp/revieu-infra.git /tmp/infra
kubectl apply -f /tmp/infra/argocd/applications/
rm -rf /tmp/infra
```

### 4. 等待自动同步

ArgoCD 会自动从 GitHub 拉取配置并部署所有资源。这可能需要几分钟。

```bash
# 监控同步进度
watch kubectl get applications -n argocd

# 查看 Pod 部署进度
watch kubectl get pods -A
```

## 故障排查

### ArgoCD 应用显示 OutOfSync

```bash
# 检查同步策略
kubectl -n argocd get application revieu-apps -o jsonpath='{.spec.syncPolicy}' | jq .

# 如果缺少 automated 配置，重新应用 Application 定义
kubectl apply -f https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/argocd/applications/revieu-apps.yaml
```

### 证书未签发

```bash
# 检查证书状态
kubectl get certificate -A
kubectl describe certificate <cert-name> -n <namespace>

# 检查 cert-manager 日志
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# 常见问题：
# 1. DNS 未正确解析
# 2. 80 端口未开放
# 3. 邮箱配置错误（不能使用 example.com）
```

### Pod 一直 Pending

```bash
# 检查 Pod 详情
kubectl describe pod <pod-name> -n <namespace>

# 常见原因：
# 1. PVC 未创建成功
# 2. 节点资源不足
# 3. 镜像拉取失败
```

## 环境清理

如果需要完全清理环境重新开始：

```bash
# 卸载 K3s（会删除所有资源）
/usr/local/bin/k3s-uninstall.sh

# 然后重新开始部署流程
```

## 重要提醒

### ⚠️ Sealed Secrets 问题

如果你是在新集群上部署，sealed secrets 将无法解密（因为加密密钥不同）。你需要：

1. 重新生成 sealed secrets，或
2. 恢复原始 sealed-secrets-controller 的私钥

详见：[部署故障排查指南](./deployment-troubleshooting.md#1-sealed-secret-无法解密)

### ⚠️ 域名配置

确保以下域名正确解析到服务器 IP：
- `revieu.weijun.online` → Web 应用
- `grafana.weijun.online` → Grafana 监控

### ⚠️ 端口开放

确保防火墙开放以下端口：
- `80/TCP` - HTTP（Let's Encrypt 验证）
- `443/TCP` - HTTPS
- `6443/TCP` - K3s API（如果需要远程访问）

## 验证清单

部署完成后，检查以下项目：

- [ ] K3s 节点状态为 Ready
- [ ] ArgoCD 应用状态为 Synced
- [ ] 所有 Pod 状态为 Running（除了已知的失败 Pod）
- [ ] Ingress 已创建并有 ADDRESS
- [ ] Certificate 状态为 Ready
- [ ] 可以通过域名访问 Web 应用
- [ ] 可以通过域名访问 Grafana
- [ ] HTTPS 证书有效

## 后续维护

部署完成后，**不需要**在服务器上保留 Git 仓库。所有更新通过以下流程：

```
本地修改 → Git Push → ArgoCD 自动同步 → 集群更新
```

如果需要更新 ArgoCD Application 定义本身：
```bash
kubectl apply -f https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/argocd/applications/revieu-apps.yaml
```

## 参考文档

- [部署故障排查指南](./deployment-troubleshooting.md)
- [日志栈迁移设计](./plans/2026-02-01-logging-stack-migration.md)
- [K3s 官方文档](https://docs.k3s.io/)
- [ArgoCD 官方文档](https://argo-cd.readthedocs.io/)

---

最后更新：2026-02-01
