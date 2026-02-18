# 本地域名配置 - local.yeanhua.asia

## 核心结论

- **本地域名**：`local.yeanhua.asia` 已配置成功
- **访问地址**：http://local.yeanhua.asia 和 http://localhost 均可用
- **配置方式**：nginx 支持多域名，无需修改系统 hosts 文件

---

## 配置内容

### nginx 配置更新

**文件**：`deploy/nginx/conf.d/default.conf`

```nginx
server {
    listen 80;
    server_name data.yeanhua.asia local.yeanhua.asia localhost;
    # ... 其他配置
}
```

**说明**：
- `data.yeanhua.asia`：生产环境域名
- `local.yeanhua.asia`：本地开发域名
- `localhost`：默认本地访问

### Makefile 新增命令

```bash
# 显示域名配置说明（不会修改系统文件）
make setup-local-domain

# 检查域名配置状态
make check-local-domain
```

---

## 验证结果

### 域名解析测试

```bash
$ make check-local-domain

==> 检查本地域名配置...
✓ local.yeanhua.asia 解析正常 → 127.0.0.1

==> 当前可用的访问地址:
  ✓ http://localhost
  ✓ http://local.yeanhua.asia
```

### HTTP 访问测试

```bash
$ curl -I http://local.yeanhua.asia

HTTP/1.1 200 OK
Server: nginx/1.29.5
Content-Type: text/html; charset=utf-8
✓ 访问正常
```

---

## 使用场景对比

| 环境 | 域名 | 用途 |
|------|------|------|
| **本地开发** | `http://local.yeanhua.asia` | 开发测试，模拟生产域名 |
| **本地开发** | `http://localhost` | 快速访问，无需配置 |
| **生产环境** | `https://data.yeanhua.asia` | 正式服务，HTTPS 加密 |

---

## 域名配置方式（可选）

虽然你的域名已经可用，但如果其他团队成员需要配置，可以参考以下方式：

### 方式 1: 修改 hosts 文件

**Mac/Linux**：
```bash
# 编辑 hosts 文件
sudo vim /etc/hosts

# 添加以下行
127.0.0.1 local.yeanhua.asia
```

**Windows**：
```cmd
# 以管理员身份运行记事本
notepad C:\Windows\System32\drivers\etc\hosts

# 添加以下行
127.0.0.1 local.yeanhua.asia
```

### 方式 2: 使用 dnsmasq（Mac 推荐）

```bash
# 安装 dnsmasq
brew install dnsmasq

# 配置泛域名解析
echo "address=/.yeanhua.asia/127.0.0.1" >> $(brew --prefix)/etc/dnsmasq.conf

# 启动服务
sudo brew services start dnsmasq

# 配置系统 DNS
sudo mkdir -p /etc/resolver
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/yeanhua.asia
```

**优势**：
- 支持泛域名（`*.yeanhua.asia` 自动解析到 127.0.0.1）
- 无需每次手动添加新的子域名
- 适合多项目开发

### 方式 3: 路由器 DNS 配置

在路由器管理界面配置本地 DNS 记录（适合团队共享）。

---

## 开发工作流

### 日常开发

```bash
# 1. 启动服务
make docker-dev

# 2. 使用域名访问（更接近生产环境）
open http://local.yeanhua.asia

# 3. 或使用 localhost（快速访问）
open http://localhost
```

### 模拟生产环境

```bash
# 本地使用域名访问，测试域名相关功能
# 例如：Cookie domain、CORS、OAuth 回调等

# 访问地址
http://local.yeanhua.asia

# 对应生产环境
https://data.yeanhua.asia
```

---

## 常见问题

### 1. 域名无法访问

```bash
# 检查域名解析
make check-local-domain

# 检查服务状态
make docker-ps

# 检查 nginx 配置
make docker-nginx-test

# 查看 nginx 日志
docker compose logs nginx
```

### 2. localhost 能访问，域名不能访问

**原因**：域名 DNS 解析未配置

**解决**：
```bash
# 查看域名解析
nslookup local.yeanhua.asia

# 如果解析失败，配置 hosts 或 dnsmasq
make setup-local-domain  # 查看配置说明
```

### 3. 修改 nginx 配置后不生效

```bash
# 测试配置语法
make docker-nginx-test

# 重载配置（不中断服务）
make docker-nginx-reload

# 或完全重启
make docker-restart
```

---

## Makefile 命令详解

### setup-local-domain

显示本地域名配置说明（不会修改系统文件）。

```bash
make setup-local-domain
```

**输出示例**：
```
==> 配置本地域名 local.yeanhua.asia

如果你想使用域名访问本地服务，请手动添加以下配置：

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Mac/Linux 用户：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  sudo vim /etc/hosts

添加以下行：
  127.0.0.1 local.yeanhua.asia
...
```

### check-local-domain

检查域名配置状态和可用性。

```bash
make check-local-domain
```

**检查内容**：
- ✅ hosts 文件配置状态
- ✅ 域名 DNS 解析
- ✅ 服务运行状态
- ✅ 可用的访问地址

---

## 技术细节

### nginx server_name 匹配规则

```nginx
server {
    listen 80;
    server_name data.yeanhua.asia local.yeanhua.asia localhost;
    # ...
}
```

**匹配优先级**：
1. 精确匹配：`server_name example.com`
2. 前缀通配符：`server_name *.example.com`
3. 后缀通配符：`server_name www.example.*`
4. 正则表达式：`server_name ~^www\d+\.example\.com$`
5. 默认 server：`default_server`

在本配置中，`data.yeanhua.asia`、`local.yeanhua.asia`、`localhost` 都是精确匹配，优先级相同。

### Host Header 传递

```nginx
location / {
    proxy_pass http://app:8080;
    proxy_set_header Host $host;  # 传递原始 Host 头
    # ...
}
```

**作用**：
- 后端应用可以获取客户端访问的域名
- 支持多租户应用
- 正确处理重定向 URL

---

## 安全注意事项

### 1. 本地域名仅用于开发

```bash
# ✓ 本地开发
http://local.yeanhua.asia

# ✗ 不要在生产环境使用
# 生产环境使用 HTTPS
https://data.yeanhua.asia
```

### 2. 避免域名泄露

```bash
# 不要在代码中硬编码域名
# ✗ 错误
const API_URL = "http://local.yeanhua.asia/api"

# ✓ 正确：使用环境变量
const API_URL = process.env.API_URL || "http://localhost/api"
```

### 3. 开发环境标识

在本地开发时，可以通过 Host 头或环境变量区分：

```javascript
// 检测开发环境
const isDevelopment =
  window.location.hostname === 'local.yeanhua.asia' ||
  window.location.hostname === 'localhost';
```

---

## 最佳实践

### 1. 团队协作

```bash
# 在 README.md 中说明域名配置
## 本地开发

1. 配置本地域名（可选）
   ```bash
   make setup-local-domain
   ```

2. 启动服务
   ```bash
   make docker-dev
   ```

3. 访问服务
   - http://local.yeanhua.asia （推荐）
   - http://localhost
```

### 2. 环境一致性

```yaml
# docker-compose.yml
services:
  app:
    environment:
      - BASE_URL=http://local.yeanhua.asia  # 本地开发
      # - BASE_URL=https://data.yeanhua.asia  # 生产环境
```

### 3. 前端代理配置

```javascript
// vite.config.js / webpack.config.js
export default {
  server: {
    proxy: {
      '/api': {
        target: 'http://local.yeanhua.asia',
        changeOrigin: true
      }
    }
  }
}
```

---

## 相关文档

- [deployment-guide-2026-02-16.md](deployment-guide-2026-02-16.md) - 完整部署指南
- [deploy-quickstart-2026-02-16.md](deploy-quickstart-2026-02-16.md) - 快速上手
- [makefile-usage-2026-02-16.md](makefile-usage-2026-02-16.md) - Makefile 使用文档

---

## 快速参考

```bash
# 检查配置
make check-local-domain

# 查看配置说明
make setup-local-domain

# 重启服务
make docker-restart

# 测试访问
curl http://local.yeanhua.asia
curl http://localhost

# 打开浏览器
open http://local.yeanhua.asia
```
