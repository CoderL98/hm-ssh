use crate::auth::password::{hash_password, verify_password};
use crate::cache::{jti_deny_key, profile_key, revoke_key, session_key};
use crate::db;
use crate::error::{AppError, AppResult};
use crate::routes::AuthUser;
use crate::state::AppState;
use axum::extract::{ConnectInfo, State};
use axum::http::HeaderMap;
use axum::Json;
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::time::Duration;

/// Shared password minimum (keep in sync with client MockAuthService / AccountPage).
pub const MIN_PASSWORD_LEN: usize = 8;

#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub email: String,
    pub username: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    /// Email or username
    pub login: Option<String>,
    pub email: Option<String>,
    pub username: Option<String>,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_at: i64,
    pub user: UserPublic,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UserPublic {
    pub id: String,
    pub email: String,
    pub username: String,
    pub created_at: i64,
    #[serde(default)]
    pub is_admin: bool,
}

#[derive(Debug, Serialize)]
pub struct LogoutResponse {
    pub ok: bool,
}

pub async fn register(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<RegisterRequest>,
) -> AppResult<Json<AuthResponse>> {
    enforce_auth_rate_limit(&state, &headers, &addr)?;

    let email = body.email.trim().to_lowercase();
    let username = body.username.trim().to_string();
    validate_credentials(&email, &username, &body.password)?;

    if db::find_user_by_email(&state.pool, &email).await?.is_some() {
        return Err(AppError::Conflict("email already registered".into()));
    }
    if db::find_user_by_username(&state.pool, &username)
        .await?
        .is_some()
    {
        return Err(AppError::Conflict("username already taken".into()));
    }

    let password_hash = hash_password(&body.password).map_err(AppError::Internal)?;
    let user = db::insert_user(&state.pool, &email, &username, &password_hash).await?;
    issue_tokens(&state, &user).await
}

pub async fn login(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<LoginRequest>,
) -> AppResult<Json<AuthResponse>> {
    enforce_auth_rate_limit(&state, &headers, &addr)?;

    let login = body
        .login
        .or(body.email)
        .or(body.username)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| AppError::BadRequest("login/email/username required".into()))?;

    // Emails are stored lowercased at register — normalize when login looks like email
    let login = if login.contains('@') {
        login.to_lowercase()
    } else {
        login
    };

    if body.password.is_empty() {
        return Err(AppError::BadRequest("password required".into()));
    }

    let user = db::find_user_by_login(&state.pool, &login)
        .await?
        .ok_or_else(|| AppError::Unauthorized("invalid credentials".into()))?;

    let ok = verify_password(&body.password, &user.password_hash).map_err(AppError::Internal)?;
    if !ok {
        return Err(AppError::Unauthorized("invalid credentials".into()));
    }

    if user.deleted_at.is_some() {
        return Err(AppError::Unauthorized("account deleted".into()));
    }
    if user.disabled {
        return Err(AppError::Unauthorized("account disabled".into()));
    }

    let _ = db::touch_last_login(&state.pool, &user.id).await;
    issue_tokens(&state, &user).await
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshRequest>,
) -> AppResult<Json<AuthResponse>> {
    let claims = state.jwt.decode_refresh(&body.refresh_token)?;

    // Light refresh rotation: previously used refresh jti is denylisted
    if state
        .cache
        .get(&jti_deny_key(&claims.jti))
        .await
        .is_some()
    {
        return Err(AppError::Unauthorized("refresh token revoked".into()));
    }

    // Reject refresh if user logged out after this token was issued
    if is_revoked(&state, &claims.sub, claims.iat).await {
        return Err(AppError::Unauthorized("session revoked".into()));
    }
    let user = db::find_user_by_id(&state.pool, &claims.sub)
        .await?
        .ok_or_else(|| AppError::Unauthorized("user not found".into()))?;
    if user.deleted_at.is_some() || user.disabled {
        return Err(AppError::Unauthorized("account disabled".into()));
    }

    // Revoke the presented refresh jti before issuing a new pair
    let remaining = (claims.exp - chrono::Utc::now().timestamp()).max(1) as u64;
    state
        .cache
        .set(
            &jti_deny_key(&claims.jti),
            "1".into(),
            Duration::from_secs(remaining),
        )
        .await;

    issue_tokens(&state, &user).await
}

/// Invalidate session/profile cache and mark user revoked-at = now.
pub async fn logout(
    State(state): State<AppState>,
    AuthUser(claims): AuthUser,
) -> AppResult<Json<LogoutResponse>> {
    let now = chrono::Utc::now().timestamp().to_string();
    state
        .cache
        .set(
            &revoke_key(&claims.sub),
            now,
            Duration::from_secs(state.config.jwt_refresh_ttl_secs as u64),
        )
        .await;
    state.cache.del(&session_key(&claims.sub)).await;
    state.cache.del(&profile_key(&claims.sub)).await;
    Ok(Json(LogoutResponse { ok: true }))
}

async fn issue_tokens(state: &AppState, user: &db::UserRow) -> AppResult<Json<AuthResponse>> {
    let (access_token, expires_at) = state.jwt.issue_access(
        &user.id,
        &user.email,
        &user.username,
        user.is_admin,
    )?;
    let (refresh_token, _) = state.jwt.issue_refresh(
        &user.id,
        &user.email,
        &user.username,
        user.is_admin,
    )?;

    let public = UserPublic {
        id: user.id.clone(),
        email: user.email.clone(),
        username: user.username.clone(),
        created_at: user.created_at,
        is_admin: user.is_admin,
    };

    // Clear user-level revoke marker so new tokens work after re-login
    state.cache.del(&revoke_key(&user.id)).await;

    let profile = serde_json::to_string(&public).unwrap_or_default();
    state
        .cache
        .set(
            &session_key(&user.id),
            "1".into(),
            Duration::from_secs(state.config.jwt_access_ttl_secs as u64),
        )
        .await;
    state
        .cache
        .set(&profile_key(&user.id), profile, Duration::from_secs(3600))
        .await;

    Ok(Json(AuthResponse {
        access_token,
        refresh_token,
        token_type: "Bearer".into(),
        expires_at,
        user: public,
    }))
}

pub async fn is_revoked(state: &AppState, user_id: &str, token_iat: i64) -> bool {
    if let Some(raw) = state.cache.get(&revoke_key(user_id)).await {
        if let Ok(rev_at) = raw.parse::<i64>() {
            // Token issued at-or-before revoke timestamp is dead
            return token_iat <= rev_at;
        }
    }
    false
}

fn enforce_auth_rate_limit(
    state: &AppState,
    headers: &HeaderMap,
    addr: &SocketAddr,
) -> AppResult<()> {
    let ip = client_ip(headers, addr);
    state
        .auth_rate_limiter
        .check(&format!("auth:{ip}"))
        .map_err(|_| {
            AppError::TooManyRequests(format!(
                "too many auth attempts; limit {} req/min per IP",
                state.auth_rate_limiter.max_per_window()
            ))
        })?;
    Ok(())
}

fn client_ip(headers: &HeaderMap, addr: &SocketAddr) -> String {
    if let Some(xff) = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
    {
        if let Some(first) = xff.split(',').next() {
            let trimmed = first.trim();
            if !trimmed.is_empty() {
                return trimmed.to_string();
            }
        }
    }
    if let Some(real) = headers.get("x-real-ip").and_then(|v| v.to_str().ok()) {
        let trimmed = real.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    addr.ip().to_string()
}

pub fn validate_credentials(email: &str, username: &str, password: &str) -> AppResult<()> {
    if email.is_empty() || !email.contains('@') {
        return Err(AppError::BadRequest("valid email required".into()));
    }
    if username.len() < 3 || username.len() > 32 {
        return Err(AppError::BadRequest(
            "username must be 3–32 characters".into(),
        ));
    }
    if !username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err(AppError::BadRequest(
            "username may only contain letters, digits, _ and -".into(),
        ));
    }
    if password.len() < MIN_PASSWORD_LEN {
        return Err(AppError::BadRequest(format!(
            "password must be at least {MIN_PASSWORD_LEN} characters"
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_min_eight() {
        let err = validate_credentials("a@b.com", "alice", "short").unwrap_err();
        match err {
            AppError::BadRequest(m) => assert!(m.contains("8")),
            other => panic!("unexpected {other:?}"),
        }
        assert!(validate_credentials("a@b.com", "alice", "secret12").is_ok());
    }

    #[test]
    fn username_rules() {
        assert!(validate_credentials("a@b.com", "ab", "secret12").is_err());
        assert!(validate_credentials("a@b.com", "alice!", "secret12").is_err());
        assert!(validate_credentials("not-an-email", "alice", "secret12").is_err());
    }
}
