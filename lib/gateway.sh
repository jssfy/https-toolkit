#!/bin/bash
# Gateway management

GATEWAY_NAME="https-toolkit-gateway"
GATEWAY_NETWORK="https-toolkit-network"
GATEWAY_DOMAIN="local.yeanhua.asia"
CERT_MODE="mkcert"
LETSENCRYPT_EMAIL=""
GATEWAY_CONF="$HOME/.https-toolkit/gateway/gateway.conf"
ACME_HOME="$HOME/.https-toolkit/gateway/acme"

# ========================================
# 配置持久化
# ========================================

# 加载网关配置
gateway_load_config() {
    if [ -f "$GATEWAY_CONF" ]; then
        source "$GATEWAY_CONF"
    fi
}

# 保存网关配置
gateway_save_config() {
    mkdir -p "$(dirname "$GATEWAY_CONF")"
    cat > "$GATEWAY_CONF" <<EOF
# HTTPS Toolkit Gateway Configuration
# Generated at $(timestamp)
CERT_MODE=$CERT_MODE
GATEWAY_DOMAIN=$GATEWAY_DOMAIN
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
EOF
    info "  ✓ Saved configuration to gateway.conf"
}

# 启动时自动加载已保存的配置
gateway_load_config

# ========================================
# 初始化网关
# ========================================

gateway_init() {
    # 解析参数
    local env="local"
    local domain_explicit=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cert-mode)
                CERT_MODE="$2"
                shift 2
                ;;
            --domain)
                GATEWAY_DOMAIN="$2"
                domain_explicit=true
                shift 2
                ;;
            --email)
                LETSENCRYPT_EMAIL="$2"
                shift 2
                ;;
            *)
                env="$1"
                shift
                ;;
        esac
    done

    # 验证 cert mode
    case "$CERT_MODE" in
        mkcert|letsencrypt|letsencrypt-wildcard) ;;
        *)
            error "Invalid cert mode: $CERT_MODE"
            echo "Valid modes: mkcert, letsencrypt, letsencrypt-wildcard"
            return 1
            ;;
    esac

    # 设置默认域名（仅当用户未通过 --domain 显式指定时）
    if [ "$domain_explicit" = false ]; then
        case "$CERT_MODE" in
            mkcert)
                GATEWAY_DOMAIN="local.yeanhua.asia"
                ;;
            letsencrypt)
                GATEWAY_DOMAIN="data.yeanhua.asia"
                ;;
            letsencrypt-wildcard)
                GATEWAY_DOMAIN="yeanhua.asia"
                ;;
        esac
    fi

    # Let's Encrypt 模式需要邮箱
    if [[ "$CERT_MODE" == letsencrypt* ]] && [ -z "$LETSENCRYPT_EMAIL" ]; then
        read -p "Enter email for Let's Encrypt registration: " LETSENCRYPT_EMAIL
        if [ -z "$LETSENCRYPT_EMAIL" ]; then
            error "Email is required for Let's Encrypt"
            return 1
        fi
    fi

    info "Initializing HTTPS Gateway..."
    info "  Cert mode: $CERT_MODE"
    info "  Domain:    $GATEWAY_DOMAIN"

    # 检查依赖
    check_dependencies || return 1

    # Let's Encrypt 模式需要 acme.sh 镜像
    if [[ "$CERT_MODE" == letsencrypt* ]]; then
        check_acme_sh || return 1
    fi

    # 创建目录结构
    mkdir -p "$GATEWAY_ROOT"/{nginx/conf.d/projects,certs,registry,html}
    mkdir -p "$ACME_HOME"
    info "  ✓ Created directory structure"

    # 保存配置
    gateway_save_config

    # 生成 Nginx 配置
    gateway_generate_nginx_config "$env"
    info "  ✓ Generated Nginx configuration"

    # 生成/检查证书
    gateway_generate_certificate "$env"
    info "  ✓ Generated SSL certificate"

    # 创建 Docker 网络
    create_network "$GATEWAY_NETWORK"
    info "  ✓ Created network: $GATEWAY_NETWORK"

    # 初始化注册表
    gateway_init_registry "$env"
    info "  ✓ Initialized project registry"

    # 生成 Dashboard
    gateway_generate_dashboard
    info "  ✓ Generated Gateway Dashboard"

    # 启动或重载网关
    if check_container "$GATEWAY_NAME"; then
        info "  Gateway already running, reloading configuration..."
        docker exec "$GATEWAY_NAME" nginx -s reload
        info "  ✓ Gateway reloaded"
    else
        gateway_start "$env"
    fi

    info "✓ Gateway initialized successfully!"
    echo ""
    echo "Gateway URL: https://$GATEWAY_DOMAIN"
    echo "Dashboard:   https://$GATEWAY_DOMAIN/"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy your first project: cd your-project && https-deploy up"
}

# 生成 Nginx 主配置
gateway_generate_nginx_config() {
    local env="$1"

    cat > "$GATEWAY_ROOT/nginx/nginx.conf" <<'EOF'
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
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    gzip on;

    # 包含配置（项目路由在 00-default.conf 的 server 块内 include）
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # 计算 server_name 和证书目录
    local server_name="$GATEWAY_DOMAIN"
    local cert_domain="$GATEWAY_DOMAIN"
    if [ "$CERT_MODE" = "letsencrypt-wildcard" ]; then
        server_name="$GATEWAY_DOMAIN *.$GATEWAY_DOMAIN"
        cert_domain="$GATEWAY_DOMAIN"
    fi

    # 生成默认服务器配置
    cat > "$GATEWAY_ROOT/nginx/conf.d/00-default.conf" <<EOF
server {
    listen 80;
    server_name $server_name;

    # 重定向到 HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name $server_name;

    # SSL 配置
    ssl_certificate /etc/nginx/certs/$cert_domain/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/$cert_domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 安全头
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # 默认路由: Dashboard
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    # 静态文件（注册表 JSON 禁止缓存）
    location /_gateway/ {
        alias /usr/share/nginx/html/_gateway/;
        autoindex on;
        autoindex_format json;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # 健康检查
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    # 项目路由（动态 include）
    include /etc/nginx/conf.d/projects/*.conf;
}
EOF
}

# ========================================
# 证书生成（分发函数）
# ========================================

gateway_generate_certificate() {
    local env="$1"

    case "$CERT_MODE" in
        mkcert)
            gateway_cert_mkcert
            ;;
        letsencrypt)
            gateway_cert_letsencrypt
            ;;
        letsencrypt-wildcard)
            gateway_cert_letsencrypt_wildcard
            ;;
        *)
            error "Unknown cert mode: $CERT_MODE"
            return 1
            ;;
    esac
}

# mkcert 模式（本地开发）
gateway_cert_mkcert() {
    local cert_dir="$GATEWAY_ROOT/certs/$GATEWAY_DOMAIN"
    mkdir -p "$cert_dir"

    # 检查是否已存在
    if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ]; then
        info "  Certificate already exists"
        return 0
    fi

    # 使用 mkcert 生成本地证书
    if ! check_command mkcert; then
        warn "  mkcert not found, installing..."
        if check_command brew; then
            brew install mkcert
        else
            error "  Please install mkcert manually: https://github.com/FiloSottile/mkcert"
            return 1
        fi
    fi

    # 安装 CA 到系统钥匙串（幂等，已安装时无副作用）
    mkcert -install

    # 生成证书
    cd "$cert_dir"
    mkcert "$GATEWAY_DOMAIN" "localhost" "127.0.0.1" "::1"

    # 重命名（先 key 后 cert，避免 glob 冲突）
    mv ${GATEWAY_DOMAIN}+*-key.pem privkey.pem 2>/dev/null || true
    mv ${GATEWAY_DOMAIN}+*.pem fullchain.pem 2>/dev/null || true
}

# Let's Encrypt 单域名模式（HTTP-01 standalone）
gateway_cert_letsencrypt() {
    local cert_dir="$GATEWAY_ROOT/certs/$GATEWAY_DOMAIN"
    mkdir -p "$cert_dir"

    # 检查是否已存在
    if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ]; then
        info "  Certificate already exists"
        return 0
    fi

    # 需要 80 端口空闲，先停 gateway（如果在运行）
    if check_container "$GATEWAY_NAME"; then
        warn "  Stopping gateway to free port 80 for ACME challenge..."
        gateway_stop
    fi

    info "  Issuing certificate for $GATEWAY_DOMAIN via HTTP-01 standalone..."

    docker run --rm \
        -v "$ACME_HOME":/acme.sh \
        --net=host \
        neilpang/acme.sh \
        --issue -d "$GATEWAY_DOMAIN" \
        --standalone \
        --server letsencrypt \
        --email "$LETSENCRYPT_EMAIL"

    if [ $? -ne 0 ]; then
        error "  Failed to issue certificate"
        return 1
    fi

    # 安装证书到标准目录
    info "  Installing certificate to certs directory..."
    docker run --rm \
        -v "$ACME_HOME":/acme.sh \
        -v "$GATEWAY_ROOT/certs":/certs \
        neilpang/acme.sh \
        --install-cert -d "$GATEWAY_DOMAIN" \
        --key-file       /certs/"$GATEWAY_DOMAIN"/privkey.pem \
        --fullchain-file /certs/"$GATEWAY_DOMAIN"/fullchain.pem
}

# Let's Encrypt 泛域名模式（DNS-01 via dns_ali）
gateway_cert_letsencrypt_wildcard() {
    local cert_dir="$GATEWAY_ROOT/certs/$GATEWAY_DOMAIN"
    mkdir -p "$cert_dir"

    # 检查是否已存在
    if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ]; then
        info "  Certificate already exists"
        return 0
    fi

    # 检查阿里云 DNS API 凭据
    local ali_key=""
    local ali_secret=""

    # 尝试从 acme.sh 的 account.conf 读取
    if [ -f "$ACME_HOME/account.conf" ]; then
        ali_key=$(sed -n "s/^SAVED_Ali_Key='\{0,1\}\([^']*\)'\{0,1\}$/\1/p" "$ACME_HOME/account.conf" 2>/dev/null || true)
        ali_secret=$(sed -n "s/^SAVED_Ali_Secret='\{0,1\}\([^']*\)'\{0,1\}$/\1/p" "$ACME_HOME/account.conf" 2>/dev/null || true)
    fi

    # 如果没有保存的凭据，交互输入
    if [ -z "$ali_key" ] || [ -z "$ali_secret" ]; then
        info "  Alibaba Cloud DNS API credentials required for wildcard certificate"
        read -p "  Ali_Key: " ali_key
        read -s -p "  Ali_Secret: " ali_secret
        echo ""

        if [ -z "$ali_key" ] || [ -z "$ali_secret" ]; then
            error "  Ali_Key and Ali_Secret are required for DNS-01 validation"
            return 1
        fi
    fi

    info "  Issuing wildcard certificate for *.$GATEWAY_DOMAIN via DNS-01..."

    docker run --rm -it \
        -v "$ACME_HOME":/acme.sh \
        -e Ali_Key="$ali_key" \
        -e Ali_Secret="$ali_secret" \
        neilpang/acme.sh \
        --issue \
        -d "$GATEWAY_DOMAIN" \
        -d "*.$GATEWAY_DOMAIN" \
        --dns dns_ali \
        --server letsencrypt \
        --email "$LETSENCRYPT_EMAIL"

    if [ $? -ne 0 ]; then
        error "  Failed to issue wildcard certificate"
        return 1
    fi

    # 安装证书到标准目录
    info "  Installing certificate to certs directory..."
    docker run --rm \
        -v "$ACME_HOME":/acme.sh \
        -v "$GATEWAY_ROOT/certs":/certs \
        neilpang/acme.sh \
        --install-cert -d "$GATEWAY_DOMAIN" \
        --key-file       /certs/"$GATEWAY_DOMAIN"/privkey.pem \
        --fullchain-file /certs/"$GATEWAY_DOMAIN"/fullchain.pem
}

# 证书续期
gateway_cert_renew() {
    gateway_load_config

    if [ "$CERT_MODE" = "mkcert" ]; then
        info "mkcert certificates don't need renewal"
        return 0
    fi

    info "Renewing certificates (mode: $CERT_MODE, domain: $GATEWAY_DOMAIN)..."

    # 需要 80 端口空闲（HTTP-01 模式）
    local was_running=false
    if [ "$CERT_MODE" = "letsencrypt" ] && check_container "$GATEWAY_NAME"; then
        was_running=true
        warn "Stopping gateway to free port 80 for ACME renewal..."
        gateway_stop
    fi

    docker run --rm \
        -v "$ACME_HOME":/acme.sh \
        -v "$GATEWAY_ROOT/certs":/certs \
        neilpang/acme.sh \
        --cron

    if [ $? -ne 0 ]; then
        error "Certificate renewal failed"
        # 尝试重启网关
        if [ "$was_running" = true ]; then
            gateway_start
        fi
        return 1
    fi

    info "✓ Certificate renewal completed"

    # 重启网关以加载新证书
    if check_container "$GATEWAY_NAME"; then
        gateway_restart
        info "✓ Gateway restarted with renewed certificate"
    elif [ "$was_running" = true ]; then
        gateway_start
        info "✓ Gateway restarted with renewed certificate"
    fi
}

# 初始化注册表
gateway_init_registry() {
    local env="$1"
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    cat > "$registry_file" <<EOF
{
  "version": "1.0.0",
  "environment": "$env",
  "projects": [],
  "created_at": "$(timestamp)",
  "updated_at": "$(timestamp)"
}
EOF
}

# 生成 Dashboard
gateway_generate_dashboard() {
    cat > "$GATEWAY_ROOT/html/index.html" <<'EOF'
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
        .container { max-width: 1200px; margin: 0 auto; }
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
            transition: transform 0.2s;
        }
        .project-card:hover { transform: translateY(-5px); }
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
            background: #d4edda;
            color: #155724;
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
        .btn:hover { background: #5568d3; }
        .empty-state {
            background: white;
            border-radius: 12px;
            padding: 3rem;
            text-align: center;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        .empty-state h2 { color: #333; margin-bottom: 1rem; }
        .empty-state p { color: #666; line-height: 1.6; }
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
        <div id="projects" class="projects"></div>
        <div id="empty-state" class="empty-state" style="display: none;">
            <h2>No projects registered</h2>
            <p>Deploy your first project:<br><code>cd your-project && https-deploy up</code></p>
        </div>
    </div>
    <script>
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
                        <span class="project-status">${project.status}</span>
                        <a href="${project.path_prefix}" class="btn">Open →</a>
                    </div>
                `).join('');
            } catch (error) {
                console.error('Failed to load projects:', error);
            }
        }
        loadProjects();
        setInterval(loadProjects, 5000);
    </script>
</body>
</html>
EOF

    mkdir -p "$GATEWAY_ROOT/html/_gateway/registry"
    ln -sf "$GATEWAY_ROOT/registry/projects.json" "$GATEWAY_ROOT/html/_gateway/registry/projects.json"
}

# 启动网关
gateway_start() {
    local env="${1:-local}"

    if check_container "$GATEWAY_NAME"; then
        info "Gateway is already running"
        return 0
    fi

    info "Starting gateway container..."

    docker run -d \
        --name "$GATEWAY_NAME" \
        --network "$GATEWAY_NETWORK" \
        -p 80:80 \
        -p 443:443 \
        -v "$GATEWAY_ROOT/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
        -v "$GATEWAY_ROOT/nginx/conf.d:/etc/nginx/conf.d:ro" \
        -v "$GATEWAY_ROOT/certs:/etc/nginx/certs:ro" \
        -v "$GATEWAY_ROOT/html:/usr/share/nginx/html:ro" \
        -v "$GATEWAY_ROOT/registry:/usr/share/nginx/html/_gateway/registry:ro" \
        --restart unless-stopped \
        nginx:alpine

    info "✓ Gateway started: https://$GATEWAY_DOMAIN"
}

# 停止网关
gateway_stop() {
    info "Stopping gateway..."
    stop_container "$GATEWAY_NAME"
    info "✓ Gateway stopped"
}

# 重启网关
gateway_restart() {
    gateway_stop
    gateway_start
}

# 网关状态
gateway_status() {
    if ! check_container "$GATEWAY_NAME"; then
        error "Gateway is not running"
        echo ""
        echo "Start gateway: https-deploy gateway init"
        return 1
    fi

    info "Gateway Status:"
    echo ""
    docker ps --filter "name=$GATEWAY_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""

    info "Cert mode:   $CERT_MODE"
    info "Domain:      $GATEWAY_DOMAIN"
    info "Gateway URL: https://$GATEWAY_DOMAIN"
    echo ""

    local project_count=$(jq '.projects | length' "$GATEWAY_ROOT/registry/projects.json" 2>/dev/null || echo "0")
    info "Registered projects: $project_count"
}

# 列出项目
gateway_list_projects() {
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    if [ ! -f "$registry_file" ]; then
        warn "No projects registered"
        return 0
    fi

    echo ""
    echo "Registered Projects:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    jq -r '.projects[] | "\(.name)\t\(.path_prefix)\t\(.backend_port)\t\(.status)"' "$registry_file" | \
        (echo -e "Name\tPath\tPort\tStatus" && cat) | print_table

    echo ""
    info "Gateway: https://$GATEWAY_DOMAIN"
}

# 网关日志
gateway_logs() {
    local follow=""
    if [ "$1" = "-f" ]; then
        follow="-f"
    fi

    docker logs $follow "$GATEWAY_NAME"
}

# 重载配置
gateway_reload() {
    info "Reloading gateway configuration..."

    # 测试配置
    if ! docker exec "$GATEWAY_NAME" nginx -t 2>&1; then
        error "Configuration test failed"
        return 1
    fi

    # 重载
    docker exec "$GATEWAY_NAME" nginx -s reload
    info "✓ Gateway reloaded"
}

# 测试配置
gateway_test_config() {
    info "Testing gateway configuration..."
    docker exec "$GATEWAY_NAME" nginx -t
}

# 清理网关
gateway_clean() {
    warn "This will stop gateway and remove all projects"
    if ! confirm "Continue?"; then
        info "Cancelled"
        return 0
    fi

    # 停止所有项目容器
    local registry_file="$GATEWAY_ROOT/registry/projects.json"
    if [ -f "$registry_file" ]; then
        local projects=$(jq -r '.projects[].name' "$registry_file")
        for project in $projects; do
            info "Stopping project: $project"
            stop_container "$project"
        done
    fi

    # 停止网关
    gateway_stop

    # 删除网络
    docker network rm "$GATEWAY_NETWORK" 2>/dev/null || true

    info "✓ Gateway cleaned"
}

# 显示路由表
gateway_show_routes() {
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    if [ ! -f "$registry_file" ]; then
        warn "No routes configured"
        return 0
    fi

    echo ""
    echo "HTTPS Gateway Routes ($GATEWAY_DOMAIN):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    jq -r '.projects[] | "\(.path_prefix)\t\(.name):\(.backend_port)\t\(.strip_prefix // false)\t\(.status)"' "$registry_file" | \
        (echo -e "Path\tTarget\tStrip\tStatus" && cat) | print_table

    echo ""
}

# 测试路由
gateway_test_route() {
    local path="$1"

    if [ -z "$path" ]; then
        error "Usage: https-deploy test-route <path>"
        return 1
    fi

    info "Testing route: $path"
    echo ""

    local url="https://$GATEWAY_DOMAIN$path"
    echo "Full URL: $url"
    echo ""

    curl -k -v "$url" 2>&1 | grep -E "(HTTP/|< )"
}
