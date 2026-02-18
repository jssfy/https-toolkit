# Issues & Fixes 记录

## 核心结论

本次部署和测试中遇到 5 个问题，均已修复，1 个已知行为待评估。根因集中在三个方面：跨平台兼容性（macOS vs Linux）、gateway init 的状态管理、以及 Nginx 默认域名匹配行为。

---

## Issue #1: gateway init 后残留项目配置导致 nginx 启动失败

**现象**: `gateway clean && gateway init` 后 gateway 容器持续 Restarting

**日志**:
```
[emerg] host not found in upstream "my-api" in /etc/nginx/conf.d/projects/my-api.conf:12
```

**根因**: `gateway clean` 停止了项目容器并删除了网络，但没有清理 `nginx/conf.d/projects/` 下的项目配置文件。nginx 启动时 resolve upstream 失败。

**修复**: 在 `gateway_clean()` 中停止网关之前，先清理项目 nginx 配置：
```bash
rm -f "$GATEWAY_ROOT/nginx/conf.d/projects/"*.conf
```

**状态**: 已修复

---

## Issue #2: 重复 init 时 gateway 使用旧配置

**现象**: 从 mkcert 切换到 letsencrypt-wildcard 后，`gateway status` 显示新配置，但实际 nginx 仍服务旧的 `server_name` 和证书

**根因**: `gateway_start()` 检测到容器已运行直接 return，没有 reload nginx

**修复**: `gateway_init()` 末尾改为条件判断：
```bash
# 修改前
gateway_start "$env"

# 修改后
if check_container "$GATEWAY_NAME"; then
    docker exec "$GATEWAY_NAME" nginx -s reload
else
    gateway_start "$env"
fi
```

**状态**: 已修复

---

## Issue #3: `docker-compose` 命令在 Linux 服务器不存在

**现象**: `https-deploy up` 失败
```
/root/.https-toolkit/lib/project.sh: line 126: docker-compose: command not found
```

**根因**: 新版 Docker 的 Compose 是插件模式（`docker compose`，无连字符），不再提供独立的 `docker-compose` 二进制。`project.sh` 硬编码了旧命令。

**修复**: 在 `project.sh` 顶部新增兼容函数，所有调用点（3 处）统一替换：
```bash
docker_compose() {
    if docker compose version &> /dev/null; then
        docker compose "$@"
    else
        docker-compose "$@"
    fi
}
```

**状态**: 已修复

---

## Issue #4: Linux 服务器缺少 yq 依赖

**现象**: `./install.sh` 失败
```
[WARN] yq not found
[ERROR] Missing dependencies. Please install them first.
```

**根因**: `install.sh` 依赖检查发现 yq 缺失，但 Linux 上没有 brew，也没有 apt/yum 包可用（yq 不在标准仓库中）。

**修复**: Makefile 新增 `make deps` / `make install-yq` target，自动检测 OS 和架构下载对应二进制：
```bash
make deps    # 一键安装 jq + yq
```

**状态**: 已修复

---

## Issue #5: Dashboard 加载 projects.json 返回 403

**现象**: 浏览器访问 `https://data.yeanhua.asia/` Dashboard 页面加载了，但注册的项目不显示。`/_gateway/registry/projects.json` 返回 403。

**排查**:
```bash
docker exec https-toolkit-gateway ls -la /usr/share/nginx/html/_gateway/registry/
# -rw-------  root root  projects.json    ← 权限 600，只有 root 可读
```

**根因**: `project_register()` 中 `mktemp` 创建临时文件后 `mv` 到 `registry_file`。Linux 上 root 用户的 umask 通常为 077，导致 `mktemp` 创建的文件权限为 600。`mv` 保留了原权限。nginx 容器内以 UID 101 运行，无权读取。

**修复**: 在 `mv` 后添加 `chmod 644`（注册和注销两处）：
```bash
mv "$tmp_file" "$registry_file"
chmod 644 "$registry_file"
```

**状态**: 已修复

**临时修复（服务器上立即生效）**:
```bash
chmod 644 ~/.https-toolkit/gateway/registry/projects.json
```

---

## Issue #6: Gateway 响应所有解析到本机的域名（已知行为）

**现象**: 任意域名（只要 DNS 解析到 gateway 所在服务器 IP）访问 443 端口，gateway 均正常响应，不限于配置的目标域名。

```bash
# 用 IP 直接访问，伪造 Host 头，也能拿到正常响应
curl -sk https://121.41.107.93/health -H "Host: anything.example.com"
# OK
```

**根因**: Nginx `00-default.conf` 中的 server 块没有使用 `default_server` 指令，也没有兜底 server 块。当只有一个 server 块时，Nginx 的行为是：**任何未匹配到其他 server_name 的请求都由第一个 server 块处理**（即使 Host 不在 `server_name` 列表中）。

当前配置：
```nginx
server {
    listen 443 ssl;
    server_name yeanhua.asia *.yeanhua.asia;  # 只配了目标域名
    ...
}
# 没有其他 server 块 → 所有请求都走这个
```

**影响**:
- **安全**: 非目标域名的请求也会被代理转发到后端服务
- **实际**: 在阿里云等有 ICP 备案管控的环境中，未备案域名会被运营商在 TLS SNI 层面直接 reset 连接，所以实际影响有限
- **合规**: 如果服务器不在有 ICP 管控的环境中（如海外），任意域名都能访问到服务

**可选修复**: 添加 `default_server` 块拒绝非目标域名的请求：

```nginx
# 在 00-default.conf 中新增（放在目标 server 块之前）
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/certs/<domain>/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/<domain>/privkey.pem;
    return 444;  # 直接关闭连接，不返回任何内容
}
```

> 注意：`default_server` 块也需要有效的 SSL 证书，因为 TLS 握手在 HTTP 路由之前。可以复用目标域名的证书。

**状态**: 已知行为，当前未修复（在 ICP 管控环境下影响可控），可根据需要添加 `default_server` 块

---

## 修复文件汇总

| 文件 | Issue | 改动 |
|------|-------|------|
| `lib/gateway.sh` | #2 | init 末尾：已运行时 reload 而非跳过 |
| `lib/project.sh` | #3 | 新增 `docker_compose()` 兼容函数 |
| `lib/project.sh` | #5 | `mv` 后 `chmod 644`（注册 + 注销两处） |
| `Makefile` | #4 | 新增 `deps` / `install-jq` / `install-yq` target |
| `lib/gateway.sh` | #1 | clean 时删除 `nginx/conf.d/projects/*.conf` |
| `lib/gateway.sh` | #6 | 可选：添加 default_server 块拒绝非目标域名 |
