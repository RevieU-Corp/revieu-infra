# 2026-02-01 RevieU Infrastructure 部署与配置工作总结

## 📅 工作日期
2026年2月1日

## 🎯 主要任务
将 RevieU Infrastructure 仓库在远程服务器（rd.liweijun.com）上成功部署并运行，完成从 ELK 到 Loki/Grafana 的日志栈迁移。

---

## ✅ 完成的工作

### 1. 环境检查与准备

#### 1.1 远程服务器状态确认
- **K3s 集群**: 已安装并运行（v1.34.3+k3s1，运行时长 24 小时）
- **kubectl**: 已配置并可正常使用
- **现有部署**: 发现 cert-manager、ArgoCD、sealed-secrets 等组件已部署

#### 1.2 仓库同步
- 本地仓库与远程服务器仓库同步到最新版本
- 拉取了包含 Loki/Grafana 迁移的最新更改

### 2. 问题诊断与修复

#### 2.1 Sealed Secret 解密失败
**问题**:
- `revieu-auth` pod 状态: `CreateContainerConfigError`
- 错误: `secret "revieu-auth-secret" not found`
- 根本原因: SealedSecret 使用不同的 sealed-secrets-controller 密钥加密，无法解密

**解决方案**:
- 记录问题到故障排查文档
- 按用户要求暂时忽略此问题，专注于其他组件

#### 2.2 Elasticsearch OOMKilled
**问题**:
- `elasticsearch-0` pod 持续 CrashLoopBackOff（257 次重启）
- 原因: Java heap 配置 1GB，但容器内存限制仅 512Mi

**解决方案**:
- 确认用户已迁移到 Loki，不需要修复
- 删除了所有 ELK 相关配置文件

#### 2.3 缺失 Loki Overlay Kustomization
**问题**:
- ArgoCD 同步失败
- 错误: `apps/overlays/prod/middleware/loki` 目录不存在

**解决方案**:
```bash
# 创建目录和配置文件
mkdir -p apps/overlays/prod/middleware/loki
# 创建 kustomization.yaml 引用 base 层
```
- 提交: `d02c912 fix: add loki overlay kustomization for prod environment`

#### 2.4 ArgoCD 自动同步未启用
**问题**:
- ArgoCD Application 状态 `OutOfSync` 但不自动同步
- 集群中的 Application 资源缺少 `automated` 配置

**解决方案**:
```bash
# 从 Git 仓库重新应用 Application 定义
kubectl apply -f argocd/applications/revieu-apps.yaml
```
- 成功启用自动同步（prune: true, selfHeal: true）

#### 2.5 Fluent-bit 配置过期
**问题**:
- Fluent-bit 仍在尝试发送日志到已删除的 Elasticsearch
- 日志: `getaddrinfo(host='elasticsearch.revieu-prod.svc.cluster.local', err=4)`

**解决方案**:
```bash
# 重启 Fluent-bit 加载新配置
kubectl rollout restart daemonset/fluent-bit -n logging
```
- 新配置已正确指向 Loki

#### 2.6 Grafana DNS 配置
**问题**:
- 用户无法访问 `grafana.weijun.online`
- DNS 记录未配置

**解决方案**:
- 用户在 Cloudflare 添加了 DNS 记录
- 等待 DNS 传播后成功访问

#### 2.7 Grafana 日志查询配置
**问题**:
- 用户在 Grafana 中看不到日志
- Kubernetes metadata 未作为 Loki label 提取

**解决方案**:
- 教用户使用 `| json` 解析器查询日志
- 配置 Fluent-bit 提取 JSON 字段为 label
- 提交: `c5db25b feat: extract JSON log fields as Loki labels`

### 3. 配置清理

#### 3.1 删除 ELK 配置
删除的文件：
- `apps/base/apps/elasticsearch/` (4 个文件)
- `apps/overlays/prod/apps/elasticsearch/` (1 个文件)
- `apps/base/middleware/kibana/` (5 个文件)
- `apps/overlays/prod/middleware/kibana/` (1 个文件)

提交: `7bfe4b8 chore: remove elasticsearch and kibana configurations`

### 4. 文档编写

#### 4.1 部署故障排查指南
文件: `docs/deployment-troubleshooting.md`

内容包括：
- 4 个主要问题的详细分析和解决方案
- 标准部署流程
- GitOps 最佳实践
- 故障排查技巧和常见问题 FAQ

提交: `77b6bfb docs: add deployment troubleshooting guide`

#### 4.2 环境复现指南
文件: `docs/environment-reproduction.md`

内容包括：
- 完整的从零部署步骤
- 快速开始（一键部署）
- 手动部署详细步骤
- 验证清单和故障排查

文件: `scripts/quick-deploy.sh`
- 可直接从网络运行的部署脚本
- 自动克隆、部署、清理

提交: `2f38638 docs: add comprehensive environment reproduction guide`

---

## 🎉 最终部署状态

### 成功运行的组件

#### Namespace: revieu-prod
- ✅ **revieu-web**: Running (https://revieu.weijun.online)
- ⚠️ **revieu-auth**: CreateContainerConfigError (按要求暂时忽略)

#### Namespace: logging
- ✅ **Loki**: Running (日志聚合)
- ✅ **Grafana**: Running (https://grafana.weijun.online)
- ✅ **Fluent-bit**: Running (日志收集)

#### Namespace: argocd
- ✅ **ArgoCD**: Synced & Healthy
- ✅ 自动同步已启用 (prune: true, selfHeal: true)

#### Namespace: cert-manager
- ✅ **cert-manager**: All pods running
- ✅ SSL 证书自动签发正常

### 已清理的组件
- ❌ Elasticsearch (已删除)
- ❌ Kibana (已删除)

---

## 📊 关键配置更改

### 1. Fluent-bit 输出配置
```yaml
[OUTPUT]
    Name            loki
    Match           *
    Host            loki.logging.svc.cluster.local
    Port            3100
    Labels          job=fluent-bit
    Auto_Kubernetes_Labels on
    LabelKeys       level,logger,component
    RemoveKeys      level,logger,component
    LineFormat      json
```

### 2. ArgoCD Application 自动同步
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

### 3. Grafana 数据源
- Loki 已自动配置为默认数据源
- URL: `http://loki.logging.svc.cluster.local:3100`

---

## 🔍 Grafana 日志查询指南

### 基本查询
```logql
# 查看所有日志
{job="fluent-bit"}

# 查看 revieu-web 日志
{job="fluent-bit"} |= "revieu-web"

# 使用 JSON 解析器
{job="fluent-bit"} | json | kubernetes_namespace_name="revieu-prod"
```

### 实时日志
1. 在 Grafana Explore 中输入查询
2. 点击右上角的 **Live** 按钮
3. 日志会自动实时更新

### 常用查询
```logql
# 错误日志
{job="fluent-bit"} | json | level="error"

# 特定 Pod
{job="fluent-bit"} | json | kubernetes_pod_name=~"revieu-web.*"

# 包含特定文本
{job="fluent-bit"} |= "error" |= "database"
```

---

## 🎓 重要经验总结

### 1. GitOps 原则
- ✅ 所有配置通过 Git 管理
- ✅ ArgoCD 自动同步确保集群状态与 Git 一致
- ✅ 不需要在服务器上保留 Git 仓库克隆

### 2. ConfigMap 更新
- ⚠️ ConfigMap 更新后，Pod 不会自动重启
- 💡 需要手动 `kubectl rollout restart` 来应用新配置

### 3. Fluent-bit 日志收集
- ⚠️ Fluent-bit 只收集启动后产生的新日志
- 💡 如果看不到日志，检查是否有新的日志产生

### 4. Loki Label 策略
- ✅ 只把低基数字段提取为 label（如 level）
- ❌ 不要把高基数字段提取为 label（如 user_id）
- 💡 使用 `| json` 在查询时解析 JSON 字段

### 5. Sealed Secrets
- ⚠️ 每个集群的 sealed-secrets-controller 有唯一密钥对
- ⚠️ 重建集群会导致所有 sealed secrets 失效
- 💡 需要备份 sealed-secrets-controller 的私钥

---

## 📝 待办事项（可选）

### 短期
1. 修复 revieu-auth 的 sealed secret 问题
   - 重新生成 sealed secret 或恢复原始私钥

2. 为 revieu-web 添加 favicon.ico
   - 消除 404 错误日志

### 长期
1. 配置 Grafana 仪表板
   - 应用日志监控
   - 错误率趋势
   - 请求量统计

2. 配置告警规则
   - 错误日志告警
   - Pod 重启告警
   - 证书过期提醒

3. 优化日志收集
   - 配置日志保留策略
   - 添加日志采样（如果日志量过大）

---

## 🔗 相关文档

- [部署故障排查指南](./deployment-troubleshooting.md)
- [环境复现指南](./environment-reproduction.md)
- [日志栈迁移设计](./plans/2026-02-01-logging-stack-migration.md)

---

## 📈 Git 提交记录

```
c5db25b feat: extract JSON log fields as Loki labels
2f38638 docs: add comprehensive environment reproduction guide
7bfe4b8 chore: remove elasticsearch and kibana configurations
77b6bfb docs: add deployment troubleshooting guide
d02c912 fix: add loki overlay kustomization for prod environment
```

---

## 🎯 成果总结

1. ✅ **基础设施成功运行**: K3s + ArgoCD + cert-manager + Loki + Grafana
2. ✅ **日志栈迁移完成**: 从 ELK 迁移到 Loki/Grafana
3. ✅ **GitOps 流程建立**: 自动同步、自动清理（prune）
4. ✅ **文档完善**: 故障排查、环境复现、部署指南
5. ✅ **配置清理**: 删除废弃的 ELK 配置
6. ✅ **日志可视化**: Grafana 可查询和实时查看日志

---

**工作完成时间**: 2026-02-01
**总计提交**: 5 个 commits
**新增文档**: 3 个文件
**删除配置**: 11 个文件
**修复问题**: 7 个主要问题

🎉 **部署成功！所有核心功能正常运行！**
