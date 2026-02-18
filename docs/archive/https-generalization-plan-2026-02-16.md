# HTTPS 部署能力通用化方案

## 核心结论

将当前项目的 HTTPS 部署能力通用化,建议打造成 **开箱即用的 HTTPS 部署工具包**,具备以下特性:

- **零配置启动**: 一条命令完成 HTTPS 部署
- **环境隔离**: 本地开发/测试/生产环境独立配置
- **证书自动化**: 自动选择最佳证书方案(mkcert/Let's Encrypt)
- **框架无关**: 支持任意后端技术栈(Go/Node.js/Python/Java 等)
- **部署通用**: 支持 Docker/Kubernetes/裸机部署
- **配置声明式**: 通过配置文件而非硬编码

---

## 当前实现分析

### 优势

1. **架构清晰**: Nginx 反向代理 + SSL Termination,后端应用无感知
2. **证书管理完善**: 支持 mkcert/Let's Encrypt 多种证书源
3. **自动化程度高**: Makefile 一键部署,自动检查/生成证书
4. **文档完备**: 使用文档、故障排查齐全

### 限制

1. **硬编码严重**: 域名、路径、证书位置等 54 处硬编码 `yeanhua.asia`
2. **配置耦合**: Nginx 配置、脚本、Docker Compose 多处配置分散
3. **单项目设计**: 仅适用于当前项目,无法快速复制到其他项目
4. **环境混杂**: 本地/公网配置混合在一起,切换不便

### 文件依赖分析

```
硬编码位置分布:
- scripts/cert-manager.sh: 32 处 → 证书路径、域名
- deploy/nginx/conf.d/*.conf: 9 处 → server_name、证书路径
- docker-compose.https.yml: 1 处 → 证书挂载路径
- deploy/setup-ecs.sh: 1 处 → 域名配置
- deploy/init-ssl.sh: 11 处 → 域名、邮箱
```

---

## 通用化方案设计

### 方案 A: 配置驱动的单体工具 (推荐)

**适用场景**: 中小型项目,需要快速集成 HTTPS

**核心设计**: 通过单一配置文件驱动所有部署逻辑

#### 1. 项目结构

```
https-toolkit/                    # 工具包根目录
├── config.yaml                   # 用户配置文件(唯一需要修改)
├── https-deploy                  # 统一命令行工具
├── templates/                    # 配置模板
│   ├── nginx-http.conf.tpl
│   ├── nginx-https.conf.tpl
│   ├── docker-compose.tpl
│   └── certbot.tpl
├── scripts/
│   ├── cert-manager.sh          # 通用证书管理
│   ├── env-detector.sh          # 环境检测
│   └── config-renderer.sh       # 配置渲染
├── hooks/                        # 生命周期钩子
│   ├── pre-deploy.sh
│   └── post-deploy.sh
└── docs/
    ├── quick-start.md
    └── configuration.md
```

#### 2. 配置文件设计 (config.yaml)

```yaml
# https-toolkit/config.yaml
project:
  name: top-ai-news
  backend_port: 8080              # 后端应用端口

domains:
  local: local.example.com        # 本地开发域名
  staging: staging.example.com    # 测试环境域名
  production: www.example.com     # 生产环境域名

# 证书配置
certificates:
  # 本地开发: 自动使用 mkcert
  local:
    provider: mkcert
    storage: ~/.local-certs/${project.name}

  # 测试/生产: Let's Encrypt
  staging:
    provider: letsencrypt
    method: http-01               # 或 dns-01
    email: admin@example.com
    storage: /etc/letsencrypt/live/${domains.staging}

  production:
    provider: letsencrypt
    method: http-01
    email: admin@example.com
    storage: /etc/letsencrypt/live/${domains.production}

# DNS API 配置(用于 dns-01 验证)
dns:
  provider: aliyun                # aliyun/cloudflare/dnspod
  credentials:
    access_key_id: ${env:ALIYUN_ACCESS_KEY_ID}
    access_key_secret: ${env:ALIYUN_ACCESS_KEY_SECRET}

# 部署配置
deployment:
  type: docker-compose            # docker-compose/kubernetes/systemd
  nginx:
    image: nginx:alpine
    ssl_protocols: TLSv1.2 TLSv1.3
    ssl_ciphers: HIGH:!aNULL:!MD5
  backend:
    image: ${project.name}:latest
    replicas: 1

# 环境变量映射
env:
  PORT: ${backend_port}
```

#### 3. 统一命令行工具

```bash
#!/bin/bash
# https-deploy - 统一部署命令

# 使用示例:
https-deploy init                    # 初始化配置
https-deploy up local                # 启动本地 HTTPS
https-deploy up production           # 启动生产 HTTPS
https-deploy cert generate local     # 生成本地证书
https-deploy cert renew production   # 续期生产证书
https-deploy config show             # 显示当前配置
https-deploy migrate from-current    # 从现有项目迁移
```

#### 4. 核心实现逻辑

```bash
# scripts/config-renderer.sh
# 配置渲染引擎

render_template() {
    local template_file=$1
    local output_file=$2
    local env=$3  # local/staging/production

    # 读取 config.yaml
    local project_name=$(yq .project.name config.yaml)
    local domain=$(yq .domains.$env config.yaml)
    local backend_port=$(yq .project.backend_port config.yaml)
    local cert_provider=$(yq .certificates.$env.provider config.yaml)
    local cert_storage=$(yq .certificates.$env.storage config.yaml)

    # 渲染变量
    sed -e "s/\${project.name}/$project_name/g" \
        -e "s/\${domain}/$domain/g" \
        -e "s/\${backend_port}/$backend_port/g" \
        -e "s/\${cert_storage}/$cert_storage/g" \
        "$template_file" > "$output_file"
}

# 使用示例
render_template templates/nginx-https.conf.tpl \
                output/nginx-https.conf \
                production
```

#### 5. Nginx 配置模板

```nginx
# templates/nginx-https.conf.tpl
server {
    listen 80;
    server_name ${domain};

    location / {
        return 301 https://$host$request_uri;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}

server {
    listen 443 ssl http2;
    server_name ${domain};

    ssl_certificate ${cert_storage}/fullchain.pem;
    ssl_certificate_key ${cert_storage}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://${project.name}:${backend_port};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### 6. Docker Compose 模板

```yaml
# templates/docker-compose.tpl
services:
  ${project.name}:
    image: ${backend_image}
    container_name: ${project.name}
    restart: always
    ports:
      - "127.0.0.1:${backend_port}:${backend_port}"
    environment:
      - TZ=Asia/Shanghai

  nginx:
    image: nginx:alpine
    container_name: ${project.name}-nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./output/nginx-${env}.conf:/etc/nginx/conf.d/default.conf:ro
      - ${cert_storage}:/etc/nginx/ssl:ro
    depends_on:
      - ${project.name}
```

---

### 方案 B: 插件化的多项目工具

**适用场景**: 大型团队,需要管理多个项目的 HTTPS 部署

**核心设计**: 中心化证书管理 + 项目插件机制

#### 架构图

```
┌─────────────────────────────────────────────────────────┐
│                   HTTPS Manager Hub                      │
│  统一管理多项目证书、域名、配置                          │
└─────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Project A   │  │  Project B   │  │  Project C   │
│  (Go)        │  │  (Node.js)   │  │  (Python)    │
└──────────────┘  └──────────────┘  └──────────────┘
```

#### 核心组件

1. **Hub CLI**: 全局命令行工具

```bash
https-hub init                        # 初始化 Hub
https-hub project add my-app          # 添加项目
https-hub project list                # 列出所有项目
https-hub cert issue my-app local     # 为项目签发证书
https-hub cert renew --all            # 批量续期所有项目证书
https-hub dashboard                   # 启动 Web 控制台
```

2. **项目配置**: 每个项目独立配置

```yaml
# my-project/.https-config.yaml
project_id: my-app
backend_port: 8080
domains:
  local: local.myapp.dev
  production: myapp.com
```

3. **中心化存储**: 证书集中管理

```
~/.https-hub/
├── config.yaml              # Hub 全局配置
├── projects/                # 项目索引
│   ├── my-app.yaml
│   └── another-app.yaml
├── certs/                   # 证书存储
│   ├── my-app/
│   │   ├── local/
│   │   └── production/
│   └── another-app/
└── templates/               # 模板库
```

---

### 方案 C: SaaS 化服务

**适用场景**: 商业化产品,提供证书管理服务

**核心设计**: 云端证书管理 + 本地 Agent

#### 架构

```
┌─────────────────────────────────────────────────────────┐
│              Cloud Certificate Service                   │
│  - 证书申请/续期/监控                                    │
│  - Web Dashboard                                         │
│  - API & Webhook                                         │
└─────────────────────────────────────────────────────────┘
                           │
                           │ HTTPS API
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Local Agent                           │
│  - 自动拉取证书                                          │
│  - 自动配置 nginx                                        │
│  - 健康检查上报                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 推荐方案: 方案 A(配置驱动)

### 理由

1. **实现成本低**: 基于现有代码改造,工作量约 2-3 天
2. **上手简单**: 用户只需修改一个 YAML 文件
3. **灵活性高**: 支持模板自定义
4. **无依赖**: 不需要中心化服务
5. **易维护**: 单体工具,逻辑集中

### 实施步骤

#### Phase 1: 核心抽象 (1 天)

1. 提取硬编码为变量
2. 设计配置文件结构
3. 实现配置渲染引擎

**产出**:
- `config.yaml` 配置文件
- `config-renderer.sh` 渲染脚本

#### Phase 2: 模板化 (1 天)

1. 将 Nginx 配置改为模板
2. 将 Docker Compose 配置改为模板
3. 将证书管理脚本通用化

**产出**:
- `templates/` 目录下的所有模板
- 通用化的 `cert-manager.sh`

#### Phase 3: 命令行工具 (1 天)

1. 实现 `https-deploy` 命令
2. 实现子命令: `init/up/cert/config`
3. 添加环境自动检测

**产出**:
- `https-deploy` 可执行文件
- `docs/quick-start.md` 快速开始文档

#### Phase 4: 迁移工具 (0.5 天)

1. 实现 `migrate from-current` 命令
2. 自动分析现有项目配置
3. 生成标准 `config.yaml`

**产出**:
- 迁移脚本
- 迁移文档

---

## 使用示例

### 场景 1: 新项目快速集成

```bash
# 1. 安装工具
git clone https://github.com/your/https-toolkit
cd my-project

# 2. 初始化配置
https-deploy init
# 生成 config.yaml,填入项目信息

# 3. 一键启动
https-deploy up local
# 自动: 生成证书 → 渲染配置 → 启动服务

# 4. 访问
open https://local.myapp.dev
```

### 场景 2: 现有项目迁移

```bash
# 当前项目目录
cd top-ai-news

# 安装工具
curl -sSL https://toolkit.example.com/install.sh | bash

# 自动迁移
https-deploy migrate from-current
# 分析现有配置,生成 config.yaml

# 验证配置
https-deploy config show

# 启动
https-deploy up local
```

### 场景 3: 多环境部署

```bash
# 本地开发
https-deploy up local
open https://local.myapp.dev

# 测试环境部署
https-deploy up staging
open https://staging.myapp.dev

# 生产环境部署
https-deploy up production
open https://myapp.com
```

---

## 配置文件完整示例

```yaml
# config.yaml - 完整配置示例

# ========================================
# 项目基础信息
# ========================================
project:
  name: top-ai-news
  version: 1.0.0
  description: AI News Aggregator
  backend_port: 8080
  backend_tech: golang           # golang/nodejs/python/java

# ========================================
# 多环境域名配置
# ========================================
domains:
  # 本地开发环境
  local:
    primary: local.yeanhua.asia
    aliases:                     # 别名列表
      - localhost
      - 127.0.0.1

  # 测试环境
  staging:
    primary: staging.yeanhua.asia
    aliases: []

  # 生产环境
  production:
    primary: data.yeanhua.asia
    aliases:
      - www.yeanhua.asia
      - yeanhua.asia

# ========================================
# 证书配置
# ========================================
certificates:
  # 本地开发: mkcert
  local:
    provider: mkcert
    storage: ~/.local-certs/${project.name}
    auto_install_ca: true        # 自动安装 CA 根证书
    wildcard: true               # 泛域名支持

  # 测试环境: Let's Encrypt HTTP-01
  staging:
    provider: letsencrypt
    method: http-01
    email: admin@yeanhua.asia
    storage: /etc/letsencrypt/live/${domains.staging.primary}
    auto_renew: true             # 自动续期
    renew_days_before: 30        # 提前 30 天续期

  # 生产环境: Let's Encrypt DNS-01
  production:
    provider: letsencrypt
    method: dns-01               # 支持泛域名
    email: admin@yeanhua.asia
    storage: /etc/letsencrypt/live/${domains.production.primary}
    auto_renew: true
    renew_days_before: 30

# ========================================
# DNS API 配置(用于 dns-01 验证)
# ========================================
dns:
  provider: aliyun               # aliyun/cloudflare/dnspod/route53
  credentials:
    # 从环境变量读取
    access_key_id: ${env:ALIYUN_ACCESS_KEY_ID}
    access_key_secret: ${env:ALIYUN_ACCESS_KEY_SECRET}
    # 或从文件读取
    # credentials_file: ~/.secrets/dns-credentials.ini

# ========================================
# Nginx 配置
# ========================================
nginx:
  image: nginx:alpine
  version: latest

  # SSL/TLS 配置
  ssl:
    protocols: TLSv1.2 TLSv1.3
    ciphers: HIGH:!aNULL:!MD5
    prefer_server_ciphers: on
    session_cache: shared:SSL:10m
    session_timeout: 10m

  # HTTP/2 配置
  http2: true

  # Gzip 压缩
  gzip:
    enabled: true
    types:
      - text/plain
      - text/css
      - application/json
      - application/javascript

  # 安全头
  security_headers:
    x_frame_options: SAMEORIGIN
    x_content_type_options: nosniff
    x_xss_protection: "1; mode=block"
    strict_transport_security: "max-age=31536000; includeSubDomains"  # HSTS

  # 自定义配置片段
  custom_config: |
    client_max_body_size 10M;
    proxy_read_timeout 300s;

# ========================================
# 部署配置
# ========================================
deployment:
  type: docker-compose           # docker-compose/kubernetes/systemd

  # Docker Compose 配置
  docker:
    backend:
      image: ${project.name}:latest
      build: .
      restart_policy: always
      environment:
        - TZ=Asia/Shanghai
        - PORT=${backend_port}
      volumes:
        - app-data:/app/data
      healthcheck:
        test: ["CMD", "curl", "-f", "http://localhost:${backend_port}/"]
        interval: 30s
        timeout: 10s
        retries: 3

    nginx:
      image: ${nginx.image}
      restart_policy: always
      volumes:
        - ./logs:/var/log/nginx    # 日志持久化

  # 资源限制(可选)
  resources:
    backend:
      cpu: "1"
      memory: 512M
    nginx:
      cpu: "0.5"
      memory: 128M

# ========================================
# 钩子脚本(生命周期回调)
# ========================================
hooks:
  pre_deploy: ./hooks/pre-deploy.sh      # 部署前执行
  post_deploy: ./hooks/post-deploy.sh    # 部署后执行
  pre_cert_renew: ./hooks/backup.sh      # 续期前备份
  post_cert_renew: ./hooks/reload.sh     # 续期后重载

# ========================================
# 监控与日志
# ========================================
monitoring:
  enabled: true
  healthcheck_url: /health
  healthcheck_interval: 60s

  # Webhook 通知(证书过期告警)
  webhooks:
    - url: https://hooks.slack.com/services/xxx
      events: [cert_expiring, cert_renewed, deploy_failed]

logging:
  level: info                    # debug/info/warn/error
  output: ./logs/${project.name}.log
  rotate:
    max_size: 100M
    max_age: 30d
    max_backups: 10

# ========================================
# 环境变量映射
# ========================================
env:
  PORT: ${backend_port}
  NODE_ENV: ${environment}       # local/staging/production
```

---

## 目录结构对比

### 通用化前(当前)

```
top-ai-news/
├── scripts/cert-manager.sh         # ❌ 硬编码 yeanhua.asia
├── deploy/nginx/conf.d/
│   ├── default.conf                # ❌ 硬编码域名
│   └── default-https.conf          # ❌ 硬编码域名
├── docker-compose.yml
├── docker-compose.https.yml        # ❌ 硬编码证书路径
└── Makefile                        # ❌ 硬编码命令
```

### 通用化后(方案 A)

```
my-project/
├── config.yaml                     # ✅ 用户配置(唯一修改)
├── https-deploy                    # ✅ 统一命令行工具
├── .https-toolkit/                 # ✅ 工具包(自动生成)
│   ├── templates/                  # ✅ 配置模板
│   │   ├── nginx-http.conf.tpl
│   │   ├── nginx-https.conf.tpl
│   │   └── docker-compose.tpl
│   ├── scripts/                    # ✅ 通用脚本
│   │   ├── cert-manager.sh         # ✅ 无硬编码
│   │   ├── config-renderer.sh
│   │   └── env-detector.sh
│   └── output/                     # ✅ 渲染后的配置
│       ├── nginx-local.conf
│       ├── nginx-production.conf
│       └── docker-compose-local.yml
├── hooks/                          # ✅ 可选的钩子脚本
│   ├── pre-deploy.sh
│   └── post-deploy.sh
└── my-backend-code/                # 业务代码
    ├── main.go
    └── ...
```

---

## 核心代码示例

### 1. 统一命令行工具

```bash
#!/bin/bash
# https-deploy - 统一部署工具

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$SCRIPT_DIR/.https-toolkit"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查依赖
check_dependencies() {
    local deps=("yq" "docker" "docker-compose")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "$dep not found. Please install it first."
            exit 1
        fi
    done
}

# 初始化配置
cmd_init() {
    info "Initializing HTTPS deployment configuration..."

    if [ -f "$CONFIG_FILE" ]; then
        warn "config.yaml already exists"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    fi

    # 复制配置模板
    cp "$TOOLKIT_DIR/templates/config.yaml.example" "$CONFIG_FILE"

    # 交互式配置
    read -p "Project name: " project_name
    read -p "Backend port: " backend_port
    read -p "Local domain: " local_domain

    # 替换默认值
    yq -i ".project.name = \"$project_name\"" "$CONFIG_FILE"
    yq -i ".project.backend_port = $backend_port" "$CONFIG_FILE"
    yq -i ".domains.local.primary = \"$local_domain\"" "$CONFIG_FILE"

    info "✓ Configuration created: $CONFIG_FILE"
    echo ""
    echo "Next steps:"
    echo "  1. Edit config.yaml to customize settings"
    echo "  2. Run: https-deploy up local"
}

# 启动服务
cmd_up() {
    local env="${1:-local}"  # local/staging/production

    info "Deploying to $env environment..."

    # 1. 渲染配置
    info "[1/4] Rendering configuration templates..."
    "$TOOLKIT_DIR/scripts/config-renderer.sh" "$env"

    # 2. 检查/生成证书
    info "[2/4] Managing SSL certificates..."
    "$TOOLKIT_DIR/scripts/cert-manager.sh" "$env" check || \
    "$TOOLKIT_DIR/scripts/cert-manager.sh" "$env" generate

    # 3. 执行 pre-deploy 钩子
    if [ -f "hooks/pre-deploy.sh" ]; then
        info "[3/4] Running pre-deploy hooks..."
        bash hooks/pre-deploy.sh "$env"
    fi

    # 4. 启动服务
    info "[4/4] Starting services..."
    docker-compose -f "$TOOLKIT_DIR/output/docker-compose-$env.yml" up -d

    # 5. 执行 post-deploy 钩子
    if [ -f "hooks/post-deploy.sh" ]; then
        info "Running post-deploy hooks..."
        bash hooks/post-deploy.sh "$env"
    fi

    # 显示访问地址
    local domain=$(yq ".domains.$env.primary" "$CONFIG_FILE")
    info "✓ Deployment complete!"
    echo ""
    echo "Access URL:"
    echo "  https://$domain"
}

# 停止服务
cmd_down() {
    local env="${1:-local}"
    info "Stopping $env environment..."
    docker-compose -f "$TOOLKIT_DIR/output/docker-compose-$env.yml" down
}

# 证书管理
cmd_cert() {
    local action="${1:-check}"  # check/generate/renew/info/clean
    local env="${2:-local}"

    "$TOOLKIT_DIR/scripts/cert-manager.sh" "$env" "$action"
}

# 显示配置
cmd_config() {
    local action="${1:-show}"

    case "$action" in
        show)
            cat "$CONFIG_FILE"
            ;;
        validate)
            info "Validating configuration..."
            yq eval "$CONFIG_FILE" > /dev/null && \
                info "✓ Configuration is valid" || \
                error "✗ Configuration has syntax errors"
            ;;
        *)
            error "Unknown config action: $action"
            exit 1
            ;;
    esac
}

# 从现有项目迁移
cmd_migrate() {
    info "Migrating from existing project..."

    # 检测现有配置
    local detected_domain=""
    local detected_port=""

    # 尝试从 nginx 配置提取
    if [ -f "deploy/nginx/conf.d/default.conf" ]; then
        detected_domain=$(grep "server_name" deploy/nginx/conf.d/default.conf | awk '{print $2}' | tr -d ';' | head -1)
    fi

    # 尝试从 Docker Compose 提取
    if [ -f "docker-compose.yml" ]; then
        detected_port=$(yq '.services.*.ports[]' docker-compose.yml | grep ':' | cut -d: -f2 | head -1)
    fi

    info "Detected configuration:"
    info "  Domain: $detected_domain"
    info "  Port: $detected_port"

    # 生成配置文件
    cmd_init

    [ -n "$detected_domain" ] && yq -i ".domains.local.primary = \"$detected_domain\"" "$CONFIG_FILE"
    [ -n "$detected_port" ] && yq -i ".project.backend_port = $detected_port" "$CONFIG_FILE"

    info "✓ Migration complete!"
    info "Please review $CONFIG_FILE and adjust as needed"
}

# 显示帮助
cmd_help() {
    cat <<EOF
HTTPS Deployment Toolkit

Usage: https-deploy <command> [options]

Commands:
  init                   Initialize configuration
  up <env>               Deploy to environment (local/staging/production)
  down <env>             Stop environment
  cert <action> <env>    Manage certificates (check/generate/renew/info/clean)
  config <action>        Configuration management (show/validate)
  migrate                Migrate from existing project
  help                   Show this help

Examples:
  https-deploy init                    # Initialize new project
  https-deploy up local                # Start local HTTPS
  https-deploy up production           # Deploy to production
  https-deploy cert renew production   # Renew production certificate
  https-deploy migrate                 # Migrate existing project

Environment:
  local       - Local development (uses mkcert)
  staging     - Staging environment (uses Let's Encrypt)
  production  - Production environment (uses Let's Encrypt)

Documentation: https://github.com/your/https-toolkit
EOF
}

# 主函数
main() {
    check_dependencies

    local command="${1:-help}"
    shift || true

    case "$command" in
        init)       cmd_init "$@" ;;
        up)         cmd_up "$@" ;;
        down)       cmd_down "$@" ;;
        cert)       cmd_cert "$@" ;;
        config)     cmd_config "$@" ;;
        migrate)    cmd_migrate "$@" ;;
        help|--help|-h) cmd_help ;;
        *)
            error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
```

### 2. 配置渲染引擎

```bash
#!/bin/bash
# scripts/config-renderer.sh
# 配置模板渲染引擎

set -e

ENV="${1:-local}"
CONFIG_FILE="config.yaml"
TEMPLATES_DIR=".https-toolkit/templates"
OUTPUT_DIR=".https-toolkit/output"

mkdir -p "$OUTPUT_DIR"

# 读取配置值
get_config() {
    yq "$1" "$CONFIG_FILE"
}

# 渲染模板
render_template() {
    local template=$1
    local output=$2

    # 读取所有配置变量
    local project_name=$(get_config ".project.name")
    local backend_port=$(get_config ".project.backend_port")
    local domain=$(get_config ".domains.$ENV.primary")
    local cert_storage=$(get_config ".certificates.$ENV.storage")

    # 展开环境变量和配置变量
    cert_storage=$(eval echo "$cert_storage")  # 展开 ${project.name}

    # 使用 envsubst 或 sed 渲染
    export PROJECT_NAME="$project_name"
    export BACKEND_PORT="$backend_port"
    export DOMAIN="$domain"
    export CERT_STORAGE="$cert_storage"
    export ENV="$ENV"

    envsubst < "$template" > "$output"
}

# 渲染所有模板
info "Rendering configuration for $ENV environment..."

# 1. Nginx 配置
render_template "$TEMPLATES_DIR/nginx-https.conf.tpl" \
                "$OUTPUT_DIR/nginx-$ENV.conf"

# 2. Docker Compose
render_template "$TEMPLATES_DIR/docker-compose.tpl" \
                "$OUTPUT_DIR/docker-compose-$ENV.yml"

info "✓ Configuration rendered to $OUTPUT_DIR/"
```

---

## 最佳实践

### 1. 配置管理

```bash
# 不同环境使用不同配置文件
config.yaml               # 默认配置
config.local.yaml         # 本地覆盖
config.production.yaml    # 生产覆盖

# 合并配置
https-deploy up local --config config.local.yaml
```

### 2. 密钥管理

```yaml
# config.yaml - 不提交敏感信息
dns:
  credentials:
    access_key_id: ${env:ALIYUN_ACCESS_KEY_ID}  # 从环境变量读取

# .env - 本地环境变量(加入 .gitignore)
ALIYUN_ACCESS_KEY_ID=xxx
ALIYUN_ACCESS_KEY_SECRET=xxx
```

### 3. CI/CD 集成

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install HTTPS Toolkit
        run: |
          curl -sSL https://toolkit.example.com/install.sh | bash

      - name: Deploy to Production
        env:
          ALIYUN_ACCESS_KEY_ID: ${{ secrets.ALIYUN_ACCESS_KEY_ID }}
          ALIYUN_ACCESS_KEY_SECRET: ${{ secrets.ALIYUN_ACCESS_KEY_SECRET }}
        run: |
          https-deploy up production
```

---

## 工作量评估

| 阶段 | 任务 | 工作量 | 产出 |
|------|------|--------|------|
| Phase 1 | 配置设计与抽象 | 1 天 | config.yaml 结构 |
| Phase 2 | 模板引擎实现 | 1 天 | config-renderer.sh |
| Phase 3 | 命令行工具 | 1 天 | https-deploy CLI |
| Phase 4 | 证书管理通用化 | 0.5 天 | 通用 cert-manager.sh |
| Phase 5 | 迁移工具 | 0.5 天 | migrate 命令 |
| Phase 6 | 文档编写 | 1 天 | 完整使用文档 |
| Phase 7 | 测试与优化 | 1 天 | 多项目测试 |
| **总计** | | **6 天** | 完整工具包 |

---

## 总结

### 通用化后的优势

1. **零学习成本**: 修改一个 YAML 文件即可使用
2. **框架无关**: 支持任意后端技术栈
3. **环境隔离**: 本地/测试/生产独立配置
4. **自动化**: 证书管理、配置渲染全自动
5. **可扩展**: 支持钩子脚本和自定义模板
6. **易迁移**: 现有项目 1 分钟迁移

### 技术亮点

- **配置驱动**: 声明式配置,符合 Infrastructure as Code 理念
- **模板渲染**: Jinja-like 模板引擎,灵活性高
- **多环境支持**: 同一套代码支持本地/测试/生产
- **中心化管理**: 证书、配置统一管理
- **生命周期钩子**: 支持 pre/post 部署钩子

### 使用建议

- **新项目**: 直接使用 `https-deploy init` 初始化
- **现有项目**: 使用 `https-deploy migrate` 快速迁移
- **团队协作**: 将 `config.yaml` 提交到代码仓库,环境变量通过 `.env` 管理
- **CI/CD**: 集成到现有 CI/CD 流程,自动化部署

---

## 下一步行动

### 立即可做

1. **MVP 实现**: 先实现 `init` 和 `up local` 命令,验证方案可行性
2. **迁移当前项目**: 将 top-ai-news 作为第一个测试项目
3. **编写文档**: 快速开始文档和配置说明

### 短期规划

1. 完善多环境支持(staging/production)
2. 添加健康检查和监控
3. 支持更多证书提供商

### 长期规划

1. 开发 Web Dashboard(可视化管理)
2. 支持 Kubernetes 部署
3. 构建社区和插件生态
