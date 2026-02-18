# HTTPS Toolkit 快速开始指南

## 5 分钟上手

### Step 1: 安装工具 (1 分钟)

```bash
# 进入工具包目录
cd https-toolkit

# 运行安装脚本
chmod +x install.sh
./install.sh

# 验证安装
https-deploy version
```

**输出**:
```
HTTPS Deployment Toolkit v1.0.0
```

---

### Step 2: 初始化网关 (2 分钟)

```bash
# 初始化网关
https-deploy gateway init
```

**执行过程**:
```
[INFO] Initializing HTTPS Gateway for local environment...
[INFO]   ✓ Created directory structure
[INFO]   ✓ Generated Nginx configuration
[INFO]   ✓ Generated SSL certificate
[INFO]   ✓ Created network: https-toolkit-network
[INFO]   ✓ Initialized project registry
[INFO]   ✓ Generated Gateway Dashboard
[INFO]   ✓ Gateway started: https://local.yeanhua.asia
[INFO] ✓ Gateway initialized successfully!

Gateway URL: https://local.yeanhua.asia
Dashboard:   https://local.yeanhua.asia/

Next steps:
  1. Add to /etc/hosts: 127.0.0.1 local.yeanhua.asia
  2. Deploy your first project: cd your-project && https-deploy up
```

**访问 Dashboard** (域名已通过 DNS 配置,无需修改 /etc/hosts):
```bash
open https://local.yeanhua.asia
```

你会看到一个美观的 Dashboard 页面(当前无项目)。

---

### Step 3: 部署第一个项目 (2 分钟)

假设你有一个 Go API 项目:

```bash
cd ~/projects/my-api

# 初始化配置
https-deploy init
```

**交互式配置**:
```
Project Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Project name (e.g., my-api): my-api
Backend port (e.g., 8080): 8080
Path prefix (e.g., /api): /api

[INFO] ✓ Configuration created: config.yaml

Next steps:
  1. Review/edit: vim config.yaml
  2. Deploy: https-deploy up
```

**查看生成的配置**:
```bash
cat config.yaml
```

```yaml
project:
  name: my-api
  backend_port: 8080

routing:
  path_prefix: /api
  strip_prefix: true

domains:
  local: local.yeanhua.asia
  production: api.example.com

gateway:
  enabled: true
  auto_register: true
```

**部署项目**:
```bash
https-deploy up
```

**部署日志**:
```
[INFO] Deploying project to local environment...
[INFO] Project: my-api
[INFO] Path: /api
[INFO] Port: 8080
[INFO] Starting backend service...
[+] Running 1/1
 ✔ Container my-api  Started                                    0.5s
[INFO]   ✓ Service is healthy
[INFO] Registering to gateway...
[INFO]   ✓ Generated: my-api.conf
[INFO]   ✓ Configuration is valid
[INFO]   ✓ Nginx reloaded (elapsed: 52ms)
[INFO] ✓ Deployment complete!

Access URL: https://local.yeanhua.asia/api/
Dashboard:  https://local.yeanhua.asia/
```

**测试访问**:
```bash
# 测试健康检查
curl https://local.yeanhua.asia/api/health

# 或浏览器访问
open https://local.yeanhua.asia/api/
```

**查看 Dashboard**:
```bash
open https://local.yeanhua.asia
```

现在 Dashboard 会显示已注册的项目:

```
🚀 HTTPS Gateway
Local Development Environment

┌───────────────┐
│ my-api        │
│ /api          │
│ ● running     │
│ [Open →]      │
└───────────────┘
```

---

## 常用命令速查

### 网关管理

```bash
# 查看网关状态
https-deploy gateway status

# 列出所有项目
https-deploy gateway list

# 查看网关日志
https-deploy gateway logs

# 重载网关配置
https-deploy gateway reload
```

### 项目操作

```bash
# 查看项目日志
https-deploy logs

# 查看实时日志
https-deploy logs -f

# 停止项目
https-deploy down

# 重启项目
https-deploy restart
```

### 路由调试

```bash
# 查看所有路由
https-deploy routes

# 测试特定路由
https-deploy test-route /api/health
```

---

## 部署多个项目

### 项目 B: Web 前端

```bash
cd ~/projects/web-app
https-deploy init

# 配置路径前缀: /web
vim config.yaml

https-deploy up
```

### 项目 C: 管理后台

```bash
cd ~/projects/admin-panel
https-deploy init

# 配置路径前缀: /admin
vim config.yaml

https-deploy up
```

### 查看所有项目

```bash
https-deploy gateway list
```

**输出**:
```
Registered Projects:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Name          Path      Port    Status
my-api        /api      8080    running
web-app       /web      3000    running
admin-panel   /admin    8000    running

Gateway: https://local.yeanhua.asia
```

### 访问不同项目

```bash
# API 服务
curl https://local.yeanhua.asia/api/users

# Web 前端
open https://local.yeanhua.asia/web/

# 管理后台
open https://local.yeanhua.asia/admin/
```

---

## 完整工作流程

### 开发新功能

```bash
# 1. 启动项目
cd my-project
https-deploy up

# 2. 开发代码
vim src/main.go

# 3. 重启应用查看效果
https-deploy restart

# 4. 查看日志
https-deploy logs -f

# 5. 测试
curl https://local.yeanhua.asia/api/new-feature

# 6. 完成后停止
https-deploy down
```

### 切换项目

```bash
# 停止当前项目
cd project-a
https-deploy down

# 启动另一个项目
cd ../project-b
https-deploy up

# 或者同时运行多个项目(推荐)
cd project-a && https-deploy up
cd project-b && https-deploy up
```

---

## 故障排查

### 问题 1: 网关未启动

```bash
$ https-deploy up
[ERROR] Gateway is not running

# 解决:
https-deploy gateway init
```

### 问题 2: 端口被占用

```bash
$ https-deploy up
[ERROR] Port 8080 is already in use

# 查看占用进程
lsof -i :8080

# 停止冲突服务
docker stop <container>

# 或修改端口
vim config.yaml
# backend_port: 8081
```

### 问题 3: 路径前缀冲突

```bash
$ https-deploy up
[ERROR] Path prefix '/api' is already in use

# 查看已注册项目
https-deploy gateway list

# 修改路径前缀
vim config.yaml
# path_prefix: /api-v2
```

### 问题 4: 无法访问 local.yeanhua.asia

```bash
# 验证 DNS 解析
ping local.yeanhua.asia

# 如果 DNS 解析异常,检查网络连接
nslookup local.yeanhua.asia
```

### 问题 5: 证书警告

```bash
# 重新安装 mkcert CA
mkcert -install

# 重新生成证书
rm -rf ~/.https-toolkit/gateway/certs/local.yeanhua.asia
https-deploy gateway init
```

---

## 项目模板

### Go API 项目

**Dockerfile**:
```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go mod download
RUN go build -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates curl
WORKDIR /root/
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
```

**config.yaml**:
```yaml
project:
  name: my-api
  backend_port: 8080

routing:
  path_prefix: /api
  strip_prefix: true

domains:
  local: local.yeanhua.asia

gateway:
  enabled: true
```

**main.go** (示例):
```go
package main

import (
    "fmt"
    "net/http"
)

func main() {
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        fmt.Fprint(w, "OK")
    })

    http.HandleFunc("/users", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        fmt.Fprint(w, `{"users": ["alice", "bob"]}`)
    })

    http.ListenAndServe(":8080", nil)
}
```

### Node.js 项目

**Dockerfile**:
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
```

**config.yaml**:
```yaml
project:
  name: web-app
  backend_port: 3000

routing:
  path_prefix: /web
  strip_prefix: false  # 前端需要知道 base path

domains:
  local: local.yeanhua.asia

gateway:
  enabled: true
```

---

## 下一步

- 阅读完整文档: [README.md](README.md)
- 查看设计方案: [docs/https-path-based-gateway-design-2026-02-17.md](../docs/https-path-based-gateway-design-2026-02-17.md)
- 查看工作原理: [docs/https-deploy-internals-2026-02-17.md](../docs/https-deploy-internals-2026-02-17.md)

---

## 获取帮助

```bash
# 查看帮助
https-deploy help

# 查看版本
https-deploy version

# 提交 Issue
https://github.com/your-org/https-toolkit/issues
```
