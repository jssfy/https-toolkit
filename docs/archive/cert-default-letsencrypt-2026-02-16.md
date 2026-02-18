# 证书管理默认改为 Let's Encrypt

## 核心结论

- ✅ **默认证书方案改为 Let's Encrypt**（原为 mkcert）
- ✅ 完整实现 DNS-01 验证支持
- ✅ 支持阿里云、Cloudflare、DNSPod 等 DNS 提供商
- ✅ 保留 mkcert 选项供本地开发使用
- ⚠️ **首次使用需配置 DNS API 凭证**

---

## 变更说明

### 调整内容

#### 1. Makefile 命令变更

**变更前**：
```bash
make cert-generate      # 默认使用 mkcert
```

**变更后**：
```bash
make cert-generate           # 默认使用 Let's Encrypt
make cert-generate-mkcert    # 使用 mkcert（本地开发）
make cert-setup-dns          # 配置 DNS API 凭证（新增）
```

#### 2. docker-up-https 行为变更

**变更前**：
```bash
make docker-up-https  # 自动使用 mkcert 生成证书
```

**变更后**：
```bash
make docker-up-https  # 自动使用 Let's Encrypt 生成证书
                      # 需要先配置 DNS API 凭证
```

#### 3. cert-manager.sh 默认方法

**变更前**：
```bash
./scripts/cert-manager.sh generate  # 默认 mkcert
```

**变更后**：
```bash
./scripts/cert-manager.sh generate  # 默认 letsencrypt
```

---

## 迁移指南

### 对现有用户的影响

#### 场景 1：本地开发用户（使用 mkcert）

**无影响**，继续使用 mkcert：

```bash
# 删除现有证书
make cert-clean

# 使用 mkcert 生成
make cert-generate-mkcert

# 启动服务
make docker-up-https
```

#### 场景 2：生产环境用户（需要全球信任证书）

**需要配置 DNS API**：

```bash
# 1. 配置 DNS API 凭证
make cert-setup-dns
vim ~/.secrets/dns-credentials.ini

# 2. 安装 DNS 插件
pip3 install certbot-dns-aliyun

# 3. 生成证书
make cert-generate

# 4. 启动服务
make docker-up-https
```

#### 场景 3：首次使用用户

**推荐使用 mkcert**（本地开发）：

```bash
# 直接启动，自动生成 Let's Encrypt 证书
make docker-up-https
# 会提示配置 DNS API

# 或使用 mkcert（更简单）
make cert-generate-mkcert
make docker-up-https
```

---

## 首次配置 Let's Encrypt

### 步骤 1：配置 DNS API

```bash
# 创建配置文件模板
make cert-setup-dns

# 编辑配置文件
vim ~/.secrets/dns-credentials.ini
```

**阿里云配置示例**：
```ini
dns_aliyun_access_key = LTAIxxxxxxxxxxxxx
dns_aliyun_access_key_secret = xxxxxxxxxxxxxxxxxxxxxxxx
```

### 步骤 2：安装 DNS 插件

```bash
# 阿里云
pip3 install certbot-dns-aliyun

# Cloudflare
pip3 install certbot-dns-cloudflare

# DNSPod
pip3 install certbot-dns-dnspod
```

### 步骤 3：生成证书

```bash
# 自动检测 DNS 提供商并生成
make cert-generate

# 或启动服务（自动生成）
make docker-up-https
```

---

## 命令对照表

| 操作 | 旧命令 | 新命令 |
|------|--------|--------|
| 生成证书（默认） | `make cert-generate` (mkcert) | `make cert-generate` (Let's Encrypt) |
| 生成 mkcert 证书 | `make cert-generate` | `make cert-generate-mkcert` |
| 生成 Let's Encrypt | 不支持 | `make cert-generate` |
| 配置 DNS API | N/A | `make cert-setup-dns` |
| HTTPS 启动 | `make docker-up-https` | `make docker-up-https` |

---

## 为什么改为 Let's Encrypt？

### 优势

1. **全球浏览器信任**
   - mkcert：仅本机信任
   - Let's Encrypt：全球所有浏览器和操作系统信任

2. **适合生产环境**
   - mkcert：仅限开发环境
   - Let's Encrypt：可用于生产环境

3. **证书兼容性**
   - mkcert：需要每台机器安装 CA
   - Let's Encrypt：无需额外配置

### 权衡

| 维度 | mkcert | Let's Encrypt |
|------|--------|---------------|
| **配置复杂度** | ⭐ 简单 | ⭐⭐⭐ 中等 |
| **前置条件** | 无 | DNS API 凭证 |
| **信任范围** | 仅本机 | 全球 |
| **证书有效期** | 1-10 年 | 90 天 |
| **续期** | 无需 | 需要 |
| **适用场景** | 本地开发 | 生产环境 |

---

## 回退到 mkcert

如果需要回退到 mkcert：

```bash
# 删除现有证书
make cert-clean

# 使用 mkcert
make cert-generate-mkcert

# 重启服务
make docker-restart
```

---

## 新增文件

### 1. .env.example

环境变量配置示例，包含 DNS API 配置：

```bash
# 阿里云 DNS API
ALIYUN_ACCESS_KEY_ID=your_access_key_id
ALIYUN_ACCESS_KEY_SECRET=your_access_key_secret
```

### 2. docs/letsencrypt-setup-2026-02-16.md

Let's Encrypt 完整配置指南：
- DNS API 配置方法
- 多种 DNS 提供商支持
- 故障排查
- 自动续期设置

---

## 技术实现

### cert-manager.sh 改进

**新增功能**：

1. **完整的 Let's Encrypt 支持**
   ```bash
   generate_cert_letsencrypt() {
       # 检查 certbot
       # 检测 DNS 提供商
       # 自动安装插件
       # DNS-01 验证
       # 复制证书
   }
   ```

2. **自动 DNS 提供商检测**
   - 阿里云（dns_aliyun）
   - Cloudflare（dns_cloudflare）
   - DNSPod（dns_dnspod）

3. **友好的错误提示**
   - 缺少配置文件 → 提示配置方法
   - 缺少插件 → 提示安装命令
   - 验证失败 → 提示排查步骤

---

## 常见问题

### Q1: 我必须使用 Let's Encrypt 吗？

**不是**。可以继续使用 mkcert：

```bash
make cert-generate-mkcert
```

### Q2: Let's Encrypt 需要什么前置条件？

- DNS API 凭证（阿里云/Cloudflare/DNSPod）
- certbot 工具
- 对应的 DNS 插件

### Q3: 本地开发建议用哪个？

**推荐 mkcert**：
- 配置简单
- 无需 DNS API
- 无需续期

### Q4: 生产环境建议用哪个？

**必须用 Let's Encrypt**：
- 全球信任
- 符合标准
- 自动续期

### Q5: 如何切换证书类型？

```bash
# 删除现有证书
make cert-clean

# 生成新证书
make cert-generate           # Let's Encrypt
# 或
make cert-generate-mkcert    # mkcert

# 重启服务
make docker-restart
```

---

## 后续计划

### 短期（已完成）

- ✅ 实现 Let's Encrypt DNS-01 验证
- ✅ 支持主流 DNS 提供商
- ✅ 创建配置向导
- ✅ 完善文档

### 长期（计划中）

- [ ] 自动续期脚本
- [ ] 多域名支持
- [ ] Kubernetes Cert-Manager 集成
- [ ] HTTP-01 验证支持

---

## 相关文档

- [letsencrypt-setup-2026-02-16.md](letsencrypt-setup-2026-02-16.md) - Let's Encrypt 完整指南
- [certificate-comparison-2026-02-16.md](certificate-comparison-2026-02-16.md) - 证书方案对比
- [why-mkcert-for-local-2026-02-16.md](why-mkcert-for-local-2026-02-16.md) - 为何本地用 mkcert
- [local-https-setup-2026-02-16.md](local-https-setup-2026-02-16.md) - 本地 HTTPS 配置

---

## 变更影响总结

### ✅ 正面影响

1. **生产就绪** - 可直接用于生产环境
2. **全局信任** - 无需客户端配置
3. **标准化** - 符合 SSL/TLS 最佳实践
4. **灵活性** - 保留 mkcert 选项

### ⚠️ 需要注意

1. **首次配置** - 需要配置 DNS API（约 5 分钟）
2. **证书续期** - 90 天有效期，需定期续期
3. **依赖外部** - 依赖 DNS API 可用性
4. **网络要求** - 需要能访问 Let's Encrypt 服务

### 📊 使用建议

```
场景决策树：

是否生产环境？
├─ 是 → Let's Encrypt（必须）
└─ 否 → 是否需要多机共享证书？
        ├─ 是 → Let's Encrypt
        └─ 否 → mkcert（推荐）
```

---

## 文档更新清单

| 文档 | 更新内容 | 状态 |
|------|---------|------|
| Makefile | 新增命令和默认行为 | ✅ |
| cert-manager.sh | 实现 Let's Encrypt | ✅ |
| README.md | 更新命令说明 | ✅ |
| .env.example | 新建配置模板 | ✅ |
| letsencrypt-setup-2026-02-16.md | 新建配置指南 | ✅ |
| cert-default-letsencrypt-2026-02-16.md | 新建变更说明 | ✅ |
| docs/README.md | 更新文档索引 | ✅ |

---

## 统计信息

- **变更日期**：2026-02-16
- **影响文件**：7 个
- **新增命令**：2 个（cert-setup-dns, cert-generate-mkcert）
- **新增文档**：2 篇
- **代码行数**：约 150 行（cert-manager.sh）
