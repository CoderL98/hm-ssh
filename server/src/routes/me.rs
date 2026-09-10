use crate::auth::password::{hash_password, verify_password};
use crate::cache::{auth_user_key, profile_key, revoke_key, session_key};
use crate::db;
use crate::error::{AppError, AppResult};
use crate::routes::auth::{self, UserPublic, AuthResponse, MIN_PASSWORD_LEN};
use crate::routes::AuthUser;
use crate::state::AppState;
use axum::extract::State;
use axum::Json;
use serde::Deserialize;
use std::time::Duration;

pub async fn me(
    State(state): State<AppState>,
    AuthUser(claims): AuthUser,
) -> AppResult<Json<UserPublic>> {
    // Prefer cache
    if let Some(raw) = state.cache.get(&profile_key(&claims.sub)).await {
        if let Ok(u) = serde_json::from_str::<UserPublic>(&raw) {
            return Ok(Json(u));
        }
    }

    let user = db::find_user_by_id(&state.pool, &claims.sub)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;

    let public = UserPublic {
        id: user.id.clone(),
        email: user.email.clone(),
        username: user.username.clone(),
        created_at: user.created_at,
        is_admin: user.is_admin,
    };
    if let Ok(s) = serde_json::to_string(&public) {
        state
            .cache
            .set(&profile_key(&user.id), s, Duration::from_secs(3600))
            .await;
    }
    Ok(Json(public))
}

#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password: String,
}

/// Change password for the authenticated user.
/// Invalidates AuthUser/profile caches and prior sessions (revoke), then issues a fresh token pair.
pub async fn change_password(
    State(state): State<AppState>,
    AuthUser(claims): AuthUser,
    Json(body): Json<ChangePasswordRequest>,
) -> AppResult<Json<AuthResponse>> {
    if body.new_password.len() < MIN_PASSWORD_LEN {
        return Err(AppError::BadRequest(format!(
            "password must be at least {MIN_PASSWORD_LEN} characters"
        )));
    }
    if body.current_password.is_empty() {
        return Err(AppError::BadRequest("current password required".into()));
    }
    if body.current_password == body.new_password {
        return Err(AppError::BadRequest(
            "new password must differ from current password".into(),
        ));
    }

    let user = db::find_user_by_id(&state.pool, &claims.sub)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    if user.deleted_at.is_some() || user.disabled {
        return Err(AppError::Unauthorized("account disabled".into()));
    }

    let ok = verify_password(&body.current_password, &user.password_hash)
        .map_err(AppError::Internal)?;
    if !ok {
        return Err(AppError::Unauthorized("invalid current password".into()));
    }

    let password_hash = hash_password(&body.new_password).map_err(AppError::Internal)?;
    db::update_password_hash(&state.pool, &user.id, &password_hash).await?;

    // Drop cached auth status / profile; revoke prior sessions (incl. current refresh).
    state.cache.del(&auth_user_key(&user.id)).await;
    state.cache.del(&profile_key(&user.id)).await;
    state.cache.del(&session_key(&user.id)).await;
    let now = chrono::Utc::now().timestamp().to_string();
    state
        .cache
        .set(
            &revoke_key(&user.id),
            now,
            Duration::from_secs(state.config.jwt_refresh_ttl_secs as u64),
        )
        .await;

    // Re-read and issue fresh tokens (clears revoke inside issue_tokens).
    let user = db::find_user_by_id(&state.pool, &claims.sub)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    // issue_tokens returns Json<AuthResponse> via auth module helper — call through a small re-export path.
    // We duplicate the public issuance via auth::refresh-style: use internal helper by re-login pattern.
    change_password_issue(&state, &user).await
}

async fn change_password_issue(
    state: &AppState,
    user: &db::UserRow,
) -> AppResult<Json<AuthResponse>> {
    // Mirror auth::issue_tokens by going through a public path: reuse login issuance via module.
    // auth::issue_tokens is private — call auth helper by re-exporting through login-equivalent.
    auth::issue_tokens_for(state, user).await
}
