use crate::auth::password::{hash_password, verify_password};
use crate::cache::{profile_key, session_key};
use crate::db;
use crate::error::{AppError, AppResult};
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
    if db::find_user_by_username(&state.pool, &username).await?.is_some() {
        return Err(AppError::Conflict("username already taken".into()));
    }

    let password_hash = hash_password(&body.password)
        .map_err(|e| AppError::Internal(e))?;
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

    if body.password.is_empty() {
        return Err(AppError::BadRequest("password required".into()));
    }

    let user = db::find_user_by_login(&state.pool, &login)
        .await?
        .ok_or_else(|| AppError::Unauthorized("invalid credentials".into()))?;

    let ok = verify_password(&body.password, &user.password_hash)
        .map_err(|e| AppError::Internal(e))?;
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
    let user = db::find_user_by_id(&state.pool, &claims.sub)
        .await?
        .ok_or_else(|| AppError::Unauthorized("user not found".into()))?;
    issue_tokens(&state, &user).await
}

async fn issue_tokens(
    state: &AppState,
    user: &db::UserRow,
) -> AppResult<Json<AuthResponse>> {
    let (access_token, expires_at) = state
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

    // Hot cache: session flag + profile JSON
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
        .set(
            &profile_key(&user.id),
            profile,
            Duration::from_secs(3600),
        )
        .await;

    Ok(Json(AuthResponse {
        access_token,
        refresh_token,
        token_type: "Bearer".into(),
        expires_at,
        user: public,
    }))
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
