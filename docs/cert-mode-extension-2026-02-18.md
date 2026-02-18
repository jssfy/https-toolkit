# 证书模式扩展：Let's Encrypt 单域名 & 泛域名

## 核心结论

- 通过 `--cert-mode` 参数扩展 `gateway init`，支持三种证书模式：`mkcert`（默认）、`letsencrypt`、`letsencrypt-wildcard`
- ACME 客户端使用 `neilpang/acme.sh` Docker 镜像，零本地依赖
- 泛域名通过阿里云 DNS API（dns_ali）完成 DNS-01 验证
- 配置持久化到 `~/.https-toolkit/gateway/gateway.conf`，跨命令共享状态
- 完全向后兼容：无参数调用保持原有 mkcert 行为

## 修改文件清单

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `lib/utils.sh` | 新增函数 | `check_acme_sh()` — 检查/拉取 acme.sh Docker 镜像 |
| `lib/gateway.sh` | 重构+新增 | 配置持久化、参数解析、证书分发、三种证书函数、续期函数 |
| `bin/https-deploy` | 新增子命令 | `gateway renew` 子命令 + 帮助文本更新 |

## 实现细节

### 新增变量

```bash
CERT_MODE="mkcert"              # 默认证书模式
LETSENCRYPT_EMAIL=""            # Let's Encrypt 注册邮箱
GATEWAY_CONF="$HOME/.https-toolkit/gateway/gateway.conf"
ACME_HOME="$HOME/.https-toolkit/gateway/acme"
```

### 新增函数

| 函数 | 文件 | 用途 |
|------|------|------|
| `check_acme_sh()` | utils.sh | 检查 acme.sh 镜像，不存在则自动拉取 |
| `gateway_load_config()` | gateway.sh | 从 gateway.conf 加载配置 |
| `gateway_save_config()` | gateway.sh | 保存当前配置到 gateway.conf |
| `gateway_cert_mkcert()` | gateway.sh | 原有 mkcert 逻辑提取 |
| `gateway_cert_letsencrypt()` | gateway.sh | HTTP-01 standalone 签发 |
| `gateway_cert_letsencrypt_wildcard()` | gateway.sh | DNS-01 via dns_ali 签发 |
| `gateway_cert_renew()` | gateway.sh | 证书续期（调用 acme.sh --cron） |

### gateway_init 参数解析

```
gateway init [--cert-mode mkcert|letsencrypt|letsencrypt-wildcard]
             [--domain <domain>]
             [--email <email>]
```

- `--cert-mode` 未指定时默认 `mkcert`
- `--domain` 未指定时按模式自动设置默认域名
- `--email` 仅 Let's Encrypt 模式需要，未提供则交互输入

### Nginx 配置变化

泛域名模式下 `server_name` 变为 `yeanhua.asia *.yeanhua.asia`，证书目录统一使用主域名（不含 `*`）。

### 阿里云 DNS 凭据（Ali_Key / Ali_Secret）完整流程

泛域名证书使用 DNS-01 验证，acme.sh 通过阿里云 DNS API 自动添加 `_acme-challenge` TXT 记录。

**凭据获取**：[阿里云 RAM 访问控制](https://ram.console.aliyun.com/manage/ak)，建议创建 RAM 子账号并仅授权 `AliyunDNSFullAccess`。

**凭据生命周期**：

```
首次签发                                 后续操作
┌──────────────┐                       ┌──────────────┐
│ 用户交互输入   │                       │ 自动从        │
│  Ali_Key      │──→ acme.sh 签发 ──→   │ account.conf │──→ acme.sh 续期/重签
│  Ali_Secret   │    ↓                  │ 读取          │
└──────────────┘    保存到              └──────────────┘
                    account.conf
```

**存储位置**: `~/.https-toolkit/gateway/acme/account.conf`

```
SAVED_Ali_Key='LTAI5t...'
SAVED_Ali_Secret='Gkj8...'
```

**读取逻辑** (`gateway_cert_letsencrypt_wildcard()`):
1. 检查 `$ACME_HOME/account.conf` 是否存在已保存的凭据
2. 若无 → 交互提示输入 Ali_Key 和 Ali_Secret
3. 通过 `docker run -e Ali_Key=... -e Ali_Secret=...` 传入 acme.sh 容器
4. acme.sh 签发成功后自动写入 `account.conf`，后续操作无需再输入

**安全建议**:
- 使用 RAM 子账号，仅授权 DNS 管理权限
- `account.conf` 权限建议设为 `600`（仅所有者可读写）
- 不要将 `~/.https-toolkit/gateway/acme/` 提交到版本控制

### 关键设计决策

1. **macOS 兼容**: 避免使用 `grep -oP`（Perl regex），改用 `sed` 解析 acme account.conf
2. **端口冲突处理**: HTTP-01 模式签发/续期前自动停止 gateway 释放 80 端口，完成后重启
3. **凭据安全**: Ali_Key/Ali_Secret 通过 Docker `-e` 传入，由 acme.sh 自动保存到 account.conf
4. **幂等性**: 证书已存在时跳过签发（三种模式均支持）
5. **重复 init 安全**: gateway 已运行时 init 执行 `nginx -s reload`（非重启），配置热更新

## gateway init 完整流程

### 流程总览

```
gateway init --cert-mode <mode> --domain <domain> --email <email>
  │
  ├── 1. 参数解析 & 验证
  │     ├── 解析 --cert-mode / --domain / --email
  │     ├── 验证 cert mode 合法性
  │     ├── 未指定 domain 时按 mode 设置默认值
  │     └── LE 模式未指定 email 时交互输入
  │
  ├── 2. 环境准备
  │     ├── check_dependencies (docker, jq, yq...)
  │     ├── LE 模式: check_acme_sh (拉取 Docker 镜像)
  │     ├── 创建目录结构 (nginx/, certs/, acme/, registry/, html/)
  │     └── 保存配置到 gateway.conf
  │
  ├── 3. Nginx 配置生成
  │     ├── nginx.conf (通用，不变)
  │     └── 00-default.conf
  │           ├── mkcert/letsencrypt: server_name = <domain>
  │           └── wildcard: server_name = <domain> *.<domain>
  │
  ├── 4. 证书签发 (dispatcher → 按 mode 分发)
  │     ├── mkcert       → gateway_cert_mkcert()
  │     ├── letsencrypt  → gateway_cert_letsencrypt()
  │     └── wildcard     → gateway_cert_letsencrypt_wildcard()
  │     注: 证书已存在时跳过 (幂等)
  │
  ├── 5. 网络 & 注册表 & Dashboard
  │     ├── 创建 Docker 网络
  │     ├── 初始化 projects.json
  │     └── 生成 Dashboard HTML
  │
  └── 6. 启动或热重载
        ├── gateway 未运行 → docker run 启动
        └── gateway 已运行 → nginx -s reload 热重载
```

### 泛域名 DNS-01 签发实际流程（基于真实日志）

以 `--cert-mode letsencrypt-wildcard --domain yeanhua.asia` 为例，总耗时约 57 秒：

| 阶段 | 耗时 | 事件 | 说明 |
|------|------|------|------|
| 连接 CA | ~5s | `Using CA: acme-v02.api.letsencrypt.org` | 注册账号、创建 ECC 域名密钥 |
| 请求验证 | ~5s | `Multi domain: yeanhua.asia, *.yeanhua.asia` | CA 返回两个 challenge |
| 添加 DNS | ~7s | 添加 2 条 `_acme-challenge` TXT 记录 | 通过阿里云 DNS API 自动完成 |
| DNS 传播 | **20s** | `Sleeping for 20 seconds` | 等待 TXT 记录在公共 DNS 生效 |
| DNS 检查 | ~4s | 查询两条 TXT 均成功 | acme.sh 主动验证 DNS 可查 |
| CA 验证 | ~10s | `yeanhua.asia` + `*.yeanhua.asia` 均 Success | Let's Encrypt 验证通过 |
| 清理 DNS | ~5s | 删除 2 条临时 TXT 记录 | 自动清理，不留残留 |
| 签名下载 | ~5s | finalize order → 下载证书 | ECC 证书，有效期 90 天 |
| 安装证书 | <1s | 复制到 `certs/yeanhua.asia/` | `privkey.pem` + `fullchain.pem` |

**证书详情**:
- 类型: ECC (ECDSA P-256)
- 颁发者: Let's Encrypt E7
- 覆盖域名: `yeanhua.asia` + `*.yeanhua.asia`
- 有效期: 90 天（需定期 `gateway renew`）

### 重复 init 与模式切换

| 场景 | 证书 | Nginx 配置 | 网关 |
|------|------|-----------|------|
| 首次 init（无容器） | 签发新证书 | 生成新配置 | `docker run` 启动 |
| 同 mode 重复 init | 跳过（证书已存在） | 重新生成 | `nginx -s reload` 热重载 |
| 切换 mode init | 签发新证书（不同目录） | 重新生成（新 server_name + cert 路径） | `nginx -s reload` 热重载 |

**为什么 reload 能生效？**

Docker 挂载的是宿主机目录（非文件快照）：

```
-v "$GATEWAY_ROOT/nginx/conf.d:/etc/nginx/conf.d:ro"   # nginx 配置
-v "$GATEWAY_ROOT/certs:/etc/nginx/certs:ro"            # 所有模式的证书
```

init 写入磁盘的新文件（`00-default.conf`、`certs/<domain>/`）在容器内立即可见。
`nginx -s reload` 让 nginx 重新读取配置，切换到新的 `server_name` 和证书路径，无需重建容器。

**幂等保证**:
- 证书：基于文件存在性检查（`fullchain.pem` + `privkey.pem`），已有则跳过，不会重复请求 Let's Encrypt
- 网关：检测容器状态，运行中 → reload，未运行 → start

**模式切换示例**:

```bash
# 本地开发 → 泛域名公网（网关不中断）
https-deploy gateway init --cert-mode letsencrypt-wildcard --domain yeanhua.asia --email you@example.com

# 泛域名 → 切回本地开发
https-deploy gateway init --cert-mode mkcert

# 确认当前模式
https-deploy gateway status
# [INFO] Cert mode:   mkcert
# [INFO] Domain:      local.yeanhua.asia
```

## 使用示例

```bash
# 本地开发（默认，向后兼容）
https-deploy gateway init

# 单域名 Let's Encrypt
https-deploy gateway init --cert-mode letsencrypt --domain data.yeanhua.asia --email user@example.com

# 泛域名 Let's Encrypt（首次需输入 Ali_Key/Ali_Secret）
https-deploy gateway init --cert-mode letsencrypt-wildcard --domain yeanhua.asia --email user@example.com

# 查看当前模式和域名
https-deploy gateway status

# 证书续期
https-deploy gateway renew
```

## 证书存放与查看

### 存放路径

```
~/.https-toolkit/gateway/certs/<domain>/
├── fullchain.pem    # 证书 + 中间 CA 链（nginx ssl_certificate 引用）
└── privkey.pem      # 私钥（权限 600，仅所有者可读）
```

各模式对应目录：

| 模式 | 证书目录 |
|------|---------|
| mkcert | `certs/local.yeanhua.asia/` |
| letsencrypt | `certs/data.yeanhua.asia/` |
| letsencrypt-wildcard | `certs/yeanhua.asia/` |

### 查看证书信息

```bash
# 基本信息（主题、颁发者、有效期、SAN）
openssl x509 -in ~/.https-toolkit/gateway/certs/yeanhua.asia/fullchain.pem \
  -noout -subject -issuer -dates -ext subjectAltName

# 示例输出:
#   subject=CN=yeanhua.asia
#   issuer=C=US, O=Let's Encrypt, CN=E7
#   notBefore=Feb 18 11:25:34 2026 GMT
#   notAfter=May 19 11:25:33 2026 GMT
#   X509v3 Subject Alternative Name:
#       DNS:*.yeanhua.asia, DNS:yeanhua.asia

# 剩余有效天数
openssl x509 -in ~/.https-toolkit/gateway/certs/yeanhua.asia/fullchain.pem -noout -enddate

# 完整详情
openssl x509 -in ~/.https-toolkit/gateway/certs/yeanhua.asia/fullchain.pem -noout -text
```

## 目录结构

```
~/.https-toolkit/gateway/
├── gateway.conf            # 配置持久化 (CERT_MODE, GATEWAY_DOMAIN, EMAIL)
├── acme/                   # acme.sh 数据目录
│   ├── account.conf        #   Ali_Key/Ali_Secret 自动保存于此
│   └── yeanhua.asia_ecc/   #   ECC 证书内部数据
├── certs/
│   ├── local.yeanhua.asia/ # mkcert 模式
│   │   ├── fullchain.pem
│   │   └── privkey.pem
│   ├── data.yeanhua.asia/  # letsencrypt 单域名
│   │   ├── fullchain.pem
│   │   └── privkey.pem
│   └── yeanhua.asia/       # letsencrypt-wildcard
│       ├── fullchain.pem
│       └── privkey.pem
└── nginx/
    └── conf.d/
        └── 00-default.conf
```
