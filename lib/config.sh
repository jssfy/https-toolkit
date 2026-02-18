#!/bin/bash
# Configuration management

# 读取配置值
config_get() {
    local key="$1"
    local config_file="${2:-$PROJECT_CONFIG}"

    if [ ! -f "$config_file" ]; then
        error "Config file not found: $config_file"
        return 1
    fi

    yq eval "$key" "$config_file" 2>/dev/null || echo ""
}

# 验证项目配置
config_validate() {
    local config_file="${1:-$PROJECT_CONFIG}"

    info "Validating configuration..."

    # 检查文件存在
    if [ ! -f "$config_file" ]; then
        error "Config file not found: $config_file"
        return 1
    fi

    # 检查 YAML 语法
    if ! yq eval "$config_file" > /dev/null 2>&1; then
        error "Invalid YAML syntax in $config_file"
        return 1
    fi

    # 检查必需字段
    local required_fields=(
        ".project.name"
        ".project.backend_port"
        ".routing.path_prefix"
    )

    for field in "${required_fields[@]}"; do
        local value=$(config_get "$field" "$config_file")
        if [ -z "$value" ] || [ "$value" = "null" ]; then
            error "Missing required field: $field"
            return 1
        fi
    done

    # 验证路径前缀格式
    local path_prefix=$(config_get ".routing.path_prefix" "$config_file")
    if [[ ! "$path_prefix" =~ ^/ ]]; then
        error "path_prefix must start with '/'"
        return 1
    fi

    # 验证端口
    local backend_port=$(config_get ".project.backend_port" "$config_file")
    if ! [[ "$backend_port" =~ ^[0-9]+$ ]] || [ "$backend_port" -lt 1 ] || [ "$backend_port" -gt 65535 ]; then
        error "Invalid backend_port: $backend_port (must be 1-65535)"
        return 1
    fi

    info "✓ Configuration is valid"
    return 0
}

# 显示配置
config_show() {
    local config_file="${1:-$PROJECT_CONFIG}"

    if [ ! -f "$config_file" ]; then
        error "Config file not found: $config_file"
        return 1
    fi

    cat "$config_file"
}

# 配置命令
config_command() {
    local subcommand="${1:-show}"
    shift || true

    case "$subcommand" in
        show)
            config_show "$@"
            ;;
        validate)
            config_validate "$@"
            ;;
        *)
            error "Unknown config command: $subcommand"
            exit 1
            ;;
    esac
}

# 初始化项目配置
config_init() {
    local template="${1:-golang}"

    if [ -f "$PROJECT_CONFIG" ]; then
        warn "config.yaml already exists"
        if ! confirm "Overwrite?"; then
            info "Cancelled"
            return 0
        fi
    fi

    # 复制模板
    local template_file="$TOOLKIT_ROOT/templates/config-$template.yaml"
    if [ ! -f "$template_file" ]; then
        template_file="$TOOLKIT_ROOT/templates/config.yaml"
    fi

    cp "$template_file" "$PROJECT_CONFIG"

    # 交互式配置
    echo ""
    echo "Project Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    read -p "Project name (e.g., my-api): " project_name
    read -p "Backend port (e.g., 8080): " backend_port
    read -p "Path prefix (e.g., /api): " path_prefix

    # 更新配置
    yq eval -i ".project.name = \"$project_name\"" "$PROJECT_CONFIG"
    yq eval -i ".project.backend_port = $backend_port" "$PROJECT_CONFIG"
    yq eval -i ".routing.path_prefix = \"$path_prefix\"" "$PROJECT_CONFIG"

    info "✓ Configuration created: $PROJECT_CONFIG"
    echo ""
    echo "Next steps:"
    echo "  1. Review/edit: vim config.yaml"
    echo "  2. Deploy: https-deploy up"
}
