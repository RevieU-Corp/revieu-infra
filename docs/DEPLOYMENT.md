# RevieU-Infra 完整部署文档

## 前置要求

### 1. 服务器准备

需要至少 2 台服务器：
- **Control Plane**: cc.weijun.online (公网 IP: 142.171.3.159)
- **Worker Node**: racknerd-7829f7f (公网 IP: 142.171.114.231)
- **Database Server**: rd.liweijun.com (公网 IP: 待填写)

### 2. WireGuard VPN 配置

所有节点必须通过 WireGuard VPN 连接，形成私有网络。

#### 在所有节点上安装 WireGuard

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install wireguard -y
```

#### WireGuard IP 分配

- Control Plane (cc.weijun.online): `10.0.0.4/24`
- Worker Node (racknerd-7829f7f): `10.0.0.1/24`
- Database Server (rd.liweijun.com): `10.0.0.1/24` (与 worker 共享，如果是同一台)

#### 配置示例 (待根据实际情况调整)

**Control Plane `/etc/wireguard/wg0.conf`:**
```ini
[Interface]
PrivateKey = <control-plane-private-key>
Address = 10.0.0.4/24
ListenPort = 51820

[Peer]
# Worker Node
PublicKey = <worker-public-key>
AllowedIPs = 10.0.0.1/32
Endpoint = 142.171.114.231:51820
PersistentKeepalive = 25
```

**Worker Node `/etc/wireguard/wg0.conf`:**
```ini
[Interface]
PrivateKey = <worker-private-key>
Address = 10.0.0.1/24
ListenPort = 51820

[Peer]
# Control Plane
PublicKey = <control-plane-public-key>
AllowedIPs = 10.0.0.4/32, 10.42.0.0/24
Endpoint = 142.171.3.159:51820
PersistentKeepalive = 25
```

#### 启动 WireGuard

```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# 验证连接
ping 10.0.0.4  # 从 worker ping control plane
ping 10.0.0.1  # 从 control plane ping worker
```

### 3. K3s 预配置 (重要！)

在安装 K3s **之前**，必须创建配置文件以使用 WireGuard 接口。

#### Control Plane

```bash
sudo mkdir -p /etc/rancher/k3s

cat <<EOF | sudo tee /etc/rancher/k3s/config.yaml
flannel-iface: wg0
EOF
```

#### Worker Node

```bash
sudo mkdir -p /etc/rancher/k3s

cat <<EOF | sudo tee /etc/rancher/k3s/config.yaml
flannel-iface: wg0
EOF
```

⚠️ **警告**: 如果没有在安装前配置 `flannel-iface: wg0`，K3s 会使用公网接口 (eth0)，导致跨节点 Pod 无法通信。修复需要删除 flannel 接口并重启 K3s。

### 4. 数据库配置

#### 在数据库服务器上安装 PostgreSQL

```bash
sudo apt update
sudo apt install postgresql-18 -y
```

#### 创建数据库和用户

```bash
sudo -u postgres psql

CREATE DATABASE revieu;
CREATE USER postgres WITH PASSWORD '123456';
GRANT ALL PRIVILEGES ON DATABASE revieu TO postgres;
\q
```

#### 配置 PostgreSQL 允许 WireGuard 网络访问

编辑 `/etc/postgresql/18/main/pg_hba.conf`，添加：

```
# Allow WireGuard network
host    all             all             10.0.0.0/24             scram-sha-256
```

编辑 `/etc/postgresql/18/main/postgresql.conf`，确保监听所有接口：

```
listen_addresses = '*'
```

重启 PostgreSQL：

```bash
sudo systemctl restart postgresql
```

#### 验证连接

```bash
# 从 K8s 节点测试
psql -h 10.0.0.1 -U postgres -d revieu
```

## 部署步骤

### Step 1: 安装 K3s

#### 在 Control Plane 节点

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip=10.0.0.4 \
  --advertise-address=10.0.0.4 \
  --tls-san=10.0.0.4 \
  --write-kubeconfig-mode 644
```

获取 node token：

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

#### 在 Worker 节点

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.4:6443 \
  K3S_TOKEN=<node-token-from-control-plane> \
  sh -
```

#### 验证集群

```bash
kubectl get nodes
# 应显示两个节点都是 Ready 状态

# 验证 flannel 使用 WireGuard 接口
ip -d link show flannel.1
# 应显示: vxlan ... local 10.0.0.x dev wg0
```

### Step 2: 部署 ArgoCD 和基础设施

在 control plane 节点执行：

```bash
curl -sfL https://raw.githubusercontent.com/RevieU-Corp/revieu-infra/main/scripts/bootstrap.sh | bash -s prod
```

等待所有组件就绪：

```bash
# 检查 ArgoCD
kubectl get pods -n argocd

# 检查 cert-manager
kubectl get pods -n cert-manager

# 检查证书签发
kubectl get certificate -A
```

### Step 3: 配置 Backend Secrets

#### 在 Backend 仓库配置密钥

编辑 `revieu-backend/apps/core/configs/secrets.yaml` (本地，不提交)：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: core-secrets
  namespace: revieu-prod
type: Opaque
stringData:
  DB_PASSWORD: "123456"
  JWT_SECRET: "your-jwt-secret-min-32-chars"
  GOOGLE_CLIENT_ID: "your-google-client-id"
  GOOGLE_CLIENT_SECRET: "your-google-client-secret"
  FRONTEND_URL: "https://revieu.weijun.online"
  SMTP_USERNAME: "your-email@gmail.com"
  SMTP_PASSWORD: "your-app-password"
  SMTP_FROM: "your-email@gmail.com"
```

#### 加密 Secrets

```bash
cd revieu-backend
./scripts/seal-secrets.sh
```

这会生成 `apps/core/configs/sealed-secrets.yaml`，提交到 git。

#### 更新 Infra 仓库引用

编辑 `revieu-infra/apps/overlays/prod/applications/core/kustomization.yaml`，更新 sealed-secrets URL 为最新的 commit。

### Step 4: 验证部署

```bash
# 检查所有 pods
kubectl get pods -A

# 检查应用
kubectl get pods -n revieu-prod

# 测试后端 API
curl https://revieu.weijun.online/api/v1/health
# 应返回: {"status":"ok"}

# 测试前端
curl https://revieu.weijun.online
```

## 故障排查

### 跨节点 Pod 无法通信

**症状**: Gateway Timeout，Pod 无法 ping 通其他节点的 Pod

**检查**:
```bash
# 检查 flannel 接口
ip -d link show flannel.1

# 如果显示 "dev eth0" 而不是 "dev wg0"，需要修复
```

**修复**:
```bash
# 1. 确保配置文件正确
cat /etc/rancher/k3s/config.yaml
# 应只包含: flannel-iface: wg0

# 2. 删除旧的 flannel 接口
ip link delete flannel.1

# 3. 重启 K3s
# Control plane:
systemctl restart k3s

# Worker:
systemctl restart k3s-agent

# 4. 验证修复
ip -d link show flannel.1  # 应显示 "dev wg0"
```

### ArgoCD 无法同步

**症状**: Application 卡在 Syncing 状态

**检查**:
```bash
# 检查 ArgoCD server 日志
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# 检查 NetworkPolicy
kubectl get networkpolicy -n argocd
```

**可能的原因**: ArgoCD NetworkPolicy 阻止出站流量，参见 `MEMORY.md`。

### 证书未签发

**症状**: Certificate 状态不是 Ready

**检查**:
```bash
kubectl describe certificate -n revieu-prod revieu-cert

# 检查 cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

## 关键配置文件位置

- **K3s 配置**: `/etc/rancher/k3s/config.yaml`
- **WireGuard 配置**: `/etc/wireguard/wg0.conf`
- **PostgreSQL 配置**: `/etc/postgresql/18/main/`
- **K3s Service**: `/etc/systemd/system/k3s.service`
- **Kubeconfig**: `/etc/rancher/k3s/k3s.yaml`

## 安全注意事项

1. **密钥管理**: 所有明文密钥文件 (secrets.yaml) 不要提交到 git
2. **WireGuard 密钥**: 私钥必须保密，不同节点使用不同的密钥对
3. **数据库密码**: 生产环境使用强密码
4. **防火墙**: 确保只有必要的端口对外开放
   - K3s API: 6443 (仅对 VPN 开放)
   - WireGuard: 51820 (UDP)
   - HTTP/HTTPS: 80, 443

## 备份和恢复

### 备份关键数据

```bash
# 1. 备份 K3s etcd/SQLite 数据
sudo tar czf k3s-backup-$(date +%Y%m%d).tar.gz /var/lib/rancher/k3s/server

# 2. 备份数据库
pg_dump -h 10.0.0.1 -U postgres revieu > revieu-backup-$(date +%Y%m%d).sql

# 3. 备份配置文件
tar czf config-backup-$(date +%Y%m%d).tar.gz \
  /etc/rancher/k3s \
  /etc/wireguard \
  /etc/systemd/system/k3s.service
```

### 恢复

参考官方文档: https://docs.k3s.io/backup-restore

## 参考资料

- [K3s 官方文档](https://docs.k3s.io/)
- [K3s 网络配置](https://docs.k3s.io/installation/network-options)
- [WireGuard 快速入门](https://www.wireguard.com/quickstart/)
- [ArgoCD 文档](https://argo-cd.readthedocs.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
