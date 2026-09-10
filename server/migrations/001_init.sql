-- Portable across SQLite / PostgreSQL / MySQL (sqlx Any).
-- Timestamps are Unix milliseconds (INTEGER / BIGINT).

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY NOT NULL,
    email TEXT NOT NULL,
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users (username);

-- Host list JSON blob per user (additive to client HostStore)
CREATE TABLE IF NOT EXISTS user_hosts (
    user_id TEXT PRIMARY KEY NOT NULL,
    payload TEXT NOT NULL,
    updated_at BIGINT NOT NULL
);

-- Theme / settings JSON blob per user
CREATE TABLE IF NOT EXISTS user_settings (
    user_id TEXT PRIMARY KEY NOT NULL,
    payload TEXT NOT NULL,
    updated_at BIGINT NOT NULL
);
