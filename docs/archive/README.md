# HTTPS Toolkit 归档文档

本目录包含 HTTPS Toolkit 设计和实现过程中的历史文档。

## 文档来源

这些文档原本位于 `top-ai-news` 项目的 `docs/` 目录下,记录了:
- HTTPS 功能的设计演进
- 从项目内置到独立工具的重构过程
- 各种技术方案的对比和选择
- 实现细节和测试结果

**迁移日期**: 2026-02-18
**迁移原因**: https-toolkit 独立为通用工具后,将相关设计文档归档到工具项目中

## 文档分类

### 设计方案
- `https-generalization-plan-2026-02-16.md` - HTTPS 功能通用化计划
- `https-path-based-gateway-design-2026-02-17.md` - 路径前缀网关架构设计
- `certificate-comparison-2026-02-16.md` - 证书方案对比

### 实现细节
- `https-deploy-internals-2026-02-17.md` - https-deploy 内部实现
- `https-deploy-execution-flow-2026-02-17.md` - 执行流程详解
- `ssl-certificate-setup-2026-02-16.md` - SSL 证书配置
- `cert-generation-location-2026-02-16.md` - 证书生成位置
- `cert-default-letsencrypt-2026-02-16.md` - Let's Encrypt 默认配置

### 使用指南
- `https-toolkit-usage-guide-2026-02-16.md` - 工具使用指南
- `https-feature-summary-2026-02-16.md` - 功能总结

### 本地开发
- `local-https-setup-2026-02-16.md` - 本地 HTTPS 配置
- `local-domain-setup-2026-02-16.md` - 本地域名配置
- `why-mkcert-for-local-2026-02-16.md` - 为什么本地用 mkcert

### 测试记录
- `https-gateway-test-results-2026-02-17.md` - 网关测试结果

### 其他
- `docs-update-https-2026-02-16.md` - 文档更新记录

## 当前文档

最新的文档请查看项目根目录:
- [README.md](../../README.md) - 项目主文档
- [QUICK_START.md](../../QUICK_START.md) - 快速开始指南
- [IMPLEMENTATION.md](../../IMPLEMENTATION.md) - 实现说明
- [MIGRATION-2026-02-18.md](../../MIGRATION-2026-02-18.md) - 迁移记录

## 价值

这些归档文档的价值:
- 📚 了解项目演进历史
- 🔍 理解设计决策背景
- 💡 为类似项目提供参考
- 📝 保留完整的开发记录

虽然这些文档已归档,但它们记录了从想法到实现的完整过程,对理解 https-toolkit 的设计理念仍然很有帮助。
