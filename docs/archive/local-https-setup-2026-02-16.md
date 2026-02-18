# 本地 HTTPS 开发环境配置

## 核心结论

- ✅ 支持一键启动 HTTPS 开发环境：`make docker-up-https`
- ✅ 使用 mkcert 生成本地可信证书（自动信任，浏览器无警告）
- ✅ 证书自动管理：检查、生成、续期
- ✅ 证书统一存储在 `~/.local-certs/yeanhua.asia/`
- ✅ 支持泛域名：`*.yeanhua.asia`、`localhost`

---

## 快速开始

### 方式 1：一键启动（推荐）

```bash
# 自动检查/生成证书并启动 HTTPS 服务
make docker-up-https

# 访问
open https://local.yeanhua.asia
```

### 方式 2：手动管理证书

```bash
# 1. 生成证书
make cert-generate

# 2. 启动 HTTPS 服务
make docker-up-https

# 3. 查看证书信息
make cert-info
```

---

## 证书管理

### 生成证书

```bash
# 使用 mkcert 生成本地开发证书（推荐）
make cert-generate

# 或手动执行
./scripts/cert-manager.sh generate mkcert
```

**首次运行时会**：
1. 安装 mkcert（如果未安装）
2. 安装本地 CA 根证书（信任根证书）
3. 生成泛域名证书：`*.yeanhua.asia`
4. 存储到 `~/.local-certs/yeanhua.asia/`

### 检查证书状态

```bash
# 检查证书是否存在及有效期
make cert-check

# 输出示例：
# [INFO] 检查证书状态...
# [INFO] 证书有效期剩余 364 天
# ✓ 证书有效，无需操作
```

### 查看证书详细信息

```bash
make cert-info

# 输出示例：
# [INFO] 证书信息:
#   Subject: CN=*.yeanhua.asia
#   Issuer: CN=mkcert yeanhua@MacBook-Pro.local
#   Not Before: Feb 16 12:00:00 2026 GMT
#   Not After : Feb 16 12:00:00 2027 GMT
#   DNS:*.yeanhua.asia
#   DNS:yeanhua.asia
#   DNS:local.yeanhua.asia
#   DNS:localhost
```

### 续期证书

```bash
# mkcert 证书有效期 1 年，到期前可以续期
make cert-renew

# 脚本会自动检测证书类型并重新生成
```

### 删除证书

```bash
# 删除本地证书（需确认）
make cert-clean
```

---

## 启动模式

### HTTP 模式（默认）

```bash
# 启动 HTTP 服务
make docker-up
# 或
make docker-up-http

# 访问地址：
#   http://local.yeanhua.asia
#   http://localhost
```

### HTTPS 模式

```bash
# 启动 HTTPS 服务（自动管理证书）
make docker-up-https

# 访问地址：
#   https://local.yeanhua.asia  🔒
#   https://localhost  🔒
#   http://local.yeanhua.asia  (自动重定向到 HTTPS)
```

### 切换模式

```bash
# 从 HTTP 切换到 HTTPS
make docker-down
make docker-up-https

# 从 HTTPS 切换到 HTTP
make docker-down
make docker-up-http
```

---

## 证书存储位置

```
~/.local-certs/yeanhua.asia/
├── fullchain.pem    # 证书（公钥）
└── privkey.pem      # 私钥
```

**特点**：
- 统一位置：所有项目共享同一证书
- 持久化：证书不会随项目删除而丢失
- 可复用：多个本地项目可以使用同一证书

---

## mkcert 工作原理

### 什么是 mkcert？

mkcert 是一个用于生成本地开发 TLS/SSL 证书的工具。

**重要**：mkcert 生成的证书需要安装本地 CA 才能被系统信任。

### 工作流程

```
1. mkcert -install
   └─ 创建本地 CA 根证书
   └─ 添加到系统信任库（钥匙串、证书存储）

2. mkcert "*.yeanhua.asia"
   └─ 使用本地 CA 签发证书

3. 浏览器访问 https://local.yeanhua.asia
   └─ 检查证书签发者
   └─ 在系统信任库中找到 mkcert CA ✓
   └─ 显示为安全连接 🔒
```

**关键点**：
- ✅ `mkcert -install` 会自动将 CA 添加到系统信任库
- ✅ 只需执行一次（首次使用时）
- ❌ 未安装 CA 的设备会显示"不安全"警告
- ⚠️ 证书只在安装了 CA 的设备上受信任

### 为什么使用 mkcert？

| 方案 | CA 安装 | 信任范围 | 优点 | 缺点 |
|------|---------|---------|------|------|
| **mkcert** | ✅ 需要<br>`mkcert -install` | 仅安装 CA 的设备 | ✅ 无需域名<br>✅ 支持泛域名<br>✅ 离线工作 | ❌ 需要手动安装 CA<br>❌ 仅限本地开发 |
| **Let's Encrypt** | ❌ 不需要<br>(预装在系统中) | 全球所有设备 | ✅ 全球自动信任<br>✅ 真实证书<br>✅ 免费 | ❌ 需要域名验证<br>❌ 需要公网访问 |
| **自签名证书** | ⚠️ 可选 | 手动信任的设备 | ✅ 快速生成 | ❌ 浏览器警告<br>❌ 不推荐使用 |

**关键区别**：

**mkcert（本地 CA）**：
```bash
# 必须安装 CA（一次性）
mkcert -install

# 生成证书
mkcert "*.yeanhua.asia"

# ✓ 本设备信任
# ✗ 其他设备不信任（除非也安装了 CA）
```

**Let's Encrypt（公共 CA）**：
```bash
# 无需安装任何东西
# Let's Encrypt CA 根证书已预装在全球所有操作系统和浏览器中

# 申请证书（需要验证域名所有权）
certbot certonly -d example.com

# ✓ 全球所有设备自动信任
# ✓ 包括手机、平板、其他用户的电脑
```

详细对比：[证书方案对比文档](certificate-comparison-2026-02-16.md)

### 安装 mkcert

```bash
# Mac
brew install mkcert

# Linux
wget https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-linux-amd64
chmod +x mkcert-linux-amd64
sudo mv mkcert-linux-amd64 /usr/local/bin/mkcert

# 验证安装
mkcert -version
```

### mkcert 工作流程

```bash
# 1. 安装本地 CA（首次运行）
mkcert -install
# 在系统钥匙串中添加可信根证书

# 2. 生成证书
mkcert "*.yeanhua.asia" "local.yeanhua.asia" "localhost"
# 创建证书文件：
#   _wildcard.yeanhua.asia+2.pem
#   _wildcard.yeanhua.asia+2-key.pem

# 3. 使用证书
# 在 nginx、node、go 等服务中配置证书路径
```

---

## 技术实现

### 目录结构

```
top-ai-news/
├── scripts/
│   └── cert-manager.sh              # 证书管理脚本
├── deploy/nginx/conf.d/
│   ├── default.conf                 # HTTP 配置
│   └── default-https.conf           # HTTPS 配置
├── docker-compose.yml               # 基础配置
└── docker-compose.https.yml         # HTTPS 覆盖配置
```

### docker-compose.https.yml

```yaml
services:
  nginx:
    volumes:
      # 挂载本地证书
      - ${HOME}/.local-certs/yeanhua.asia:/etc/nginx/ssl:ro
      # 使用 HTTPS 配置
      - ./deploy/nginx/conf.d/default-https.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "80:80"
      - "443:443"
```

### nginx HTTPS 配置

```nginx
server {
    listen 443 ssl http2;
    server_name local.yeanhua.asia localhost *.yeanhua.asia;

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    # ...
}
```

### Makefile 集成

```makefile
docker-up-https:
	# 1. 检查证书
	@if ./scripts/cert-manager.sh check; then
		echo "✓ 证书有效";
	else
		# 2. 自动生成证书
		./scripts/cert-manager.sh generate mkcert;
	fi
	# 3. 启动 HTTPS 服务
	docker compose -f docker-compose.yml -f docker-compose.https.yml up -d
```

---

## 常见问题

### 1. 浏览器显示"不安全"警告

**原因**：mkcert 根证书未安装或未信任

**解决**：
```bash
# 重新安装 mkcert CA
mkcert -uninstall
mkcert -install

# 重新生成证书
make cert-clean
make cert-generate
```

### 2. 证书文件不存在

**错误信息**：
```
nginx: [emerg] cannot load certificate "/etc/nginx/ssl/fullchain.pem"
```

**解决**：
```bash
# 检查证书
make cert-check

# 生成证书
make cert-generate

# 重启服务
make docker-up-https
```

### 3. 证书过期

**检查过期时间**：
```bash
make cert-info
```

**续期证书**：
```bash
make cert-renew
make docker-restart
```

### 4. 多个项目共享证书

**方案 1**：使用同一证书目录（推荐）

所有项目的 `docker-compose.https.yml` 都挂载同一目录：
```yaml
volumes:
  - ${HOME}/.local-certs/yeanhua.asia:/etc/nginx/ssl:ro
```

**方案 2**：每个项目独立证书

修改 `scripts/cert-manager.sh` 中的 `CERT_DIR` 变量。

### 5. 为什么必须安装 CA？

**问题**：不执行 `mkcert -install` 可以吗？

**答案**：❌ 不可以，浏览器会显示"不安全"警告

**原因**：
1. mkcert 创建的是**本地私有 CA**
2. 这个 CA **不在**操作系统的预装信任列表中
3. 浏览器无法验证证书的签发者
4. 显示为"自签名证书"或"不安全连接"

**对比**：

| 证书类型 | CA 位置 | 是否需要安装 |
|---------|--------|-------------|
| mkcert | 本地生成 | ✅ 必须 `mkcert -install` |
| Let's Encrypt | 预装在系统中 | ❌ 不需要（自动信任） |
| 自签名 | 无 CA | ⚠️ 需要手动信任每个证书 |

**验证**：
```bash
# 未安装 CA
curl https://local.yeanhua.asia
# 错误: SSL certificate problem: unable to get local issuer certificate

# 安装 CA 后
mkcert -install
curl https://local.yeanhua.asia
# ✓ 正常访问
```

### 6. Let's Encrypt 为什么不需要安装？

**问题**：为什么 Let's Encrypt 证书可以自动信任？

**答案**：Let's Encrypt CA 根证书已经**预装**在所有操作系统和浏览器中

**预装位置**：
- **macOS**：钥匙串访问 → 系统根证书
- **Windows**：certmgr.msc → 受信任的根证书颁发机构
- **Linux**：/etc/ssl/certs/
- **浏览器**：Firefox、Chrome、Safari 内置

**验证**（macOS）：
```bash
# 查看系统信任的 CA
security find-certificate -a -p \
  /System/Library/Keychains/SystemRootCertificates.keychain | \
  openssl x509 -noout -subject | grep -i "let's encrypt"
```

**结论**：
- Let's Encrypt 是**公共 CA**，全球信任
- mkcert 是**私有 CA**，仅本地信任
- 生产环境用 Let's Encrypt，开发环境用 mkcert

### 7. 在其他设备访问

**问题**：手机、其他电脑访问 HTTPS 显示不安全

**原因**：mkcert CA 只在生成证书的设备上受信任

**解决方案**：

**方案 A：在其他设备上也安装 mkcert CA**
```bash
# 1. 导出 CA 根证书
mkcert -CAROOT
# 输出: /Users/xxx/Library/Application Support/mkcert

cd "$(mkcert -CAROOT)"
ls -la
# rootCA.pem（公钥）
# rootCA-key.pem（私钥，不要分享！）

# 2. 将 rootCA.pem 复制到其他设备

# 3. 在其他设备上安装
# iOS: 设置 → 通用 → VPN与设备管理 → 安装描述文件 → 启用完全信任
# Android: 设置 → 安全 → 加密与凭据 → 从存储设备安装
# macOS: 双击 rootCA.pem → 添加到钥匙串 → 设置为"始终信任"
# Windows: 双击 rootCA.pem → 安装证书 → 受信任的根证书颁发机构
```

**⚠️ 安全警告**：
- ❌ 不要分享 `rootCA-key.pem`（私钥）
- ❌ 不要将 CA 提交到 Git
- ✅ 只分享 `rootCA.pem`（公钥）
- ✅ 团队成员最好各自生成 CA

**方案 B：使用 Let's Encrypt 真实证书**

适用于需要真实公网访问的场景：
```bash
# 使用真实域名（如 dev.example.com）
certbot certonly --dns-xxx -d dev.example.com

# ✓ 所有设备自动信任，无需额外配置
```

**方案 C：接受证书警告（不推荐）**

浏览器显示警告 → 高级 → 继续访问（不安全）

---

## 与生产环境对比

| 特性 | 本地开发（mkcert） | 生产环境（Let's Encrypt） |
|------|-------------------|--------------------------|
| **证书类型** | 本地自签名 | 公网可信证书 |
| **域名** | `*.yeanhua.asia` | `data.yeanhua.asia` |
| **验证方式** | 无需验证 | HTTP/DNS 验证 |
| **自动续期** | 1 年有效期 | 90 天自动续期 |
| **浏览器信任** | 本地设备自动信任 | 全球信任 |
| **配置复杂度** | 低（一键生成） | 中（需要域名和服务器） |
| **适用场景** | 本地开发、内网测试 | 生产环境、公网访问 |

---

## 最佳实践

### 1. 证书生命周期管理

```bash
# 定期检查证书状态（可加入 crontab）
make cert-check

# 证书过期前 30 天自动续期
# scripts/cert-manager.sh 已内置过期检查
```

### 2. 团队协作

**方式 1**：每个开发者自己生成证书
```bash
# 每个开发者执行
make cert-generate
make docker-up-https
```

**方式 2**：共享 mkcert CA（不推荐）

将 `$(mkcert -CAROOT)` 目录下的文件分享给团队（有安全风险）。

### 3. CI/CD 环境

CI/CD 环境不建议使用 HTTPS，因为：
- 无需真实证书
- 增加配置复杂度
- 测试主要验证功能而非 SSL

### 4. 与生产环境一致性

虽然使用不同证书，但配置保持一致：
- nginx SSL 配置相同
- 安全头配置相同
- 代理配置相同

---

## 安全注意事项

### 1. 私钥保护

```bash
# 证书私钥权限
chmod 600 ~/.local-certs/yeanhua.asia/privkey.pem

# 不要提交证书到 Git
echo "*.pem" >> .gitignore
```

### 2. mkcert CA 根证书

mkcert CA 根证书存储在：
```bash
mkcert -CAROOT
# Mac: ~/Library/Application Support/mkcert
# Linux: ~/.local/share/mkcert
```

**重要**：
- ❌ 不要分享 CA 根证书私钥
- ❌ 不要将 CA 提交到 Git
- ✅ 每个开发者独立生成

### 3. 仅用于开发环境

- ❌ 不要在生产环境使用 mkcert 证书
- ✅ 生产环境使用 Let's Encrypt
- ✅ 开发/生产环境隔离

---

## 故障排查

### 检查清单

```bash
# 1. 检查 mkcert 是否安装
mkcert -version

# 2. 检查 CA 是否已安装
mkcert -CAROOT

# 3. 检查证书是否存在
ls -la ~/.local-certs/yeanhua.asia/

# 4. 检查证书内容
make cert-info

# 5. 检查 nginx 配置
docker compose exec nginx nginx -t

# 6. 查看 nginx 日志
docker compose logs nginx
```

### 完全重置

```bash
# 1. 停止服务
make docker-down

# 2. 删除证书
make cert-clean

# 3. 卸载 mkcert CA
mkcert -uninstall

# 4. 重新安装
mkcert -install

# 5. 重新生成证书
make cert-generate

# 6. 启动 HTTPS
make docker-up-https
```

---

## 快速参考

### Makefile 命令

```bash
# HTTPS 启动
make docker-up-https     # 启动 HTTPS 服务
make docker-up-http      # 启动 HTTP 服务

# 证书管理
make cert-check          # 检查证书
make cert-generate       # 生成证书
make cert-info           # 查看证书
make cert-renew          # 续期证书
make cert-clean          # 删除证书
```

### 证书管理脚本

```bash
./scripts/cert-manager.sh check      # 检查
./scripts/cert-manager.sh generate   # 生成
./scripts/cert-manager.sh info       # 信息
./scripts/cert-manager.sh renew      # 续期
./scripts/cert-manager.sh clean      # 清理
./scripts/cert-manager.sh help       # 帮助
```

### 访问地址

```bash
# HTTPS（推荐）
https://local.yeanhua.asia
https://localhost

# HTTP
http://local.yeanhua.asia
http://localhost
```

---

## 相关文档

- [local-domain-setup-2026-02-16.md](local-domain-setup-2026-02-16.md) - 本地域名配置
- [deployment-guide-2026-02-16.md](deployment-guide-2026-02-16.md) - 完整部署指南
- [makefile-usage-2026-02-16.md](makefile-usage-2026-02-16.md) - Makefile 使用文档
- [ssl-certificate-setup-2026-02-16.md](ssl-certificate-setup-2026-02-16.md) - 生产环境 SSL 配置

---

## 参考资料

- [mkcert GitHub](https://github.com/FiloSottile/mkcert)
- [Let's Encrypt 官方文档](https://letsencrypt.org/docs/)
- [nginx SSL 配置最佳实践](https://nginx.org/en/docs/http/configuring_https_servers.html)
