# HmSSH Admin（云端管理 UI）

基于 **SvelteKit + pnpm + shadcn-svelte** 的管理控制台，对接 Rust 云端 API（`/api/v1/admin/*`）。

## 环境

- Node 20+ / pnpm 9+
- 已启动的 Rust 服务（默认 `http://127.0.0.1:8080`）

## 安装与运行

```bash
cd admin
cp .env.example .env   # 按需改 PUBLIC_API_BASE
pnpm install
pnpm dev               # http://localhost:5173
```

构建：

```bash
pnpm build
pnpm preview
```

环境变量：

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `PUBLIC_API_BASE` | Rust API 根地址（无尾斜杠） | `http://127.0.0.1:8080` |

## 创建首位管理员

在 **server** 侧设置环境变量后启动即可自动种子（若不存在则创建，若邮箱已存在则提升为 admin）：

```bash
cd ../server
# .env
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=change-me-admin-pass   # 至少 8 位
JWT_SECRET=please-change-me-now-16+
cargo run
```

然后在本 UI 用该邮箱/密码登录。非 `is_admin` 帐号会被拒绝。

## 功能

- 登录（管理员）；access token **自动 refresh**（临近过期 ~60s / 遇 401 重试一次，失败回登录页）
- 仪表盘：用户数 / 健康 / 基础统计
- 用户表：搜索、禁用/启用、软删除
- 用户详情：同步 hosts/settings **元数据**（大小、updated_at），强制注销（吊销会话）

## 技术栈

- SvelteKit + TypeScript
- Tailwind CSS v4 + shadcn-svelte（zinc 语义色、暗色模式）
- Sonner 吐司；Sidebar / Card / Table / Badge / Button 等组合
