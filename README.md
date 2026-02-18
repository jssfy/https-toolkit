# HTTPS Toolkit

基于路径前缀的 HTTPS 开发网关。多项目共享一个域名，通过路径前缀路由到不同后端服务。支持本地开发（mkcert）和公网部署（Let's Encrypt）。

## 核心特性

- **路径前缀路由** — 所有项目共享同一域名，通过 `/api`、`/web`、`/admin` 等路径区分
- **动态注册** — `https-deploy up` 自动注册，`https-deploy down` 自动注销
- **零停机** — Nginx 热重载 (~50ms)，不影响现有连接
- **可视化 Dashboard** — 浏览器访问根路径查看所有项目
- **三种证书模式** — mkcert（本地开发）、Let's Encrypt 单域名、Let's Encrypt 泛域名
- **DNS 预配置** — `local.yeanhua.asia` 已通过 DNS 解析到本地，无需修改 `/etc/hosts`

## 快速开始

```bash
# 1. 安装
cd https-toolkit
chmod +x install.sh && ./install.sh

# 2. 初始化网关（本地开发，默认 mkcert）
https-deploy gateway init

# 3. 打开 Dashboard
open https://local.yeanhua.asia
```

### 公网部署（Let's Encrypt）

```bash
# 单域名（HTTP-01 验证，需要 80 端口可从公网访问）
https-deploy gateway init --cert-mode letsencrypt --domain data.yeanhua.asia --email you@example.com

# 泛域名（DNS-01 验证，通过阿里云 DNS API，首次需输入 AccessKey）
https-deploy gateway init --cert-mode letsencrypt-wildcard --domain yeanhua.asia --email you@example.com
```

### 切换证书模式

gateway 已运行时可直接切换模式，init 自动处理配置更新和 nginx reload：

```bash
# 从 mkcert 切换到泛域名（网关不中断，nginx 热重载）
https-deploy gateway init --cert-mode letsencrypt-wildcard --domain yeanhua.asia --email you@example.com
https-deploy gateway init --cert-mode letsencrypt-wildcard --domain yeanhua.asia --email kidd_4@163.com

# 切回本地开发模式
https-deploy gateway init --cert-mode mkcert

# 查看当前模式
https-deploy gateway status
```

> init 是幂等的：已有证书不会重新签发，已运行的 gateway 执行 `nginx -s reload` 而非重建容器。

用内置 demo 项目验证：

```bash
cd https-toolkit/demo
https-deploy up          # 构建 + 启动 + 注册（config.yaml 已预置）
open https://local.yeanhua.asia/demo/
```

或部署你自己的项目：

```bash
cd your-project          # 进入项目根目录（需要有 Dockerfile）
https-deploy init        # 交互式配置（项目名、端口、路径前缀）→ 生成 config.yaml
https-deploy up          # 构建镜像、启动容器、注册到网关
```

## 使用示例

```bash
# 部署 API 服务到 /api
cd ~/projects/api-service
https-deploy init        # path_prefix: /api, backend_port: 8080
https-deploy up
# → https://local.yeanhua.asia/api/

# 部署 Web 前端到 /web
cd ~/projects/web-frontend
https-deploy init        # path_prefix: /web, backend_port: 3000
https-deploy up
# → https://local.yeanhua.asia/web/

# 多项目并发运行，互不干扰
# https://local.yeanhua.asia/api/     → api-service:8080
# https://local.yeanhua.asia/web/     → web-frontend:3000
# https://local.yeanhua.asia/admin/   → admin-panel:8000
```

## 命令参考

### 网关管理

```bash
https-deploy gateway init [options]  # 初始化网关
  --cert-mode <mode>                 #   mkcert (默认) | letsencrypt | letsencrypt-wildcard
  --domain <domain>                  #   域名（各模式有默认值）
  --email <email>                    #   Let's Encrypt 注册邮箱
https-deploy gateway status          # 查看网关状态
https-deploy gateway list            # 列出所有已注册项目
https-deploy gateway logs            # 查看网关日志
https-deploy gateway reload          # 热重载 Nginx 配置
https-deploy gateway renew           # 续期 Let's Encrypt 证书
https-deploy gateway clean           # 停止网关并清理所有项目
```

### 项目部署

```bash
https-deploy init              # 生成 config.yaml（交互式）
https-deploy up                # Docker 模式: 构建镜像 + 启动容器 + 注册（需要 Dockerfile）
https-deploy register          # 注册模式: 只注册已有服务（go run / npm start 等）
https-deploy unregister        # 仅从网关注销（不停止服务）
https-deploy down              # 停止 Docker 容器并注销
https-deploy restart           # 重启项目
https-deploy logs [-f]         # 查看项目日志
https-deploy status            # 查看项目状态
```

**两种部署方式**：

```bash
# 方式 1: Docker 模式 — 项目有 Dockerfile，由工具构建和管理
https-deploy init && https-deploy up

# 方式 2: 注册模式 — 服务已在宿主机运行，只需网关代理
go run main.go &               # 自己启动服务
https-deploy init && https-deploy register   # 注册到网关
```

### 路由调试

```bash
https-deploy routes                  # 查看所有路由表
https-deploy test-route /api/health  # 测试指定路由
```

### Make 快捷命令

```bash
make dev              # 一键安装 + 初始化网关
make gateway-status   # 查看网关状态
make gateway-list     # 列出项目
make gateway-logs     # 查看日志
make test             # 运行测试
make doctor           # 检查依赖和环境
make dashboard        # 浏览器打开 Dashboard
```

## 配置文件

每个项目根目录的 `config.yaml`：

```yaml
project:
  name: my-project              # 项目名称（Docker 容器名）
  backend_port: 8080            # 后端服务端口

routing:
  path_prefix: /api             # URL 路径前缀
  strip_prefix: true            # 转发时去除前缀
  # https://local.yeanhua.asia/api/users → http://my-project:8080/users

domains:
  local: local.yeanhua.asia

gateway:
  enabled: true
```

## 证书模式

### 模式对比

| 模式 | 用途 | 验证方式 | 默认域名 | 依赖 |
|------|------|---------|---------|------|
| `mkcert` | 本地开发 | 本地 CA | `local.yeanhua.asia` | mkcert |
| `letsencrypt` | 公网单域名 | HTTP-01 | `data.yeanhua.asia` | Docker + 80 端口 |
| `letsencrypt-wildcard` | 公网泛域名 | DNS-01 | `*.yeanhua.asia` | Docker + 阿里云 AccessKey |

### 泛域名模式：阿里云 DNS 配置

泛域名证书使用 DNS-01 验证，需要阿里云 DNS API 的 AccessKey 来自动创建 TXT 记录。

**1. 获取 AccessKey**

登录 [阿里云 RAM 访问控制](https://ram.console.aliyun.com/manage/ak)，创建 AccessKey 并记录 `AccessKey ID` 和 `AccessKey Secret`。

> 建议创建 RAM 子账号并仅授权 `AliyunDNSFullAccess` 权限，避免使用主账号 AK。

**2. 首次签发**

```bash
https-deploy gateway init --cert-mode letsencrypt-wildcard --domain yeanhua.asia --email you@example.com
```

首次运行会交互提示输入：

```
Ali_Key: <你的 AccessKey ID>
Ali_Secret: <你的 AccessKey Secret>
```

acme.sh 会通过阿里云 DNS API 自动添加 `_acme-challenge.yeanhua.asia` TXT 记录完成验证。

**3. 凭据自动持久化**

输入一次后，acme.sh 自动保存到 `~/.https-toolkit/gateway/acme/account.conf`：

```
SAVED_Ali_Key='LTAI5t...'
SAVED_Ali_Secret='Gkj8...'
```

后续操作（重新签发、续期）自动读取，无需再次输入。

**4. 证书续期**

```bash
https-deploy gateway renew   # 检查并续期即将过期的证书
```

续期使用保存的凭据自动完成，gateway 会自动重启加载新证书。

## 架构

```
            https://<domain>
                       ↓
               HTTPS Gateway (Nginx)
           证书: mkcert / Let's Encrypt
                       ↓
             路径前缀路由分发:
             /api    → api-service:8080
             /web    → web-frontend:3000
             /admin  → admin-panel:8000
```

### 部署流程

```
https-deploy init (任意目录)
  → 复制模板 → 交互式填写 → 生成 config.yaml

https-deploy up (项目根目录，需要 Dockerfile + config.yaml)
  → 检查网关运行状态
  → 验证 config.yaml (project.name / backend_port / path_prefix)
  → docker-compose up --build (构建镜像、启动容器)
  → 生成 Nginx location 配置
  → 注册到项目注册表
  → nginx -s reload (~50ms, 零停机)
  → 完成
```

## 目录结构

```
~/.https-toolkit/
├── bin/https-deploy              # CLI 入口
├── lib/                          # Shell 库
│   ├── gateway.sh                # 网关管理
│   ├── project.sh                # 项目部署
│   ├── config.sh                 # 配置管理
│   └── utils.sh                  # 工具函数
├── templates/config.yaml         # 项目配置模板
└── gateway/                      # 运行时数据
    ├── gateway.conf              # 网关配置（cert-mode, domain, email）
    ├── acme/                     # acme.sh 数据（证书内部数据 + 凭据）
    ├── nginx/conf.d/projects/    # 各项目 Nginx 配置（动态生成）
    ├── certs/                    # SSL 证书（mkcert 或 Let's Encrypt）
    ├── registry/projects.json    # 项目注册表
    └── html/                     # Dashboard 静态页面
```

## 依赖

| 工具 | 用途 | 安装 | 必需 |
|------|------|------|------|
| Docker | 运行容器 | `brew install docker` | 所有模式 |
| mkcert | 本地 SSL 证书 | `brew install mkcert && mkcert -install` | 仅 mkcert 模式 |
| jq | JSON 处理 | `brew install jq` | 所有模式 |
| yq | YAML 处理 | `brew install yq` | 所有模式 |
| acme.sh | Let's Encrypt 客户端 | 自动通过 Docker 拉取 (`neilpang/acme.sh`) | 仅 LE 模式 |

## 故障排查

| 问题 | 解决方案 |
|------|---------|
| Gateway is not running | `https-deploy gateway init` |
| Port already in use | 修改 `config.yaml` 中的 `backend_port`，或 `docker stop <container>` |
| Path prefix already in use | `https-deploy gateway list` 查看冲突，修改 `path_prefix` |
| mkcert not found | `brew install mkcert && mkcert -install` |
| 浏览器显示「不安全」(mkcert) | 见下方 [证书信任](#证书信任mkcert-模式) |
| LE HTTP-01 验证失败 (403) | 确认域名 DNS 指向本机公网 IP，且 80 端口可从外网访问 |
| LE DNS-01 验证失败 | 检查 Ali_Key/Ali_Secret 是否正确，RAM 账号需有 `AliyunDNSFullAccess` 权限 |
| 续期失败 | `https-deploy gateway renew`；HTTP-01 模式会自动停 gateway 释放 80 端口 |

### 证书信任（mkcert 模式）

`gateway init` 使用 mkcert 生成本地 CA 和站点证书。如果浏览器仍显示「不安全」：

**Chrome / Safari** — 使用系统钥匙串，运行 `mkcert -install` 后**重启浏览器**即可。

**Firefox** — 使用独立证书存储，不读系统钥匙串，需额外处理：

```bash
brew install nss          # 提供 certutil，让 mkcert 能写入 Firefox 证书库
mkcert -install           # 自动导入到系统钥匙串 + Firefox
```

或手动导入：Firefox → 设置 → 搜索「证书」→ 查看证书 → 证书颁发机构 → 导入 → 选择 `$(mkcert -CAROOT)/rootCA.pem` → 勾选「信任此 CA 以标识网站」。

> **为什么需要重启浏览器？** 浏览器启动时从系统钥匙串加载受信任 CA 列表并缓存到进程内存。`mkcert -install` 写入钥匙串后，已运行的浏览器进程仍持有旧的缓存副本，必须重启才能重新加载。

> **Let's Encrypt 模式无需此步骤** — LE 证书由公共 CA 签发，所有浏览器原生信任。

## 许可证

MIT License
