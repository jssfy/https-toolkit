# HTTPS Toolkit 使用指南

## 核心结论

方案 A 采用 **独立工具包 + 项目轻量集成** 的模式:

- **工具包独立**: 作为独立仓库维护,类似 `create-react-app`
- **项目集成**: 通过安装脚本或包管理器集成到项目
- **配置文件**: 每个项目维护自己的 `config.yaml`
- **零侵入性**: 工具包文件不提交到项目仓库

---

## 方案对比

### 方案 1: 独立工具包仓库 (推荐)

```
https://github.com/your-org/https-toolkit  (工具包仓库)
    ↓ 安装/引用
你的项目 1 (top-ai-news)
你的项目 2 (another-app)
你的项目 3 (third-app)
```

**优势**:
- 工具包统一维护,所有项目自动受益
- 项目代码库干净,不包含工具代码
- 便于版本管理和升级

### 方案 2: 复制模板方式

```
每个项目独立复制一份工具代码
```

**劣势**:
- 工具升级需要手动同步到每个项目
- 项目代码库膨胀

---

## 详细使用流程

### 场景 1: 新项目快速集成

#### 步骤 1: 安装工具

```bash
# 方式 A: 通过安装脚本 (推荐)
cd my-new-project
curl -sSL https://toolkit.example.com/install.sh | bash

# 方式 B: 通过 npm/yarn (如果发布到 npm)
npm install -g @your-org/https-toolkit
# 或项目级安装
npm install --save-dev @your-org/https-toolkit

# 方式 C: 通过 Homebrew (Mac/Linux)
brew install your-org/tap/https-toolkit

# 方式 D: 直接下载二进制
curl -LO https://github.com/your-org/https-toolkit/releases/latest/download/https-deploy
chmod +x https-deploy
sudo mv https-deploy /usr/local/bin/
```

#### 步骤 2: 初始化配置

```bash
cd my-new-project

# 初始化(交互式)
https-deploy init

# 或使用默认配置
https-deploy init --defaults

# 或从模板创建
https-deploy init --template=golang
https-deploy init --template=nodejs
https-deploy init --template=python
```

**生成的文件结构**:
```
my-new-project/
├── config.yaml              # ✅ 提交到 Git(项目配置)
├── .env.example             # ✅ 提交到 Git(环境变量模板)
├── .env                     # ❌ 不提交(本地环境变量)
├── .gitignore               # ✅ 更新(添加工具生成的文件)
├── .https-toolkit/          # ❌ 不提交(工具生成,动态)
│   ├── output/              # 渲染后的配置
│   └── cache/               # 缓存文件
└── hooks/                   # ✅ 可选提交(自定义钩子)
    ├── pre-deploy.sh
    └── post-deploy.sh
```

#### 步骤 3: 自定义配置

```bash
# 编辑配置文件
vim config.yaml
```

```yaml
# config.yaml
project:
  name: my-new-project
  backend_port: 3000

domains:
  local: local.myapp.dev
  production: myapp.com

# ... 其他配置
```

#### 步骤 4: 一键启动

```bash
# 本地开发环境
https-deploy up local

# 访问
open https://local.myapp.dev
```

---

### 场景 2: 现有项目迁移

假设你有一个现有项目结构如下:

```
existing-project/
├── docker-compose.yml
├── nginx/
│   └── nginx.conf
├── scripts/
│   └── deploy.sh
└── src/
    └── ...
```

#### 步骤 1: 安装工具

```bash
cd existing-project
curl -sSL https://toolkit.example.com/install.sh | bash
```

#### 步骤 2: 自动迁移

```bash
# 自动分析现有配置并生成 config.yaml
https-deploy migrate

# 工具会扫描:
# - docker-compose.yml (提取端口、服务名)
# - nginx.conf (提取域名、SSL 配置)
# - .env (提取环境变量)
```

**迁移输出**:
```
Analyzing existing configuration...
  ✓ Detected backend port: 8080
  ✓ Detected domain: api.example.com
  ✓ Detected nginx config

Generated config.yaml with detected settings.
Please review and adjust:
  vim config.yaml

Next steps:
  1. Backup existing configs: https-deploy migrate --backup
  2. Test new setup: https-deploy up local
  3. If OK, remove old configs
```

#### 步骤 3: 对比验证

```bash
# 使用新配置启动(不影响现有部署)
https-deploy up local --dry-run

# 查看会生成哪些配置
ls .https-toolkit/output/

# 对比配置差异
diff nginx/nginx.conf .https-toolkit/output/nginx-local.conf
```

#### 步骤 4: 切换到新方式

```bash
# 备份旧配置
mkdir _old_configs
mv docker-compose.yml nginx/ scripts/ _old_configs/

# 使用新工具启动
https-deploy up local

# 验证无误后删除旧配置
rm -rf _old_configs/
```

---

### 场景 3: 团队协作

#### 团队成员 A (首次配置)

```bash
# 1. Clone 项目
git clone https://github.com/your-org/your-project
cd your-project

# 2. 安装工具
curl -sSL https://toolkit.example.com/install.sh | bash

# 3. 配置本地环境变量
cp .env.example .env
vim .env  # 填写个人凭证

# 4. 启动
https-deploy up local

# 首次运行会:
# - 自动安装 mkcert
# - 生成本地证书
# - 配置 /etc/hosts (需要 sudo 密码)
# - 启动服务
```

#### 团队成员 B (后续加入)

```bash
# 1. Clone 项目
git clone https://github.com/your-org/your-project
cd your-project

# 2. 安装工具(如果已全局安装可跳过)
which https-deploy || curl -sSL https://toolkit.example.com/install.sh | bash

# 3. 配置环境变量
cp .env.example .env

# 4. 直接启动
https-deploy up local
```

#### 项目配置管理

```bash
# 项目仓库中提交的内容:
your-project/
├── config.yaml           # ✅ 团队共享配置
├── .env.example          # ✅ 环境变量模板
├── .gitignore            # ✅ 忽略规则
│   ├── .env              # 忽略本地环境变量
│   └── .https-toolkit/   # 忽略工具生成的文件
└── README.md             # ✅ 项目文档

# 每个成员本地独立的内容:
├── .env                  # ❌ 个人凭证(不提交)
└── .https-toolkit/       # ❌ 工具生成(不提交)
    └── output/           # 渲染后的配置
```

---

### 场景 4: 多项目管理

假设你在本地同时开发多个项目:

```
~/projects/
├── project-a/  (Go, 端口 8080)
├── project-b/  (Node.js, 端口 3000)
└── project-c/  (Python, 端口 8000)
```

#### 方式 1: 独立端口部署

```bash
# 项目 A
cd ~/projects/project-a
https-deploy up local
# 访问: https://project-a.local:443

# 项目 B
cd ~/projects/project-b
https-deploy up local
# 访问: https://project-b.local:443

# 项目 C
cd ~/projects/project-c
https-deploy up local
# 访问: https://project-c.local:443
```

每个项目的 `config.yaml`:
```yaml
# project-a/config.yaml
domains:
  local: project-a.local

# project-b/config.yaml
domains:
  local: project-b.local

# project-c/config.yaml
domains:
  local: project-c.local
```

#### 方式 2: 路径路由部署(高级)

使用统一域名 + 路径区分:

```yaml
# project-a/config.yaml
domains:
  local: dev.local
routing:
  path_prefix: /api

# project-b/config.yaml
domains:
  local: dev.local
routing:
  path_prefix: /web

# project-c/config.yaml
domains:
  local: dev.local
routing:
  path_prefix: /admin
```

访问:
- https://dev.local/api → 项目 A
- https://dev.local/web → 项目 B
- https://dev.local/admin → 项目 C

#### 证书共享

所有项目可以共享泛域名证书:

```bash
# 生成一次泛域名证书
cd ~/projects/project-a
https-deploy cert generate local --wildcard
# 生成: ~/.local-certs/dev.local/*

# 其他项目自动复用
cd ~/projects/project-b
https-deploy up local  # 自动检测到证书已存在
```

---

## 工具包的分发与版本管理

### 方式 1: Shell 安装脚本 (最灵活)

```bash
# install.sh
#!/bin/bash
set -e

TOOLKIT_VERSION="${HTTPS_TOOLKIT_VERSION:-latest}"
INSTALL_DIR="${HTTPS_TOOLKIT_INSTALL_DIR:-$HOME/.https-toolkit}"
BIN_DIR="/usr/local/bin"

echo "Installing HTTPS Toolkit $TOOLKIT_VERSION..."

# 1. 下载工具包
mkdir -p "$INSTALL_DIR"
curl -sSL "https://github.com/your-org/https-toolkit/archive/refs/tags/$TOOLKIT_VERSION.tar.gz" \
    | tar xz -C "$INSTALL_DIR" --strip-components=1

# 2. 安装命令行工具
sudo ln -sf "$INSTALL_DIR/bin/https-deploy" "$BIN_DIR/https-deploy"
chmod +x "$BIN_DIR/https-deploy"

# 3. 安装依赖
if ! command -v yq &> /dev/null; then
    echo "Installing yq..."
    brew install yq || apt-get install yq || yum install yq
fi

echo "✓ HTTPS Toolkit installed successfully!"
echo ""
echo "Next steps:"
echo "  cd your-project"
echo "  https-deploy init"
```

**使用**:
```bash
# 安装最新版本
curl -sSL https://toolkit.example.com/install.sh | bash

# 安装指定版本
curl -sSL https://toolkit.example.com/install.sh | HTTPS_TOOLKIT_VERSION=v1.2.0 bash

# 更新到最新版本
curl -sSL https://toolkit.example.com/install.sh | bash
```

### 方式 2: npm 包 (适合 Node.js 生态)

```bash
# 发布到 npm
npm publish @your-org/https-toolkit

# 全局安装
npm install -g @your-org/https-toolkit

# 项目级安装
cd your-project
npm install --save-dev @your-org/https-toolkit

# 使用
npx https-deploy init
npx https-deploy up local
```

**package.json**:
```json
{
  "name": "@your-org/https-toolkit",
  "version": "1.0.0",
  "bin": {
    "https-deploy": "./bin/https-deploy"
  },
  "scripts": {
    "postinstall": "node scripts/setup.js"
  }
}
```

### 方式 3: Docker 镜像 (容器化)

```bash
# 构建镜像
docker build -t your-org/https-toolkit:latest .

# 使用(无需本地安装)
docker run --rm -v $(pwd):/workspace \
    -v /var/run/docker.sock:/var/run/docker.sock \
    your-org/https-toolkit:latest \
    https-deploy up local
```

### 方式 4: GitHub Releases (二进制分发)

```bash
# 下载预编译二进制
curl -LO https://github.com/your-org/https-toolkit/releases/latest/download/https-deploy-$(uname -s)-$(uname -m)
chmod +x https-deploy-*
sudo mv https-deploy-* /usr/local/bin/https-deploy

# 使用
https-deploy init
```

---

## 版本管理与升级

### 检查版本

```bash
# 查看当前版本
https-deploy version
# Output: HTTPS Toolkit v1.2.0

# 查看可用更新
https-deploy version --check-update
# Output: New version available: v1.3.0
#         Run 'https-deploy upgrade' to update
```

### 升级工具

```bash
# 升级到最新版本
https-deploy upgrade

# 升级到指定版本
https-deploy upgrade --version=v1.3.0

# 查看变更日志
https-deploy changelog
```

### 项目锁定版本

```yaml
# config.yaml
toolkit:
  version: "1.2.0"  # 锁定工具版本
  auto_upgrade: false  # 禁止自动升级
```

```bash
# 使用项目锁定的版本
https-deploy up local
# Warning: Current toolkit version (1.3.0) differs from project requirement (1.2.0)
# Run with locked version: https-deploy up local --use-project-version
```

---

## 配置文件管理

### 配置文件层级

```bash
# 优先级: 从高到低
1. 命令行参数:     https-deploy up local --port=3000
2. 环境变量:       BACKEND_PORT=3000 https-deploy up local
3. .env 文件:      .env
4. config.yaml:    config.yaml
5. 默认值:         内置默认配置
```

### 多环境配置

```bash
your-project/
├── config.yaml              # 基础配置
├── config.local.yaml        # 本地开发覆盖
├── config.staging.yaml      # 测试环境覆盖
└── config.production.yaml   # 生产环境覆盖
```

```bash
# 自动合并配置
https-deploy up local        # 使用 config.yaml + config.local.yaml
https-deploy up staging      # 使用 config.yaml + config.staging.yaml
https-deploy up production   # 使用 config.yaml + config.production.yaml
```

### 配置共享与继承

```yaml
# config.yaml (团队共享)
project:
  name: my-app
  backend_port: 8080

domains:
  local: local.myapp.dev
  production: myapp.com

# 所有环境通用的配置
nginx:
  ssl:
    protocols: TLSv1.2 TLSv1.3

# config.local.yaml (个人覆盖)
project:
  backend_port: 3000  # 覆盖: 个人喜欢用 3000 端口

domains:
  local: local.myname.dev  # 覆盖: 使用个人域名
```

---

## .gitignore 配置

```bash
# .gitignore (项目根目录)

# HTTPS Toolkit 生成的文件
.https-toolkit/
*.https-deploy.log

# 环境变量(包含敏感信息)
.env
.env.local
.env.*.local

# 本地证书(每个开发者独立生成)
certs/
*.pem
*.key

# 个人配置覆盖
config.local.yaml

# 日志文件
logs/
*.log
```

---

## 最佳实践

### 1. 项目结构建议

```bash
your-project/
├── config.yaml              # ✅ 提交(团队共享配置)
├── .env.example             # ✅ 提交(环境变量模板)
├── .gitignore               # ✅ 提交
├── README.md                # ✅ 提交(包含快速开始)
├── hooks/                   # ✅ 可选提交(自定义部署逻辑)
│   ├── pre-deploy.sh
│   └── post-deploy.sh
├── .env                     # ❌ 不提交(本地环境变量)
├── config.local.yaml        # ❌ 不提交(个人配置)
└── .https-toolkit/          # ❌ 不提交(工具生成)
```

### 2. README 模板

```markdown
# Your Project

## 快速开始

### 前置条件

- Docker & Docker Compose
- [HTTPS Toolkit](https://github.com/your-org/https-toolkit)

### 安装

```bash
# 1. Clone 项目
git clone https://github.com/your-org/your-project
cd your-project

# 2. 安装 HTTPS Toolkit
curl -sSL https://toolkit.example.com/install.sh | bash

# 3. 配置环境变量
cp .env.example .env
vim .env  # 填写必要的配置

# 4. 启动服务
https-deploy up local

# 5. 访问
open https://local.yourapp.dev
```

### 常用命令

```bash
# 启动/停止
https-deploy up local
https-deploy down local

# 查看日志
https-deploy logs

# 证书管理
https-deploy cert check
https-deploy cert renew
```

### 配置

项目配置文件: `config.yaml`

个人配置覆盖: `config.local.yaml` (不提交到 Git)
```

### 3. 环境变量模板

```bash
# .env.example
# HTTPS Toolkit 环境变量模板
# 复制此文件为 .env 并填写实际值

# ========================================
# 项目配置
# ========================================
BACKEND_PORT=8080

# ========================================
# DNS API 凭证(用于 Let's Encrypt DNS-01)
# ========================================
# 阿里云
ALIYUN_ACCESS_KEY_ID=your_access_key_id
ALIYUN_ACCESS_KEY_SECRET=your_access_key_secret

# Cloudflare
# CLOUDFLARE_API_TOKEN=your_api_token

# ========================================
# 数据库(示例)
# ========================================
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myapp
DB_USER=postgres
DB_PASSWORD=password
```

---

## 故障排查

### 问题 1: 工具未找到

```bash
$ https-deploy init
bash: https-deploy: command not found

# 解决:
# 1. 检查安装
which https-deploy

# 2. 重新安装
curl -sSL https://toolkit.example.com/install.sh | bash

# 3. 检查 PATH
echo $PATH | grep /usr/local/bin
```

### 问题 2: 配置渲染失败

```bash
$ https-deploy up local
Error: Failed to parse config.yaml

# 解决:
# 1. 验证 YAML 语法
https-deploy config validate

# 2. 查看详细错误
https-deploy up local --debug

# 3. 使用默认配置重新初始化
mv config.yaml config.yaml.bak
https-deploy init
```

### 问题 3: 证书生成失败

```bash
$ https-deploy up local
Error: Certificate generation failed

# 解决:
# 1. 检查 mkcert 是否安装
which mkcert

# 2. 安装 mkcert
brew install mkcert

# 3. 手动生成证书
https-deploy cert generate local --verbose
```

### 问题 4: 端口冲突

```bash
$ https-deploy up local
Error: Port 443 is already in use

# 解决:
# 1. 查看占用进程
lsof -i :443

# 2. 停止冲突服务
https-deploy down local  # 如果是其他项目

# 3. 修改端口
vim config.yaml
# 将 443 改为 8443
```

---

## 与 CI/CD 集成

### GitHub Actions

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
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Install HTTPS Toolkit
        run: |
          curl -sSL https://toolkit.example.com/install.sh | bash

      - name: Deploy to production
        env:
          ALIYUN_ACCESS_KEY_ID: ${{ secrets.ALIYUN_ACCESS_KEY_ID }}
          ALIYUN_ACCESS_KEY_SECRET: ${{ secrets.ALIYUN_ACCESS_KEY_SECRET }}
        run: |
          https-deploy up production --non-interactive
```

### GitLab CI

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y curl
    - curl -sSL https://toolkit.example.com/install.sh | bash
  script:
    - https-deploy up production
  only:
    - main
```

---

## 总结

### 工具包使用流程

```
1. 安装工具包(一次性)
   curl -sSL https://toolkit.example.com/install.sh | bash

2. 初始化项目配置
   cd your-project
   https-deploy init

3. 自定义配置
   vim config.yaml

4. 启动服务
   https-deploy up local

5. 后续使用
   git clone your-project
   https-deploy up local  # 开箱即用
```

### 关键特性

- ✅ **独立工具包**: 所有项目共享同一套工具,统一维护
- ✅ **轻量集成**: 项目只需维护 `config.yaml`,无需包含工具代码
- ✅ **版本管理**: 支持工具版本升级和锁定
- ✅ **多项目支持**: 可同时管理多个项目
- ✅ **团队协作**: 配置共享,环境变量隔离
- ✅ **CI/CD 友好**: 一条命令完成部署

### 与其他方案对比

| 特性 | 方案 A(独立工具包) | 复制模板方式 | 手动配置 |
|------|------------------|-------------|---------|
| **工具升级** | 一次升级,所有项目受益 | 每个项目手动升级 | N/A |
| **代码库大小** | 轻量(只有 config.yaml) | 每个项目都包含工具代码 | 中等 |
| **维护成本** | 低 | 高 | 极高 |
| **上手难度** | 低(一条命令) | 中等 | 高 |
| **灵活性** | 高(支持钩子和模板) | 高 | 极高 |
