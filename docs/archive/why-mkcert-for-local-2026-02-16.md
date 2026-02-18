# 为什么本地开发使用 mkcert 而不是 Let's Encrypt

## 核心结论

**mkcert 简单在**：无需域名、无需验证、无需公网、一条命令即可

**Let's Encrypt 无法用于本地开发的原因**：
- ❌ 不能为 `localhost` 签发证书
- ❌ 不能为内网 IP（`192.168.x.x` 等 RFC 1918 私有地址）签发证书
  - 注：Let's Encrypt 从 2025.7 起支持公网 IP 证书，但明确不支持私有 IP
- ❌ 不能为你不拥有的域名签发证书
- ❌ 必须通过公网访问验证域名所有权

**重要区别**：
- **为 IP 颁发证书**：证书 SAN 字段包含 IP 地址（Let's Encrypt 仅支持公网 IP）
- **为域名颁发证书**：证书 SAN 字段包含域名，域名可以解析到任意 IP（包括内网 IP）
  - ✓ 验证时：域名需要指向公网（用于 Let's Encrypt 验证）
  - ✓ 使用时：域名可以通过 `/etc/hosts` 解析到 `127.0.0.1` 或内网 IP

---

## 详细对比

### 场景 1：本地开发（localhost）

#### 使用 mkcert（简单）

```bash
# 1. 安装 mkcert（一次性）
brew install mkcert
mkcert -install

# 2. 生成证书（1 秒完成）
mkcert localhost 127.0.0.1 ::1

# 3. 使用证书
# ✓ 完成！无需其他配置

# 总耗时：1 分钟
# 前置条件：无
```

#### 使用 Let's Encrypt（不可行）

```bash
# Let's Encrypt 不能为 localhost 签发证书

certbot certonly -d localhost
# ❌ 错误: localhost 不是有效的公网域名
# ❌ Let's Encrypt 只能为你拥有并能验证的公网域名签发证书
```

**结论**：Let's Encrypt **无法**用于 localhost。

---

### 场景 2：内网开发（192.168.x.x）

> **注意**：这里讨论的是"为内网 IP 地址颁发证书"。如果你有域名，可以为域名颁发证书，然后通过 `/etc/hosts` 将域名解析到内网 IP（参见场景 4）。

#### 使用 mkcert（简单）

```bash
# 为内网 IP 生成证书
mkcert 192.168.1.100 192.168.1.101

# ✓ 完成！可以使用 https://192.168.1.100
```

#### 使用 Let's Encrypt（不可行）

```bash
# Let's Encrypt 不能为内网 IP 签发证书

certbot certonly --standalone -d 192.168.1.100
# ❌ 错误: 192.168.x.x 是 RFC 1918 私有地址
# ❌ Let's Encrypt 只支持公网 IP，不支持内网 IP (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
# 注: Let's Encrypt 从 2025.7 起支持公网 IP 证书，但私有 IP 被行业标准明确禁止
```

**结论**：Let's Encrypt **无法**用于内网 IP（RFC 1918 私有地址）。

---

### 场景 3：自定义本地域名（*.local.dev）

#### 使用 mkcert（简单）

```bash
# 为任意域名生成证书（不需要真实拥有）
mkcert "*.local.dev" "*.test" "*.localhost"

# 配置 /etc/hosts
echo "127.0.0.1 app.local.dev" >> /etc/hosts

# ✓ 完成！可以使用 https://app.local.dev
```

#### 使用 Let's Encrypt（不可行）

```bash
# 尝试为不拥有的域名申请证书

certbot certonly -d "app.local.dev"
# ❌ 错误: 无法验证域名所有权
# ❌ 你不拥有 .dev 域名，无法通过 DNS 验证
# ❌ 本地没有公网服务器，无法通过 HTTP 验证
```

**结论**：Let's Encrypt 只能为你**真实拥有**的域名签发证书。

---

### 场景 4：使用真实域名（local.yeanhua.asia）

这是**唯一**可以使用 Let's Encrypt 的本地开发场景。

> **重要区别**：
>
> - ❌ **为内网 IP 颁发证书**：Let's Encrypt 不支持（如 `certbot -d 192.168.1.100`）
> - ✅ **为域名颁发证书**：Let's Encrypt 支持，证书验证的是域名，不关心域名解析到哪个 IP
>
> **实际使用**：
> 1. **验证时**：域名需要解析到公网 IP（用于 Let's Encrypt 验证）
> 2. **使用时**：域名可以通过 `/etc/hosts` 解析到任意 IP（包括 127.0.0.1、192.168.x.x）
> 3. **证书内容**：`DNS Name: local.yeanhua.asia`（不包含 IP 信息）
> 4. **浏览器验证**：只检查证书中的域名是否匹配，不检查 IP 地址

#### 使用 mkcert（简单）

```bash
# 1. 生成证书（1 秒）
mkcert "*.yeanhua.asia" "local.yeanhua.asia"

# 2. 配置 /etc/hosts（可选）
echo "127.0.0.1 local.yeanhua.asia" >> /etc/hosts

# ✓ 完成！

# 总耗时：1 分钟
# 前置条件：无
# 需要公网：否
# 需要域名验证：否
```

#### 使用 Let's Encrypt（复杂）

**方案 A：HTTP-01 验证（需要公网访问）**

```bash
# 前置条件
1. 拥有域名 yeanhua.asia ✓
2. 配置 DNS: local.yeanhua.asia → 你的公网 IP
3. 服务器有公网 IP
4. 防火墙开放 80 端口
5. 运行 web 服务器（nginx/apache）

# 申请证书
certbot certonly --webroot \
  -w /var/www/html \
  -d local.yeanhua.asia

# 验证过程
1. certbot 在 /var/www/html/.well-known/acme-challenge/ 创建验证文件
2. Let's Encrypt 服务器访问 http://local.yeanhua.asia/.well-known/acme-challenge/xxx
3. 验证成功 → 签发证书

# 问题
❌ 本地开发环境通常没有公网 IP
❌ 如果使用路由器端口转发，配置复杂
❌ 开发机器需要保持在线，Let's Encrypt 才能访问
❌ 防火墙、路由器配置复杂

# 总耗时：30 分钟 - 1 小时（如果顺利）
```

**Let's Encrypt 证书 + 本地域名解析实践**

```bash
# 完整流程：在公网服务器获取证书，然后在本地使用

# 步骤 1：在公网服务器上获取证书（验证阶段）
# DNS 配置：local.yeanhua.asia -> 你的公网服务器 IP (1.2.3.4)
ssh user@1.2.3.4
certbot certonly --standalone -d local.yeanhua.asia

# 步骤 2：下载证书到本地
scp -r user@1.2.3.4:/etc/letsencrypt/live/local.yeanhua.asia ./certs/

# 步骤 3：本地修改 hosts 文件（使用阶段）
sudo sh -c 'echo "127.0.0.1 local.yeanhua.asia" >> /etc/hosts'

# 步骤 4：本地 nginx 配置使用证书
server {
    listen 443 ssl;
    server_name local.yeanhua.asia;

    ssl_certificate     ./certs/fullchain.pem;
    ssl_certificate_key ./certs/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
    }
}

# 步骤 5：访问本地服务
# 浏览器访问 https://local.yeanhua.asia
# ✓ 证书有效！浏览器只验证域名匹配，不关心 IP 是 127.0.0.1
```

**关键理解**：
- 证书内容：`Subject: CN=local.yeanhua.asia, SAN: DNS:local.yeanhua.asia`
- 验证时解析：`local.yeanhua.asia -> 1.2.3.4`（公网 DNS）
- 使用时解析：`local.yeanhua.asia -> 127.0.0.1`（/etc/hosts）
- 浏览器验证：检查证书中的 `local.yeanhua.asia` 与访问的域名匹配 ✓

**方案 B：DNS-01 验证（推荐，但仍复杂）**

```bash
# 前置条件
1. 拥有域名 yeanhua.asia ✓
2. 有 DNS 管理权限
3. DNS 提供商支持 API 或手动添加 TXT 记录

# 申请证书（以阿里云 DNS 为例）
# 安装 DNS 插件
pip install certbot-dns-aliyun

# 配置 DNS API 凭证
cat > ~/.secrets/aliyun.ini <<EOF
dns_aliyun_access_key = your_access_key
dns_aliyun_access_key_secret = your_secret
EOF
chmod 600 ~/.secrets/aliyun.ini

# 申请证书
certbot certonly --dns-aliyun \
  --dns-aliyun-credentials ~/.secrets/aliyun.ini \
  -d "*.yeanhua.asia"

# 验证过程
1. certbot 通过 API 在 DNS 添加 TXT 记录
   _acme-challenge.yeanhua.asia. TXT "验证码"
2. 等待 DNS 传播（可能需要几分钟）
3. Let's Encrypt 查询 DNS TXT 记录
4. 验证成功 → 签发证书

# 问题
❌ 需要配置 DNS API（不同提供商配置不同）
❌ 需要保管 API 密钥（安全风险）
❌ 首次配置复杂
❌ DNS 传播有延迟（等待时间）
❌ 证书 90 天有效期，需要续期脚本

# 总耗时：30 分钟 - 1 小时（首次配置）
```

**方案 C：手动 DNS 验证（最不推荐）**

```bash
# 申请证书
certbot certonly --manual \
  --preferred-challenges dns \
  -d local.yeanhua.asia

# 会提示
Please deploy a DNS TXT record under the name:
_acme-challenge.local.yeanhua.asia.

with the following value:
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 你需要
1. 登录 DNS 服务商控制台
2. 手动添加 TXT 记录
3. 等待 DNS 生效
4. 回到 certbot 按回车继续

# 问题
❌ 每次续期（90 天）都要重复这个过程
❌ 完全手动，无法自动化
❌ 容易出错

# 总耗时：每次 15-30 分钟
```

#### 对比总结

| 维度 | mkcert | Let's Encrypt (HTTP-01) | Let's Encrypt (DNS-01) |
|------|--------|------------------------|----------------------|
| **前置条件** | 无 | 公网 IP + 域名 | DNS API + 域名 |
| **配置复杂度** | ⭐ 极简 | ⭐⭐⭐⭐ 复杂 | ⭐⭐⭐ 中等 |
| **首次耗时** | 1 分钟 | 30-60 分钟 | 30-60 分钟 |
| **是否需要公网** | ❌ 不需要 | ✅ 需要 | ❌ 不需要 |
| **是否需要 DNS API** | ❌ 不需要 | ❌ 不需要 | ✅ 需要 |
| **证书有效期** | 1-10 年 | 90 天 | 90 天 |
| **自动续期** | 无需续期 | 需要配置 | 需要配置 |
| **离线使用** | ✅ 支持 | ❌ 不支持 | ❌ 不支持 |

---

## mkcert 简单的原因

### 1. 无需域名所有权

**mkcert**：
```bash
# 可以为任何域名生成证书
mkcert localhost
mkcert example.com
mkcert google.com
mkcert "*.anything.you.want"

# ✓ 无需证明你拥有这些域名
```

**Let's Encrypt**：
```bash
# 只能为你拥有的域名生成证书
certbot certonly -d your-domain.com

# ✗ 必须证明你拥有该域名
# ✗ 通过 HTTP-01 或 DNS-01 验证
```

### 2. 无需验证过程

**mkcert**：
```bash
mkcert localhost
# ✓ 立即生成，0 秒验证
```

**Let's Encrypt**：
```bash
certbot certonly -d example.com

# 验证流程
1. certbot 请求验证挑战
2. Let's Encrypt 返回验证任务
3. certbot 部署验证文件/DNS 记录
4. Let's Encrypt 验证
5. 签发证书

# ✗ 需要几秒到几分钟
# ✗ 可能因为网络、配置问题失败
```

### 3. 无需公网访问

**mkcert**：
```bash
# 离线也能工作
# 没有网络？没问题！
mkcert localhost
# ✓ 正常生成
```

**Let's Encrypt (HTTP-01)**：
```bash
certbot certonly --webroot -d example.com

# ✗ Let's Encrypt 服务器需要通过互联网访问你的服务器
# ✗ http://example.com:80 必须可以从公网访问
# ✗ 防火墙必须开放 80 端口
# ✗ 路由器需要配置端口转发（如果在内网）
```

### 4. 一条命令完成

**mkcert**：
```bash
mkcert localhost
# ✓ 完成！
```

**Let's Encrypt**：
```bash
# 需要多个步骤

# 1. 安装 certbot
sudo apt-get install certbot

# 2. 配置 web 服务器
sudo nano /etc/nginx/sites-available/default

# 3. 配置防火墙
sudo ufw allow 80/tcp

# 4. 申请证书
sudo certbot certonly --webroot -w /var/www/html -d example.com

# 5. 配置自动续期
sudo certbot renew --dry-run

# 6. 配置 nginx 使用证书
sudo nano /etc/nginx/sites-available/default

# 7. 重启 nginx
sudo systemctl reload nginx
```

### 5. 支持任意域名格式

**mkcert**：
```bash
# 支持所有格式
mkcert localhost                  # ✓ 域名
mkcert 127.0.0.1                  # ✓ IPv4
mkcert ::1                        # ✓ IPv6
mkcert 192.168.1.100              # ✓ 内网 IP
mkcert "*.local.dev"              # ✓ 泛域名
mkcert example.test               # ✓ .test 域名
mkcert my-app.localhost           # ✓ .localhost 域名
```

**Let's Encrypt**：
```bash
# 只支持公网域名
certbot certonly -d localhost          # ❌ 不支持
certbot certonly -d 127.0.0.1          # ❌ 不支持
certbot certonly -d 192.168.1.100      # ❌ 不支持
certbot certonly -d example.test       # ❌ 不支持（你不拥有）
certbot certonly -d your-domain.com    # ✓ 支持（如果你拥有）
```

---

## 为什么不直接用 Let's Encrypt？

### 原因 1：本地开发的典型场景

**开发者的实际需求**：
```
我想在本地开发时使用 HTTPS
├── 使用 localhost 或 127.0.0.1
├── 或使用内网 IP 192.168.x.x
├── 或使用自定义域名 *.local.dev
├── 不想花钱买域名
├── 不想配置 DNS
├── 不想开放公网访问
└── 不想处理复杂的验证过程

Let's Encrypt：这些我都做不到 ❌
mkcert：这些我全能做到 ✓
```

### 原因 2：Let's Encrypt 的设计目标

Let's Encrypt 设计用于：
- ✅ 生产环境
- ✅ 公网可访问的服务
- ✅ 真实拥有的域名
- ✅ 需要全球信任的证书

Let's Encrypt **不**适用于：
- ❌ 本地开发环境
- ❌ 内网服务
- ❌ 测试域名
- ❌ localhost

### 原因 3：Let's Encrypt 的限制

**速率限制**：
```
每个域名每周最多 50 个证书
每个账户每 3 小时最多 300 个待处理授权
每个 IP 每 3 小时最多 10 个账户
每个域名每小时最多 5 次失败验证

本地开发频繁创建/销毁环境
→ 容易触发速率限制
→ 被 Let's Encrypt 暂时封禁
```

**证书有效期**：
```
Let's Encrypt：90 天
→ 需要配置自动续期
→ 开发环境可能几个月不用，证书过期
→ 需要处理续期脚本

mkcert：1-10 年
→ 生成一次，长期使用
→ 无需关心续期
```

### 原因 4：配置复杂度

**mkcert 配置**：
```bash
# 完整配置（首次）
brew install mkcert
mkcert -install
mkcert localhost

# ✓ 3 条命令，1 分钟完成
```

**Let's Encrypt 配置（DNS-01，最简单的本地开发方案）**：
```bash
# 完整配置（首次）
1. 注册域名（如果没有）
2. 配置 DNS 解析到 127.0.0.1
3. 安装 certbot
4. 安装 DNS 插件
5. 配置 DNS API 凭证
6. 申请证书
7. 配置 web 服务器
8. 配置自动续期
9. 处理证书权限问题
10. 重启服务

# ✗ 10+ 个步骤，30-60 分钟
# ✗ 需要处理各种潜在问题
```

---

## 实际对比：完整流程

### 使用 mkcert（本地开发）

```bash
# 场景：我想在本地开发项目，使用 https://local.myapp.dev

# 步骤 1：安装 mkcert（一次性）
brew install mkcert
mkcert -install

# 步骤 2：生成证书
mkcert "*.myapp.dev" "local.myapp.dev"

# 步骤 3：配置 hosts
echo "127.0.0.1 local.myapp.dev" | sudo tee -a /etc/hosts

# 步骤 4：使用证书
# 在 nginx/docker/应用中配置证书路径

# ✓ 总耗时：2 分钟
# ✓ 前置条件：无
# ✓ 成本：0 元
# ✓ 复杂度：极低
```

### 使用 Let's Encrypt（本地开发，理想情况）

```bash
# 场景：我想在本地开发项目，使用 https://local.myapp.dev

# 步骤 1：注册域名
# 去域名注册商（如阿里云、GoDaddy）购买 myapp.dev
# 成本：60-200 元/年
# 耗时：10-30 分钟

# 步骤 2：配置 DNS
# 登录 DNS 管理控制台
# 添加 A 记录：local.myapp.dev → 127.0.0.1
# 等待 DNS 传播（可能需要几分钟到几小时）
# 耗时：5-60 分钟

# 步骤 3：安装 certbot
sudo apt-get update
sudo apt-get install certbot python3-certbot-dns-xxx
# 耗时：5 分钟

# 步骤 4：配置 DNS API
# 在 DNS 提供商获取 API Key
# 创建凭证文件
cat > ~/.secrets/dns-credentials.ini <<EOF
dns_xxx_api_key = your_api_key
EOF
chmod 600 ~/.secrets/dns-credentials.ini
# 耗时：10-20 分钟

# 步骤 5：申请证书
sudo certbot certonly --dns-xxx \
  --dns-xxx-credentials ~/.secrets/dns-credentials.ini \
  -d local.myapp.dev
# 等待 DNS 验证
# 耗时：2-10 分钟

# 步骤 6：配置自动续期
sudo crontab -e
# 添加：0 3 * * * certbot renew --quiet
# 耗时：5 分钟

# 步骤 7：处理证书权限
sudo chmod 644 /etc/letsencrypt/live/local.myapp.dev/fullchain.pem
# 耗时：2 分钟

# 步骤 8：使用证书
# 在 nginx/docker/应用中配置证书路径

# ✗ 总耗时：37-92 分钟（首次）
# ✗ 前置条件：域名、DNS API
# ✗ 成本：60-200 元/年
# ✗ 复杂度：高
# ✗ 维护：需要监控续期、处理失败情况
```

**对比**：

| 维度 | mkcert | Let's Encrypt |
|------|--------|--------------|
| 耗时 | 2 分钟 | 37-92 分钟 |
| 成本 | 0 元 | 60-200 元/年 |
| 前置条件 | 无 | 域名 + DNS API |
| 复杂度 | ⭐ | ⭐⭐⭐⭐⭐ |
| 后续维护 | 无 | 监控续期 |

---

## 什么时候应该用 Let's Encrypt？

### 生产环境

```yaml
场景: 真实的公网服务
域名: example.com
用户: 全球访问

推荐: Let's Encrypt

原因:
  - ✅ 需要全球用户信任（mkcert 只有开发者信任）
  - ✅ 有真实域名
  - ✅ 有公网 IP
  - ✅ 永久在线（不像开发环境随时关闭）
  - ✅ 免费（节省证书成本）

方案:
  certbot certonly --webroot -d example.com
  配置自动续期
```

### 内网生产环境（特殊情况）

```yaml
场景: 公司内网服务，需要所有员工都能访问
域名: internal.company.com（公司拥有 company.com）
用户: 公司员工

推荐: Let's Encrypt (DNS-01)

原因:
  - ✅ 员工设备多，不可能每台都安装 mkcert CA
  - ✅ 公司拥有域名，可以使用 DNS-01 验证
  - ✅ 一次配置，所有设备自动信任
  - ⚠️ 虽然复杂，但一次配置长期受益

方案:
  certbot certonly --dns-xxx -d internal.company.com
  配置自动续期
```

---

## 误区澄清

### 误区 1："Let's Encrypt 更安全"

**错误理解**：
- Let's Encrypt 是公共 CA，所以更安全
- mkcert 是本地 CA，不安全

**正确理解**：
- 对于本地开发，mkcert 和 Let's Encrypt 的安全性**相同**
- 加密强度相同（RSA 2048 位或 ECC）
- TLS 协议相同（TLS 1.2/1.3）
- 唯一区别是**信任范围**，不是安全性

**类比**：
```
公司内部门禁卡（mkcert）
  - 在公司内有效
  - 安全级别：高

国际护照（Let's Encrypt）
  - 在全球有效
  - 安全级别：高

哪个更安全？一样安全！
区别是使用场景，不是安全性。
```

### 误区 2："mkcert 是临时方案"

**错误理解**：
- mkcert 只是权宜之计
- 应该尽快迁移到 Let's Encrypt

**正确理解**：
- mkcert 是**正式**的本地开发方案
- 由 Google Chrome 安全团队成员维护
- 被广泛使用和推荐
- 不需要"迁移"到 Let's Encrypt

**正确思路**：
```
本地开发 → mkcert ✓
生产环境 → Let's Encrypt ✓

这是两个不同的场景，不是迁移关系。
```

### 误区 3："既然要用 HTTPS，不如一开始就用 Let's Encrypt"

**错误理解**：
- 本地开发也用 Let's Encrypt
- 保持本地和生产环境一致

**正确理解**：
- 本地和生产环境的**需求**不同
- 本地：快速迭代、频繁重启、离线工作
- 生产：稳定在线、全球访问、长期运行

**类比**：
```
本地开发环境
  ├── 使用 SQLite（快速、简单）
  └── 使用 mkcert（快速、简单）

生产环境
  ├── 使用 PostgreSQL（稳定、可扩展）
  └── 使用 Let's Encrypt（全球信任）

不需要"保持一致"，而是"适合场景"。
```

---

## 决策树

```
需要 HTTPS 证书？
│
├─ 使用场景是什么？
│
├─ 本地开发/测试？
│   │
│   ├─ 使用 localhost？
│   │   └─ ✓ mkcert（Let's Encrypt 不支持）
│   │
│   ├─ 使用内网 IP？
│   │   └─ ✓ mkcert（Let's Encrypt 不支持）
│   │
│   ├─ 使用自定义域名（不拥有）？
│   │   └─ ✓ mkcert（Let's Encrypt 不支持）
│   │
│   └─ 使用真实域名（拥有）？
│       │
│       ├─ 想要简单？
│       │   └─ ✓ mkcert（2 分钟）
│       │
│       └─ 不介意复杂？
│           └─ ⚠️ Let's Encrypt（30-60 分钟）
│
└─ 生产环境/公网服务？
    │
    ├─ 有真实域名？
    │   │
    │   ├─ 有公网 IP？
    │   │   └─ ✓ Let's Encrypt (HTTP-01)
    │   │
    │   └─ 无公网 IP（内网服务）？
    │       │
    │       ├─ 有 DNS API？
    │       │   └─ ✓ Let's Encrypt (DNS-01)
    │       │
    │       └─ 用户数量？
    │           │
    │           ├─ 少（<10 人）
    │           │   └─ ⚠️ mkcert（每人安装 CA）
    │           │
    │           └─ 多（>10 人）
    │               └─ ✓ Let's Encrypt (DNS-01)
    │
    └─ 无域名？
        └─ ⚠️ 购买域名 → Let's Encrypt
```

---

## 总结

### mkcert 简单在哪里？

1. **无需域名**：不需要购买或拥有域名
2. **无需验证**：不需要证明域名所有权
3. **无需公网**：可以离线工作，不需要公网访问
4. **一条命令**：`mkcert localhost` 即可完成
5. **支持任意域名**：localhost、IP、自定义域名都支持
6. **即时生成**：1 秒生成证书，无需等待
7. **配置简单**：3 条命令即可开始使用
8. **无需续期**：证书有效期 1-10 年

### 为什么不直接用 Let's Encrypt？

1. **不支持 localhost**：Let's Encrypt 无法为 localhost 签发
2. **不支持内网 IP**：无法为 192.168.x.x 签发
3. **必须拥有域名**：需要购买域名（成本、时间）
4. **必须验证域名**：需要配置 DNS 或公网访问
5. **配置复杂**：需要 30-60 分钟首次配置
6. **需要续期**：90 天有效期，需要配置自动续期
7. **有速率限制**：频繁创建环境可能触发限制

### 推荐方案

```
本地开发：
  └─ mkcert
     理由：简单、快速、无需域名

生产环境：
  └─ Let's Encrypt
     理由：全球信任、免费、自动续期
```

---

## 快速参考

```bash
# 本地开发（推荐）
make docker-up-https     # 自动使用 mkcert
# 耗时：1 分钟
# 成本：0 元
# 复杂度：⭐

# 生产环境（推荐）
./deploy/init-ssl.sh data.yeanhua.asia email@example.com
# 耗时：5 分钟（配置好的情况下）
# 成本：0 元
# 复杂度：⭐⭐⭐
```

**结论**：本地开发用 mkcert 不是妥协，而是**正确选择**。
