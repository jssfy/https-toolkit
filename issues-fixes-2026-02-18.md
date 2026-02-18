# Issues & Fixes 记录

## 核心结论

本次部署和测试中遇到 4 个问题，均已修复。根因集中在两个方面：跨平台兼容性（macOS vs Linux）和 gateway init 的状态管理。

---

## Issue #1: gateway init 后残留项目配置导致 nginx 启动失败

**现象**: `gateway clean && gateway init` 后 gateway 容器持续 Restarting

**日志**:
```
[emerg] host not found in upstream "my-api" in /etc/nginx/conf.d/projects/my-api.conf:12
```

**根因**: `gateway clean` 停止了项目容器并删除了网络，但没有清理 `nginx/conf.d/projects/` 下的项目配置文件。nginx 启动时 resolve upstream 失败。

**修复**: 手动删除残留配置文件后重启。

**建议**: `gateway_clean()` 应增加清理项目 nginx 配置的逻辑：
```bash
rm -f "$GATEWAY_ROOT/nginx/conf.d/projects/"*.conf
```

**状态**: 临时修复（手动删除），待后续补全到 `gateway_clean()`

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

## 修复文件汇总

| 文件 | Issue | 改动 |
|------|-------|------|
| `lib/gateway.sh` | #2 | init 末尾：已运行时 reload 而非跳过 |
| `lib/project.sh` | #3 | 新增 `docker_compose()` 兼容函数 |
| `lib/project.sh` | #5 | `mv` 后 `chmod 644`（注册 + 注销两处） |
| `Makefile` | #4 | 新增 `deps` / `install-jq` / `install-yq` target |
| `lib/gateway.sh` | #1 | 待补全：clean 时删除项目配置 |
