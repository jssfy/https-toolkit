# https-deploy up local 执行流程详解

## 核心结论

`https-deploy up local` 会经历 **7 个阶段**,但存在 **端口冲突问题**。多项目并发部署需要:

- **方案 A**: 共享 Nginx 网关 (推荐)
- **方案 B**: 动态端口分配
- **方案 C**: 项目命名空间隔离

---

## 命令执行流程

### 完整流程图

```
https-deploy up local
        ↓
┌──────────────────────────────────────────┐
│ Phase 1: 环境检测与验证                    │
│ - 检查 Docker/Docker Compose             │
│ - 验证 config.yaml 语法                   │
│ - 检查端口占用                             │
└──────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────┐
│ Phase 2: 配置文件渲染                     │
│ - 读取 config.yaml                        │
│ - 合并 config.local.yaml (如果存在)       │
│ - 渲染 Nginx 配置模板                     │
│ - 渲染 Docker Compose 配置                │
│ - 输出到 .https-toolkit/output/           │
└──────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────┐
│ Phase 3: SSL 证书管理                     │
│ - 检查证书是否存在                         │
│ - 如果不存在:                             │
│   - 安装 mkcert (如果未安装)              │
│   - 生成本地 CA 根证书                    │
│   - 生成域名证书                           │
│ - 如果存在但即将过期: 自动续期            │
└──────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────┐
│ Phase 4: 本地域名配置                     │
│ - 检查 /etc/hosts 配置                    │
│ - 如果未配置: 提示用户添加                │
│   (需要 sudo 密码)                        │
└──────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────┐
│ Phase 5: 执行 pre-deploy 钩子             │
│ - 如果存在 hooks/pre-deploy.sh           │
│ - 执行自定义部署前逻辑                     │
└──────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────┐
│ Phase 6: 启动服务                         │
│ - 构建/拉取镜像                           │
│ - 启动 Docker Compose                     │
│   - 后端应用容器                          │
│   - Nginx 容器 (监听 80/443)             │
│ - 等待健康检查通过                         │
└──────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────┐
│ Phase 7: 执行 post-deploy 钩子 & 验证     │
│ - 如果存在 hooks/post-deploy.sh          │
│ - 验证服务可访问性                         │
│ - 显示访问 URL                            │
└──────────────────────────────────────────┘
        ↓
    完成 ✓
```

---

## 详细执行步骤

### Phase 1: 环境检测与验证

```bash
# 伪代码
check_environment() {
    info "Checking environment..."

    # 1. 检查 Docker
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker first."
        exit 1
    fi

    # 2. 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose not found."
        exit 1
    fi

    # 3. 验证配置文件
    if [ ! -f "config.yaml" ]; then
        error "config.yaml not found. Run 'https-deploy init' first."
        exit 1
    fi

    # 4. 验证 YAML 语法
    yq eval config.yaml > /dev/null || {
        error "config.yaml has syntax errors"
        exit 1
    }

    # 5. 检查端口占用
    local backend_port=$(yq .project.backend_port config.yaml)
    if lsof -Pi :$backend_port -sTCP:LISTEN &> /dev/null; then
        warn "Port $backend_port is already in use"
        read -p "Continue anyway? [y/N] " -n 1 -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi

    # 6. 检查 443 端口 (关键!)
    if lsof -Pi :443 -sTCP:LISTEN &> /dev/null; then
        error "Port 443 is already in use"
        lsof -Pi :443 -sTCP:LISTEN
        echo ""
        echo "Solutions:"
        echo "  1. Stop other services using port 443"
        echo "  2. Use dynamic ports: https-deploy up local --dynamic-ports"
        exit 1
    fi

    info "✓ Environment check passed"
}
```

**输出示例**:
```
[INFO] Checking environment...
[INFO]   ✓ Docker installed (version 24.0.5)
[INFO]   ✓ Docker Compose installed (version 2.20.0)
[INFO]   ✓ config.yaml found and valid
[INFO]   ✓ Port 8080 available
[INFO]   ✓ Port 443 available
[INFO] ✓ Environment check passed
```

### Phase 2: 配置文件渲染

```bash
render_configuration() {
    local env="local"
    info "Rendering configuration templates..."

    # 1. 读取配置
    local project_name=$(yq .project.name config.yaml)
    local backend_port=$(yq .project.backend_port config.yaml)
    local domain=$(yq .domains.local.primary config.yaml)
    local cert_storage=$(yq .certificates.local.storage config.yaml)

    # 2. 展开变量 (如 ${project.name})
    cert_storage=$(eval echo "$cert_storage")

    # 3. 渲染 Nginx 配置
    export PROJECT_NAME="$project_name"
    export BACKEND_PORT="$backend_port"
    export DOMAIN="$domain"
    export CERT_STORAGE="$cert_storage"

    envsubst < templates/nginx-https.conf.tpl \
             > .https-toolkit/output/nginx-local.conf

    # 4. 渲染 Docker Compose
    envsubst < templates/docker-compose.tpl \
             > .https-toolkit/output/docker-compose-local.yml

    info "✓ Configuration rendered"
    info "  Output: .https-toolkit/output/"
}
```

**生成的文件**:
```
.https-toolkit/output/
├── nginx-local.conf              # 渲染后的 Nginx 配置
├── docker-compose-local.yml      # 渲染后的 Docker Compose
└── .rendered-vars                # 渲染时使用的变量 (用于调试)
```

### Phase 3: SSL 证书管理

```bash
manage_certificate() {
    local env="local"
    info "Managing SSL certificate..."

    # 1. 检查证书状态
    if cert_exists && cert_valid; then
        info "✓ Certificate exists and valid"
        return 0
    fi

    # 2. 证书不存在或即将过期
    if cert_exists && cert_expiring_soon; then
        warn "Certificate expiring soon, renewing..."
        generate_certificate "$env"
    else
        info "Certificate not found, generating..."
        generate_certificate "$env"
    fi
}

generate_certificate() {
    local env="$1"
    local provider=$(yq .certificates.$env.provider config.yaml)

    case "$provider" in
        mkcert)
            generate_mkcert_certificate
            ;;
        letsencrypt)
            generate_letsencrypt_certificate
            ;;
        *)
            error "Unknown certificate provider: $provider"
            exit 1
            ;;
    esac
}

generate_mkcert_certificate() {
    info "Generating local certificate with mkcert..."

    # 1. 检查 mkcert
    if ! command -v mkcert &> /dev/null; then
        info "Installing mkcert..."
        brew install mkcert || {
            error "Failed to install mkcert"
            exit 1
        }
    fi

    # 2. 安装 CA 根证书 (首次)
    if [ ! -d "$(mkcert -CAROOT)" ]; then
        info "Installing local CA root certificate..."
        mkcert -install
    fi

    # 3. 生成证书
    local domain=$(yq .domains.local.primary config.yaml)
    local cert_dir=$(yq .certificates.local.storage config.yaml)
    cert_dir=$(eval echo "$cert_dir")

    mkdir -p "$cert_dir"
    cd "$cert_dir"

    mkcert "$domain" "localhost" "127.0.0.1" "::1"

    # 4. 重命名为标准名称
    mv "${domain}+3.pem" fullchain.pem
    mv "${domain}+3-key.pem" privkey.pem

    info "✓ Certificate generated: $cert_dir"
}
```

**输出示例**:
```
[INFO] Managing SSL certificate...
[INFO] Certificate not found, generating...
[INFO] Generating local certificate with mkcert...
[INFO] mkcert already installed
[INFO] Installing local CA root certificate...

Created a new local CA 💥
The local CA is now installed in the system trust store! ⚡️

[INFO] Generating certificate for local.myapp.dev...

Created a new certificate valid for the following names 📜
 - "local.myapp.dev"
 - "localhost"
 - "127.0.0.1"
 - "::1"

The certificate is at "local.myapp.dev+3.pem" and the key at "local.myapp.dev+3-key.pem" ✅

[INFO] ✓ Certificate generated: /Users/you/.local-certs/my-project
```

### Phase 4: 本地域名配置

```bash
setup_local_domain() {
    local domain=$(yq .domains.local.primary config.yaml)

    info "Checking local domain configuration..."

    # 检查 /etc/hosts
    if grep -q "$domain" /etc/hosts 2>/dev/null; then
        info "✓ $domain already configured in /etc/hosts"
        return 0
    fi

    # 需要配置
    warn "$domain not configured in /etc/hosts"
    echo ""
    echo "To access via domain name, add this line to /etc/hosts:"
    echo "  127.0.0.1 $domain"
    echo ""
    read -p "Add automatically? (requires sudo) [y/N] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "127.0.0.1 $domain" | sudo tee -a /etc/hosts
        info "✓ Added $domain to /etc/hosts"
    else
        info "Skipped. You can still access via https://localhost"
    fi
}
```

### Phase 5: 执行 pre-deploy 钩子

```bash
run_pre_deploy_hook() {
    if [ -f "hooks/pre-deploy.sh" ]; then
        info "Running pre-deploy hook..."
        bash hooks/pre-deploy.sh "$env" || {
            error "Pre-deploy hook failed"
            exit 1
        }
        info "✓ Pre-deploy hook completed"
    fi
}
```

### Phase 6: 启动服务

```bash
start_services() {
    local env="local"
    local compose_file=".https-toolkit/output/docker-compose-$env.yml"

    info "Starting services..."

    # 1. 构建镜像 (如果需要)
    if [ -f "Dockerfile" ]; then
        info "Building Docker image..."
        docker-compose -f "$compose_file" build
    fi

    # 2. 启动服务
    info "Starting containers..."
    docker-compose -f "$compose_file" up -d

    # 3. 等待服务启动
    info "Waiting for services to be healthy..."
    sleep 5

    # 4. 健康检查
    local max_retries=30
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -k -f https://localhost/ &> /dev/null; then
            info "✓ Services are healthy"
            return 0
        fi
        retry=$((retry + 1))
        sleep 1
    done

    error "Services failed to start"
    docker-compose -f "$compose_file" logs
    exit 1
}
```

**Docker Compose 启动的容器**:
```
CONTAINER ID   IMAGE              COMMAND                  PORTS
abc123def456   my-project:latest  "/app/main"             127.0.0.1:8080->8080/tcp
def456abc789   nginx:alpine       "/docker-entrypoint.…"  0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
```

### Phase 7: 验证与完成

```bash
post_deploy() {
    local env="local"

    # 1. 执行 post-deploy 钩子
    if [ -f "hooks/post-deploy.sh" ]; then
        info "Running post-deploy hook..."
        bash hooks/post-deploy.sh "$env"
    fi

    # 2. 显示访问信息
    local domain=$(yq .domains.local.primary config.yaml)

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Deployment complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Access URLs:"
    echo "  • https://$domain 🔒"
    echo "  • https://localhost 🔒"
    echo ""
    echo "Useful commands:"
    echo "  View logs:    https-deploy logs"
    echo "  Stop:         https-deploy down local"
    echo "  Restart:      https-deploy restart local"
    echo ""
}
```

---

## 多项目端口冲突问题

### 问题场景

```bash
# 项目 A
cd ~/projects/project-a
https-deploy up local
# ✓ 成功启动: Nginx 监听 443 端口

# 项目 B
cd ~/projects/project-b
https-deploy up local
# ✗ 失败: Port 443 is already in use
```

**根本原因**: 每个项目都启动独立的 Nginx 容器,默认都监听 443 端口,必然冲突。

---

## 解决方案

### 方案 A: 共享 Nginx 网关 (推荐)

**设计**: 所有项目共享一个 Nginx 容器,通过域名路由到不同后端。

#### 架构图

```
                    ┌─────────────────────────┐
                    │   Shared Nginx Gateway   │
                    │   (Port 443)            │
                    └─────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ Project A     │   │ Project B     │   │ Project C     │
│ :8080         │   │ :3000         │   │ :8000         │
│ app-a.local   │   │ app-b.local   │   │ app-c.local   │
└───────────────┘   └───────────────┘   └───────────────┘
```

#### 实现方式

##### 1. 创建共享 Nginx 容器

```bash
# 创建共享网络
docker network create https-toolkit-network

# 启动共享 Nginx
docker run -d \
    --name https-toolkit-gateway \
    --network https-toolkit-network \
    -p 80:80 \
    -p 443:443 \
    -v ~/.local-certs:/etc/nginx/certs:ro \
    -v ~/.https-toolkit/nginx-config:/etc/nginx/conf.d:ro \
    --restart unless-stopped \
    nginx:alpine
```

##### 2. 项目配置

```yaml
# config.yaml
project:
  name: my-project
  backend_port: 8080

domains:
  local: app-a.local

deployment:
  type: docker-compose
  shared_gateway: true           # ✓ 使用共享网关
  gateway_network: https-toolkit-network
```

##### 3. 修改 Docker Compose

```yaml
# 渲染后的 docker-compose-local.yml
services:
  my-project:
    image: my-project:latest
    container_name: my-project
    networks:
      - https-toolkit-network    # 连接到共享网络
    ports:
      - "127.0.0.1:8080:8080"    # 只暴露给本地

  # ❌ 不再启动独立的 Nginx
  # nginx:
  #   ...

networks:
  https-toolkit-network:
    external: true               # 使用外部网络
```

##### 4. 动态注册到网关

```bash
# https-deploy up local 时
start_with_shared_gateway() {
    local domain=$(yq .domains.local.primary config.yaml)
    local backend_port=$(yq .project.backend_port config.yaml)
    local project_name=$(yq .project.name config.yaml)

    # 1. 启动后端服务
    docker-compose -f .https-toolkit/output/docker-compose-local.yml up -d

    # 2. 生成 Nginx upstream 配置
    cat > ~/.https-toolkit/nginx-config/${project_name}.conf <<EOF
server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/nginx/certs/${project_name}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/${project_name}/privkey.pem;

    location / {
        proxy_pass http://${project_name}:${backend_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # 3. 重载 Nginx 配置
    docker exec https-toolkit-gateway nginx -s reload

    info "✓ Registered $domain → $project_name:$backend_port"
}
```

##### 5. 使用流程

```bash
# 首次使用: 初始化共享网关
https-deploy gateway init

# 项目 A
cd ~/projects/project-a
https-deploy up local
# ✓ 注册到网关: app-a.local → project-a:8080

# 项目 B (并发启动)
cd ~/projects/project-b
https-deploy up local
# ✓ 注册到网关: app-b.local → project-b:3000

# 项目 C
cd ~/projects/project-c
https-deploy up local
# ✓ 注册到网关: app-c.local → project-c:8000

# 同时访问
open https://app-a.local
open https://app-b.local
open https://app-c.local
```

##### 6. 网关管理命令

```bash
# 初始化共享网关
https-deploy gateway init

# 查看网关状态
https-deploy gateway status
# Output:
#   Gateway: https-toolkit-gateway (running)
#   Registered projects:
#     - app-a.local → project-a:8080
#     - app-b.local → project-b:3000
#     - app-c.local → project-c:8000

# 查看网关日志
https-deploy gateway logs

# 重载网关配置
https-deploy gateway reload

# 停止网关
https-deploy gateway stop

# 清理网关
https-deploy gateway clean
```

---

### 方案 B: 动态端口分配

**设计**: 每个项目使用不同的 HTTPS 端口。

#### 实现

```yaml
# config.yaml
deployment:
  ports:
    https: auto    # 自动分配可用端口 (44301, 44302, ...)
    # 或手动指定
    https: 8443
```

```bash
# https-deploy up local --dynamic-ports
# 自动分配端口

# 输出:
#   ✓ HTTPS port assigned: 44301
#   Access URL: https://localhost:44301
```

**优势**:
- 简单,无需共享网关
- 每个项目完全隔离

**劣势**:
- 需要记住端口号
- 不能使用标准 443 端口
- 证书域名验证可能有问题

---

### 方案 C: 项目命名空间隔离

**设计**: 通过 Docker 网络隔离,每个项目独立的 443 端口(只暴露给项目内部)。

```yaml
# docker-compose-local.yml
services:
  app:
    networks:
      - project-a-network

  nginx:
    networks:
      - project-a-network
    ports:
      - "127.0.0.1:8443:443"   # 映射到本地不同端口

networks:
  project-a-network:
    name: project-a-network
```

---

## 方案对比

| 方案 | 优势 | 劣势 | 推荐度 |
|------|------|------|--------|
| **A. 共享网关** | • 标准 443 端口<br>• 统一证书管理<br>• 域名自动路由 | • 需要额外网关管理<br>• 稍复杂 | ⭐⭐⭐⭐⭐ |
| **B. 动态端口** | • 简单<br>• 完全隔离 | • 非标准端口<br>• 需要记住端口 | ⭐⭐⭐ |
| **C. 命名空间** | • 隔离性好 | • 本地端口映射复杂<br>• 不能用标准端口 | ⭐⭐ |

---

## 推荐实现: 方案 A 详细设计

### 完整命令流程

```bash
# 1. 全局初始化(一次性)
$ https-deploy gateway init

Creating shared HTTPS gateway...
  ✓ Created network: https-toolkit-network
  ✓ Started gateway: https-toolkit-gateway
  ✓ Gateway listening on: 0.0.0.0:443

Gateway initialized successfully!

# 2. 项目启动(自动检测网关)
$ cd ~/projects/project-a
$ https-deploy up local

[INFO] Checking shared gateway...
[INFO]   ✓ Gateway is running
[INFO] Starting project...
[INFO]   ✓ Backend started: project-a:8080
[INFO]   ✓ Registered to gateway: app-a.local
[INFO] ✓ Deployment complete!

Access URL: https://app-a.local

# 3. 并发启动其他项目
$ cd ~/projects/project-b
$ https-deploy up local

[INFO] Checking shared gateway...
[INFO]   ✓ Gateway is running
[INFO] Starting project...
[INFO]   ✓ Backend started: project-b:3000
[INFO]   ✓ Registered to gateway: app-b.local
[INFO] ✓ Deployment complete!

Access URL: https://app-b.local

# 4. 查看所有项目
$ https-deploy gateway status

Shared HTTPS Gateway Status:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Gateway:    https-toolkit-gateway (running)
Network:    https-toolkit-network
Ports:      80, 443

Registered Projects:
  • app-a.local → project-a:8080 (running)
  • app-b.local → project-b:3000 (running)

# 5. 停止单个项目(不影响网关)
$ cd ~/projects/project-a
$ https-deploy down local

[INFO] Stopping project...
[INFO]   ✓ Stopped: project-a
[INFO]   ✓ Unregistered from gateway: app-a.local

# 6. 完全清理
$ https-deploy gateway clean

Stopping all projects...
  ✓ Stopped: project-a
  ✓ Stopped: project-b
Stopping gateway...
  ✓ Stopped: https-toolkit-gateway
Cleaning network...
  ✓ Removed: https-toolkit-network

All cleaned up!
```

---

## 配置文件更新

```yaml
# config.yaml (新增 gateway 配置)
deployment:
  type: docker-compose

  # 网关配置
  gateway:
    enabled: true                          # 启用共享网关
    auto_create: true                      # 自动创建网关(如果不存在)
    name: https-toolkit-gateway            # 网关容器名
    network: https-toolkit-network         # 共享网络名

    # 高级配置
    certificate_path: ~/.local-certs       # 证书根目录
    config_path: ~/.https-toolkit/nginx-config  # Nginx 配置目录
```

---

## 总结

### `https-deploy up local` 核心流程

1. ✅ 环境检测 (Docker/配置)
2. ✅ 渲染配置 (Nginx/Docker Compose)
3. ✅ 证书管理 (生成/续期)
4. ✅ 域名配置 (/etc/hosts)
5. ✅ 执行钩子 (pre-deploy)
6. ✅ 启动服务 (Docker Compose)
7. ✅ 验证完成 (健康检查 + post-deploy)

### 多项目部署推荐方案

**方案 A: 共享 Nginx 网关**

优势:
- ✅ 标准 443 端口,无需记忆额外端口
- ✅ 自动域名路由,访问体验好
- ✅ 统一证书和配置管理
- ✅ 支持无限项目并发

实现:
- 新增 `https-deploy gateway` 命令族
- 修改项目部署逻辑: 不启动独立 Nginx,注册到共享网关
- 配置文件新增 `deployment.gateway` 配置

### 下一步建议

1. 先实现基础流程(单项目)
2. 再实现共享网关(多项目)
3. 提供 `--standalone` 选项支持独立部署(兼容旧方式)
