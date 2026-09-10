//! Database pool + queries. Backend selected by DATABASE_URL scheme.

use crate::error::{AppError, AppResult};
use sqlx::any::{Any, AnyPoolOptions};
use sqlx::{AnyPool, Row};
use uuid::Uuid;

pub type DbPool = AnyPool;

#[derive(Debug, Clone)]
pub struct UserRow {
    pub id: String,
    pub email: String,
    pub username: String,
    pub password_hash: String,
    pub created_at: i64,
    #[allow(dead_code)]
    pub updated_at: i64,
}

#[derive(Debug, Clone)]
pub struct SyncBlob {
    pub payload: String,
    #[allow(dead_code)]
    pub updated_at: i64,
}

pub async fn connect(database_url: &str) -> AppResult<DbPool> {
    // Required for sqlx::Any to resolve sqlite / postgres / mysql at runtime.
    sqlx::any::install_default_drivers();

    let url = normalize_sqlite_url(database_url);
    let pool = AnyPoolOptions::new()
        .max_connections(10)
        .connect(&url)
        .await
        .map_err(|e| AppError::Internal(anyhow::anyhow!("connect db: {e}")))?;

    run_migrations(&pool).await?;
    Ok(pool)
}

/// Normalize SQLite URLs so the file is created if missing (`mode=rwc`).
fn normalize_sqlite_url(url: &str) -> String {
    let lower = url.to_lowercase();
    if !(lower.starts_with("sqlite:") || lower.starts_with("sqlite://")) {
        return url.to_string();
    }
    // Already has query options
    if url.contains('?') {
        if !lower.contains("mode=") {
            return format!("{url}&mode=rwc");
        }
        return url.to_string();
    }
    // Prefer sqlite:path?mode=rwc form used by sqlx
    if lower.starts_with("sqlite://") {
        // sqlite:///abs or sqlite://rel
        return format!("{url}?mode=rwc");
    }
    // sqlite:hmssh.db → ensure creatable
    format!("{url}?mode=rwc")
}

async fn run_migrations(pool: &DbPool) -> AppResult<()> {
    // Inline portable DDL (same as migrations/001_init.sql) so Any backends work
    // without relying on sqlx migrate folder dialect quirks.
    let stmts = [
        r#"CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY NOT NULL,
            email TEXT NOT NULL,
            username TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            created_at BIGINT NOT NULL,
            updated_at BIGINT NOT NULL
        )"#,
        r#"CREATE TABLE IF NOT EXISTS user_hosts (
            user_id TEXT PRIMARY KEY NOT NULL,
            payload TEXT NOT NULL,
            updated_at BIGINT NOT NULL
        )"#,
        r#"CREATE TABLE IF NOT EXISTS user_settings (
            user_id TEXT PRIMARY KEY NOT NULL,
            payload TEXT NOT NULL,
            updated_at BIGINT NOT NULL
        )"#,
    ];
    for sql in stmts {
        sqlx::query(sql)
            .execute(pool)
            .await
            .map_err(|e| AppError::Internal(anyhow::anyhow!("migrate: {e}")))?;
    }
    // Unique indexes — IF NOT EXISTS is widely supported; ignore race duplicates.
    let indexes = [
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users (email)",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users (username)",
    ];
    for sql in indexes {
        if let Err(e) = sqlx::query(sql).execute(pool).await {
            tracing::warn!("index create (may already exist): {e}");
        }
    }
    Ok(())
}

pub async fn find_user_by_email(pool: &DbPool, email: &str) -> AppResult<Option<UserRow>> {
    let row = sqlx::query(
        "SELECT id, email, username, password_hash, created_at, updated_at FROM users WHERE email = ?",
    )
    .bind(email)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(map_user))
}

pub async fn find_user_by_username(pool: &DbPool, username: &str) -> AppResult<Option<UserRow>> {
    let row = sqlx::query(
        "SELECT id, email, username, password_hash, created_at, updated_at FROM users WHERE username = ?",
    )
    .bind(username)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(map_user))
}

pub async fn find_user_by_login(pool: &DbPool, login: &str) -> AppResult<Option<UserRow>> {
    let row = sqlx::query(
        "SELECT id, email, username, password_hash, created_at, updated_at FROM users WHERE email = ? OR username = ?",
    )
    .bind(login)
    .bind(login)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(map_user))
}

pub async fn find_user_by_id(pool: &DbPool, id: &str) -> AppResult<Option<UserRow>> {
    let row = sqlx::query(
        "SELECT id, email, username, password_hash, created_at, updated_at FROM users WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(map_user))
}

pub async fn insert_user(
    pool: &DbPool,
    email: &str,
    username: &str,
    password_hash: &str,
) -> AppResult<UserRow> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    sqlx::query(
        "INSERT INTO users (id, email, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(email)
    .bind(username)
    .bind(password_hash)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await
    .map_err(|e| {
        let msg = e.to_string().to_lowercase();
        if msg.contains("unique") || msg.contains("duplicate") {
            AppError::Conflict("email or username already registered".into())
        } else {
            AppError::Sqlx(e)
        }
    })?;
    Ok(UserRow {
        id,
        email: email.to_string(),
        username: username.to_string(),
        password_hash: password_hash.to_string(),
        created_at: now,
        updated_at: now,
    })
}

pub async fn get_hosts(pool: &DbPool, user_id: &str) -> AppResult<Option<SyncBlob>> {
    get_blob(pool, "user_hosts", user_id).await
}

pub async fn put_hosts(pool: &DbPool, user_id: &str, payload: &str) -> AppResult<SyncBlob> {
    put_blob(pool, "user_hosts", user_id, payload).await
}

pub async fn get_settings(pool: &DbPool, user_id: &str) -> AppResult<Option<SyncBlob>> {
    get_blob(pool, "user_settings", user_id).await
}

pub async fn put_settings(pool: &DbPool, user_id: &str, payload: &str) -> AppResult<SyncBlob> {
    put_blob(pool, "user_settings", user_id, payload).await
}

async fn get_blob(pool: &DbPool, table: &str, user_id: &str) -> AppResult<Option<SyncBlob>> {
    // table is internal constant only
    let sql = format!("SELECT payload, updated_at FROM {table} WHERE user_id = ?");
    let row = sqlx::query(&sql).bind(user_id).fetch_optional(pool).await?;
    Ok(row.map(|r| SyncBlob {
        payload: r.get::<String, _>("payload"),
        updated_at: r.get::<i64, _>("updated_at"),
    }))
}

async fn put_blob(
    pool: &DbPool,
    table: &str,
    user_id: &str,
    payload: &str,
) -> AppResult<SyncBlob> {
    let now = chrono::Utc::now().timestamp_millis();
    // Upsert: try update then insert (portable across SQLite/PG/MySQL without ON CONFLICT dialect)
    let update_sql = format!("UPDATE {table} SET payload = ?, updated_at = ? WHERE user_id = ?");
    let result = sqlx::query(&update_sql)
        .bind(payload)
        .bind(now)
        .bind(user_id)
        .execute(pool)
        .await?;
    if result.rows_affected() == 0 {
        let insert_sql =
            format!("INSERT INTO {table} (user_id, payload, updated_at) VALUES (?, ?, ?)");
        sqlx::query(&insert_sql)
            .bind(user_id)
            .bind(payload)
            .bind(now)
            .execute(pool)
            .await?;
    }
    Ok(SyncBlob {
        payload: payload.to_string(),
        updated_at: now,
    })
}

fn map_user(row: sqlx::any::AnyRow) -> UserRow {
    UserRow {
        id: row.get("id"),
        email: row.get("email"),
        username: row.get("username"),
        password_hash: row.get("password_hash"),
        created_at: row.get("created_at"),
        updated_at: row.get("updated_at"),
    }
}

// silence unused import warning for Any in some feature combos
#[allow(dead_code)]
fn _ty(_: Any) {}
