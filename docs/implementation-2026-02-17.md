# HTTPS Toolkit 实现说明

## 核心结论

- 基于路径前缀的本地 HTTPS 反向代理，多项目共享 `https://local.yeanhua.asia`
- 两种部署模式：Docker 模式（`up`）和注册模式（`register`）
- Nginx location 块动态 include，热重载 ~50ms 零停机
- 健康检查：TCP 端口检测（`nc -z`）+ 可选 HTTP 路径检查

---

## 目录结构

```
https-toolkit/
├── bin/
│   └── https-deploy              # 主命令脚本（符号链接解析）
├── lib/
│   ├── utils.sh                  # 工具函数（颜色输出、依赖检查、健康检查）
│   ├── config.sh                 # 配置管理（YAML 读取/验证）
│   ├── gateway.sh                # 网关管理（Nginx、证书、容器）
│   └── project.sh                # 项目部署（Docker/注册、网关注册）
├── templates/
│   └── config.yaml               # 项目配置模板
├── docs/                         # 文档
├── install.sh                    # 安装脚本
├── Makefile                      # 快捷命令
└── README.md                     # 主文档
```

运行时数据：

```
~/.https-toolkit/
├── bin/https-deploy              # CLI 入口（/usr/local/bin 链接目标）
├── lib/                          # Shell 库（从源码同步）
├── templates/                    # 配置模板
└── gateway/                      # 运行时数据
    ├── nginx/
    │   ├── nginx.conf            # Nginx 主配置
    │   └── conf.d/
    │       ├── 00-default.conf   # 默认 server 块（Dashboard + SSL）
    │       └── projects/         # 各项目 location 配置（动态生成）
    ├── certs/local.yeanhua.asia/ # SSL 证书（mkcert）
    ├── registry/projects.json    # 项目注册表
    └── html/                     # Dashboard 静态页面
```

---

## 功能清单

### 网关管理

| 命令 | 功能 |
|------|------|
| `gateway init` | 初始化网关（目录、Nginx 配置、SSL 证书、Docker 网络、Dashboard、启动容器） |
| `gateway status` | 查看网关状态和已注册项目数 |
| `gateway list` | 列出所有注册项目 |
| `gateway logs [-f]` | 查看网关日志 |
| `gateway reload` | 热重载 Nginx 配置 |
| `gateway stop/restart` | 停止/重启网关 |
| `gateway clean` | 停止所有项目和网关，删除网络 |

### 项目部署

| 命令 | 功能 |
|------|------|
| `init` | 交互式生成 `config.yaml`（任意目录可执行） |
| `up [env]` | Docker 模式：构建镜像 + 启动容器 + 注册到网关（需 Dockerfile） |
| `register [env]` | 注册模式：仅注册已运行的宿主机服务（使用 `host.docker.internal`） |
| `unregister` | 仅从网关注销（不停止服务） |
| `down [env]` | 停止 Docker 容器并注销 |
| `restart [env]` | 重启项目 |
| `logs [-f]` | 查看项目日志 |
| `status` | 查看项目状态 |

### 路由管理

| 命令 | 功能 |
|------|------|
| `routes` | 显示所有路由表 |
| `test-route <path>` | 测试指定路由 |

---

## 关键实现细节

### 1. Nginx 配置架构

主配置 `00-default.conf` 包含一个 HTTPS server 块，通过 `include` 引入项目 location：

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name local.yeanhua.asia;

    ssl_certificate /etc/nginx/certs/local.yeanhua.asia/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/local.yeanhua.asia/privkey.pem;

    # Dashboard
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ =404;
    }

    # 项目路由（动态 include）
    include /etc/nginx/conf.d/projects/*.conf;
}
```

每个项目生成独立的 location 配置文件（非 server 块），例如 `projects/news.conf`：

```nginx
# 强制尾部斜杠
location = /news {
    return 301 /news/;
}

location /news/ {
    rewrite ^/news/?(.*)$ /$1 break;
    proxy_pass http://news:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

**设计要点**：
- 项目只生成 `location` 块，避免 `server_name` 优先级冲突
- 尾部斜杠重定向确保浏览器相对路径解析正确
- Dashboard 使用 `try_files $uri $uri/ =404`，不 catch-all 避免污染项目静态资源

### 2. 两种部署模式

```
Docker 模式 (up):
  项目 Dockerfile → docker-compose build → 容器启动 → 注册到网关
  backend_host = 容器名（Docker 网络内互通）

注册模式 (register):
  宿主机已运行服务 → 仅注册到网关
  backend_host = host.docker.internal（网关容器访问宿主机）
```

`project_register()` 的 `$6 backend_host` 参数控制上游地址：
- Docker 模式：默认使用 `$project_name`（容器名）
- 注册模式：传 `"host"` → 转换为 `host.docker.internal`

### 3. 健康检查策略

```bash
wait_for_service() {
    # 阶段 1: TCP 端口检测 (nc -z, 毫秒级)
    docker exec "$container" nc -z localhost "$port"

    # 阶段 2: 可选 HTTP 健康检查 (从 config.yaml 读取路径)
    if [ -n "$health_path" ]; then
        docker exec "$container" wget -qO /dev/null "http://localhost:$port$health_path"
    fi

    # 失败不阻断 → warn 而非 error
}
```

### 4. 注册表管理

```json
{
  "version": "1.0.0",
  "environment": "local",
  "projects": [
    {
      "name": "news",
      "path_prefix": "/news",
      "backend_port": 8080,
      "backend_host": "news",
      "strip_prefix": true,
      "status": "running",
      "registered_at": "2026-02-18T09:21:36Z",
      "updated_at": "2026-02-18T09:21:36Z"
    }
  ]
}
```

使用 `jq` 原子更新：`del` 旧记录 → 追加新记录 → `sort_by(.path_prefix)` → 写入临时文件 → `mv` 替换。

### 5. 热重载流程

```
project_register()
  → 生成 projects/{name}.conf (location 块)
  → nginx -t 测试 (失败则删除配置回滚)
  → jq 更新 registry/projects.json
  → nginx -s reload (~50ms, 零停机)
```

---

## 依赖

| 工具 | 用途 | 安装 |
|------|------|------|
| Docker | 运行容器 | `brew install docker` |
| Docker Compose | 编排容器 | Docker Desktop 自带 |
| mkcert | 本地 SSL 证书 | `brew install mkcert && mkcert -install` |
| jq | JSON 处理 | `brew install jq` |
| yq | YAML 处理 | `brew install yq` |

---

## 已知限制

1. **证书**: 仅支持 mkcert（本地开发），生产环境需 Let's Encrypt
2. **平台**: macOS/Linux，Windows 需 WSL2
3. **并发**: 注册表无文件锁（单用户场景足够）
4. **Docker Compose**: 使用 `docker-compose`（v1），部分环境需 `docker compose`（v2）
