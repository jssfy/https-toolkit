# 证书方案对比 - mkcert vs Let's Encrypt

## 核心结论

| 特性 | mkcert | Let's Encrypt (ACME) |
|------|--------|---------------------|
| **是否需要安装 CA** | ✅ 必须（本地 CA） | ❌ 不需要（全球信任） |
| **客户端信任** | 仅安装了 CA 的设备 | 全球所有设备 |
| **适用场景** | 本地开发 | 生产环境、公网服务 |
| **域名验证** | 无需验证 | 必须验证域名所有权 |
| **证书有效期** | 1-10 年（自定义） | 90 天（自动续期） |
| **泛域名支持** | ✅ 支持 | ✅ 支持（需 DNS-01 验证） |

**推荐策略**：
- 本地开发：使用 mkcert（简单、无需域名）
- 生产环境：使用 Let's Encrypt（全球信任、自动续期）

---

## 详细对比

### 1. mkcert（本地开发证书）

#### 工作原理

```
┌─────────────────────────────────────────┐
│  1. mkcert -install                     │
│     安装本地 CA 根证书到系统信任库      │
│     (仅在当前设备上)                    │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  2. mkcert "*.example.com"              │
│     使用本地 CA 签发证书                │
│     (无需域名验证)                      │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  3. 浏览器/系统检查证书                 │
│     → 查找签发者: mkcert CA             │
│     → 在系统信任库中找到 mkcert CA      │
│     → 信任该证书 ✓                      │
└─────────────────────────────────────────┘
```

#### 是否必须安装 CA？

**是的，必须安装。**

**原因**：
1. mkcert 创建的是**本地私有 CA**
2. 这个 CA **不在**操作系统或浏览器的预装信任列表中
3. 必须手动执行 `mkcert -install` 将 CA 根证书添加到系统信任库
4. 未安装 CA 的设备会显示"不安全"警告

**验证**：
```bash
# 在安装 mkcert CA 前
curl https://local.example.com
# 错误: SSL certificate problem: unable to get local issuer certificate

# 执行 mkcert -install 后
curl https://local.example.com
# ✓ 正常访问
```

#### 信任范围

| 设备 | 是否信任 | 说明 |
|------|---------|------|
| 开发者电脑 | ✅ | 执行了 `mkcert -install` |
| 同事电脑 | ❌ | 需要单独安装 CA |
| 手机/平板 | ❌ | 需要导入 CA 证书 |
| 其他用户 | ❌ | 不会信任 |
| 生产环境 | ❌ | 不应使用 |

#### 优点

- ✅ **零配置域名**：无需拥有域名或配置 DNS
- ✅ **即时生成**：1 秒生成证书
- ✅ **支持泛域名**：无限制
- ✅ **离线工作**：不需要网络
- ✅ **适合内网**：192.168.x.x、localhost 都支持

#### 缺点

- ❌ **仅限本地**：只能在安装了 CA 的设备上使用
- ❌ **不能共享**：团队协作时每个人都要安装
- ❌ **移动设备复杂**：手机/平板需要手动导入证书
- ❌ **不适合生产**：公网用户无法访问

---

### 2. Let's Encrypt (ACME 协议)

#### 工作原理

```
┌─────────────────────────────────────────┐
│  1. certbot certonly -d example.com     │
│     请求 Let's Encrypt 签发证书         │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  2. Let's Encrypt 验证域名所有权        │
│     HTTP-01: 访问 http://example.com/.well-known/acme-challenge/xxx │
│     DNS-01:  检查 _acme-challenge.example.com TXT 记录 │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  3. 验证通过，签发证书                  │
│     使用 Let's Encrypt CA 签发          │
│     (全球信任的 CA)                     │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  4. 浏览器/系统检查证书                 │
│     → 查找签发者: Let's Encrypt CA      │
│     → 在预装信任库中找到 ✓              │
│     → 信任该证书 ✓                      │
└─────────────────────────────────────────┘
```

#### 是否需要安装 CA？

**不需要，自动信任。**

**原因**：
1. Let's Encrypt CA 根证书已经**预装**在：
   - 所有主流操作系统（Windows、macOS、Linux）
   - 所有主流浏览器（Chrome、Firefox、Safari、Edge）
   - 所有移动设备（iOS、Android）
2. 用户无需做任何额外操作
3. 证书立即被全球所有设备信任

#### 验证域名所有权

**必须验证**，有三种方式：

**HTTP-01 验证**（最常用）：
```bash
# Let's Encrypt 访问
http://example.com/.well-known/acme-challenge/xxx

# certbot 在服务器上创建验证文件
/var/www/certbot/.well-known/acme-challenge/xxx

# 验证通过 → 签发证书
```

**DNS-01 验证**（泛域名）：
```bash
# Let's Encrypt 查询 DNS 记录
dig _acme-challenge.example.com TXT

# 需要在 DNS 服务商添加 TXT 记录
_acme-challenge.example.com. 300 IN TXT "验证码"

# 验证通过 → 签发泛域名证书 *.example.com
```

**TLS-ALPN-01 验证**（不常用）：
通过 TLS 握手验证域名所有权。

#### 信任范围

| 设备 | 是否信任 | 说明 |
|------|---------|------|
| 全球所有设备 | ✅ | 预装 Let's Encrypt CA |
| 所有浏览器 | ✅ | 自动信任 |
| 移动设备 | ✅ | 自动信任 |
| IoT 设备 | ✅ | 大部分支持 |
| 旧设备 | ⚠️ | Android < 2.3.6 不支持 |

#### 优点

- ✅ **全球信任**：无需安装任何东西
- ✅ **免费**：永久免费
- ✅ **自动续期**：certbot 自动续期（90 天）
- ✅ **生产就绪**：数百万网站使用
- ✅ **多域名**：支持 SAN（一个证书多个域名）

#### 缺点

- ❌ **需要域名**：必须拥有域名
- ❌ **需要验证**：HTTP 或 DNS 验证
- ❌ **公网可达**：HTTP-01 需要 80 端口对外开放
- ❌ **泛域名复杂**：需要 DNS API 或手动操作
- ❌ **速率限制**：每周最多 50 个证书/域名

---

### 3. ACME 协议

#### 什么是 ACME？

**ACME** = Automatic Certificate Management Environment（自动化证书管理环境）

- **协议规范**：定义了如何自动申请、续期、撤销证书
- **标准化**：IETF RFC 8555
- **实现**：Let's Encrypt、ZeroSSL、Buypass 等

#### ACME 工作流程

```
1. 客户端（certbot）→ ACME 服务器（Let's Encrypt）
   "我想申请 example.com 的证书"

2. ACME 服务器 → 客户端
   "请证明你拥有这个域名，完成以下挑战之一："
   - HTTP-01: 在 http://example.com/.well-known/acme-challenge/xxx 放置文件
   - DNS-01: 在 DNS 添加 TXT 记录

3. 客户端 → 完成挑战
   创建文件或添加 DNS 记录

4. ACME 服务器 → 验证挑战
   访问 URL 或查询 DNS

5. 验证通过 → 签发证书
   ACME 服务器用自己的 CA 签发证书

6. 客户端 → 下载证书
   保存证书和私钥
```

#### certbot vs acme.sh

| 工具 | 语言 | 维护者 | 特点 |
|------|------|--------|------|
| **certbot** | Python | EFF（电子前沿基金会） | 官方推荐、功能完整 |
| **acme.sh** | Shell | 社区 | 轻量、无依赖、支持更多 DNS |
| **lego** | Go | 社区 | 跨平台、库和 CLI |

---

## 对比总结

### 场景 1：本地开发（内网、localhost）

**推荐：mkcert**

```bash
# 1. 安装 mkcert
brew install mkcert

# 2. 安装本地 CA（一次性）
mkcert -install

# 3. 生成证书
mkcert localhost 127.0.0.1 ::1 "*.local.dev"

# ✓ 立即可用，无需域名和验证
```

**优势**：
- 无需公网域名
- 无需 DNS 配置
- 支持任意域名（包括 .local、.dev）
- 离线工作

### 场景 2：生产环境（公网、真实域名）

**推荐：Let's Encrypt (certbot)**

```bash
# 1. 安装 certbot
sudo apt-get install certbot

# 2. 申请证书（自动验证）
sudo certbot certonly --webroot \
  -w /var/www/html \
  -d example.com

# 3. 配置自动续期
sudo certbot renew --dry-run

# ✓ 全球信任，自动续期
```

**优势**：
- 全球所有设备自动信任
- 免费且持续更新
- 自动化续期
- 生产环境标准方案

### 场景 3：内网测试（团队协作）

**方案 A：每人安装 mkcert CA**

```bash
# 开发者 A
mkcert -install
mkcert "*.company.local"

# 开发者 B（同样操作）
mkcert -install
mkcert "*.company.local"
```

**缺点**：每个人都要操作

**方案 B：内网 Let's Encrypt（需要公网域名）**

```bash
# 使用真实域名指向内网 IP
# DNS: internal.company.com → 192.168.1.100

# 申请证书（DNS-01 验证）
certbot certonly --dns-xxx \
  -d internal.company.com
```

**优势**：证书全员信任

### 场景 4：移动设备开发

**方案 A：导出 mkcert CA**

```bash
# 1. 查找 CA 位置
mkcert -CAROOT
# 输出: /Users/xxx/Library/Application Support/mkcert

# 2. 导出 rootCA.pem

# 3. 在手机上安装
# iOS: 设置 → 通用 → VPN与设备管理 → 安装描述文件
# Android: 设置 → 安全 → 加密与凭据 → 从存储设备安装
```

**缺点**：手动操作，较繁琐

**方案 B：使用 Let's Encrypt**

使用真实域名（如 dev.example.com），无需额外操作。

---

## 实际使用建议

### 本地开发环境

```yaml
项目: top-ai-news
场景: 本地开发
推荐: mkcert

原因:
  - 无需购买域名
  - 无需配置 DNS
  - 支持 *.yeanhua.asia
  - 可以离线工作
  - 一次安装，永久使用

操作:
  make docker-up-https  # 自动使用 mkcert
```

### 生产环境

```yaml
项目: top-ai-news
场景: 阿里云 ECS
推荐: Let's Encrypt

原因:
  - 全球用户信任
  - 免费且自动续期
  - 生产环境标准
  - 无需用户安装任何东西

操作:
  ./deploy/init-ssl.sh data.yeanhua.asia email@example.com
```

---

## 常见误解

### 误解 1："Let's Encrypt 不需要安装"

**正确理解**：
- Let's Encrypt CA 根证书**已预装**在操作系统中
- 用户不需要**额外安装**任何东西
- 但 Let's Encrypt 根证书确实存在于系统信任库中

**验证**（macOS）：
```bash
# 查看系统信任的根证书
security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain | \
  openssl x509 -noout -subject | \
  grep "Let's Encrypt"
```

### 误解 2："mkcert 生成的证书可以分享"

**错误做法**：
```bash
# 开发者 A 生成证书
mkcert "*.company.com"

# 将证书分享给开发者 B
# ❌ 开发者 B 的浏览器仍会显示不安全
```

**原因**：
- 证书可以分享，但 **CA 根证书不在开发者 B 的系统中**
- 开发者 B 需要安装 CA：`mkcert -install`

**正确做法**：
- 每个开发者独立执行 `mkcert -install`
- 每个开发者独立生成证书
- 不共享 CA 根证书（有安全风险）

### 误解 3："ACME 是一种证书"

**正确理解**：
- ACME 是**协议**，不是证书类型
- Let's Encrypt **使用** ACME 协议
- 其他 CA 也可以使用 ACME 协议
- certbot 是 ACME 协议的**客户端实现**

**类比**：
```
ACME   ≈ HTTP 协议
certbot ≈ 浏览器
Let's Encrypt ≈ 网站服务器
```

---

## 技术细节

### mkcert 实现原理

```bash
# 1. 生成本地 CA
mkcert -install
# 创建: ~/.local/share/mkcert/rootCA.pem
#       ~/.local/share/mkcert/rootCA-key.pem

# 2. 添加 CA 到系统信任库
# macOS:    钥匙串访问
# Linux:    /usr/local/share/ca-certificates/
# Windows:  证书管理器

# 3. 生成证书
mkcert "*.example.com"
# 使用 rootCA-key.pem 签名
# 创建: _wildcard.example.com.pem
#       _wildcard.example.com-key.pem
```

### Let's Encrypt CA 层级

```
ISRG Root X1 (根 CA，预装在操作系统中)
    │
    └── Let's Encrypt Authority X3 (中间 CA)
            │
            └── example.com (你的网站证书)
```

**证书链**：
```
fullchain.pem = 网站证书 + 中间 CA 证书
privkey.pem = 网站私钥
chain.pem = 中间 CA 证书
cert.pem = 网站证书
```

---

## 安全考虑

### mkcert CA 泄露风险

如果 mkcert CA 私钥泄露：
- 攻击者可以签发任意域名的证书
- 可以伪造 google.com、bank.com 等
- 受影响范围：所有安装了该 CA 的设备

**防护措施**：
1. ❌ 不要共享 CA 私钥
2. ❌ 不要提交 CA 到 Git
3. ✅ 定期重新生成 CA：`mkcert -uninstall && mkcert -install`
4. ✅ 只在开发环境使用

### Let's Encrypt 安全性

- ✅ 公开透明：所有证书记录在 Certificate Transparency Log
- ✅ 速率限制：防止滥用
- ✅ 短有效期：90 天（减少泄露影响）
- ✅ 自动续期：避免过期

---

## 快速决策树

```
需要 HTTPS 证书？
    │
    ├─ 本地开发/内网？
    │   └─ 使用 mkcert
    │       - make cert-generate
    │       - make docker-up-https
    │
    └─ 公网/生产环境？
        └─ 使用 Let's Encrypt
            │
            ├─ 单域名？
            │   └─ HTTP-01 验证
            │       - certbot --webroot
            │
            └─ 泛域名？
                └─ DNS-01 验证
                    - certbot --dns-xxx
```

---

## 相关资源

### mkcert
- [GitHub](https://github.com/FiloSottile/mkcert)
- [工作原理](https://words.filippo.io/mkcert-valid-https-certificates-for-localhost/)

### Let's Encrypt
- [官网](https://letsencrypt.org/)
- [工作原理](https://letsencrypt.org/how-it-works/)
- [速率限制](https://letsencrypt.org/docs/rate-limits/)

### ACME 协议
- [RFC 8555](https://tools.ietf.org/html/rfc8555)
- [certbot 文档](https://eff-certbot.readthedocs.io/)
- [acme.sh 文档](https://github.com/acmesh-official/acme.sh)

---

## 总结

| 问题 | 答案 |
|------|------|
| mkcert 需要安装 CA 吗？ | **是**，必须 `mkcert -install` |
| Let's Encrypt 自动信任吗？ | **是**，CA 根证书已预装 |
| mkcert vs ACME 区别？ | mkcert=本地开发工具<br>ACME=自动化证书协议 |

**推荐组合**：
- 本地开发：mkcert（简单）
- 生产环境：Let's Encrypt (ACME)（全球信任）
