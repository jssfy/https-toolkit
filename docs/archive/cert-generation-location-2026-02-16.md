# 证书生成运行位置说明

## 核心结论

- ⚠️ **HTTP-01 验证必须在生产服务器上运行**
- ✅ **DNS-01 验证可以在本地或服务器运行**
- ✅ **mkcert 可以在任何地方运行**
- 📝 根本原因：HTTP-01 需要 Let's Encrypt 访问服务器的 80 端口

---

## 快速决策表

| 证书方式 | 运行位置 | 原因 | 部署复杂度 |
|---------|---------|------|-----------|
| **HTTP-01 Standalone** | ⚠️ **必须在服务器** | Let's Encrypt 需访问服务器 80 端口 | ⭐ 简单 |
| **HTTP-01 Webroot** | ⚠️ **必须在服务器** | 验证文件需写入服务器 webroot | ⭐⭐ 中等 |
| **DNS-01** | ✅ **本地或服务器** | 只需 DNS API，无需服务器访问 | ⭐⭐⭐ 复杂 |
| **mkcert** | ✅ **任何地方** | 本地 CA，无外部依赖 | ⭐ 极简 |

---

## HTTP-01：为什么必须在服务器运行？

### 验证流程图

```
本地电脑 (你的笔记本)                  生产服务器 (121.41.107.93)
    |                                          |
    | make cert-generate                      |
    | ❌ 运行 certbot                          |
    |                                          |
    |                              data.yeanhua.asia
    |                              DNS 解析指向此服务器
    |                                          |
    +-----> Let's Encrypt 服务器 --------------+
                    |
    访问: http://data.yeanhua.asia/.well-known/acme-challenge/xxx
                    |
                 ❌ 失败！
    因为域名解析到服务器，而验证文件在本地
```

**正确的流程**：

```
生产服务器 (121.41.107.93)
    |
    | SSH 登录
    | cd ~/top-ai-news
    | make cert-generate
    | ✅ certbot 在服务器上启动 HTTP 服务
    |
data.yeanhua.asia 解析到本机
    |
Let's Encrypt 服务器
    |
访问: http://data.yeanhua.asia/.well-known/acme-challenge/xxx
    |
✅ 验证成功！验证文件在服务器上
```

### 关键点

1. **域名解析的位置**：
   - `data.yeanhua.asia` DNS 解析 → 121.41.107.93（生产服务器）
   - Let's Encrypt 会访问这个 IP 地址

2. **验证文件的位置**：
   - HTTP-01 验证需要在 `http://data.yeanhua.asia/.well-known/acme-challenge/` 下放置验证文件
   - 这个路径必须在域名解析到的服务器上

3. **为什么本地不行**：
   - 即使在本地运行 `make cert-generate`
   - Let's Encrypt 仍然会访问 `data.yeanhua.asia` 的公网 IP（服务器）
   - 而验证文件在本地，Let's Encrypt 访问不到
   - 结果：`Connection refused` 或 `404 Not Found`

---

## DNS-01：为什么可以在本地运行？

### 验证流程图

```
本地电脑
    |
    | make cert-generate-dns
    | ✅ certbot 调用 DNS API
    |
DNS 提供商（阿里云/Cloudflare）
    |
    | 添加 TXT 记录
    | _acme-challenge.yeanhua.asia. TXT "验证码"
    |
Let's Encrypt 服务器
    |
    | 查询 DNS TXT 记录
    | ✅ 验证成功！
    |
证书生成在本地
    |
    | scp 上传到服务器
    |
生产服务器部署
```

### 关键点

1. **无需服务器访问**：
   - DNS-01 验证通过 DNS TXT 记录
   - Let's Encrypt 查询 DNS，不访问服务器

2. **只需 DNS API**：
   - 需要 DNS 提供商的 API 凭证
   - 在任何能访问 DNS API 的地方都能运行

3. **证书可本地生成**：
   - 证书生成后保存在本地
   - 通过 `scp` 上传到服务器

---

## 实际操作指南

### 场景 1：HTTP-01 Standalone（80 端口空闲）

**⚠️ 必须在服务器上运行**

```bash
# 1. SSH 到服务器
ssh user@121.41.107.93

# 2. 停止占用 80 端口的服务
cd ~/top-ai-news
docker compose down

# 3. 生成证书
make cert-generate

# 4. 启动服务
make docker-up-https
```

**验证**：
```bash
# 在服务器上检查证书
make cert-info

# 浏览器访问
open https://data.yeanhua.asia
```

---

### 场景 2：HTTP-01 Webroot（80 端口被占用）

**⚠️ 必须在服务器上运行**

```bash
# 1. SSH 到服务器
ssh user@121.41.107.93

# 2. 配置 Nginx 支持 ACME 验证
sudo vim /etc/nginx/sites-available/data.yeanhua.asia

# 添加以下配置
server {
    listen 80;
    server_name data.yeanhua.asia;

    # ACME 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # 现有配置...
}

# 3. 重载 Nginx
sudo nginx -s reload

# 4. 生成证书（自动使用 webroot 模式）
cd ~/top-ai-news
make cert-generate

# 5. 部署服务
make docker-up-https
```

---

### 场景 3：DNS-01（可本地运行）

**✅ 可以在本地或服务器运行**

#### 在本地生成

```bash
# 1. 配置 DNS API（本地）
make cert-setup-dns
vim ~/.secrets/dns-credentials.ini
# 填入阿里云 Access Key

# 2. 安装 DNS 插件
pip3 install certbot-dns-aliyun

# 3. 生成证书（本地）
make cert-generate-dns

# 4. 检查证书
ls ~/.local-certs/yeanhua.asia/
make cert-info

# 5. 上传到服务器
scp ~/.local-certs/yeanhua.asia/fullchain.pem \
    user@121.41.107.93:~/certs/
scp ~/.local-certs/yeanhua.asia/privkey.pem \
    user@121.41.107.93:~/certs/

# 6. 在服务器上部署
ssh user@121.41.107.93
cd ~/top-ai-news
# 确保证书在 ~/.local-certs/yeanhua.asia/
make docker-up-https
```

#### 在服务器生成

```bash
# 1. SSH 到服务器
ssh user@121.41.107.93

# 2. 配置 DNS API（服务器）
cd ~/top-ai-news
make cert-setup-dns
vim ~/.secrets/dns-credentials.ini

# 3. 安装插件
pip3 install certbot-dns-aliyun

# 4. 生成证书
make cert-generate-dns

# 5. 部署服务
make docker-up-https
```

---

### 场景 4：mkcert（本地开发）

**✅ 在本地运行**

```bash
# 1. 本地生成证书
make cert-generate-mkcert

# 2. 启动本地 HTTPS 服务
make docker-up-https

# 3. 访问
open https://local.yeanhua.asia
```

---

## 常见错误和解决方案

### 错误 1：在本地运行 HTTP-01 失败

**错误信息**：
```
Connection refused
Challenge failed for domain data.yeanhua.asia
```

**原因**：
- 在本地运行了 `make cert-generate`
- Let's Encrypt 访问 `data.yeanhua.asia`（解析到服务器）
- 验证文件在本地，Let's Encrypt 访问不到

**解决方案**：
```bash
# 方案 1：在服务器上运行 HTTP-01
ssh user@121.41.107.93
cd ~/top-ai-news
make cert-generate

# 方案 2：改用 DNS-01（可本地运行）
make cert-generate-dns
scp ~/.local-certs/yeanhua.asia/* user@121.41.107.93:~/certs/
```

---

### 错误 2：服务器 80 端口被占用

**错误信息**：
```
[WARN] 80 端口被占用，使用 Webroot 模式
```

**解决方案**：

**选项 1：使用 Webroot 模式（推荐）**
```bash
# 配置 Nginx 支持 ACME 验证
sudo vim /etc/nginx/sites-available/data.yeanhua.asia

# 添加
location /.well-known/acme-challenge/ {
    root /var/www/html;
}

sudo nginx -s reload
make cert-generate  # 自动使用 webroot
```

**选项 2：临时停止服务**
```bash
docker compose down
make cert-generate
make docker-up-https
```

**选项 3：改用 DNS-01**
```bash
make cert-generate-dns  # 无需 80 端口
```

---

### 错误 3：DNS-01 本地生成后服务器找不到证书

**错误信息**：
```
Error: Certificate not found
```

**原因**：
- 证书在本地生成：`~/.local-certs/yeanhua.asia/`
- 服务器上没有证书文件

**解决方案**：
```bash
# 1. 上传证书到服务器
scp ~/.local-certs/yeanhua.asia/fullchain.pem \
    user@121.41.107.93:~/.local-certs/yeanhua.asia/
scp ~/.local-certs/yeanhua.asia/privkey.pem \
    user@121.41.107.93:~/.local-certs/yeanhua.asia/

# 2. 或者直接在服务器上生成
ssh user@121.41.107.93
cd ~/top-ai-news
make cert-generate-dns
```

---

## 最佳实践建议

### 本地开发

```bash
# 推荐：mkcert（极简，无需服务器）
make cert-generate-mkcert
make docker-up-https
```

### 单域名生产部署

```bash
# 推荐：HTTP-01（在服务器上运行）
ssh user@121.41.107.93
cd ~/top-ai-news
make cert-generate
make docker-up-https
```

### 多子域名生产部署

```bash
# 推荐：DNS-01（可本地生成）
make cert-generate-dns
scp ~/.local-certs/yeanhua.asia/* user@121.41.107.93:~/certs/
ssh user@121.41.107.93
make docker-up-https
```

### 服务器 80 端口被占用

```bash
# 推荐：Webroot 模式（在服务器上运行）
ssh user@121.41.107.93
# 配置 Nginx
sudo vim /etc/nginx/sites-available/data.yeanhua.asia
# 添加 ACME 验证路径
sudo nginx -s reload
make cert-generate  # 自动使用 webroot
```

---

## 总结

### 关键要点

1. **HTTP-01 = 必须在服务器**
   - Let's Encrypt 需要访问服务器 80 端口
   - 验证文件必须在域名解析到的服务器上

2. **DNS-01 = 本地或服务器都可以**
   - 只需 DNS API 访问权限
   - 证书可在任何地方生成

3. **mkcert = 任何地方**
   - 本地 CA，无外部依赖
   - 仅适合开发环境

### 快速选择指南

**我的情况**：只部署 `data.yeanhua.asia`
- ✅ 使用 HTTP-01
- ⚠️ 在服务器上运行

**我的情况**：需要 `*.yeanhua.asia` 泛域名
- ✅ 使用 DNS-01
- ✅ 可以在本地生成

**我的情况**：本地开发测试
- ✅ 使用 mkcert
- ✅ 在本地生成

**我的情况**：服务器 80 端口被占用
- ✅ 使用 Webroot 模式或 DNS-01
- ⚠️ Webroot 仍需在服务器运行

---

## 相关文档

- [single-domain-deployment-2026-02-16.md](single-domain-deployment-2026-02-16.md) - 单域名部署指南
- [http01-implementation-2026-02-16.md](http01-implementation-2026-02-16.md) - HTTP-01 实现说明
- [letsencrypt-setup-2026-02-16.md](letsencrypt-setup-2026-02-16.md) - Let's Encrypt 完整指南
- [certificate-comparison-2026-02-16.md](certificate-comparison-2026-02-16.md) - 证书方案对比
