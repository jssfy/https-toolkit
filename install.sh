#!/bin/bash
# HTTPS Toolkit Installer
# Usage: curl -sSL https://toolkit.example.com/install.sh | bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 配置
TOOLKIT_VERSION="${HTTPS_TOOLKIT_VERSION:-main}"
INSTALL_DIR="$HOME/.https-toolkit"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/your-org/https-toolkit"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HTTPS Deployment Toolkit Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查操作系统
OS="$(uname -s)"
case "$OS" in
    Darwin*)
        info "Detected: macOS"
        ;;
    Linux*)
        info "Detected: Linux"
        ;;
    *)
        error "Unsupported OS: $OS"
        exit 1
        ;;
esac

# 检查依赖
check_dependencies() {
    info "Checking dependencies..."

    local missing=0

    # Docker
    if ! command -v docker &> /dev/null; then
        warn "  Docker not found"
        echo "    Install: https://docs.docker.com/get-docker/"
        missing=1
    else
        info "  ✓ Docker"
    fi

    # Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        warn "  Docker Compose not found"
        missing=1
    else
        info "  ✓ Docker Compose"
    fi

    # yq
    if ! command -v yq &> /dev/null; then
        warn "  yq not found"
        echo "    Installing yq..."
        if [ "$OS" = "Darwin" ]; then
            if command -v brew &> /dev/null; then
                brew install yq
            else
                error "    Homebrew not found. Install yq manually: https://github.com/mikefarah/yq"
                missing=1
            fi
        else
            error "    Install yq: https://github.com/mikefarah/yq#install"
            missing=1
        fi
    else
        info "  ✓ yq"
    fi

    # jq
    if ! command -v jq &> /dev/null; then
        warn "  jq not found"
        echo "    Installing jq..."
        if [ "$OS" = "Darwin" ]; then
            if command -v brew &> /dev/null; then
                brew install jq
            else
                error "    Homebrew not found. Install jq manually"
                missing=1
            fi
        else
            error "    Install jq: apt-get install jq / yum install jq"
            missing=1
        fi
    else
        info "  ✓ jq"
    fi

    if [ $missing -eq 1 ]; then
        error "Missing dependencies. Please install them first."
        exit 1
    fi
}

check_dependencies

# 下载/更新工具包
info "Installing HTTPS Toolkit..."

# 获取源码目录
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$INSTALL_DIR" ]; then
    info "  Toolkit already installed, updating..."
else
    info "  Installing toolkit..."
    mkdir -p "$INSTALL_DIR"
fi

# 从源码目录同步文件（保留 gateway/ 运行时数据）
if [ -f "$SOURCE_DIR/bin/https-deploy" ]; then
    info "  Syncing from $SOURCE_DIR"
    for dir in bin lib templates; do
        rm -rf "$INSTALL_DIR/$dir"
        cp -r "$SOURCE_DIR/$dir" "$INSTALL_DIR/$dir"
    done
    info "  ✓ Files synced"
else
    warn "  Source directory not found, skipping file sync"
fi

# 创建符号链接
info "Creating symbolic link..."
sudo ln -sf "$INSTALL_DIR/bin/https-deploy" "$BIN_DIR/https-deploy"
chmod +x "$INSTALL_DIR/bin/https-deploy"

# 验证安装
if command -v https-deploy &> /dev/null; then
    info "✓ Installation complete!"
    echo ""
    VERSION=$(https-deploy version | head -1)
    info "$VERSION"
else
    error "Installation failed"
    exit 1
fi

# 显示后续步骤
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Initialize gateway (first time):"
echo "   https-deploy gateway init"
echo ""
echo "2. Create a test project:"
echo "   mkdir my-project && cd my-project"
echo "   https-deploy init"
echo "   https-deploy up"
echo ""
echo "3. Access gateway:"
echo "   open https://local.yeanhua.asia"
echo ""
echo "Documentation: https://github.com/your-org/https-toolkit"
echo ""
