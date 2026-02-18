# https-deploy 工作原理详解

## 核心结论

`https-deploy` 是一个 **独立的 Shell 脚本工具**,工作方式类似 `git`/`docker`:

- **安装位置**: `/usr/local/bin/https-deploy` (全局可用)
- **配置读取**: 读取当前目录的 `config.yaml`
- **Nginx 变化**: 新增配置文件 + 热重载(无需重启)
- **零停机**: 使用 `nginx -s reload` 实现配置热更新

---

## 一、https-deploy 脚本结构

### 1.1 安装方式

```bash
# 方式 1: 安装脚本 (推荐)
curl -sSL https://toolkit.example.com/install.sh | bash

# 实际执行:
# 1. 下载工具包到 ~/.https-toolkit/
# 2. 创建符号链接到 /usr/local/bin/https-deploy
# 3. 设置可执行权限
```

### 1.2 目录结构

```
安装后的目录结构:

~/.https-toolkit/                      # 工具包根目录
├── bin/
│   └── https-deploy                   # 主脚本
├── lib/                               # 库文件
│   ├── gateway.sh                     # 网关管理
│   ├── project.sh                     # 项目部署
│   ├── config.sh                      # 配置解析
│   └── utils.sh                       # 工具函数
├── templates/                         # 配置模板
│   ├── nginx-project.conf.tpl
│   ├── docker-compose.yml.tpl
│   └── config.yaml.example
└── gateway/                           # 网关数据
    ├── config.yaml                    # 网关配置
    ├── nginx/                         # Nginx 配置
    │   ├── nginx.conf
    │   └── conf.d/
    │       ├── 00-default.conf
    │       └── projects/              # 项目配置(动态生成)
    │           ├── project-a.conf
    │           └── project-b.conf
    ├── certs/                         # SSL 证书
    ├── html/                          # Dashboard
    └── registry/                      # 项目注册表
        └── projects.json

/usr/local/bin/
└── https-deploy -> ~/.https-toolkit/bin/https-deploy  # 符号链接
```

### 1.3 主脚本结构

```bash
#!/bin/bash
# ~/.https-toolkit/bin/https-deploy
# HTTPS 部署工具主脚本

set -e

# ========================================
# 全局变量
# ========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(dirname "$SCRIPT_DIR")"
GATEWAY_ROOT="$HOME/.https-toolkit/gateway"
PROJECT_CONFIG="config.yaml"

# ========================================
# 加载库文件
# ========================================
source "$TOOLKIT_ROOT/lib/utils.sh"
source "$TOOLKIT_ROOT/lib/config.sh"
source "$TOOLKIT_ROOT/lib/gateway.sh"
source "$TOOLKIT_ROOT/lib/project.sh"

# ========================================
# 命令路由
# ========================================
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        # 网关管理
        gateway)
            gateway_command "$@"
            ;;

        # 项目部署
        init)
            project_init "$@"
            ;;
        up)
            project_up "$@"
            ;;
        down)
            project_down "$@"
            ;;
        restart)
            project_restart "$@"
            ;;

        # 工具命令
        routes)
            gateway_show_routes "$@"
            ;;
        test-route)
            gateway_test_route "$@"
            ;;
        logs)
            project_logs "$@"
            ;;

        # 帮助
        help|--help|-h)
            show_help
            ;;

        # 版本
        version|--version|-v)
            show_version
            ;;

        *)
            error "Unknown command: $command"
            echo "Run 'https-deploy help' for usage"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
```

---

## 二、https-deploy 工作流程

### 2.1 项目部署流程 (https-deploy up)

```
用户执行: https-deploy up
        ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 1: 环境检查                                        │
│ - 检查 Docker 是否运行                                   │
│ - 检查网关是否存在                                       │
│ - 验证 config.yaml                                       │
└─────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 2: 解析配置                                        │
│ - 读取 config.yaml                                       │
│ - 提取: project_name, backend_port, path_prefix         │
│ - 验证路径前缀是否冲突                                   │
└─────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 3: 启动后端服务                                    │
│ - 渲染 docker-compose.yml                               │
│ - docker-compose up -d                                   │
│ - 等待服务健康                                           │
└─────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 4: 注册到网关                                      │
│ - 生成 Nginx 配置文件                                    │
│ - 保存到 gateway/nginx/conf.d/projects/<name>.conf     │
│ - 更新注册表 projects.json                               │
│ - 执行 nginx -s reload (热重载,无需重启)                │
└─────────────────────────────────────────────────────────┘
        ↓
        完成 ✓
```

### 2.2 详细代码实现

```bash
#!/bin/bash
# lib/project.sh

# 项目部署主函数
project_up() {
    local env="${1:-local}"

    info "Deploying project to $env environment..."

    # ========================================
    # Phase 1: 环境检查
    # ========================================
    check_environment() {
        # 检查 Docker
        if ! docker info &> /dev/null; then
            error "Docker is not running"
            exit 1
        fi

        # 检查网关
        if ! docker ps --filter "name=https-toolkit-gateway" --format "{{.Names}}" | grep -q "https-toolkit-gateway"; then
            warn "Gateway is not running"
            read -p "Initialize gateway now? [Y/n] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                gateway_init "$env"
            else
                error "Gateway is required. Run: https-deploy gateway init"
                exit 1
            fi
        fi

        # 验证配置文件
        if [ ! -f "$PROJECT_CONFIG" ]; then
            error "config.yaml not found. Run: https-deploy init"
            exit 1
        fi

        # 验证 YAML 语法
        yq eval "$PROJECT_CONFIG" > /dev/null || {
            error "config.yaml has syntax errors"
            exit 1
        }
    }

    check_environment

    # ========================================
    # Phase 2: 解析配置
    # ========================================
    local project_name=$(yq .project.name "$PROJECT_CONFIG")
    local backend_port=$(yq .project.backend_port "$PROJECT_CONFIG")
    local path_prefix=$(yq .routing.path_prefix "$PROJECT_CONFIG")
    local strip_prefix=$(yq .routing.strip_prefix "$PROJECT_CONFIG")
    local domain=$(yq ".domains.$env" "$PROJECT_CONFIG")

    info "Project: $project_name"
    info "Path: $path_prefix"
    info "Port: $backend_port"

    # 检查路径前缀冲突
    if check_path_conflict "$path_prefix" "$project_name"; then
        error "Path prefix '$path_prefix' is already in use by another project"
        exit 1
    fi

    # ========================================
    # Phase 3: 启动后端服务
    # ========================================
    info "Starting backend service..."

    # 渲染 Docker Compose 配置
    mkdir -p .https-toolkit/output
    render_docker_compose "$env" "$project_name" "$backend_port"

    # 启动服务
    docker-compose -f .https-toolkit/output/docker-compose-$env.yml up -d

    # 等待服务就绪
    wait_for_service "$project_name" "$backend_port"

    info "✓ Backend service started"

    # ========================================
    # Phase 4: 注册到网关
    # ========================================
    info "Registering to gateway..."

    register_to_gateway "$env" "$project_name" "$backend_port" "$path_prefix" "$strip_prefix"

    info "✓ Project deployed successfully!"
    echo ""
    echo "Access URL: https://$domain$path_prefix"
    echo "Dashboard:  https://$domain/"
}

# 渲染 Docker Compose 配置
render_docker_compose() {
    local env="$1"
    local project_name="$2"
    local backend_port="$3"

    cat > .https-toolkit/output/docker-compose-$env.yml <<EOF
services:
  $project_name:
    image: ${project_name}:latest
    container_name: $project_name
    build:
      context: .
      dockerfile: Dockerfile
    networks:
      - https-toolkit-network
    environment:
      - TZ=Asia/Shanghai
      - PORT=$backend_port
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$backend_port/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  https-toolkit-network:
    external: true
EOF
}

# 等待服务就绪
wait_for_service() {
    local project_name="$1"
    local port="$2"
    local max_wait=60
    local elapsed=0

    info "Waiting for service to be healthy..."

    while [ $elapsed -lt $max_wait ]; do
        if docker exec "$project_name" curl -f "http://localhost:$port/health" &> /dev/null; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    error "Service failed to start within ${max_wait}s"
    docker logs "$project_name"
    exit 1
}

# 检查路径前缀冲突
check_path_conflict() {
    local path_prefix="$1"
    local project_name="$2"
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    if [ ! -f "$registry_file" ]; then
        return 1  # 注册表不存在,无冲突
    fi

    # 检查是否已有项目使用相同路径(排除自己)
    local conflict=$(jq -r --arg path "$path_prefix" --arg name "$project_name" \
        '.projects[] | select(.path_prefix == $path and .name != $name) | .name' \
        "$registry_file")

    [ -n "$conflict" ]  # 有冲突返回 0 (true)
}
```

---

## 三、Nginx 配置变化详解

### 3.1 初始状态(无项目)

```
gateway/nginx/conf.d/
├── 00-default.conf          # 默认配置(网关 Dashboard)
└── projects/                # 空目录
```

**Nginx 配置**:
```nginx
# 00-default.conf
server {
    listen 443 ssl http2;
    server_name dev.local;

    # 默认路由: Dashboard
    location = / {
        root /usr/share/nginx/html;
        index index.html;
    }

    # 健康检查
    location /health {
        return 200 "OK\n";
    }
}
```

### 3.2 添加项目 A (https-deploy up)

**执行过程**:
```bash
cd ~/projects/project-a
https-deploy up

# 内部执行:
# 1. 生成 Nginx 配置文件
cat > ~/.https-toolkit/gateway/nginx/conf.d/projects/project-a.conf <<EOF
# Auto-generated for: project-a
# Path: /api

upstream project-a_backend {
    server project-a:8080;
}

server {
    listen 443 ssl http2;
    server_name _;

    location /api {
        rewrite ^/api/?(.*)$ /$1 break;
        proxy_pass http://project-a_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# 2. 更新注册表
jq '.projects += [{
    "name": "project-a",
    "path_prefix": "/api",
    "backend_port": 8080,
    "status": "running"
}]' projects.json > tmp.json
mv tmp.json projects.json

# 3. 热重载 Nginx (关键!)
docker exec https-toolkit-gateway nginx -s reload
```

**变化后的目录结构**:
```
gateway/nginx/conf.d/
├── 00-default.conf
└── projects/
    └── project-a.conf        # ✓ 新增
```

**Nginx 行为**:
- ✅ 不会重启容器
- ✅ 不会断开现有连接
- ✅ 新配置立即生效(下一个请求)
- ✅ 耗时: ~50ms

### 3.3 添加项目 B (并发,无需重启)

```bash
cd ~/projects/project-b
https-deploy up
```

**变化后的目录结构**:
```
gateway/nginx/conf.d/
├── 00-default.conf
└── projects/
    ├── project-a.conf
    └── project-b.conf        # ✓ 新增
```

**Nginx 行为**:
- ✅ 再次执行 `nginx -s reload`
- ✅ 项目 A 不受影响,继续运行
- ✅ 项目 B 立即可访问

### 3.4 移除项目 A (https-deploy down)

```bash
cd ~/projects/project-a
https-deploy down

# 内部执行:
# 1. 停止容器
docker-compose down

# 2. 删除 Nginx 配置
rm ~/.https-toolkit/gateway/nginx/conf.d/projects/project-a.conf

# 3. 更新注册表
jq 'del(.projects[] | select(.name == "project-a"))' projects.json > tmp.json
mv tmp.json projects.json

# 4. 热重载 Nginx
docker exec https-toolkit-gateway nginx -s reload
```

**变化后的目录结构**:
```
gateway/nginx/conf.d/
├── 00-default.conf
└── projects/
    └── project-b.conf        # project-a.conf 已删除
```

**Nginx 行为**:
- ✅ 不会重启
- ✅ 项目 B 不受影响
- ✅ 访问 `/api` 返回 404

---

## 四、Nginx 热重载机制

### 4.1 nginx -s reload 原理

```
执行: docker exec https-toolkit-gateway nginx -s reload
        ↓
┌─────────────────────────────────────────────────────────┐
│ Step 1: 发送 SIGHUP 信号给 Master 进程                   │
└─────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────┐
│ Step 2: Master 进程重新加载配置文件                       │
│ - 读取所有 .conf 文件                                    │
│ - 验证配置语法                                           │
│ - 如果语法错误: 回滚,保持旧配置                          │
└─────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────┐
│ Step 3: 启动新的 Worker 进程                             │
│ - 使用新配置启动新 Worker                                │
│ - 旧 Worker 继续处理现有连接                             │
└─────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────┐
│ Step 4: 平滑切换                                         │
│ - 新请求由新 Worker 处理(新配置生效)                     │
│ - 旧 Worker 等待现有连接完成后退出                       │
│ - 最长等待时间: worker_shutdown_timeout (默认无限)      │
└─────────────────────────────────────────────────────────┘
        ↓
        完成 ✓
```

### 4.2 零停机验证

```bash
# 终端 1: 持续访问项目 A
while true; do
    curl -s https://dev.local/api/health
    sleep 0.5
done

# 终端 2: 添加项目 B
cd ~/projects/project-b
https-deploy up

# 终端 3: 监控 Nginx 进程
watch -n 0.5 'docker exec https-toolkit-gateway ps aux | grep nginx'

# 结果:
# - 终端 1: 没有任何请求失败
# - 终端 2: 部署成功
# - 终端 3: 看到 Worker 进程平滑切换
#   - 旧 Worker: 继续运行直到连接结束
#   - 新 Worker: 处理新请求
```

### 4.3 配置错误保护

```bash
# 如果生成的 Nginx 配置有语法错误
project_up() {
    # ...

    # 生成配置文件
    generate_nginx_config "$project_name" "$path_prefix" > "$config_file"

    # 测试配置语法
    if ! docker exec https-toolkit-gateway nginx -t 2>&1; then
        error "Generated Nginx config has syntax errors"
        rm "$config_file"  # 删除错误的配置
        exit 1
    fi

    # 语法正确才执行 reload
    docker exec https-toolkit-gateway nginx -s reload
}
```

**Nginx 测试输出**:
```bash
$ docker exec https-toolkit-gateway nginx -t

# 成功:
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

# 失败:
nginx: [emerg] invalid number of arguments in "proxy_pass" directive in /etc/nginx/conf.d/projects/project-a.conf:10
nginx: configuration file /etc/nginx/nginx.conf test failed
```

---

## 五、注册表管理

### 5.1 注册表结构

```json
{
  "version": "1.0.0",
  "environment": "local",
  "projects": [
    {
      "name": "project-a",
      "path_prefix": "/api",
      "backend_port": 8080,
      "container_name": "project-a",
      "strip_prefix": true,
      "status": "running",
      "registered_at": "2026-02-17T10:30:15Z",
      "updated_at": "2026-02-17T10:30:15Z",
      "health_check": {
        "url": "/api/health",
        "status": "healthy",
        "last_check": "2026-02-17T10:35:20Z"
      }
    },
    {
      "name": "project-b",
      "path_prefix": "/web",
      "backend_port": 3000,
      "container_name": "project-b",
      "strip_prefix": false,
      "status": "running",
      "registered_at": "2026-02-17T10:32:22Z",
      "updated_at": "2026-02-17T10:32:22Z",
      "health_check": {
        "url": "/web/health",
        "status": "healthy",
        "last_check": "2026-02-17T10:35:21Z"
      }
    }
  ],
  "updated_at": "2026-02-17T10:35:21Z"
}
```

### 5.2 注册表操作

```bash
# 添加项目
add_to_registry() {
    local project_name="$1"
    local path_prefix="$2"
    local backend_port="$3"
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    # 加锁(防止并发冲突)
    local lock_file="$GATEWAY_ROOT/registry/.lock"
    exec 200>"$lock_file"
    flock -x 200

    # 更新注册表
    local tmp_file=$(mktemp)
    jq --arg name "$project_name" \
       --arg path "$path_prefix" \
       --argjson port "$backend_port" \
       --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '
       # 删除同名项目(如果存在)
       del(.projects[] | select(.name == $name)) |
       # 添加新项目
       .projects += [{
           name: $name,
           path_prefix: $path,
           backend_port: $port,
           status: "running",
           registered_at: $now,
           updated_at: $now
       }] |
       # 按路径排序
       .projects |= sort_by(.path_prefix) |
       # 更新时间戳
       .updated_at = $now
       ' "$registry_file" > "$tmp_file"

    mv "$tmp_file" "$registry_file"

    # 解锁
    flock -u 200
}

# 删除项目
remove_from_registry() {
    local project_name="$1"
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    # 加锁
    local lock_file="$GATEWAY_ROOT/registry/.lock"
    exec 200>"$lock_file"
    flock -x 200

    # 更新注册表
    local tmp_file=$(mktemp)
    jq --arg name "$project_name" \
       --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '
       del(.projects[] | select(.name == $name)) |
       .updated_at = $now
       ' "$registry_file" > "$tmp_file"

    mv "$tmp_file" "$registry_file"

    # 解锁
    flock -u 200
}

# 列出所有项目
list_projects() {
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    jq -r '.projects[] | "\(.name)\t\(.path_prefix)\t\(.backend_port)\t\(.status)"' \
        "$registry_file" | column -t -s $'\t'
}
```

---

## 六、完整执行日志

### 6.1 首次初始化网关

```bash
$ https-deploy gateway init

[INFO] Initializing HTTPS Gateway for local environment...
[INFO] Creating directory structure...
[INFO]   ✓ Created: ~/.https-toolkit/gateway/nginx/conf.d/projects
[INFO]   ✓ Created: ~/.https-toolkit/gateway/certs
[INFO]   ✓ Created: ~/.https-toolkit/gateway/registry
[INFO]   ✓ Created: ~/.https-toolkit/gateway/html
[INFO] Generating Nginx configuration...
[INFO]   ✓ Generated: nginx.conf
[INFO]   ✓ Generated: 00-default.conf
[INFO] Generating SSL certificate...
[INFO]   ✓ mkcert installed
[INFO]   ✓ CA root certificate installed
[INFO]   ✓ Certificate generated: dev.local
[INFO] Creating Docker network...
[INFO]   ✓ Created network: https-toolkit-network
[INFO] Initializing project registry...
[INFO]   ✓ Created: projects.json
[INFO] Generating Gateway Dashboard...
[INFO]   ✓ Generated: index.html
[INFO] Starting gateway container...
[INFO]   ✓ Container started: https-toolkit-gateway
[INFO] ✓ Gateway initialized successfully!

Gateway URL: https://dev.local
Dashboard:   https://dev.local/

Next steps:
  1. Add to /etc/hosts: 127.0.0.1 dev.local
  2. Deploy your first project: cd your-project && https-deploy up
```

### 6.2 部署第一个项目

```bash
$ cd ~/projects/api-service
$ https-deploy up

[INFO] Deploying project to local environment...
[INFO] Checking environment...
[INFO]   ✓ Docker is running
[INFO]   ✓ Gateway is running
[INFO]   ✓ config.yaml is valid
[INFO] Project: api-service
[INFO] Path: /api
[INFO] Port: 8080
[INFO] Checking path conflicts...
[INFO]   ✓ No conflicts found
[INFO] Starting backend service...
[INFO]   Rendering Docker Compose configuration...
[INFO]   ✓ Rendered: .https-toolkit/output/docker-compose-local.yml
[INFO]   Starting containers...
[+] Running 1/1
 ✔ Container api-service  Started                                    0.5s
[INFO]   Waiting for service to be healthy...
[INFO]   ✓ Service is healthy (8080)
[INFO] ✓ Backend service started
[INFO] Registering to gateway...
[INFO]   Generating Nginx configuration...
[INFO]   ✓ Generated: ~/.https-toolkit/gateway/nginx/conf.d/projects/api-service.conf
[INFO]   Testing Nginx configuration...
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
[INFO]   ✓ Configuration is valid
[INFO]   Updating project registry...
[INFO]   ✓ Project added to registry
[INFO]   Reloading Nginx...
[INFO]   ✓ Nginx reloaded (elapsed: 52ms)
[INFO] ✓ Project deployed successfully!

Access URL: https://dev.local/api/
Dashboard:  https://dev.local/

Available commands:
  View logs:  https-deploy logs
  Stop:       https-deploy down
  Restart:    https-deploy restart
```

### 6.3 部署第二个项目(并发)

```bash
$ cd ~/projects/web-frontend
$ https-deploy up

[INFO] Deploying project to local environment...
[INFO] Checking environment...
[INFO]   ✓ Docker is running
[INFO]   ✓ Gateway is running
[INFO]   ✓ config.yaml is valid
[INFO] Project: web-frontend
[INFO] Path: /web
[INFO] Port: 3000
[INFO] Checking path conflicts...
[INFO]   ✓ No conflicts found
[INFO] Starting backend service...
[INFO]   ✓ Service is healthy (3000)
[INFO] ✓ Backend service started
[INFO] Registering to gateway...
[INFO]   ✓ Generated: web-frontend.conf
[INFO]   ✓ Configuration is valid
[INFO]   ✓ Nginx reloaded (elapsed: 48ms)
[INFO] ✓ Project deployed successfully!

Access URL: https://dev.local/web/
Dashboard:  https://dev.local/

Active projects (2):
  • /api  → api-service:8080
  • /web  → web-frontend:3000
```

### 6.4 查看所有项目

```bash
$ https-deploy gateway list

Registered Projects (2):
┌────────────────┬──────────┬──────┬──────────┬─────────────────────┐
│ Name           │ Path     │ Port │ Status   │ Registered At       │
├────────────────┼──────────┼──────┼──────────┼─────────────────────┤
│ api-service    │ /api     │ 8080 │ running  │ 2026-02-17 10:30:15 │
│ web-frontend   │ /web     │ 3000 │ running  │ 2026-02-17 10:32:22 │
└────────────────┴──────────┴──────┴──────────┴─────────────────────┘

Gateway: https://dev.local
Dashboard: https://dev.local/
```

### 6.5 停止项目

```bash
$ cd ~/projects/api-service
$ https-deploy down

[INFO] Stopping project...
[INFO]   Stopping containers...
[+] Running 1/1
 ✔ Container api-service  Removed                                    0.8s
[INFO]   ✓ Backend service stopped
[INFO] Unregistering from gateway...
[INFO]   Deleting Nginx configuration...
[INFO]   ✓ Deleted: api-service.conf
[INFO]   Updating project registry...
[INFO]   ✓ Project removed from registry
[INFO]   Reloading Nginx...
[INFO]   ✓ Nginx reloaded (elapsed: 45ms)
[INFO] ✓ Project stopped

Active projects (1):
  • /web  → web-frontend:3000
```

---

## 七、关键问题回答

### Q1: https-deploy 是独立安装的脚本吗?

**答**: 是的,类似 `git`/`docker` 等工具。

- **安装位置**: `/usr/local/bin/https-deploy`
- **工具包位置**: `~/.https-toolkit/`
- **工作方式**: 读取当前目录的 `config.yaml`,操作 Docker/Nginx

### Q2: 如何工作?

**答**: 通过操作 Docker 和生成 Nginx 配置文件。

1. **读取配置**: 解析项目的 `config.yaml`
2. **启动后端**: 使用 Docker Compose 启动后端服务
3. **生成配置**: 生成项目的 Nginx 配置文件
4. **注册路由**: 保存到网关的 `conf.d/projects/` 目录
5. **热重载**: 执行 `nginx -s reload`

### Q3: 新加项目时 Nginx 有哪些变化?

**答**: 新增配置文件 + 更新注册表。

**变化**:
```
Before:
gateway/nginx/conf.d/projects/
└── project-a.conf

After:
gateway/nginx/conf.d/projects/
├── project-a.conf
└── project-b.conf          # ✓ 新增
```

**注册表变化**:
```json
{
  "projects": [
    {"name": "project-a", "path_prefix": "/api"},
    {"name": "project-b", "path_prefix": "/web"}  // ✓ 新增
  ]
}
```

### Q4: 是否需要重启 Nginx?

**答**: 不需要! 使用 `nginx -s reload` 热重载。

**特点**:
- ✅ 不会重启容器
- ✅ 不会断开现有连接
- ✅ 新配置立即生效
- ✅ 耗时: ~50ms
- ✅ 零停机

**验证**:
```bash
# 持续访问项目 A
while true; do curl https://dev.local/api/health; sleep 0.5; done

# 同时添加项目 B
cd ~/projects/project-b && https-deploy up

# 结果: 项目 A 没有任何请求失败
```

---

## 八、工作流程图

```
┌─────────────────────────────────────────────────────────────┐
│                    用户操作                                  │
│  cd project-a && https-deploy up                            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              https-deploy 脚本执行                           │
│  1. 读取 config.yaml                                         │
│  2. 验证配置和环境                                           │
│  3. 启动后端服务 (Docker Compose)                            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              生成 Nginx 配置                                 │
│  template + config → project-a.conf                          │
│  保存到: gateway/nginx/conf.d/projects/                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              更新注册表                                      │
│  projects.json += {name: "project-a", path: "/api"}         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              热重载 Nginx (关键!)                            │
│  docker exec nginx nginx -s reload                           │
│  耗时: ~50ms                                                 │
│  零停机: 现有连接不受影响                                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              完成                                            │
│  项目可立即访问: https://dev.local/api/                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 九、总结

### 关键特性

1. **独立工具**: `https-deploy` 是独立安装的脚本,全局可用
2. **配置驱动**: 读取项目的 `config.yaml` 工作
3. **零停机**: 使用 `nginx -s reload` 热重载,不重启容器
4. **自动化**: 自动生成 Nginx 配置,自动注册/注销
5. **并发安全**: 使用文件锁防止并发冲突

### Nginx 变化

- **新增项目**: 新增配置文件 + 热重载 (~50ms)
- **删除项目**: 删除配置文件 + 热重载 (~45ms)
- **修改项目**: 更新配置文件 + 热重载
- **零影响**: 其他项目不受影响,继续正常运行

### 性能指标

| 操作 | 耗时 | 停机时间 |
|------|------|---------|
| 添加项目 | 2-3s | 0ms |
| 删除项目 | 1-2s | 0ms |
| Nginx 重载 | ~50ms | 0ms |
| 配置测试 | ~10ms | 0ms |

### 适用场景

✅ **适合**:
- 本地开发环境
- 多项目并发开发
- 微服务架构
- 快速迭代

❌ **不适合**:
- 超大规模部署(建议用 Kubernetes)
- 需要复杂路由规则(建议用 API Gateway)
