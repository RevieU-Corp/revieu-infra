# Sealed Secrets 管理指南

## 📋 概述

使用 Bitnami Sealed Secrets 加密敏感信息，安全地存储在 Git 仓库中。

## 🔑 公钥位置

- **Prod**: `secrets/sealed-secrets-prod.pem`
- **Staging**: `secrets/sealed-secrets-staging.pem`（待生成）
- **Dev**: `secrets/sealed-secrets-dev.pem`（待生成）

## 📝 Secret 模板

### 1. Cloudflare API Token（cert-manager DNS01）

**模板**: `secrets/cloudflare-api-token-secret.yaml.template`

**用途**: cert-manager 使用 DNS01 challenge 自动签发 Let's Encrypt 证书

**配置步骤**:
```bash
# 1. 复制模板
cp secrets/cloudflare-api-token-secret.yaml.template secrets/cloudflare-api-token-secret.yaml

# 2. 编辑并填入你的 Cloudflare API Token
vim secrets/cloudflare-api-token-secret.yaml
# 替换 <YOUR_CLOUDFLARE_API_TOKEN>

# 3. 使用 kubeseal 加密
kubeseal --format yaml --cert secrets/sealed-secrets-prod.pem \
  < secrets/cloudflare-api-token-secret.yaml \
  > apps/overlays/shared/platform/cloudflare-api-token-sealed.yaml

# 4. 删除明文文件
rm secrets/cloudflare-api-token-secret.yaml

# 5. 提交加密后的 SealedSecret
git add apps/overlays/shared/platform/cloudflare-api-token-sealed.yaml
git commit -m "feat(secrets): add cloudflare API token for DNS01"
git push
```

### 2. GitHub Container Registry Credentials

**模板**: `secrets/ghcr-credentials-secret.yaml.template`

**用途**: 拉取 ghcr.io 私有镜像

**配置步骤**:
```bash
# 1. 创建 GitHub PAT
# 访问 https://github.com/settings/tokens/new?scopes=read:packages
# 创建一个带 read:packages 权限的 token

# 2. 复制模板
cp secrets/ghcr-credentials-secret.yaml.template secrets/ghcr-credentials-secret.yaml

# 3. 编辑并填入信息
vim secrets/ghcr-credentials-secret.yaml
# 替换:
#   - <YOUR_GITHUB_USERNAME>
#   - <YOUR_GITHUB_TOKEN>
#   - namespace（根据环境修改）

# 4. 为每个环境加密
# Prod:
kubeseal --format yaml --cert secrets/sealed-secrets-prod.pem \
  --namespace revieu-prod \
  < secrets/ghcr-credentials-secret.yaml \
  > apps/overlays/prod/common/ghcr-credentials-sealed.yaml

# Staging:
kubeseal --format yaml --cert secrets/sealed-secrets-staging.pem \
  --namespace revieu-staging \
  < secrets/ghcr-credentials-secret.yaml \
  > apps/overlays/staging/common/ghcr-credentials-sealed.yaml

# Dev:
kubeseal --format yaml --cert secrets/sealed-secrets-dev.pem \
  --namespace revieu-dev \
  < secrets/ghcr-credentials-secret.yaml \
  > apps/overlays/dev/common/ghcr-credentials-sealed.yaml

# 5. 删除明文文件
rm secrets/ghcr-credentials-secret.yaml

# 6. 提交
git add apps/overlays/*/common/*-sealed.yaml
git commit -m "feat(secrets): add GitHub registry credentials"
git push
```

## 🔄 更新 ClusterIssuer 使用 Cloudflare Token

更新 `apps/base/common/cluster-issuer.yaml` 以使用 Cloudflare API token：

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

## 🔄 更新 Deployment 使用 GitHub Credentials

在 `apps/base/apps/web/deployment.yaml` 和 `apps/base/apps/core/deployment.yaml` 中添加：

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-credentials
```

## 🛠️ 故障排查

### 获取新的公钥（如果 sealed-secrets controller 重新部署）

```bash
# Prod
ssh root@cc.weijun.online "kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o jsonpath='{.items[0].data.tls\.crt}'" | base64 -d > secrets/sealed-secrets-prod.pem

# Staging
ssh root@staging-server "kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o jsonpath='{.items[0].data.tls\.crt}'" | base64 -d > secrets/sealed-secrets-staging.pem

# Dev
ssh root@dev-server "kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o jsonpath='{.items[0].data.tls\.crt}'" | base64 -d > secrets/sealed-secrets-dev.pem
```

### 验证 SealedSecret 是否正确解密

```bash
# 检查 SealedSecret 状态
kubectl get sealedsecret -n cert-manager
kubectl get sealedsecret -n revieu-prod

# 检查生成的 Secret
kubectl get secret cloudflare-api-token -n cert-manager
kubectl get secret ghcr-credentials -n revieu-prod

# 查看 sealed-secrets controller 日志
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

## 📁 目录结构

```
revieu-infra/
├── secrets/
│   ├── sealed-secrets-prod.pem          # 公钥（可提交）
│   ├── README.md                        # 本文件
│   ├── *.yaml.template                  # Secret 模板（可提交）
│   └── *.yaml                           # 明文 Secret（不提交，添加到 .gitignore）
└── apps/overlays/*/common/
    └── *-sealed.yaml                    # 加密的 SealedSecret（可安全提交）
```

## ⚠️ 安全注意事项

1. **永远不要**提交明文 Secret（`secrets/*.yaml`）到 Git
2. **只提交**加密后的 SealedSecret（`apps/overlays/*/common/*-sealed.yaml`）
3. 公钥可以安全提交，私钥由 sealed-secrets controller 管理
4. 定期轮换敏感 token
5. 使用最小权限原则创建 API token
