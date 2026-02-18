# Demo Project

HTTPS Toolkit 的演示项目，用于验证网关部署流程。

## 使用

### 前提

网关已初始化（只需首次执行一次，所有项目共享）：

```bash
https-deploy gateway init
```

### 部署（Docker 模式）

`config.yaml` 已预置，直接部署：

```bash
cd demo
https-deploy up
```

访问 https://local.yeanhua.asia/demo/

### 如果需要重新生成 config.yaml

```bash
cd demo
https-deploy init
# Project name: demo
# Backend port: 8080
# Path prefix: /demo
# Strip prefix: true
```

### 注册模式（本地运行）

```bash
cd demo
go run main.go &          # 宿主机启动服务
https-deploy register     # 仅注册到网关（不构建 Docker）
```

### 停止

```bash
https-deploy down         # Docker 模式：停止容器 + 注销
# 或
https-deploy unregister   # 注册模式：仅注销
```

## 端点

| 路径 | 说明 |
|------|------|
| `/` | HTML 首页 |
| `/health` | 健康检查，返回 `OK` |
| `/api/info` | 服务信息（JSON） |
| `/api/time` | 当前时间（JSON） |

通过网关访问时路径带前缀：`/demo/`、`/demo/health`、`/demo/api/info`。

## 配置说明

`config.yaml`：

```yaml
project:
  name: demo              # 容器名
  backend_port: 8080      # 服务端口

routing:
  path_prefix: /demo      # URL 路径前缀
  strip_prefix: true      # 转发时去除前缀
  # https://local.yeanhua.asia/demo/api/info → http://demo:8080/api/info

health_check:
  enabled: true
  path: /health           # 部署时自动检测此端点
```

## 网络架构

```
浏览器 → 宿主机:443 → gateway 容器 → Docker 内部网络 → demo 容器:8080
              ↑                            ↑
        唯一需要 -p 的地方          容器间通信，不经过宿主机
```

- **只有 gateway** 映射端口到宿主机（`-p 80:80 -p 443:443`）
- 业务容器（demo、news 等）**不暴露端口**到宿主机，仅加入 `https-toolkit-network`
- 同一 Docker network 内的容器通过 `容器名:端口` 互访（Docker DNS 解析）
- 多个项目可以使用相同的 `backend_port`（如都用 8080），因为各容器有独立的网络命名空间，互不冲突

**两种模式的网络路径**：

```
Docker 模式 (up):
  gateway 容器 → demo:8080
                 ↑ 同一 Docker 网络，容器名即 DNS

注册模式 (register):
  gateway 容器 → host.docker.internal:8080 → 宿主机 localhost:8080
                 ↑ Docker Desktop 提供的特殊 DNS，解析为宿主机 IP
```

| 模式 | 命令 | 上游地址 | 原理 |
|------|------|---------|------|
| Docker | `https-deploy up` | `demo:8080` | 容器名，Docker 网络内直连 |
| 注册 | `https-deploy register` | `host.docker.internal:8080` | 特殊地址，从容器回访宿主机 |

> `host.docker.internal` 是 Docker Desktop（macOS/Windows）内置的 DNS 名称，在容器内解析为宿主机 IP。容器内的 `localhost` 指向容器自身，无法访问宿主机服务，因此需要这个特殊地址绕回去。`register` 命令自动处理了这个细节，用户无需手动配置。
>
> 注意：Linux 原生 Docker 默认不提供此 DNS，需启动时加 `--add-host=host.docker.internal:host-gateway`。
