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
    pub is_admin: bool,
    pub disabled: bool,
    pub last_login_at: Option<i64>,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct SyncBlob {
    pub payload: String,
    pub updated_at: i64,
}

pub async fn connect(database_url: &str) -> AppResult<DbPool> {
    // Required for sqlx::Any to resolve sqlite / postgres / mysql at runtime.
    sqlx::any::install_default_drivers();

    let url = normalize_sqlite_url(database_url);
    // sqlx pool: keep a small warm set; raise max_connections behind a real PG/MySQL
    // deployment if admin/list + sync traffic grows. SQLite benefits little from >~5 writers.
    let pool = AnyPoolOptions::new()
        .max_connections(10)
        .min_connections(1)
        .acquire_timeout(std::time::Duration::from_secs(8))
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
    if url.contains('?') {
        if !lower.contains("mode=") {
            return format!("{url}&mode=rwc");
        }
        return url.to_string();
    }
    if lower.starts_with("sqlite://") {
        return format!("{url}?mode=rwc");
    }
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
    let indexes = [
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users (email)",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users (username)",
    ];
    for sql in indexes {
        if let Err(e) = sqlx::query(sql).execute(pool).await {
            tracing::warn!("index create (may already exist): {e}");
        }
    }

    // 002_admin: additive columns (ignore if already present)
    let alters = [
        "ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE users ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE users ADD COLUMN last_login_at BIGINT",
        "ALTER TABLE users ADD COLUMN deleted_at BIGINT",
    ];
    for sql in alters {
        if let Err(e) = sqlx::query(sql).execute(pool).await {
            let msg = e.to_string().to_lowercase();
            if msg.contains("duplicate")
                || msg.contains("already exists")
                || msg.contains("existing column")
            {
                tracing::debug!("alter skip (column exists): {e}");
            } else {
                tracing::warn!("alter (may already exist): {e}");
            }
        }
    }
    Ok(())
}

const USER_COLS: &str =
    "id, email, username, password_hash, created_at, updated_at, is_admin, disabled, last_login_at, deleted_at";

pub async fn find_user_by_email(pool: &DbPool, email: &str) -> AppResult<Option<UserRow>> {
    let sql = format!("SELECT {USER_COLS} FROM users WHERE email = ?");
    let row = sqlx::query(&sql).bind(email).fetch_optional(pool).await?;
    Ok(row.map(map_user))
}

pub async fn find_user_by_username(pool: &DbPool, username: &str) -> AppResult<Option<UserRow>> {
    let sql = format!("SELECT {USER_COLS} FROM users WHERE username = ?");
    let row = sqlx::query(&sql)
        .bind(username)
        .fetch_optional(pool)
        .await?;
    Ok(row.map(map_user))
}

pub async fn find_user_by_login(pool: &DbPool, login: &str) -> AppResult<Option<UserRow>> {
    let sql = format!("SELECT {USER_COLS} FROM users WHERE email = ? OR username = ?");
    let row = sqlx::query(&sql)
        .bind(login)
        .bind(login)
        .fetch_optional(pool)
        .await?;
    Ok(row.map(map_user))
}

pub async fn find_user_by_id(pool: &DbPool, id: &str) -> AppResult<Option<UserRow>> {
    let sql = format!("SELECT {USER_COLS} FROM users WHERE id = ?");
    let row = sqlx::query(&sql).bind(id).fetch_optional(pool).await?;
    Ok(row.map(map_user))
}

pub async fn insert_user(
    pool: &DbPool,
    email: &str,
    username: &str,
    password_hash: &str,
) -> AppResult<UserRow> {
    insert_user_full(pool, email, username, password_hash, false).await
}

pub async fn insert_user_full(
    pool: &DbPool,
    email: &str,
    username: &str,
    password_hash: &str,
    is_admin: bool,
) -> AppResult<UserRow> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    let admin_i: i64 = if is_admin { 1 } else { 0 };
    sqlx::query(
        "INSERT INTO users (id, email, username, password_hash, created_at, updated_at, is_admin, disabled) VALUES (?, ?, ?, ?, ?, ?, ?, 0)",
    )
    .bind(&id)
    .bind(email)
    .bind(username)
    .bind(password_hash)
    .bind(now)
    .bind(now)
    .bind(admin_i)
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
        is_admin,
        disabled: false,
        last_login_at: None,
        deleted_at: None,
    })
}

/// Seed first admin from env if missing. If email exists, promote to admin.
pub async fn seed_admin_if_needed(
    pool: &DbPool,
    email: &str,
    password: &str,
) -> AppResult<Option<UserRow>> {
    let email = email.trim().to_lowercase();
    if email.is_empty() || !email.contains('@') || password.len() < 8 {
        tracing::warn!("ADMIN_EMAIL/ADMIN_PASSWORD invalid or too short; skip seed");
        return Ok(None);
    }
    if let Some(mut existing) = find_user_by_email(pool, &email).await? {
        if !existing.is_admin {
            set_is_admin(pool, &existing.id, true).await?;
            existing.is_admin = true;
            tracing::info!(email = %email, "promoted existing user to admin");
        } else {
            tracing::info!(email = %email, "admin already present");
        }
        return Ok(Some(existing));
    }
    let local = email
        .split('@')
        .next()
        .unwrap_or("admin")
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect::<String>();
    let mut username = if local.len() >= 3 {
        local
    } else {
        "admin".into()
    };
    // Ensure unique username
    if find_user_by_username(pool, &username).await?.is_some() {
        username = format!("admin_{}", &Uuid::new_v4().to_string()[..8]);
    }
    let hash = crate::auth::password::hash_password(password)
        .map_err(AppError::Internal)?;
    let user = insert_user_full(pool, &email, &username, &hash, true).await?;
    tracing::info!(email = %email, username = %username, "seeded first admin user");
    Ok(Some(user))
}

pub async fn set_is_admin(pool: &DbPool, user_id: &str, is_admin: bool) -> AppResult<()> {
    let v: i64 = if is_admin { 1 } else { 0 };
    let now = chrono::Utc::now().timestamp_millis();
    sqlx::query("UPDATE users SET is_admin = ?, updated_at = ? WHERE id = ?")
        .bind(v)
        .bind(now)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn set_disabled(pool: &DbPool, user_id: &str, disabled: bool) -> AppResult<()> {
    let v: i64 = if disabled { 1 } else { 0 };
    let now = chrono::Utc::now().timestamp_millis();
    sqlx::query("UPDATE users SET disabled = ?, updated_at = ? WHERE id = ?")
        .bind(v)
        .bind(now)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn soft_delete_user(pool: &DbPool, user_id: &str) -> AppResult<()> {
    let now = chrono::Utc::now().timestamp_millis();
    sqlx::query(
        "UPDATE users SET disabled = 1, deleted_at = ?, updated_at = ? WHERE id = ?",
    )
    .bind(now)
    .bind(now)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn update_password_hash(pool: &DbPool, user_id: &str, password_hash: &str) -> AppResult<()> {
    let now = chrono::Utc::now().timestamp_millis();
    sqlx::query("UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?")
        .bind(password_hash)
        .bind(now)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn touch_last_login(pool: &DbPool, user_id: &str) -> AppResult<()> {
    let now = chrono::Utc::now().timestamp_millis();
    sqlx::query("UPDATE users SET last_login_at = ?, updated_at = ? WHERE id = ?")
        .bind(now)
        .bind(now)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

#[derive(Debug, Clone)]
pub struct UserPage {
    pub items: Vec<UserRow>,
    pub total: i64,
    pub page: u32,
    pub page_size: u32,
}

/// Admin user list with true pagination. Includes soft-deleted users so admins can see self-deletes.
pub async fn list_users_page(
    pool: &DbPool,
    q: Option<&str>,
    page: u32,
    page_size: u32,
) -> AppResult<UserPage> {
    let page = page.max(1);
    let page_size = page_size.clamp(1, 100);
    let offset = ((page - 1) as i64) * (page_size as i64);
    let pattern = q
        .filter(|s| !s.trim().is_empty())
        .map(|s| format!("%{}%", s.trim()));

    let total: i64 = if let Some(ref pattern) = pattern {
        let sql = "SELECT COUNT(*) AS c FROM users WHERE (email LIKE ? OR username LIKE ? OR id LIKE ?)";
        let row = sqlx::query(sql)
            .bind(pattern)
            .bind(pattern)
            .bind(pattern)
            .fetch_one(pool)
            .await?;
        row.get::<i64, _>("c")
    } else {
        let row = sqlx::query("SELECT COUNT(*) AS c FROM users")
            .fetch_one(pool)
            .await?;
        row.get::<i64, _>("c")
    };

    let rows = if let Some(ref pattern) = pattern {
        let sql = format!(
            "SELECT {USER_COLS} FROM users WHERE (email LIKE ? OR username LIKE ? OR id LIKE ?) ORDER BY created_at DESC LIMIT ? OFFSET ?"
        );
        sqlx::query(&sql)
            .bind(pattern)
            .bind(pattern)
            .bind(pattern)
            .bind(page_size as i64)
            .bind(offset)
            .fetch_all(pool)
            .await?
    } else {
        let sql = format!(
            "SELECT {USER_COLS} FROM users ORDER BY created_at DESC LIMIT ? OFFSET ?"
        );
        sqlx::query(&sql)
            .bind(page_size as i64)
            .bind(offset)
            .fetch_all(pool)
            .await?
    };

    Ok(UserPage {
        items: rows.into_iter().map(map_user).collect(),
        total,
        page,
        page_size,
    })
}

/// Backward-compatible helper used by older call sites / tests.
pub async fn list_users(pool: &DbPool, q: Option<&str>) -> AppResult<Vec<UserRow>> {
    let page = list_users_page(pool, q, 1, 200).await?;
    Ok(page.items)
}

pub async fn delete_user_sync_blobs(pool: &DbPool, user_id: &str) -> AppResult<()> {
    sqlx::query("DELETE FROM user_hosts WHERE user_id = ?")
        .bind(user_id)
        .execute(pool)
        .await?;
    sqlx::query("DELETE FROM user_settings WHERE user_id = ?")
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn count_users(pool: &DbPool) -> AppResult<i64> {
    let row = sqlx::query("SELECT COUNT(*) AS c FROM users WHERE deleted_at IS NULL")
        .fetch_one(pool)
        .await?;
    Ok(row.get::<i64, _>("c"))
}

pub async fn count_admins(pool: &DbPool) -> AppResult<i64> {
    let row = sqlx::query(
        "SELECT COUNT(*) AS c FROM users WHERE deleted_at IS NULL AND is_admin = 1",
    )
    .fetch_one(pool)
    .await?;
    Ok(row.get::<i64, _>("c"))
}

pub async fn count_disabled(pool: &DbPool) -> AppResult<i64> {
    let row = sqlx::query(
        "SELECT COUNT(*) AS c FROM users WHERE deleted_at IS NULL AND disabled = 1",
    )
    .fetch_one(pool)
    .await?;
    Ok(row.get::<i64, _>("c"))
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
    let sql = format!("SELECT payload, updated_at FROM {table} WHERE user_id = ?");
    let row = sqlx::query(&sql).bind(user_id).fetch_optional(pool).await?;
    Ok(row.map(|r| SyncBlob {
        payload: r.get::<String, _>("payload"),
        updated_at: r.get::<i64, _>("updated_at"),
    }))
}

async fn put_blob(pool: &DbPool, table: &str, user_id: &str, payload: &str) -> AppResult<SyncBlob> {
    let now = chrono::Utc::now().timestamp_millis();
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
    let is_admin = row.try_get::<i64, _>("is_admin").unwrap_or(0) != 0;
    let disabled = row.try_get::<i64, _>("disabled").unwrap_or(0) != 0;
    let last_login_at = row
        .try_get::<Option<i64>, _>("last_login_at")
        .ok()
        .flatten();
    let deleted_at = row
        .try_get::<Option<i64>, _>("deleted_at")
        .ok()
        .flatten();
    UserRow {
        id: row.get("id"),
        email: row.get("email"),
        username: row.get("username"),
        password_hash: row.get("password_hash"),
        created_at: row.get("created_at"),
        updated_at: row.get("updated_at"),
        is_admin,
        disabled,
        last_login_at,
        deleted_at,
    }
}

#[allow(dead_code)]
fn _ty(_: Any) {}
