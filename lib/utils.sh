#!/bin/bash
# Utility functions

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 信息输出
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

debug() {
    if [ "${DEBUG:-}" = "1" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# 检查命令是否存在
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi
    return 0
}

# 检查 Docker 是否运行
check_docker() {
    if ! docker info &> /dev/null; then
        error "Docker is not running"
        return 1
    fi
    return 0
}

# 检查 Docker Compose
check_docker_compose() {
    if ! check_command docker-compose && ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed"
        return 1
    fi
    return 0
}

# 检查 yq (YAML 处理器)
check_yq() {
    if ! check_command yq; then
        error "yq is not installed"
        echo ""
        echo "Install yq:"
        echo "  Mac:   brew install yq"
        echo "  Linux: https://github.com/mikefarah/yq#install"
        return 1
    fi
    return 0
}

# 检查 jq (JSON 处理器)
check_jq() {
    if ! check_command jq; then
        error "jq is not installed"
        echo ""
        echo "Install jq:"
        echo "  Mac:   brew install jq"
        echo "  Linux: apt-get install jq / yum install jq"
        return 1
    fi
    return 0
}

# 检查所有依赖
check_dependencies() {
    local missing=0

    check_docker || missing=1
    check_docker_compose || missing=1
    check_yq || missing=1
    check_jq || missing=1

    if [ $missing -eq 1 ]; then
        error "Missing dependencies. Please install them first."
        return 1
    fi

    return 0
}

# 等待服务就绪
# 策略: 先 TCP 端口检测（快），再可选健康检查路径
wait_for_service() {
    local container="$1"
    local port="$2"
    local max_wait="${3:-15}"
    local health_path="${4:-}"
    local elapsed=0

    # 阶段 1: TCP 端口检测（nc -z，毫秒级）
    while [ $elapsed -lt $max_wait ]; do
        if docker exec "$container" nc -z localhost "$port" 2>/dev/null; then
            # 端口通了，可选做健康检查
            if [ -n "$health_path" ]; then
                if docker exec "$container" wget -qO /dev/null "http://localhost:$port$health_path" 2>/dev/null; then
                    info "  ✓ Health check passed ($health_path)"
                else
                    warn "  Port $port is open, but $health_path not available (skipped)"
                fi
            fi
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        echo -n "."
    done

    echo ""
    warn "Port $port not ready after ${max_wait}s (may still be starting)"
    return 1
}

# 生成时间戳
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 文件锁
acquire_lock() {
    local lock_file="$1"
    local max_wait="${2:-30}"
    local elapsed=0

    mkdir -p "$(dirname "$lock_file")"

    while [ $elapsed -lt $max_wait ]; do
        if mkdir "$lock_file" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    error "Failed to acquire lock: $lock_file"
    return 1
}

# 释放锁
release_lock() {
    local lock_file="$1"
    rmdir "$lock_file" 2>/dev/null || true
}

# 确认操作
confirm() {
    local prompt="${1:-Continue?}"
    read -p "$prompt [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# 渲染模板
render_template() {
    local template="$1"
    local output="$2"
    shift 2

    # 导出所有变量
    export "$@"

    # 使用 envsubst 渲染
    if check_command envsubst; then
        envsubst < "$template" > "$output"
    else
        # 简单的变量替换
        local content=$(cat "$template")
        for var in "$@"; do
            local key="${var%%=*}"
            local value="${var#*=}"
            content="${content//\$\{$key\}/$value}"
            content="${content//\$$key/$value}"
        done
        echo "$content" > "$output"
    fi
}

# 表格输出
print_table() {
    column -t -s $'\t'
}

# 高亮输出
highlight() {
    echo -e "${GREEN}$1${NC}"
}

# 检查网络是否存在
check_network() {
    local network="$1"
    docker network inspect "$network" &> /dev/null
}

# 创建网络
create_network() {
    local network="$1"
    if ! check_network "$network"; then
        docker network create "$network"
        info "Created network: $network"
    fi
}

# 检查容器是否运行
check_container() {
    local container="$1"
    docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "^$container$"
}

# 停止容器
stop_container() {
    local container="$1"
    if check_container "$container"; then
        docker stop "$container" &> /dev/null || true
        docker rm "$container" &> /dev/null || true
    fi
}
