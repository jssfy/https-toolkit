# 基于路径前缀的 HTTPS 网关方案

## 核心结论

采用 **路径前缀 + 共享域名** 的架构,实现零运维成本的多项目 HTTPS 部署:

- **统一域名**: 所有项目共享 `dev.local` (本地) / `api.yourdomain.com` (生产)
- **路径区分**: `/project-a/`, `/project-b/`, `/admin/` 等
- **动态注册**: 项目启动自动注册,停止自动移除
- **零配置**: 无需修改 `/etc/hosts`,无需 DNS 管理

**访问示例**:
```
https://dev.local/project-a/     → 项目 A
https://dev.local/project-b/     → 项目 B
https://dev.local/admin/         → 项目 C
```

---

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                  HTTPS Gateway (dev.local:443)              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │            Nginx 路径路由规则                          │  │
│  │  /project-a/  → http://project-a:8080                │  │
│  │  /project-b/  → http://project-b:3000                │  │
│  │  /admin/      → http://admin-panel:8000              │  │
│  │  /           → http://dashboard:80 (默认首页)        │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  project-a    │   │  project-b    │   │  admin-panel  │
│  :8080        │   │  :3000        │   │  :8000        │
└───────────────┘   └───────────────┘   └───────────────┘
```

### 网关组件

```
https-toolkit-gateway/
├── nginx/
│   ├── nginx.conf                    # 主配置
│   ├── conf.d/
│   │   ├── 00-default.conf          # 默认配置
│   │   └── projects/                # 项目动态配置
│   │       ├── project-a.conf       # 自动生成
│   │       ├── project-b.conf       # 自动生成
│   │       └── admin.conf           # 自动生成
│   └── html/
│       └── index.html               # 网关首页(项目导航)
├── certs/                           # SSL 证书
│   ├── dev.local/
│   │   ├── fullchain.pem
│   │   └── privkey.pem
│   └── production/
│       ├── fullchain.pem
│       └── privkey.pem
└── registry/                        # 项目注册表
    ├── projects.json                # 已注册项目列表
    └── lock                         # 注册锁文件
```

---

## 配置文件设计

### 1. 项目配置 (config.yaml)

```yaml
# config.yaml
project:
  name: my-project              # 项目名称
  backend_port: 8080            # 后端端口

# 路径前缀配置
routing:
  path_prefix: /my-project      # 路径前缀 (必填)
  strip_prefix: false           # 是否去除前缀再转发给后端
  rewrite_rules: []             # 可选的 URL 重写规则

# 共享域名配置
domains:
  local: dev.local              # 本地开发域名 (所有项目共享)
  staging: staging.example.com  # 测试环境域名
  production: api.example.com   # 生产环境域名

# 网关配置
gateway:
  enabled: true                 # 启用共享网关
  auto_register: true           # 自动注册到网关
  registry_path: ~/.https-toolkit/gateway/registry

# 部署配置
deployment:
  type: docker-compose
  network: https-toolkit-network
```

### 2. 网关全局配置

```yaml
# ~/.https-toolkit/gateway/config.yaml
gateway:
  name: https-toolkit-gateway
  network: https-toolkit-network

  # 域名配置
  domains:
    local: dev.local
    staging: staging.example.com
    production: api.example.com

  # SSL 配置
  ssl:
    cert_dir: ~/.https-toolkit/gateway/certs
    auto_generate: true

  # 默认路由
  default_routes:
    - path: /
      target: http://gateway-dashboard:80
      description: "Gateway Dashboard"

  # 中间件配置
  middlewares:
    - name: cors
      enabled: true
    - name: rate-limit
      enabled: false
      config:
        requests_per_minute: 100
    - name: auth
      enabled: false
      exclude_paths: ["/health", "/metrics"]
```

---

## 命令行工具设计

### 网关管理命令

```bash
# ========================================
# 网关初始化与管理
# ========================================

# 初始化网关(首次使用)
https-deploy gateway init [env]

# 查看网关状态
https-deploy gateway status [--env=local]

# 启动/停止网关
https-deploy gateway start [env]
https-deploy gateway stop [env]
https-deploy gateway restart [env]

# 查看注册的项目列表
https-deploy gateway list [--env=local]

# 查看网关日志
https-deploy gateway logs [-f] [--tail=100]

# 测试网关配置
https-deploy gateway test

# 重载网关配置(不中断服务)
https-deploy gateway reload

# 清理网关和所有注册项目
https-deploy gateway clean [--force]

# 导出/导入项目注册表
https-deploy gateway export > projects.json
https-deploy gateway import < projects.json

# ========================================
# 项目部署命令
# ========================================

# 启动项目(自动注册到网关)
https-deploy up [env]

# 停止项目(自动从网关注销)
https-deploy down [env]

# 重启项目
https-deploy restart [env]

# 查看项目日志
https-deploy logs [-f] [--tail=100]

# 查看项目状态
https-deploy status

# ========================================
# 调试命令
# ========================================

# 查看项目的 Nginx 配置
https-deploy config show

# 验证项目配置
https-deploy config validate

# 测试路由
https-deploy test-route /my-project/api/health

# 查看网关路由表
https-deploy routes [--env=local]
```

---

## 核心实现

### 1. 网关初始化

```bash
#!/bin/bash
# https-deploy gateway init

gateway_init() {
    local env="${1:-local}"

    info "Initializing HTTPS Gateway for $env environment..."

    # 1. 创建目录结构
    local gateway_root="$HOME/.https-toolkit/gateway"
    mkdir -p "$gateway_root"/{nginx/conf.d/projects,certs,registry,html}

    # 2. 生成主 Nginx 配置
    generate_gateway_nginx_config "$env"

    # 3. 生成/检查证书
    generate_gateway_certificate "$env"

    # 4. 创建 Docker 网络
    if ! docker network inspect https-toolkit-network &> /dev/null; then
        docker network create https-toolkit-network
        info "✓ Created network: https-toolkit-network"
    fi

    # 5. 初始化注册表
    cat > "$gateway_root/registry/projects.json" <<EOF
{
  "version": "1.0.0",
  "environment": "$env",
  "projects": [],
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    # 6. 生成网关 Dashboard 页面
    generate_gateway_dashboard

    # 7. 启动网关容器
    start_gateway_container "$env"

    info "✓ Gateway initialized successfully!"
    echo ""
    echo "Gateway URL: https://dev.local"
    echo "Dashboard:   https://dev.local/"
    echo ""
    echo "Next steps:"
    echo "  1. Add to /etc/hosts: 127.0.0.1 dev.local"
    echo "  2. Deploy your first project: cd your-project && https-deploy up"
}

# 生成网关 Nginx 主配置
generate_gateway_nginx_config() {
    local env="$1"
    local gateway_root="$HOME/.https-toolkit/gateway"
    local domain=$(yq ".gateway.domains.$env" ~/.https-toolkit/gateway/config.yaml)

    cat > "$gateway_root/nginx/nginx.conf" <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    gzip on;

    # 包含项目配置
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/conf.d/projects/*.conf;
}
EOF

    # 生成默认服务器配置
    cat > "$gateway_root/nginx/conf.d/00-default.conf" <<EOF
server {
    listen 80;
    server_name $domain;

    # 重定向到 HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $domain;

    # SSL 配置
    ssl_certificate /etc/nginx/certs/$domain/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/$domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 安全头
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # 默认路由: 网关 Dashboard
    location = / {
        root /usr/share/nginx/html;
        index index.html;
    }

    # 健康检查
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    # 网关 API
    location /_gateway/ {
        alias /usr/share/nginx/html/;
        autoindex on;
        autoindex_format json;
    }

    # 404 处理
    location @404 {
        return 404 '{"error": "Project not found", "available_routes": "See https://$domain/"}';
        add_header Content-Type application/json;
    }

    # 项目路由将由动态配置文件添加
    # 格式: /project-name/ → http://project-name:port/
}
EOF
}

# 生成网关 Dashboard
generate_gateway_dashboard() {
    local gateway_root="$HOME/.https-toolkit/gateway"

    cat > "$gateway_root/html/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HTTPS Gateway Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 2rem;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            color: white;
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        .subtitle {
            color: rgba(255,255,255,0.9);
            font-size: 1.1rem;
            margin-bottom: 2rem;
        }
        .projects {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-top: 2rem;
        }
        .project-card {
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .project-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.3);
        }
        .project-name {
            font-size: 1.3rem;
            font-weight: 600;
            color: #333;
            margin-bottom: 0.5rem;
        }
        .project-path {
            font-family: monospace;
            background: #f5f5f5;
            padding: 0.5rem;
            border-radius: 6px;
            font-size: 0.9rem;
            color: #666;
            margin-bottom: 1rem;
        }
        .project-status {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 500;
        }
        .status-running {
            background: #d4edda;
            color: #155724;
        }
        .status-stopped {
            background: #f8d7da;
            color: #721c24;
        }
        .btn {
            display: inline-block;
            padding: 0.5rem 1rem;
            margin-top: 1rem;
            background: #667eea;
            color: white;
            text-decoration: none;
            border-radius: 6px;
            font-weight: 500;
            transition: background 0.2s;
        }
        .btn:hover {
            background: #5568d3;
        }
        .empty-state {
            background: white;
            border-radius: 12px;
            padding: 3rem;
            text-align: center;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        .empty-state h2 {
            color: #333;
            margin-bottom: 1rem;
        }
        .empty-state p {
            color: #666;
            line-height: 1.6;
        }
        .empty-state code {
            background: #f5f5f5;
            padding: 0.2rem 0.5rem;
            border-radius: 4px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 HTTPS Gateway</h1>
        <p class="subtitle">Local Development Environment</p>

        <div id="projects" class="projects">
            <!-- 动态加载项目 -->
        </div>

        <div id="empty-state" class="empty-state" style="display: none;">
            <h2>No projects registered</h2>
            <p>
                Deploy your first project:<br>
                <code>cd your-project && https-deploy up</code>
            </p>
        </div>
    </div>

    <script>
        // 从注册表加载项目
        async function loadProjects() {
            try {
                const response = await fetch('/_gateway/registry/projects.json');
                const data = await response.json();

                if (data.projects.length === 0) {
                    document.getElementById('empty-state').style.display = 'block';
                    return;
                }

                const container = document.getElementById('projects');
                container.innerHTML = data.projects.map(project => `
                    <div class="project-card">
                        <div class="project-name">${project.name}</div>
                        <div class="project-path">${project.path_prefix}</div>
                        <span class="project-status status-${project.status}">
                            ${project.status}
                        </span>
                        <a href="${project.path_prefix}" class="btn">Open →</a>
                    </div>
                `).join('');
            } catch (error) {
                console.error('Failed to load projects:', error);
            }
        }

        loadProjects();
        // 每 5 秒刷新
        setInterval(loadProjects, 5000);
    </script>
</body>
</html>
EOF
}

# 启动网关容器
start_gateway_container() {
    local env="$1"
    local gateway_root="$HOME/.https-toolkit/gateway"
    local domain=$(yq ".gateway.domains.$env" ~/.https-toolkit/gateway/config.yaml)

    info "Starting gateway container..."

    docker run -d \
        --name https-toolkit-gateway \
        --network https-toolkit-network \
        -p 80:80 \
        -p 443:443 \
        -v "$gateway_root/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
        -v "$gateway_root/nginx/conf.d:/etc/nginx/conf.d:ro" \
        -v "$gateway_root/certs:/etc/nginx/certs:ro" \
        -v "$gateway_root/html:/usr/share/nginx/html:ro" \
        -v "$gateway_root/registry:/usr/share/nginx/html/_gateway/registry:ro" \
        --restart unless-stopped \
        nginx:alpine

    info "✓ Gateway started: https://$domain"
}
```

### 2. 项目注册

```bash
#!/bin/bash
# https-deploy up

project_deploy() {
    local env="${1:-local}"

    info "Deploying project to $env environment..."

    # 1. 检查网关是否存在
    ensure_gateway_running "$env"

    # 2. 读取项目配置
    local project_name=$(yq .project.name config.yaml)
    local backend_port=$(yq .project.backend_port config.yaml)
    local path_prefix=$(yq .routing.path_prefix config.yaml)
    local strip_prefix=$(yq .routing.strip_prefix config.yaml)

    # 3. 启动后端服务
    start_backend_service "$env"

    # 4. 注册到网关
    register_to_gateway "$env" "$project_name" "$backend_port" "$path_prefix" "$strip_prefix"

    # 5. 验证部署
    verify_deployment "$env" "$path_prefix"

    local domain=$(yq ".domains.$env" config.yaml)
    info "✓ Deployment complete!"
    echo ""
    echo "Access URL: https://$domain$path_prefix"
    echo "Dashboard:  https://$domain/"
}

# 注册项目到网关
register_to_gateway() {
    local env="$1"
    local project_name="$2"
    local backend_port="$3"
    local path_prefix="$4"
    local strip_prefix="$5"

    info "Registering project to gateway..."

    local gateway_root="$HOME/.https-toolkit/gateway"
    local nginx_config_file="$gateway_root/nginx/conf.d/projects/${project_name}.conf"
    local registry_file="$gateway_root/registry/projects.json"

    # 1. 生成 Nginx 配置
    local upstream_url="http://${project_name}:${backend_port}"

    cat > "$nginx_config_file" <<EOF
# Auto-generated config for project: $project_name
# Generated at: $(date)

upstream ${project_name}_backend {
    server ${project_name}:${backend_port};
}

server {
    listen 443 ssl http2;
    server_name _;  # 匹配所有域名

    # 路径: $path_prefix
    location $path_prefix {
EOF

    # 是否去除前缀
    if [ "$strip_prefix" = "true" ]; then
        cat >> "$nginx_config_file" <<EOF
        # 去除路径前缀后转发
        rewrite ^$path_prefix/?(.*)\$ /\$1 break;
EOF
    fi

    cat >> "$nginx_config_file" <<EOF
        proxy_pass $upstream_url;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Original-URI \$request_uri;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 超时配置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 健康检查
    location = ${path_prefix}/health {
        access_log off;
        proxy_pass $upstream_url/health;
    }
}
EOF

    # 2. 更新注册表
    local tmp_file=$(mktemp)
    jq --arg name "$project_name" \
       --arg path "$path_prefix" \
       --arg port "$backend_port" \
       --arg status "running" \
       --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.projects += [{
           name: $name,
           path_prefix: $path,
           backend_port: $port,
           status: $status,
           registered_at: $updated_at
       }] | .updated_at = $updated_at' \
       "$registry_file" > "$tmp_file"
    mv "$tmp_file" "$registry_file"

    # 3. 重载 Nginx
    docker exec https-toolkit-gateway nginx -s reload

    info "✓ Registered: $path_prefix → $project_name:$backend_port"
}

# 启动后端服务
start_backend_service() {
    local env="$1"
    local project_name=$(yq .project.name config.yaml)

    info "Starting backend service..."

    # 渲染 Docker Compose 配置
    cat > .https-toolkit/output/docker-compose-$env.yml <<EOF
services:
  ${project_name}:
    image: ${project_name}:latest
    container_name: ${project_name}
    networks:
      - https-toolkit-network
    environment:
      - TZ=Asia/Shanghai
    restart: unless-stopped

networks:
  https-toolkit-network:
    external: true
EOF

    # 启动服务
    docker-compose -f .https-toolkit/output/docker-compose-$env.yml up -d

    info "✓ Backend service started"
}
```

### 3. 项目注销

```bash
#!/bin/bash
# https-deploy down

project_unregister() {
    local env="${1:-local}"
    local project_name=$(yq .project.name config.yaml)

    info "Unregistering project from gateway..."

    local gateway_root="$HOME/.https-toolkit/gateway"
    local nginx_config_file="$gateway_root/nginx/conf.d/projects/${project_name}.conf"
    local registry_file="$gateway_root/registry/projects.json"

    # 1. 停止后端服务
    docker-compose -f .https-toolkit/output/docker-compose-$env.yml down

    # 2. 删除 Nginx 配置
    rm -f "$nginx_config_file"

    # 3. 从注册表删除
    local tmp_file=$(mktemp)
    jq --arg name "$project_name" \
       'del(.projects[] | select(.name == $name)) | .updated_at = now | strftime("%Y-%m-%dT%H:%M:%SZ")' \
       "$registry_file" > "$tmp_file"
    mv "$tmp_file" "$registry_file"

    # 4. 重载 Nginx
    docker exec https-toolkit-gateway nginx -s reload

    info "✓ Project unregistered"
}
```

---

## 配置示例

### 项目 A: API 服务

```yaml
# project-a/config.yaml
project:
  name: api-service
  backend_port: 8080

routing:
  path_prefix: /api          # 访问路径: https://dev.local/api/
  strip_prefix: true         # 转发给后端时去除 /api 前缀
  rewrite_rules: []

domains:
  local: dev.local
  production: api.example.com

gateway:
  enabled: true
  auto_register: true
```

**效果**:
```
用户请求:  https://dev.local/api/users
转发给后端: http://api-service:8080/users
```

### 项目 B: Web 前端

```yaml
# project-b/config.yaml
project:
  name: web-frontend
  backend_port: 3000

routing:
  path_prefix: /web           # 访问路径: https://dev.local/web/
  strip_prefix: false         # 保留前缀(前端需要知道 base path)

domains:
  local: dev.local

gateway:
  enabled: true
```

**效果**:
```
用户请求:  https://dev.local/web/index.html
转发给后端: http://web-frontend:3000/web/index.html
```

### 项目 C: 管理后台

```yaml
# project-c/config.yaml
project:
  name: admin-panel
  backend_port: 8000

routing:
  path_prefix: /admin
  strip_prefix: true

domains:
  local: dev.local

gateway:
  enabled: true
```

---

## 使用流程

### 1. 首次初始化

```bash
# 1. 安装工具
curl -sSL https://toolkit.example.com/install.sh | bash

# 2. 初始化网关
https-deploy gateway init

# 输出:
[INFO] Initializing HTTPS Gateway for local environment...
[INFO]   ✓ Created directory structure
[INFO]   ✓ Generated Nginx configuration
[INFO]   ✓ Generated SSL certificate (mkcert)
[INFO]   ✓ Created network: https-toolkit-network
[INFO]   ✓ Started gateway container
[INFO] ✓ Gateway initialized successfully!

Gateway URL: https://dev.local
Dashboard:   https://dev.local/

Next steps:
  1. Add to /etc/hosts: 127.0.0.1 dev.local
  2. Deploy your first project: cd your-project && https-deploy up

# 3. 配置域名
echo "127.0.0.1 dev.local" | sudo tee -a /etc/hosts

# 4. 访问 Dashboard
open https://dev.local
```

### 2. 部署项目

```bash
# 项目 A
cd ~/projects/api-service
https-deploy init --template=golang
vim config.yaml  # 设置 path_prefix: /api
https-deploy up

# 输出:
[INFO] Deploying project to local environment...
[INFO]   ✓ Gateway is running
[INFO]   ✓ Backend service started: api-service
[INFO]   ✓ Registered: /api → api-service:8080
[INFO] ✓ Deployment complete!

Access URL: https://dev.local/api/
Dashboard:  https://dev.local/

# 项目 B
cd ~/projects/web-frontend
https-deploy init
vim config.yaml  # 设置 path_prefix: /web
https-deploy up

# 项目 C
cd ~/projects/admin-panel
https-deploy init
vim config.yaml  # 设置 path_prefix: /admin
https-deploy up
```

### 3. 查看所有项目

```bash
$ https-deploy gateway list

Registered Projects (3):
┌────────────────────┬──────────────┬──────────┬──────────┬─────────────────────┐
│ Name               │ Path         │ Port     │ Status   │ Registered At       │
├────────────────────┼──────────────┼──────────┼──────────┼─────────────────────┤
│ api-service        │ /api         │ 8080     │ running  │ 2026-02-17 10:30:15 │
│ web-frontend       │ /web         │ 3000     │ running  │ 2026-02-17 10:32:22 │
│ admin-panel        │ /admin       │ 8000     │ running  │ 2026-02-17 10:35:10 │
└────────────────────┴──────────────┴──────────┴──────────┴─────────────────────┘

Gateway URL: https://dev.local
```

### 4. 访问服务

```bash
# 访问不同项目
curl https://dev.local/api/health
curl https://dev.local/web/
curl https://dev.local/admin/

# 或浏览器访问
open https://dev.local/           # Dashboard
open https://dev.local/api/       # API 服务
open https://dev.local/web/       # Web 前端
open https://dev.local/admin/     # 管理后台
```

### 5. 停止项目

```bash
cd ~/projects/api-service
https-deploy down

# 输出:
[INFO] Unregistering project from gateway...
[INFO]   ✓ Backend service stopped
[INFO]   ✓ Nginx configuration removed
[INFO]   ✓ Project unregistered from registry
[INFO] ✓ Project stopped

# 其他项目继续运行,不受影响
```

---

## 路由表管理

### 查看路由表

```bash
$ https-deploy routes

HTTPS Gateway Routes (dev.local):
┌──────────────────────────────────────────────────────────────────┐
│ Path              Target                     Strip    Status     │
├──────────────────────────────────────────────────────────────────┤
│ /                 gateway-dashboard:80       -        active     │
│ /api              api-service:8080           ✓        active     │
│ /web              web-frontend:3000          ✗        active     │
│ /admin            admin-panel:8000           ✓        active     │
└──────────────────────────────────────────────────────────────────┘

Total: 4 routes
```

### 测试路由

```bash
$ https-deploy test-route /api/health

Testing route: /api/health
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Full URL:      https://dev.local/api/health
Matched route: /api → api-service:8080
Strip prefix:  yes
Backend URL:   http://api-service:8080/health

Response:
  Status:  200 OK
  Time:    45ms
  Body:    {"status": "healthy"}

✓ Route is working correctly
```

---

## Dashboard 截图(文字描述)

```
┌─────────────────────────────────────────────────────────────┐
│  🚀 HTTPS Gateway                                           │
│  Local Development Environment                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  │
│  │ API Service   │  │ Web Frontend  │  │ Admin Panel   │  │
│  │               │  │               │  │               │  │
│  │ /api          │  │ /web          │  │ /admin        │  │
│  │               │  │               │  │               │  │
│  │ ● running     │  │ ● running     │  │ ● running     │  │
│  │               │  │               │  │               │  │
│  │ [Open →]      │  │ [Open →]      │  │ [Open →]      │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 高级特性

### 1. 路径重写规则

```yaml
# config.yaml
routing:
  path_prefix: /api/v1
  strip_prefix: true
  rewrite_rules:
    - pattern: ^/users/(.*)$
      replacement: /v2/users/$1
    - pattern: ^/old-endpoint$
      replacement: /new-endpoint
```

### 2. 环境变量注入

```yaml
# config.yaml
environment:
  - BASE_PATH=/api
  - API_VERSION=v1
  - NODE_ENV=development
```

### 3. 健康检查配置

```yaml
# config.yaml
health_check:
  enabled: true
  path: /health
  interval: 30s
  timeout: 5s
  unhealthy_threshold: 3
```

### 4. 中间件配置

```yaml
# config.yaml
middlewares:
  - name: cors
    config:
      allowed_origins: ["*"]
      allowed_methods: ["GET", "POST", "PUT", "DELETE"]

  - name: rate-limit
    config:
      requests_per_minute: 100

  - name: request-logging
    enabled: true
```

---

## 对比

### 方案对比

| 特性 | 域名区分 | 路径区分 (本方案) |
|------|---------|------------------|
| **配置域名** | 每个项目一个域名 | 所有项目共享一个域名 |
| **运维成本** | 需要配置多个域名和 DNS | 只需配置一个域名 |
| **访问方式** | `https://app-a.local`<br>`https://app-b.local` | `https://dev.local/app-a/`<br>`https://dev.local/app-b/` |
| **证书管理** | 泛域名证书 or 每个域名独立证书 | 单域名证书 |
| **扩展性** | 域名数量有限 | 无限扩展 |
| **生产部署** | 需要 DNS 管理 | 更接近生产环境(通常也是路径区分) |

---

## 目录结构

### 网关目录

```
~/.https-toolkit/gateway/
├── config.yaml                        # 网关配置
├── nginx/
│   ├── nginx.conf                     # 主配置
│   └── conf.d/
│       ├── 00-default.conf           # 默认服务器
│       └── projects/                  # 项目配置(自动生成)
│           ├── api-service.conf
│           ├── web-frontend.conf
│           └── admin-panel.conf
├── certs/
│   └── dev.local/
│       ├── fullchain.pem
│       └── privkey.pem
├── html/
│   └── index.html                     # Dashboard
└── registry/
    └── projects.json                  # 项目注册表
```

### 项目目录

```
your-project/
├── config.yaml              # ✅ 提交(项目配置)
├── .env.example             # ✅ 提交
├── .gitignore               # ✅ 提交
├── Dockerfile               # ✅ 提交
├── .https-toolkit/          # ❌ 不提交(自动生成)
│   └── output/
│       └── docker-compose-local.yml
└── src/                     # 业务代码
```

---

## 总结

### 核心优势

1. **零运维成本**
   - 只需维护一个域名 `dev.local`
   - 无需配置多个域名和 DNS
   - 证书管理简单(单域名证书)

2. **动态注册机制**
   - 项目启动自动注册到网关
   - 项目停止自动从网关移除
   - 无需手动修改 Nginx 配置

3. **开发体验好**
   - 统一的访问入口: `https://dev.local`
   - Dashboard 可视化管理
   - 路径前缀清晰直观

4. **接近生产环境**
   - 生产环境通常也是路径区分
   - 配置迁移简单(只需改域名)
   - 测试环境和生产环境一致

5. **无限扩展**
   - 支持无限项目并发
   - 不受域名数量限制
   - 按需添加/移除项目

### 关键命令

```bash
# 网关管理
https-deploy gateway init      # 初始化
https-deploy gateway list      # 查看所有项目
https-deploy gateway status    # 查看状态

# 项目部署
https-deploy up                # 启动并注册
https-deploy down              # 停止并注销

# 调试
https-deploy routes            # 查看路由表
https-deploy test-route /path  # 测试路由
```

### 下一步实现

1. **MVP 阶段**: 实现基础网关和项目注册
2. **完善阶段**: 添加 Dashboard、健康检查、中间件
3. **生产化**: 支持多环境(local/staging/production)
