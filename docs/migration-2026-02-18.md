# HTTPS Toolkit 迁移与修复记录

**日期**: 2026-02-18

## 核心结论

- https-toolkit 从 top-ai-news 项目独立，迁移到独立目录维护
- 域名从 `dev.local` 切换为 `local.yeanhua.asia`（DNS 预配置，无需 `/etc/hosts`）
- 新增 `register` / `unregister` 命令，支持非 Docker 服务注册
- 修复了 12 个影响可用性的 bug，当前所有端点验证通过

---

## 一、项目迁移

### 目录变更

```
# 旧位置
/Users/yeanhua/workspace/playground/claude/top-ai-news/https-toolkit

# 新位置（独立项目）
/Users/yeanhua/workspace/playground/claude/https-toolkit
```

### 安装方式

```bash
# 源码 → 安装目录
./install.sh    # 同步 bin/ lib/ templates/ 到 ~/.https-toolkit/
```

安装后 `/usr/local/bin/https-deploy` 是指向 `~/.https-toolkit/bin/https-deploy` 的符号链接。

---

## 二、域名切换

`dev.local` → `local.yeanhua.asia`

### 变更范围

| 文件 | 变更 |
|------|------|
| `lib/gateway.sh` | `GATEWAY_DOMAIN` 常量 |
| `templates/config.yaml` | 域名配置和注释示例 |
| `install.sh` | 移除 `/etc/hosts` 步骤 |
| `Makefile` | `make hosts` / `make doctor` |
| `README.md` | 全文替换 |
| `QUICK_START.md` | 全文替换 |
| `IMPLEMENTATION.md` | 全文替换 |

### 关键变化

- `/etc/hosts` 不再需要 — `local.yeanhua.asia` 通过 DNS 解析到 127.0.0.1
- 证书目录变为 `~/.https-toolkit/gateway/certs/local.yeanhua.asia/`
- Nginx `server_name` 变为 `local.yeanhua.asia`

---

## 三、Bug 修复

### Fix 1: 符号链接路径解析失败

**现象**: `https-deploy` 报 `No such file or directory: /usr/local/lib/utils.sh`

**原因**: `/usr/local/bin/https-deploy` 是符号链接，`BASH_SOURCE[0]` 返回链接本身路径而非目标路径，导致 `TOOLKIT_ROOT` 解析为 `/usr/local/`。

**修复** (`bin/https-deploy`):
```bash
# 修改前
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 修改后 — 循环解析符号链接
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
```

### Fix 2: install.sh 不更新已安装文件

**现象**: `make install` 后安装目录仍是旧代码。

**原因**: 已安装时只尝试 `git pull`，安装目录不是 git 仓库，pull 失败后静默跳过。

**修复** (`install.sh`): 改为每次从源码目录 `cp -r` 同步 `bin/` `lib/` `templates/`，保留 `gateway/` 运行时数据不覆盖。

### Fix 3: mkcert 证书重命名失败

**现象**: Nginx 启动报 `cannot load certificate fullchain.pem: No such file`，容器反复重启。

**原因**: glob `${DOMAIN}+*.pem` 同时匹配 cert 和 key 两个文件，`mv` 多文件到单文件目标失败。

**修复** (`lib/gateway.sh`): 调换重命名顺序，先 key 后 cert：
```bash
# 修改前（glob 冲突）
mv ${GATEWAY_DOMAIN}+*.pem fullchain.pem
mv ${GATEWAY_DOMAIN}+*-key.pem privkey.pem

# 修改后（先移走 key，剩余文件不再冲突）
mv ${GATEWAY_DOMAIN}+*-key.pem privkey.pem
mv ${GATEWAY_DOMAIN}+*.pem fullchain.pem
```

### Fix 4: Nginx http2 指令废弃

**现象**: 日志警告 `the "listen ... http2" directive is deprecated`。

**修复** (`lib/gateway.sh`):
```nginx
# 修改前
listen 443 ssl http2;

# 修改后
listen 443 ssl;
http2 on;
```

### Fix 5: Dashboard 返回 404

**现象**: `https://local.yeanhua.asia/` 返回 404。

**原因**: `location = /` 精确匹配，`index` 指令内部重定向到 `/index.html` 后无 location 能匹配。

**修复** (`lib/gateway.sh`):
```nginx
# 修改前
location = / {
    root /usr/share/nginx/html;
    index index.html;
}

# 修改后
location / {
    root /usr/share/nginx/html;
    index index.html;
    try_files $uri $uri/ /index.html;
}
```

### Fix 6: Registry API 返回 404

**现象**: `/_gateway/registry/projects.json` 在容器内访问 404。

**原因**: Dashboard 生成时用宿主机绝对路径创建符号链接，Docker 容器内无法解析。

**修复** (`lib/gateway.sh`): 给容器添加 registry 目录的 volume 挂载：
```bash
docker run -d \
    ...
    -v "$GATEWAY_ROOT/html:/usr/share/nginx/html:ro" \
    -v "$GATEWAY_ROOT/registry:/usr/share/nginx/html/_gateway/registry:ro" \
    ...
```

### Fix 7: Docker build context 路径错误

**现象**: `https-deploy up` 报 `Dockerfile: no such file or directory`。

**原因**: docker-compose 的 `context: .` 相对于 compose 文件所在目录 (`.https-toolkit/output/`)，而非项目根目录。

**修复** (`lib/project.sh`): 使用项目根目录绝对路径：
```yaml
# 修改前
context: .

# 修改后
context: /absolute/path/to/project  # $(pwd)
```

### Fix 8: 健康检查超时阻塞部署

**现象**: `https-deploy up` 在 `Waiting for service to be ready...` 处卡住 30+ 秒。

**原因**: 硬编码 `curl /health`，容器内无 curl 且项目不一定有 `/health` 端点。

**修复** (`lib/utils.sh`):
- TCP 端口检测优先（`nc -z`，毫秒级）
- 健康检查路径从 `config.yaml` 读取，可选
- 健康检查失败不阻断注册（warn 代替 error + return 1）

```bash
# 策略: 先 TCP 端口检测（快），再可选健康检查路径
wait_for_service() {
    # 阶段 1: nc -z 检测端口（毫秒级）
    # 阶段 2: 可选 wget 健康检查（失败不阻断）
}
```

### Fix 9: 项目页面显示 Dashboard 内容

**现象**: 访问 `https://local.yeanhua.asia/news/` 返回 Dashboard 页面而非项目内容。

**原因**: 项目 Nginx 配置生成独立 `server { server_name _; }` 块，但主配置有精确匹配 `server_name local.yeanhua.asia`，Nginx 始终优先选择精确匹配 → 所有请求走 Dashboard。

**修复** (`lib/project.sh` + `lib/gateway.sh`):
- 项目配置改为仅生成 `location` 块（非独立 `server` 块）
- 主配置通过 `include /etc/nginx/conf.d/projects/*.conf` 在 HTTPS server 块内引入

```nginx
# 修改前 — 独立 server 块（被主配置覆盖）
server {
    listen 443 ssl;
    server_name _;
    location /news { ... }
}

# 修改后 — location 块，由主 server include
location /news/ {
    proxy_pass http://news:8080;
    ...
}
```

### Fix 10: 项目静态资源加载失败

**现象**: 访问 `https://local.yeanhua.asia/news/` 页面样式/脚本全部失效。

**原因**: 两个问题叠加：
1. `/news`（无尾部斜杠）→ 浏览器将相对路径 `style.css` 解析为 `/style.css` 而非 `/news/style.css`
2. Dashboard 的 `try_files $uri $uri/ /index.html` 对任意不存在路径返回 Dashboard HTML → `/style.css` 返回 200 但内容是 HTML

**修复**:

(`lib/project.sh`) 强制尾部斜杠重定向：
```nginx
# 精确匹配无斜杠路径 → 301 重定向
location = /news {
    return 301 /news/;
}

# 带斜杠前缀匹配
location /news/ {
    ...
}
```

(`lib/gateway.sh`) Dashboard 不再 catch-all：
```nginx
# 修改前 — 任意路径返回 index.html
try_files $uri $uri/ /index.html;

# 修改后 — 未匹配路径返回 404
try_files $uri $uri/ =404;
```

---

## 四、新增功能

### `register` / `unregister` 命令

用于已在宿主机运行的服务（`go run`、`npm start` 等），无需 Docker：

```bash
# 启动服务后，仅注册到网关
go run main.go &
https-deploy register

# 从网关注销（不停止服务）
https-deploy unregister
```

**实现**: `project_register()` 新增 `$6 backend_host` 参数，`register` 模式传 `host`（→ `host.docker.internal`），`up` 模式使用容器名。

---

## 五、证书信任

### 现象

`gateway init` 生成证书后，浏览器仍显示「不安全」/ 证书警告。

### 原因

mkcert 通过 `mkcert -install` 将自签 CA 根证书写入 macOS 系统钥匙串（`/Library/Keychains/System.keychain`）。但**浏览器在启动时加载系统钥匙串中的受信任 CA 列表并缓存到进程内存**，运行期间不会重新读取。因此 `mkcert -install` 执行后，已运行的浏览器进程仍持有旧的缓存副本。

此外，Firefox 使用独立的 NSS 证书存储（`cert9.db`），完全不读系统钥匙串，需要单独导入。

### 解决方案

**Chrome / Safari**：

```bash
mkcert -install   # 写入系统钥匙串（如已执行可跳过）
# 重启浏览器 — 使进程重新加载钥匙串
```

**Firefox**：

```bash
brew install nss      # 提供 certutil，让 mkcert 能写入 Firefox 的 NSS 证书库
mkcert -install       # 自动导入到系统钥匙串 + Firefox cert9.db
# 重启 Firefox
```

或手动导入：Firefox → 设置 → 搜索「证书」→ 查看证书 → 证书颁发机构 → 导入 → 选择 `$(mkcert -CAROOT)/rootCA.pem` → 勾选「信任此 CA 以标识网站」。

### 验证

```bash
# 系统钥匙串中存在 mkcert CA
security find-certificate -c "mkcert" /Library/Keychains/System.keychain

# 证书链验证通过
openssl verify -CAfile "$(mkcert -CAROOT)/rootCA.pem" \
  ~/.https-toolkit/gateway/certs/local.yeanhua.asia/fullchain.pem
```

---

## 六、验证结果

| 测试项 | 结果 |
|--------|------|
| `https-deploy version` | v1.0.0 |
| 容器状态 | Up, 端口 80/443 |
| `https://local.yeanhua.asia/health` | OK |
| `https://local.yeanhua.asia/` (Dashboard) | HTTP 200 |
| `/_gateway/registry/projects.json` | JSON 正常 |
| HTTP → HTTPS 重定向 | 301 |
| `https-deploy gateway status` | 正常 |
| `https-deploy gateway list` | 正常 |
| `/news` → `/news/` 重定向 | 301 |
| `/news/` 返回项目页面 | HTTP 200, text/html |
| `/news/style.css` 返回 CSS | HTTP 200, 实际 CSS 内容 |
| `/style.css`（根级别）| HTTP 404 |
| `https-deploy register` (host 模式) | 注册成功 |
| `https-deploy up` (Docker 模式) | 构建+启动+注册成功 |
