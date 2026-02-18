#!/bin/bash
# Project deployment

# docker compose 兼容：优先使用插件模式，回退到独立命令
docker_compose() {
    if docker compose version &> /dev/null; then
        docker compose "$@"
    else
        docker-compose "$@"
    fi
}

# 初始化项目
project_init() {
    local template="${1:-default}"
    config_init "$template"
}

# 部署项目
project_up() {
    local env="${1:-local}"

    info "Deploying project to $env environment..."

    # 检查依赖
    check_dependencies || return 1

    # 检查网关
    if ! check_container "$GATEWAY_NAME"; then
        warn "Gateway is not running"
        if confirm "Initialize gateway now?"; then
            gateway_init "$env"
        else
            error "Gateway is required. Run: https-deploy gateway init"
            return 1
        fi
    fi

    # 验证配置
    config_validate || return 1

    # 读取配置
    local project_name=$(config_get ".project.name")
    local backend_port=$(config_get ".project.backend_port")
    local path_prefix=$(config_get ".routing.path_prefix")
    local strip_prefix=$(config_get ".routing.strip_prefix")
    local domain=$(config_get ".domains.$env")

    info "Project: $project_name"
    info "Path: $path_prefix"
    info "Port: $backend_port"

    # 检查路径冲突
    if check_path_conflict "$path_prefix" "$project_name"; then
        error "Path prefix '$path_prefix' is already in use"
        return 1
    fi

    # 启动后端服务
    project_start_backend "$env" "$project_name" "$backend_port"

    # 注册到网关
    project_register "$env" "$project_name" "$backend_port" "$path_prefix" "$strip_prefix"

    info "✓ Deployment complete!"
    echo ""
    echo "Access URL: https://$domain$path_prefix"
    echo "Dashboard:  https://$domain/"
}

# 启动后端服务
project_start_backend() {
    local env="$1"
    local project_name="$2"
    local backend_port="$3"

    info "Starting backend service..."

    # 检查是否已运行
    if check_container "$project_name"; then
        warn "Container $project_name is already running"
        if confirm "Restart?"; then
            docker stop "$project_name"
            docker rm "$project_name"
        else
            return 0
        fi
    fi

    # 读取健康检查配置
    local health_enabled=$(config_get ".health_check.enabled" 2>/dev/null)
    local health_path=$(config_get ".health_check.path" 2>/dev/null)
    [ "$health_path" = "null" ] || [ -z "$health_path" ] && health_path=""

    # 渲染 Docker Compose（context 使用项目根目录绝对路径）
    local project_dir="$(pwd)"
    mkdir -p .https-toolkit/output

    cat > .https-toolkit/output/docker-compose-$env.yml <<EOF
services:
  $project_name:
    image: ${project_name}:latest
    container_name: $project_name
    build:
      context: $project_dir
      dockerfile: Dockerfile
    networks:
      - $GATEWAY_NETWORK
    environment:
      - TZ=Asia/Shanghai
      - PORT=$backend_port
    restart: unless-stopped
EOF

    # 有健康检查路径才加 healthcheck（用 wget，alpine 自带）
    if [ -n "$health_path" ] && [ "$health_enabled" = "true" ]; then
        cat >> .https-toolkit/output/docker-compose-$env.yml <<EOF
    healthcheck:
      test: ["CMD", "wget", "-qO", "/dev/null", "http://localhost:$backend_port$health_path"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    fi

    cat >> .https-toolkit/output/docker-compose-$env.yml <<EOF

networks:
  $GATEWAY_NETWORK:
    external: true
EOF

    # 启动服务
    docker_compose -f .https-toolkit/output/docker-compose-$env.yml up -d --build

    # 等待就绪（失败不阻断后续注册）
    sleep 1
    if ! wait_for_service "$project_name" "$backend_port" 15 "$health_path"; then
        warn "Continuing with registration anyway..."
    else
        info "  ✓ Service is healthy"
    fi

    info "✓ Backend service started"
}

# 注册到网关
# $6 backend_host: 可选，默认为 $project_name（Docker 容器名）
#                  传 "host" 则使用 host.docker.internal（宿主机服务）
project_register() {
    local env="$1"
    local project_name="$2"
    local backend_port="$3"
    local path_prefix="$4"
    local strip_prefix="$5"
    local backend_host="${6:-$project_name}"

    # "host" 简写 → Docker Desktop 宿主机地址
    if [ "$backend_host" = "host" ]; then
        backend_host="host.docker.internal"
    fi

    info "Registering to gateway..."

    local nginx_config="$GATEWAY_ROOT/nginx/conf.d/projects/${project_name}.conf"
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    # 生成 Nginx 配置（只有 location 块，由主 server include）
    cat > "$nginx_config" <<EOF
# Auto-generated for: $project_name
# Generated at: $(date)
# Backend: $backend_host:$backend_port

# 强制尾部斜杠（避免相对路径解析错误）
location = $path_prefix {
    return 301 $path_prefix/;
}

location $path_prefix/ {
EOF

    if [ "$strip_prefix" = "true" ]; then
        cat >> "$nginx_config" <<EOF
    rewrite ^$path_prefix/?(.*)$ /\$1 break;
EOF
    fi

    cat >> "$nginx_config" <<EOF
    proxy_pass http://$backend_host:$backend_port;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";

    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
EOF

    info "  ✓ Generated: $project_name.conf"

    # 测试配置
    if ! docker exec "$GATEWAY_NAME" nginx -t 2>&1 | grep -q "successful"; then
        error "  Nginx configuration test failed"
        rm "$nginx_config"
        return 1
    fi
    info "  ✓ Configuration is valid"

    # 更新注册表
    local tmp_file=$(mktemp)
    jq --arg name "$project_name" \
       --arg path "$path_prefix" \
       --argjson port "$backend_port" \
       --arg strip "$strip_prefix" \
       --arg host "$backend_host" \
       --arg now "$(timestamp)" \
       '
       del(.projects[] | select(.name == $name)) |
       .projects += [{
           name: $name,
           path_prefix: $path,
           backend_port: $port,
           backend_host: $host,
           strip_prefix: ($strip == "true"),
           status: "running",
           registered_at: $now,
           updated_at: $now
       }] |
       .projects |= sort_by(.path_prefix) |
       .updated_at = $now
       ' "$registry_file" > "$tmp_file"
    mv "$tmp_file" "$registry_file"

    info "  ✓ Updated registry"

    # 重载 Nginx
    docker exec "$GATEWAY_NAME" nginx -s reload
    info "  ✓ Nginx reloaded"

    info "✓ Registered: $path_prefix → $backend_host:$backend_port"
}

# 仅注册已有服务到网关（不启动 Docker）
# 用于本地 go run / npm start 等非 Docker 服务
project_register_only() {
    local env="${1:-local}"

    info "Registering existing service to gateway..."

    # 检查网关
    if ! check_container "$GATEWAY_NAME"; then
        error "Gateway is not running. Run: https-deploy gateway init"
        return 1
    fi

    # 验证配置
    config_validate || return 1

    # 读取配置
    local project_name=$(config_get ".project.name")
    local backend_port=$(config_get ".project.backend_port")
    local path_prefix=$(config_get ".routing.path_prefix")
    local strip_prefix=$(config_get ".routing.strip_prefix")
    local domain=$(config_get ".domains.$env")

    info "Project: $project_name"
    info "Path: $path_prefix"
    info "Port: $backend_port (host)"

    # 检查路径冲突
    if check_path_conflict "$path_prefix" "$project_name"; then
        error "Path prefix '$path_prefix' is already in use"
        return 1
    fi

    # 注册到网关（使用 host.docker.internal 访问宿主机服务）
    project_register "$env" "$project_name" "$backend_port" "$path_prefix" "$strip_prefix" "host"

    info "✓ Registered!"
    echo ""
    echo "Access URL: https://${domain:-$GATEWAY_DOMAIN}$path_prefix/"
    echo "Dashboard:  https://${domain:-$GATEWAY_DOMAIN}/"
    echo ""
    echo "Ensure your service is running on port $backend_port"
}

# 从网关注销
project_unregister_only() {
    # 验证配置
    config_validate || return 1

    local project_name=$(config_get ".project.name")
    project_unregister "$project_name"

    info "✓ Unregistered: $project_name"
}

# 检查路径冲突
check_path_conflict() {
    local path_prefix="$1"
    local project_name="$2"
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    if [ ! -f "$registry_file" ]; then
        return 1
    fi

    local conflict=$(jq -r --arg path "$path_prefix" --arg name "$project_name" \
        '.projects[] | select(.path_prefix == $path and .name != $name) | .name' \
        "$registry_file")

    [ -n "$conflict" ]
}

# 停止项目
project_down() {
    local env="${1:-local}"

    info "Stopping project..."

    # 读取配置
    local project_name=$(config_get ".project.name")

    # 停止容器
    if [ -f .https-toolkit/output/docker-compose-$env.yml ]; then
        docker_compose -f .https-toolkit/output/docker-compose-$env.yml down
    else
        stop_container "$project_name"
    fi
    info "  ✓ Backend service stopped"

    # 注销
    project_unregister "$project_name"

    info "✓ Project stopped"
}

# 从网关注销
project_unregister() {
    local project_name="$1"

    info "Unregistering from gateway..."

    local nginx_config="$GATEWAY_ROOT/nginx/conf.d/projects/${project_name}.conf"
    local registry_file="$GATEWAY_ROOT/registry/projects.json"

    # 删除 Nginx 配置
    if [ -f "$nginx_config" ]; then
        rm "$nginx_config"
        info "  ✓ Deleted: $project_name.conf"
    fi

    # 更新注册表
    local tmp_file=$(mktemp)
    jq --arg name "$project_name" \
       --arg now "$(timestamp)" \
       'del(.projects[] | select(.name == $name)) | .updated_at = $now' \
       "$registry_file" > "$tmp_file"
    mv "$tmp_file" "$registry_file"
    info "  ✓ Updated registry"

    # 重载 Nginx
    docker exec "$GATEWAY_NAME" nginx -s reload 2>/dev/null || true
    info "  ✓ Nginx reloaded"
}

# 重启项目
project_restart() {
    local env="${1:-local}"
    project_down "$env"
    project_up "$env"
}

# 项目日志
project_logs() {
    local follow=""
    if [ "$1" = "-f" ]; then
        follow="-f"
    fi

    local project_name=$(config_get ".project.name")
    docker logs $follow "$project_name"
}

# 项目状态
project_status() {
    local project_name=$(config_get ".project.name")

    if ! check_container "$project_name"; then
        warn "Project is not running"
        return 1
    fi

    info "Project Status:"
    echo ""
    docker ps --filter "name=$project_name" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}
