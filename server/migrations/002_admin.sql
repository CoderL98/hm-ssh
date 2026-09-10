-- 002_admin: account lifecycle + admin flag (applied via ALTER in db::run_migrations).
-- Portable INTEGER/BIGINT across SQLite / PostgreSQL / MySQL (sqlx Any).

-- ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0;
-- ALTER TABLE users ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0;
-- ALTER TABLE users ADD COLUMN last_login_at BIGINT;
-- ALTER TABLE users ADD COLUMN deleted_at BIGINT;
