# HmSSH Cloud Server / 鸿蒙SSH 云端服务

Rust（axum + sqlx + JWT + Argon2）REST API：用户注册/登录，主机列表与设置云同步。

English + 中文说明如下。

## Features / 功能

| API | 说明 |
| --- | --- |
| `POST /api/v1/auth/register` | 注册 `{ email, username, password }` |
| `POST /api/v1/auth/login` | 登录 `{ login\|email\|username, password }` → JWT |
| `POST /api/v1/auth/refresh` | 刷新 `{ refresh_token }` |
| `POST /api/v1/auth/logout` | 注销（吊销会话缓存，需 Bearer） |
| `GET /api/v1/me` | 当前用户（需 Bearer） |
| `POST /api/v1/me/password` | 改密 `{ current_password, new_password }` → 新 JWT |
| `DELETE /api/v1/me` | 自助删号 `{ password }`：软删 + 清 sync blobs + 吊销令牌 |
| `GET/PUT /api/v1/sync/hosts` | 主机列表 JSON 同步（服务端剥离 password/privateKey） |
| `GET/PUT /api/v1/sync/settings` | 主题/设置 JSON 同步 |
| `GET /health` | 健康检查（status/db/db_backend/cache/uptime_ms；db 失败 → 503） |
| `GET /api/v1/admin/stats` | 管理统计（需 admin） |
| `GET /api/v1/admin/users?q=&page=&page_size=` | 用户分页列表（含已删除）`{ items, total, page, page_size }` |
| `GET /api/v1/admin/users/:id` | 用户详情 |
| `PATCH /api/v1/admin/users/:id` | `{ disabled? }` 启用/禁用 |
| `DELETE /api/v1/admin/users/:id` | 软删除 |
| `POST /api/v1/admin/users/:id/revoke` | 强制注销会话 |
| `GET /api/v1/admin/users/:id/sync` | 同步元数据（无密钥原文） |

密码 **Argon2** 哈希，从不存明文。JWT 密钥来自 `JWT_SECRET`。

## Quick start / 快速启动

```bash
cd server
cp .env.example .env
# 编辑 JWT_SECRET
cargo run
# → http://0.0.0.0:8080
```

可选 TOML：`cp config.example.toml config.toml`（环境变量优先于 TOML）。

### Docker

```bash
docker build -t hm-ssh-server .
docker run --rm -p 8080:8080 \
  -e JWT_SECRET=please-change-me-now-16+ \
  -e DATABASE_URL=sqlite:/data/hmssh.db \
  -v hmssh-data:/data \
  hm-ssh-server
```

## Database backends / 数据库切换

由 `DATABASE_URL` **scheme** 决定（sqlx `Any` + feature flags）：

| URL | 后端 |
| --- | --- |
| `sqlite:hmssh.db` / `sqlite:///path/hmssh.db` | SQLite（默认） |
| `postgres://user:pass@host:5432/hmssh` | PostgreSQL |
| `mysql://user:pass@host:3306/hmssh` | MySQL |

启动时自动建表：`users`、`user_hosts`、`user_settings`（JSON payload + `updated_at` 毫秒时间戳）。

## Cache backends / 缓存切换

| 条件 | 后端 |
| --- | --- |
| 未设置 `REDIS_URL` | 内存 **moka**（默认） |
| 设置 `REDIS_URL` | **Redis**（同一 `CacheBackend` trait；连接失败则回退内存） |

用于会话标记与用户 profile 热缓存。

## Environment / 环境变量

见 [`.env.example`](./.env.example)：

- `BIND` — 监听地址（默认 `0.0.0.0:8080`）
- `DATABASE_URL` — 见上
- `JWT_SECRET` — 至少 16 字符
- `JWT_ACCESS_TTL_SECS` / `JWT_REFRESH_TTL_SECS`
- `REDIS_URL` — 可选
- `CORS_ORIGINS` — `*` 或逗号分隔源
- `AUTH_RATE_LIMIT_PER_MIN` — 注册/登录每 IP 每分钟上限（默认 20）
- `ADMIN_EMAIL` / `ADMIN_PASSWORD` — 启动时种子首位管理员（缺失则跳过；密码 ≥8）
- `MAX_BODY_BYTES` — JSON body 上限（默认 2 MiB）
- `MAX_SYNC_HOSTS` — `PUT /sync/hosts` 数组最大长度（默认 500）

## Sync semantics / 同步语义

- 每个资源（hosts / settings）存一份 JSON + 服务端 `updated_at`（Unix ms）。
- **Last-write-wins**：客户端以服务端时间戳为准；`PUT` 会覆盖并更新 `updated_at`。
- 客户端合并策略见仓库根 README「云同步」：按条目 `updatedAt` 取较新者，再推回服务端。
- **Secrets**：`PUT /sync/hosts` 会清空每条主机的 `password` / `privateKey`（及 `private_key`）后再落库；**保留**客户端保险柜字段 `passwordEnc` / `privateKeyEnc`。GET 同样保证不回传明文机密。

## Rate limiting / 速率限制

`POST /auth/register` 与 `POST /auth/login` 按客户端 IP（`X-Forwarded-For` / `X-Real-IP` / 直连）做进程内固定窗口限流；超限返回 **429**。默认 **20 次/分钟**，可由 `AUTH_RATE_LIMIT_PER_MIN` 调整。多实例部署时需改为 Redis 共享计数（尚未实现）。

密码规则：注册至少 **8** 字符（与客户端 Mock / AccountPage 对齐）。

## Refresh rotation / Refresh 轮换

`POST /auth/refresh` 签发新的 access + refresh，并将**旧 refresh 的 jti** 写入缓存 denylist（TTL ≈ 旧 token 剩余寿命）。重放旧 refresh → 401。

## Session invalidation / 会话吊销

- 登录/刷新写入 `sess:` / `profile:` 缓存（内存 moka 按条目 TTL；Redis 用 `SET EX`）。
- `POST /auth/logout` 写入 `revoke:{userId}` 并删除会话缓存；之后该用户在吊销前签发的 access/refresh 均被拒绝。

## Example curl

```bash
curl -s localhost:8080/health
curl -s -X POST localhost:8080/api/v1/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"a@b.com","username":"alice","password":"secret123"}'
TOKEN=... # access_token
curl -s localhost:8080/api/v1/me -H "Authorization: Bearer $TOKEN"
curl -s -X PUT localhost:8080/api/v1/sync/hosts \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"data":[{"id":"h1","name":"demo","host":"1.2.3.4","port":22}]}'
```


## Admin API / 管理端

需 **管理员** JWT（`users.is_admin = 1`）。中间件校验 JWT 后再次读取数据库 flag。

启动种子：

```bash
export ADMIN_EMAIL=admin@example.com
export ADMIN_PASSWORD=change-me-admin-pass
cargo run
```

管理 UI 见仓库 [`admin/`](../admin/)（SvelteKit + shadcn-svelte）。

## Dev notes

```bash
cargo check
cargo test
cargo run
```

Feature `redis-cache` 默认开启（引入 `redis` crate）；无 Redis 时不设 `REDIS_URL` 即可。

## AuthUser lookup cache

Authenticated requests cache a short-TTL (`~45s`) `authuser:{id}` entry (`ok` / `disabled`) in the pluggable `CacheBackend` to avoid a DB hit on every request. Entries are invalidated on logout, admin revoke/disable/delete, and disabled lookups are also written so repeated rejects stay cheap. Prefer invalidate-on-write over long TTLs.

## Ops notes / 运维要点

- **Body limit**：axum `DefaultBodyLimit`（`MAX_BODY_BYTES`）；同步另限 hosts 条数与 payload 字节。
- **Compression**：响应可协商 gzip / br（`tower-http` CompressionLayer）。
- **Graceful shutdown**：Ctrl+C 与 Unix `SIGTERM`。
- **sqlx pool**：`max_connections=10`、`min_connections=1`、acquire 超时 8s；PG/MySQL 高并发时可按实例调高。
- **AuthUser cache**：短 TTL；logout / disable / delete / revoke / **改密** 均 invalidate。
