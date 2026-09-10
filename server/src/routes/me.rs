use crate::cache::profile_key;
use crate::db;
use crate::error::{AppError, AppResult};
use crate::routes::auth::UserPublic;
use crate::routes::AuthUser;
use crate::state::AppState;
use axum::extract::State;
use axum::Json;
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
