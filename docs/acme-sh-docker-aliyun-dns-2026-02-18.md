# acme.sh Docker + Aliyun DNS 证书自动化方案

## 核心结论

- **Docker 镜像**: `neilpang/acme.sh` 基于 Alpine，仅约 5MB，支持作为一次性命令执行或常驻 daemon 运行
- **Aliyun DNS 集成**: 需要 `Ali_Key` 和 `Ali_Secret` 两个环境变量，从阿里云 RAM 控制台获取
- **证书存储**: 容器内 `/acme.sh` 目录，需挂载为 volume 持久化
- **通配符证书**: 必须使用 DNS 验证模式 (`--dns dns_ali`)，不能使用 standalone 模式
- **证书安装**: 使用 `--install-cert` 命令复制到目标目录，**不要**直接引用 `/acme.sh/` 内部文件
- **自动续签**: daemon 模式下内置 cron job，每 30 天自动续签；或手动 `--cron` 触发
- **默认 CA**: 当前 acme.sh 默认 CA 是 ZeroSSL，如需 Let's Encrypt 需显式指定 `--server letsencrypt`

## 1. Docker 镜像 `neilpang/acme.sh`

### 基本信息

| 属性 | 值 |
|------|------|
| 镜像地址 | `neilpang/acme.sh` (Docker Hub) |
| 基础镜像 | Alpine Linux |
| 镜像大小 | ~5MB (压缩后约 22MB with dev tag) |
| 数据目录 | `/acme.sh` (容器内，即 `LE_CONFIG_HOME`) |
| 默认用户 | root (也提供 `acme` 用户 UID/GID 1000) |
| 下载量 | 10M+ |

> 引用来源: [Docker Hub - neilpang/acme.sh](https://hub.docker.com/r/neilpang/acme.sh), [Run acme.sh in docker Wiki](https://github.com/acmesh-official/acme.sh/wiki/Run-acme.sh-in-docker)

### 两种使用模式

#### 模式 A: 作为一次性可执行命令

```bash
docker run --rm -it \
  -v "$(pwd)/acmeout":/acme.sh \
  --net=host \
  neilpang/acme.sh --issue -d example.com --standalone
```

关键点:
- `--rm` 执行完毕后自动删除容器
- `-v "$(pwd)/acmeout":/acme.sh` 挂载宿主机目录到 `/acme.sh` 用于持久化证书和配置
- `--net=host` standalone 模式下需要监听 80 端口，必须使用 host 网络
- 镜像名后面直接跟 acme.sh 的参数

#### 模式 B: 作为 Daemon 常驻运行（推荐用于自动续签）

```bash
docker run --rm -itd \
  -v "$(pwd)/acmeout":/acme.sh \
  --net=host \
  --name=acme.sh \
  neilpang/acme.sh daemon
```

Docker Compose 写法:

```yaml
services:
  acme-sh:
    image: neilpang/acme.sh
    container_name: acme.sh
    volumes:
      - ./acmeout:/acme.sh
    network_mode: host
    command: daemon
    stdin_open: true
    tty: true
    restart: unless-stopped
```

daemon 模式下，容器内置 cron job 自动执行续签。之后通过 `docker exec` 执行命令:

```bash
docker exec acme.sh --issue -d example.com --standalone
docker exec acme.sh --list
docker exec acme.sh --cron
```

## 2. Aliyun DNS API 集成

### 获取 API 凭证

1. 登录阿里云 RAM 控制台: https://ram.console.aliyun.com/users
2. 创建一个 RAM 用户（或使用已有用户）
3. 授予 `AliyunDNSFullAccess` 权限
4. 创建 AccessKey，获取 `AccessKey ID` 和 `AccessKey Secret`

> 引用来源: [acme.sh dnsapi Wiki - Aliyun DNS](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#11-use-aliyun-domain-api-to-automatically-issue-cert)

### 环境变量

| 变量名 | 说明 | 来源 |
|--------|------|------|
| `Ali_Key` | 阿里云 AccessKey ID | RAM 控制台 |
| `Ali_Secret` | 阿里云 AccessKey Secret | RAM 控制台 |

### 凭证保存机制

首次使用后，`Ali_Key` 和 `Ali_Secret` 会被自动保存到 `/acme.sh/account.conf` 文件中，后续续签时自动读取，无需再次设置环境变量。

> 引用来源: dns_ali.sh 源码中 `_saveaccountconf_mutable Ali_Key "$Ali_Key"` 和 `_saveaccountconf_mutable Ali_Secret "$Ali_Secret"` 证实了此行为。
> 源码地址: [dns_ali.sh](https://github.com/acmesh-official/acme.sh/blob/master/dnsapi/dns_ali.sh)

### dns_ali.sh 工作原理

- 调用阿里云 DNS API 端点: `https://alidns.aliyuncs.com/`
- 使用 HMAC-SHA1 签名认证
- 自动查找域名的根区域（root zone）
- 添加 `_acme-challenge` TXT 记录完成验证
- 验证完成后自动清理 TXT 记录

## 3. 证书签发命令

### 重要前提: 指定 CA 服务器

acme.sh 当前默认 CA 是 **ZeroSSL**（非 Let's Encrypt）。如果要使用 Let's Encrypt，需要显式指定:

```bash
# 一次性切换默认 CA（全局生效）
acme.sh --set-default-ca --server letsencrypt

# 或每次签发时指定
acme.sh --issue ... --server letsencrypt
```

### 3.1 单域名证书 (Standalone 模式)

```bash
docker run --rm -it \
  -v "$(pwd)/acmeout":/acme.sh \
  --net=host \
  neilpang/acme.sh \
  --issue -d data.yeanhua.asia --standalone --server letsencrypt
```

**说明**:
- `--standalone` 模式使用 acme.sh 内置 HTTP 服务器监听 **80 端口** 完成 HTTP-01 验证
- **必须** `--net=host`，否则容器内的 80 端口无法被 Let's Encrypt 服务器访问
- 宿主机的 80 端口 **必须空闲**（不能有 nginx/apache 等占用）
- 不需要 DNS API 凭证

如果 daemon 模式下:

```bash
docker exec acme.sh \
  --issue -d data.yeanhua.asia --standalone --server letsencrypt
```

### 3.2 通配符域名证书 (DNS 验证模式)

```bash
docker run --rm -it \
  -v "$(pwd)/acmeout":/acme.sh \
  -e Ali_Key="你的AccessKeyID" \
  -e Ali_Secret="你的AccessKeySecret" \
  neilpang/acme.sh \
  --issue -d "*.yeanhua.asia" -d yeanhua.asia --dns dns_ali --server letsencrypt
```

**说明**:
- 通配符证书 (`*.yeanhua.asia`) **只能**使用 DNS-01 验证，不支持 HTTP-01 (standalone)
- `--dns dns_ali` 指定使用阿里云 DNS API 自动添加/清理 TXT 记录
- 建议同时包含 `-d yeanhua.asia`（根域名）和 `-d "*.yeanhua.asia"`（通配符），这样根域名和所有子域名都能覆盖
- **不需要** `--net=host`，因为 DNS 验证不需要监听端口
- `-e Ali_Key` 和 `-e Ali_Secret` 通过环境变量传入（首次使用后会保存到 volume 中的 account.conf）

如果 daemon 模式下:

```bash
# 首次需要设置环境变量（进入容器设置，或在 docker-compose.yml 中配置）
docker exec -e Ali_Key="你的AccessKeyID" -e Ali_Secret="你的AccessKeySecret" \
  acme.sh \
  --issue -d "*.yeanhua.asia" -d yeanhua.asia --dns dns_ali --server letsencrypt
```

### 3.3 同时签发多域名 + 通配符 (推荐)

```bash
docker run --rm -it \
  -v "$(pwd)/acmeout":/acme.sh \
  -e Ali_Key="你的AccessKeyID" \
  -e Ali_Secret="你的AccessKeySecret" \
  neilpang/acme.sh \
  --issue \
  -d yeanhua.asia \
  -d "*.yeanhua.asia" \
  -d data.yeanhua.asia \
  --dns dns_ali \
  --server letsencrypt
```

## 4. 证书存储位置

### 容器内结构 (`/acme.sh` = 挂载的 volume)

```
/acme.sh/                          # LE_CONFIG_HOME
├── account.conf                   # 账户配置（含 Ali_Key, Ali_Secret 等）
├── ca/                            # CA 账户信息
│   └── acme-v02.api.letsencrypt.org/
│       └── directory/
│           ├── account.json
│           └── account.key
├── yeanhua.asia/                  # 按主域名组织的证书目录
│   ├── yeanhua.asia.cer           # 域名证书
│   ├── yeanhua.asia.key           # 私钥
│   ├── ca.cer                     # CA 证书
│   ├── fullchain.cer              # 完整证书链（证书 + CA）
│   └── yeanhua.asia.conf          # 该证书的配置信息（含签发参数、续签配置等）
├── data.yeanhua.asia/             # 单独签发的证书
│   ├── data.yeanhua.asia.cer
│   ├── data.yeanhua.asia.key
│   ├── ca.cer
│   ├── fullchain.cer
│   └── data.yeanhua.asia.conf
└── http.header                    # HTTP header 文件
```

### 宿主机映射

如果你用 `-v "$(pwd)/acmeout":/acme.sh` 挂载，则上述文件在宿主机 `$(pwd)/acmeout/` 下。

> **重要警告**: 官方文档明确指出，**不要直接**引用 `/acme.sh/域名/` 下的文件给 nginx/apache 使用。这些文件是内部使用的，目录结构可能在未来版本变更。应使用 `--install-cert` 命令复制到目标位置。

> 引用来源: [acme.sh README - Install the cert](https://github.com/acmesh-official/acme.sh#3-install-the-cert-to-apachenginx-etc) 原文: "You MUST use this command to copy the certs to the target files. DO NOT use the certs files in ~/.acme.sh/ folder — they are for internal use only, the folder structure may change in the future."

## 5. 证书安装（复制到自定义目录）

### 基本语法

```bash
acme.sh --install-cert -d example.com \
  --cert-file      /path/to/cert.pem \
  --key-file       /path/to/key.pem \
  --fullchain-file /path/to/fullchain.pem \
  --ca-file        /path/to/ca.pem \
  --reloadcmd      "service nginx force-reload"
```

### Docker 中的实际用法

需要挂载目标证书目录为另一个 volume:

```bash
docker run --rm -it \
  -v "$(pwd)/acmeout":/acme.sh \
  -v "$(pwd)/certs":/certs \
  neilpang/acme.sh \
  --install-cert -d "*.yeanhua.asia" \
  --key-file       /certs/yeanhua.asia/key.pem \
  --fullchain-file /certs/yeanhua.asia/fullchain.pem \
  --cert-file      /certs/yeanhua.asia/cert.pem \
  --ca-file        /certs/yeanhua.asia/ca.pem
```

### 带 reloadcmd 的 Nginx 场景 (daemon 模式)

```bash
docker exec acme.sh \
  --install-cert -d "*.yeanhua.asia" \
  --key-file       /certs/yeanhua.asia/key.pem \
  --fullchain-file /certs/yeanhua.asia/fullchain.pem \
  --reloadcmd      "echo 'cert installed, reload needed'"
```

> `--reloadcmd` 会在每次续签后自动执行。在 Docker 环境中，如果需要重载宿主机的 nginx，可以考虑:
> - 使用 `docker exec` 方式重载 nginx 容器
> - 或将 docker.sock 挂载到 acme.sh 容器中

### install-cert 关键行为

- `--install-cert` 参数（路径和 reloadcmd）会被保存到证书的 `.conf` 文件中
- **续签时自动执行** install-cert，将新证书复制到相同目标路径并执行 reloadcmd
- 目标文件已存在时，会保留原文件的 ownership 和 permission
- 可以提前创建目标文件以预设权限

## 6. 证书续签方案

### 自动续签 (Daemon 模式 - 推荐)

Daemon 模式下，容器内的 cron job 会自动检查并续签即将到期的证书:

```yaml
# docker-compose.yml
services:
  acme-sh:
    image: neilpang/acme.sh
    container_name: acme.sh
    volumes:
      - ./acmeout:/acme.sh
      - ./certs:/certs          # 证书安装目标目录
    environment:
      - Ali_Key=你的AccessKeyID       # 可选，首次保存后从 account.conf 读取
      - Ali_Secret=你的AccessKeySecret
    network_mode: host               # standalone 模式需要; 纯 DNS 模式可不要
    command: daemon
    stdin_open: true
    tty: true
    restart: unless-stopped
```

### 手动续签

```bash
# 续签所有到期证书
docker exec acme.sh --cron

# 强制续签特定证书（不管是否到期）
docker exec acme.sh --renew -d "*.yeanhua.asia" --force

# 查看所有证书及其到期时间
docker exec acme.sh --list
```

### 一次性容器触发续签（适合外部 cron）

如果不想运行 daemon，可以在宿主机 crontab 中添加:

```bash
# 每天凌晨 2 点检查续签
0 2 * * * docker run --rm -v /path/to/acmeout:/acme.sh --net=host neilpang/acme.sh --cron
```

### 续签周期

- Let's Encrypt 证书有效期 **90 天**
- acme.sh 默认在到期前 **30 天**（即签发后 60 天）自动续签
- 可通过 `--renew-hook` 在续签成功后执行自定义操作

## 完整 Docker Compose 示例

```yaml
services:
  acme-sh:
    image: neilpang/acme.sh
    container_name: acme.sh
    volumes:
      - ./acmeout:/acme.sh         # acme.sh 数据持久化
      - ./gateway/certs:/certs     # 证书安装目标 (供 nginx 等读取)
    environment:
      - Ali_Key=${ALI_KEY}
      - Ali_Secret=${ALI_SECRET}
    network_mode: host
    command: daemon
    stdin_open: true
    tty: true
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "443:443"
    volumes:
      - ./gateway/certs:/etc/nginx/certs:ro   # 只读挂载证书
      - ./gateway/nginx/conf.d:/etc/nginx/conf.d:ro
    depends_on:
      - acme-sh
    restart: unless-stopped
```

### 初始化流程

```bash
# 1. 设置默认 CA 为 Let's Encrypt
docker exec acme.sh --set-default-ca --server letsencrypt

# 2. 签发通配符证书
docker exec -e Ali_Key="$ALI_KEY" -e Ali_Secret="$ALI_SECRET" \
  acme.sh --issue -d yeanhua.asia -d "*.yeanhua.asia" --dns dns_ali

# 3. 安装证书到 nginx 可读取的目录
docker exec acme.sh --install-cert -d yeanhua.asia \
  --key-file       /certs/yeanhua.asia/key.pem \
  --fullchain-file /certs/yeanhua.asia/fullchain.pem \
  --reloadcmd      "echo cert renewed"

# 4. 查看证书列表
docker exec acme.sh --list
```

## 参考来源

- [Docker Hub - neilpang/acme.sh](https://hub.docker.com/r/neilpang/acme.sh)
- [Run acme.sh in Docker Wiki](https://github.com/acmesh-official/acme.sh/wiki/Run-acme.sh-in-docker)
- [acme.sh DNS API Wiki - Aliyun](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#11-use-aliyun-domain-api-to-automatically-issue-cert)
- [dns_ali.sh 源码](https://github.com/acmesh-official/acme.sh/blob/master/dnsapi/dns_ali.sh)
- [acme.sh GitHub README](https://github.com/acmesh-official/acme.sh)
- [DeepWiki - Certificate Storage](https://deepwiki.com/acmesh-official/acme.sh/2.4-certificate-storage)
- [DeepWiki - Using acme.sh in Containers](https://deepwiki.com/acmesh-official/acme.sh/6.2-using-acme.sh-in-containers)
