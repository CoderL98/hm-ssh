# HmSSH Cloud Server / 鸿蒙SSH 云端服务

Rust（axum + sqlx + JWT + Argon2）REST API：用户注册/登录，主机列表与设置云同步。

English + 中文说明如下。

## Features / 功能

| API | 说明 |
| --- | --- |
| `POST /api/v1/auth/register` | 注册 `{ email, username, password }` |
| `POST /api/v1/auth/login` | 登录 `{ login\|email\|username, password }` → JWT |
| `POST /api/v1/auth/refresh` | 刷新 `{ refresh_token }` |
| `GET /api/v1/me` | 当前用户（需 Bearer） |
| `GET/PUT /api/v1/sync/hosts` | 主机列表 JSON 同步 |
| `GET/PUT /api/v1/sync/settings` | 主题/设置 JSON 同步 |
| `GET /health` | 健康检查 |

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

## Sync semantics / 同步语义

- 每个资源（hosts / settings）存一份 JSON + 服务端 `updated_at`（Unix ms）。
- **Last-write-wins**：客户端以服务端时间戳为准；`PUT` 会覆盖并更新 `updated_at`。
- 客户端合并策略见仓库根 README「云同步」：按条目 `updatedAt` 取较新者，再推回服务端。

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

## Dev notes

```bash
cargo check
cargo run
```

Feature `redis-cache` 默认开启（引入 `redis` crate）；无 Redis 时不设 `REDIS_URL` 即可。
