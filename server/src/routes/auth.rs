use crate::auth::password::{hash_password, verify_password};
use crate::cache::{profile_key, revoke_key, session_key};
use crate::db;
use crate::error::{AppError, AppResult};
use crate::routes::AuthUser;
use crate::state::AppState;
use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use std::time::Duration;

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
}

#[derive(Debug, Serialize)]
pub struct LogoutResponse {
    pub ok: bool,
}

pub async fn register(
    State(state): State<AppState>,
    Json(body): Json<RegisterRequest>,
) -> AppResult<Json<AuthResponse>> {
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
    Json(body): Json<LoginRequest>,
) -> AppResult<Json<AuthResponse>> {
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

    issue_tokens(&state, &user).await
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshRequest>,
) -> AppResult<Json<AuthResponse>> {
    let claims = state.jwt.decode_refresh(&body.refresh_token)?;
    // Reject refresh if user logged out after this token was issued
    if is_revoked(&state, &claims.sub, claims.iat).await {
        return Err(AppError::Unauthorized("session revoked".into()));
    }
    let user = db::find_user_by_id(&state.pool, &claims.sub)
        .await?
        .ok_or_else(|| AppError::Unauthorized("user not found".into()))?;
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
    let (access_token, expires_at) =
        state
            .jwt
            .issue_access(&user.id, &user.email, &user.username)?;
    let (refresh_token, _) = state
        .jwt
        .issue_refresh(&user.id, &user.email, &user.username)?;

    let public = UserPublic {
        id: user.id.clone(),
        email: user.email.clone(),
        username: user.username.clone(),
        created_at: user.created_at,
    };

    // Clear revoke marker so new tokens work after re-login
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

fn validate_credentials(email: &str, username: &str, password: &str) -> AppResult<()> {
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
    if password.len() < 8 {
        return Err(AppError::BadRequest(
            "password must be at least 8 characters".into(),
        ));
    }
    Ok(())
}
