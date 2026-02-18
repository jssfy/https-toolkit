# HTTPS Toolkit Makefile
# 简化常用操作的快捷命令

.PHONY: help install uninstall test clean gateway-init gateway-stop gateway-clean gateway-status gateway-list gateway-logs dev deps install-jq install-yq

# 默认目标: 显示帮助
help:
	@echo "HTTPS Toolkit - Makefile 命令"
	@echo ""
	@echo "安装/卸载:"
	@echo "  make install          - 安装 HTTPS Toolkit 到 ~/.https-toolkit"
	@echo "  make uninstall        - 卸载工具包"
	@echo ""
	@echo "网关管理:"
	@echo "  make gateway-init     - 初始化并启动网关"
	@echo "  make gateway-status   - 查看网关状态"
	@echo "  make gateway-list     - 列出所有注册项目"
	@echo "  make gateway-logs     - 查看网关日志"
	@echo "  make gateway-reload   - 重载网关配置"
	@echo "  make gateway-stop     - 停止网关"
	@echo "  make gateway-clean    - 清理网关和所有项目"
	@echo ""
	@echo "开发/测试:"
	@echo "  make dev              - 快速启动开发环境(安装+初始化)"
	@echo "  make test             - 运行测试"
	@echo "  make clean            - 清理临时文件"
	@echo ""
	@echo "快捷访问:"
	@echo "  make dashboard        - 在浏览器打开 Dashboard"
	@echo "  make hosts            - 配置 /etc/hosts (需要 sudo)"
	@echo ""
	@echo "依赖安装:"
	@echo "  make deps             - 安装 jq + yq (自动检测 macOS/Linux)"
	@echo "  make install-jq       - 仅安装 jq"
	@echo "  make install-yq       - 仅安装 yq"
	@echo ""
	@echo "工具信息:"
	@echo "  make version          - 显示版本信息"
	@echo "  make doctor           - 检查依赖和环境"

# ============================================
# 安装/卸载
# ============================================

install:
	@echo "📦 安装 HTTPS Toolkit..."
	@chmod +x install.sh
	@./install.sh
	@echo "✅ 安装完成!"
	@echo ""
	@echo "验证安装: make version"
	@echo "快速开始: make dev"

uninstall:
	@echo "🗑️  卸载 HTTPS Toolkit..."
	@rm -rf ~/.https-toolkit
	@echo "✅ 已卸载"

# ============================================
# 依赖安装
# ============================================

OS := $(shell uname -s)
ARCH := $(shell uname -m)

install-jq:
ifeq ($(OS),Darwin)
	@command -v jq >/dev/null 2>&1 && echo "jq already installed" || brew install jq
else
	@command -v jq >/dev/null 2>&1 && echo "jq already installed" || sudo apt-get install -y jq 2>/dev/null || sudo yum install -y jq
endif

install-yq:
ifeq ($(OS),Darwin)
	@command -v yq >/dev/null 2>&1 && echo "yq already installed" || brew install yq
else
	@if command -v yq >/dev/null 2>&1; then echo "yq already installed"; else \
		YQ_ARCH=$$([ "$(ARCH)" = "aarch64" ] || [ "$(ARCH)" = "arm64" ] && echo "arm64" || echo "amd64"); \
		sudo wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$${YQ_ARCH}"; \
		sudo chmod +x /usr/local/bin/yq; \
		echo "yq installed successfully"; \
	fi
endif

deps: install-jq install-yq
	@echo ""
	@jq --version
	@yq --version
	@echo "All dependencies installed"

# ============================================
# 网关管理
# ============================================

gateway-init:
	@echo "🚀 初始化 HTTPS Gateway..."
	@~/.https-toolkit/bin/https-deploy gateway init
	@echo ""
	@echo "✅ 网关已启动"
	@echo "访问 Dashboard: make dashboard"

gateway-status:
	@~/.https-toolkit/bin/https-deploy gateway status

gateway-list:
	@~/.https-toolkit/bin/https-deploy gateway list

gateway-logs:
	@docker logs https-toolkit-gateway --tail 50 -f

gateway-reload:
	@echo "🔄 重载 Nginx 配置..."
	@docker exec https-toolkit-gateway nginx -t
	@docker exec https-toolkit-gateway nginx -s reload
	@echo "✅ 配置已重载"

gateway-stop:
	@echo "⏹️  停止网关..."
	@~/.https-toolkit/bin/https-deploy gateway stop
	@echo "✅ 网关已停止"

gateway-clean:
	@echo "🧹 清理网关和所有项目..."
	@~/.https-toolkit/bin/https-deploy gateway clean
	@echo "✅ 清理完成"

# ============================================
# 开发/测试
# ============================================

dev: install gateway-init
	@echo ""
	@echo "🎉 开发环境就绪!"
	@echo ""
	@echo "下一步:"
	@echo "  1. 配置域名: make hosts"
	@echo "  2. 打开 Dashboard: make dashboard"
	@echo "  3. 部署项目: cd your-project && https-deploy up"

test: test-deps test-gateway test-endpoints
	@echo "✅ 所有测试通过"

test-deps:
	@echo "🔍 检查依赖..."
	@command -v docker >/dev/null 2>&1 || (echo "❌ Docker 未安装"; exit 1)
	@command -v jq >/dev/null 2>&1 || (echo "❌ jq 未安装"; exit 1)
	@command -v curl >/dev/null 2>&1 || (echo "❌ curl 未安装"; exit 1)
	@echo "✅ 依赖检查通过"

test-gateway:
	@echo "🔍 测试网关..."
	@docker ps | grep https-toolkit-gateway >/dev/null || (echo "❌ 网关未运行"; exit 1)
	@echo "✅ 网关运行正常"

test-endpoints:
	@echo "🔍 测试端点..."
	@curl -k -s https://localhost/health | grep -q "OK" || (echo "❌ 健康检查失败"; exit 1)
	@curl -k -s https://localhost/ | grep -q "HTTPS Gateway" || (echo "❌ Dashboard 失败"; exit 1)
	@echo "✅ 端点测试通过"

clean:
	@echo "🧹 清理临时文件..."
	@find . -name "*.tmp" -delete
	@find . -name ".DS_Store" -delete
	@rm -rf test-projects/
	@echo "✅ 清理完成"

# ============================================
# 快捷访问
# ============================================

dashboard:
	@echo "🌐 打开 Dashboard..."
	@open https://localhost/

hosts:
	@echo "📝 域名 local.yeanhua.asia 已通过 DNS 配置,无需修改 /etc/hosts"
	@echo "✅ 直接访问: https://local.yeanhua.asia"

# ============================================
# 工具信息
# ============================================

version:
	@~/.https-toolkit/bin/https-deploy version || echo "未安装,运行: make install"

doctor:
	@echo "🔍 检查环境..."
	@echo ""
	@echo "依赖检查:"
	@command -v docker >/dev/null 2>&1 && echo "  ✅ Docker" || echo "  ❌ Docker (未安装)"
	@command -v docker-compose >/dev/null 2>&1 && echo "  ✅ Docker Compose" || echo "  ⚠️  Docker Compose (可选)"
	@command -v jq >/dev/null 2>&1 && echo "  ✅ jq" || echo "  ❌ jq (make install-jq)"
	@command -v yq >/dev/null 2>&1 && echo "  ✅ yq" || echo "  ❌ yq (make install-yq)"
	@command -v curl >/dev/null 2>&1 && echo "  ✅ curl" || echo "  ❌ curl"
	@command -v mkcert >/dev/null 2>&1 && echo "  ✅ mkcert" || echo "  ❌ mkcert (必需: brew install mkcert)"
	@echo ""
	@echo "网关状态:"
	@docker ps | grep https-toolkit-gateway >/dev/null 2>&1 && echo "  ✅ 网关运行中" || echo "  ⏹️  网关未运行"
	@docker network ls | grep https-toolkit-network >/dev/null 2>&1 && echo "  ✅ 网络已创建" || echo "  ❌ 网络未创建"
	@echo ""
	@echo "安装状态:"
	@[ -d ~/.https-toolkit ] && echo "  ✅ 工具包已安装" || echo "  ❌ 工具包未安装 (运行: make install)"
	@[ -f ~/.https-toolkit/bin/https-deploy ] && echo "  ✅ CLI 工具可用" || echo "  ❌ CLI 工具不可用"
	@echo ""
	@echo "域名配置:"
	@echo "  ✅ local.yeanhua.asia (DNS 已配置)"
	@echo ""

# ============================================
# 调试命令
# ============================================

debug-nginx:
	@echo "📋 Nginx 配置:"
	@docker exec https-toolkit-gateway nginx -T

debug-logs:
	@echo "📋 完整日志:"
	@docker logs https-toolkit-gateway --tail 100

debug-network:
	@echo "📋 网络信息:"
	@docker network inspect https-toolkit-network | jq '.[0].Containers'

debug-mounts:
	@echo "📋 挂载信息:"
	@docker inspect https-toolkit-gateway | jq '.[0].Mounts'

# ============================================
# 示例项目
# ============================================

example-create:
	@echo "📝 创建示例项目..."
	@mkdir -p test-projects/hello-api
	@cd test-projects/hello-api && \
	cat > main.go <<'EOF' && \
	package main\n\
	import (\n\
	    "fmt"\n\
	    "net/http"\n\
	)\n\
	func main() {\n\
	    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {\n\
	        fmt.Fprint(w, "Hello from HTTPS Gateway!")\n\
	    })\n\
	    http.ListenAndServe(":8080", nil)\n\
	}\n\
	EOF\
	cat > Dockerfile <<'EOF'\n\
	FROM golang:1.21-alpine\n\
	WORKDIR /app\n\
	COPY . .\n\
	RUN go mod init hello-api && go build -o main .\n\
	CMD ["./main"]\n\
	EOF
	@echo "✅ 示例项目已创建: test-projects/hello-api"
	@echo ""
	@echo "部署示例:"
	@echo "  cd test-projects/hello-api"
	@echo "  https-deploy init"
	@echo "  https-deploy up"

# ============================================
# 快速命令别名
# ============================================

i: install
d: dev
s: gateway-status
l: gateway-list
c: gateway-clean
t: test
h: help
