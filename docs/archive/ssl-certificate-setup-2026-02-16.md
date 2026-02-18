# SSL 证书配置指南

## 核心结论

- **问题原因**：nginx 配置引用了不存在的 SSL 证书文件，导致容器启动失败
- **解决方案**：先用 HTTP-only 配置启动服务，再通过 `init-ssl.sh` 自动申请 Let's Encrypt 证书
- **关键操作**：运行 `./deploy/init-ssl.sh <域名> <邮箱>` 完成 SSL 自动化配置

---

## 问题诊断

### 错误现象

```
nginx: [emerg] cannot load certificate "/etc/letsencrypt/live/data.yeanhua.asia/fullchain.pem":
BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory)
```

### 根本原因

1. `deploy/nginx/conf.d/default.conf` 配置文件已包含 HTTPS 配置（监听 443 端口）
2. 配置引用了 SSL 证书路径：`/etc/letsencrypt/live/data.yeanhua.asia/fullchain.pem`
3. 证书文件尚未生成（需要先通过 certbot 申请）
4. nginx 启动时加载配置失败，容器反复重启

---

## 解决方案

### 方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| 运行 `init-ssl.sh` | 自动化，一次性完成 HTTP → HTTPS 切换 | 需要域名已正确解析 | **生产环境（推荐）** |
| 手动注释 HTTPS 配置 | 快速恢复 HTTP 服务 | 后续需手动启用 HTTPS | 开发测试环境 |

### 推荐方案：自动化 SSL 配置

#### 前置条件

1. **域名解析**：`data.yeanhua.asia` 已解析到服务器公网 IP
   ```bash
   # 验证域名解析
   dig +short data.yeanhua.asia
   # 或
   nslookup data.yeanhua.asia
   ```

2. **防火墙开放端口**：
   ```bash
   # 确保 80 和 443 端口对外开放
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **服务器可访问**：能通过 HTTP 访问（用于 Let's Encrypt 验证）

#### 执行步骤

```bash
# 1. 添加执行权限（已完成）
chmod +x deploy/init-ssl.sh

# 2. 运行 SSL 初始化脚本
./deploy/init-ssl.sh data.yeanhua.asia your-email@example.com

# 脚本会自动完成以下步骤：
# - 生成临时 HTTP-only nginx 配置
# - 启动 app + nginx 容器
# - 使用 certbot webroot 模式申请证书
# - 切换到 HTTPS nginx 配置
# - 重启 nginx 使证书生效
```

---

## init-ssl.sh 脚本详解

### 参数说明

```bash
./deploy/init-ssl.sh <域名> <邮箱>
```

#### 1. 域名参数（必填）
- **作用**：指定要申请证书的域名
- **示例**：`data.yeanhua.asia`
- **要求**：必须已正确解析到服务器 IP

#### 2. 邮箱参数（必填）
- **用途**：Let's Encrypt 账户邮箱，用于以下场景：

  | 通知类型 | 说明 | 示例 |
  |---------|------|------|
  | 证书过期提醒 | 自动续期失败时发送警告（提前 20/10/1 天） | "证书将在 10 天后过期" |
  | 安全通知 | 证书存在安全问题需紧急撤销 | "检测到私钥泄露风险" |
  | 账户关联 | 用于查询/管理该账户下的所有证书 | 同一邮箱可管理多个域名证书 |
  | 服务变更 | Let's Encrypt API 或政策重大变更 | "API v2 即将停止服务" |

- **隐私保护**：
  - `--no-eff-email`：不订阅 EFF（电子前沿基金会）邮件列表
  - 邮箱不会被公开，仅用于上述通知

- **建议**：使用真实且能及时查收的运维邮箱

### 脚本执行流程

```bash
# Step 1: 生成临时 HTTP-only 配置
cat > deploy/nginx/conf.d/default.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;  # Let's Encrypt 验证目录
    }
    location / {
        proxy_pass http://app:8080;
    }
}
EOF

# Step 2: 启动服务
docker compose up -d app nginx

# Step 3: 申请证书
docker compose run --rm certbot certonly \
    --webroot \                          # webroot 验证模式
    --webroot-path=/var/www/certbot \    # 验证文件存放路径
    -d "${DOMAIN}" \                     # 域名
    --email "${EMAIL}" \                 # 通知邮箱
    --agree-tos \                        # 同意 Let's Encrypt 服务条款
    --no-eff-email                       # 不订阅 EFF 邮件

# Step 4: 生成完整 HTTPS 配置
cat > deploy/nginx/conf.d/default.conf <<EOF
server {
    listen 80;
    location / {
        return 301 https://\$host\$request_uri;  # HTTP 重定向到 HTTPS
    }
}
server {
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    # ... SSL 安全配置 ...
}
EOF

# Step 5: 重启 nginx 应用 HTTPS 配置
docker compose restart nginx
```

### 验证方式详解

脚本使用 **webroot 验证模式**：

1. Let's Encrypt 服务器访问 `http://data.yeanhua.asia/.well-known/acme-challenge/<token>`
2. certbot 在 `/var/www/certbot/.well-known/acme-challenge/` 目录下生成验证文件
3. nginx 配置 `location /.well-known/acme-challenge/` 使该目录对外可访问
4. 验证成功后，Let's Encrypt 签发证书

---

## 手动配置方案

如果自动化脚本失败，可以手动执行：

### 1. 临时切换到 HTTP-only

已将 `deploy/nginx/conf.d/default.conf` 中的 HTTPS 配置注释掉：

```bash
# 重启服务使配置生效
docker compose restart nginx

# 验证 HTTP 服务正常
curl http://data.yeanhua.asia
```

### 2. 手动申请证书

```bash
# 确保服务已启动
docker compose up -d app nginx

# 手动运行 certbot
docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    -d data.yeanhua.asia \
    --email your-email@example.com \
    --agree-tos \
    --no-eff-email
```

### 3. 启用 HTTPS 配置

取消注释 `deploy/nginx/conf.d/default.conf` 中的 HTTPS 部分：

```bash
# 方法 1: 重新运行 init-ssl.sh（会自动生成配置）
./deploy/init-ssl.sh data.yeanhua.asia your-email@example.com

# 方法 2: 手动取消注释配置文件后重启
docker compose restart nginx
```

---

## 证书自动续期

### 续期机制

`docker-compose.yml` 中配置了 certbot 容器自动续期：

```yaml
certbot:
  image: certbot/certbot
  volumes:
    - certbot-etc:/etc/letsencrypt      # 证书存储
    - certbot-var:/var/lib/letsencrypt
    - certbot-webroot:/var/www/certbot  # webroot 验证目录
  entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done'"
```

- **检查频率**：每 12 小时
- **续期时机**：证书剩余有效期 < 30 天时自动续期
- **Let's Encrypt 证书有效期**：90 天

### 手动续期测试

```bash
# 模拟续期（dry-run，不实际续期）
docker compose run --rm certbot renew --dry-run

# 强制续期（测试用，会计入速率限制）
docker compose run --rm certbot renew --force-renewal
```

### 监控续期状态

```bash
# 查看证书过期时间
docker compose run --rm certbot certificates

# 查看 certbot 容器日志
docker compose logs certbot -f
```

---

## 常见问题

### 1. 证书申请失败：域名无法访问

**错误信息**：
```
Challenge failed for domain data.yeanhua.asia
Connection refused
```

**排查步骤**：
```bash
# 1. 验证域名解析
dig +short data.yeanhua.asia

# 2. 检查服务器防火墙
sudo ufw status
curl -I http://data.yeanhua.asia

# 3. 检查 nginx 容器状态
docker compose logs nginx
```

### 2. Let's Encrypt 速率限制

**错误信息**：
```
too many failed authorizations recently
```

**限制规则**：
- 每个域名每小时最多 5 次失败验证
- 每周最多 5 次失败尝试
- 每个注册域名每周最多 50 个证书

**解决方案**：
- 使用 `--dry-run` 测试配置
- 等待速率限制重置（1 小时或 1 周）
- 使用 Let's Encrypt Staging 环境测试

### 3. nginx 重启后证书失效

**原因**：certbot 容器未启动，证书未自动续期

**解决**：
```bash
# 确保 certbot 容器运行
docker compose up -d certbot

# 手动续期
docker compose run --rm certbot renew
docker compose restart nginx
```

### 4. 证书文件权限问题

**错误信息**：
```
Permission denied: '/etc/letsencrypt/live/data.yeanhua.asia/fullchain.pem'
```

**解决**：
```bash
# 检查 volume 权限
docker compose exec nginx ls -l /etc/letsencrypt/live/data.yeanhua.asia/

# 重建 certbot volume
docker compose down
docker volume rm top-ai-news_certbot-etc
docker compose up -d
./deploy/init-ssl.sh data.yeanhua.asia your-email@example.com
```

---

## 安全最佳实践

### SSL 配置优化（已应用）

```nginx
# 现代 TLS 协议
ssl_protocols TLSv1.2 TLSv1.3;

# 高强度加密套件
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;

# 会话缓存（提升性能）
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;

# 安全头
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
```

### 安全检查

```bash
# 1. 使用 SSL Labs 检测
# 访问 https://www.ssllabs.com/ssltest/analyze.html?d=data.yeanhua.asia

# 2. 检查证书有效期
openssl s_client -connect data.yeanhua.asia:443 -servername data.yeanhua.asia </dev/null 2>/dev/null | openssl x509 -noout -dates

# 3. 测试 TLS 协议
nmap --script ssl-enum-ciphers -p 443 data.yeanhua.asia
```

---

## 快速参考

### 常用命令

```bash
# 查看所有证书
docker compose run --rm certbot certificates

# 测试续期
docker compose run --rm certbot renew --dry-run

# 强制续期（会消耗速率限制配额）
docker compose run --rm certbot renew --force-renewal

# 撤销证书
docker compose run --rm certbot revoke --cert-path /etc/letsencrypt/live/data.yeanhua.asia/cert.pem

# 删除证书
docker compose run --rm certbot delete --cert-name data.yeanhua.asia

# 查看 nginx 配置语法
docker compose exec nginx nginx -t

# 重载 nginx 配置（不中断服务）
docker compose exec nginx nginx -s reload
```

### 证书文件说明

```
/etc/letsencrypt/live/data.yeanhua.asia/
├── cert.pem          # 服务器证书
├── chain.pem         # 中间证书链
├── fullchain.pem     # cert.pem + chain.pem（nginx 使用）
└── privkey.pem       # 私钥（nginx 使用）
```

---

## 相关文件

- `deploy/init-ssl.sh` - SSL 自动化配置脚本
- `deploy/nginx/conf.d/default.conf` - nginx 配置文件
- `docker-compose.yml` - 服务编排配置

## 参考资料

- [Let's Encrypt 官方文档](https://letsencrypt.org/docs/)
- [Certbot 用户指南](https://eff-certbot.readthedocs.io/)
- [nginx SSL 配置最佳实践](https://nginx.org/en/docs/http/configuring_https_servers.html)
