//! Admin management API under `/api/v1/admin/*`.

use crate::cache::{auth_user_key, profile_key, revoke_key, session_key};
use crate::db;
use crate::error::{AppError, AppResult};
use crate::routes::AuthUser;
use crate::state::AppState;
use axum::extract::{Path, Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::Duration;

#[derive(Debug, Serialize)]
pub struct AdminStats {
    pub user_count: i64,
    pub admin_count: i64,
    pub disabled_count: i64,
    pub health: String,
    pub db_backend: String,
}

#[derive(Debug, Serialize)]
pub struct AdminUserView {
    pub id: String,
    pub email: String,
    pub username: String,
    pub created_at: i64,
    pub last_login_at: Option<i64>,
    pub is_admin: bool,
    pub disabled: bool,
    pub deleted_at: Option<i64>,
}

impl From<&db::UserRow> for AdminUserView {
    fn from(u: &db::UserRow) -> Self {
        Self {
            id: u.id.clone(),
            email: u.email.clone(),
            username: u.username.clone(),
            created_at: u.created_at,
            last_login_at: u.last_login_at,
            is_admin: u.is_admin,
            disabled: u.disabled,
            deleted_at: u.deleted_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct ListUsersQuery {
    pub q: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct PatchUserBody {
    pub disabled: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct OkResponse {
    pub ok: bool,
}

#[derive(Debug, Serialize)]
pub struct SyncMeta {
    pub hosts: BlobMeta,
    pub settings: BlobMeta,
}

#[derive(Debug, Serialize)]
pub struct BlobMeta {
    pub updated_at: i64,
    pub byte_size: usize,
    pub item_count: Option<usize>,
}

/// Ensure caller is an active admin (JWT claim + live DB flag).
pub async fn require_admin(state: &AppState, auth: &AuthUser) -> AppResult<db::UserRow> {
    let user = db::find_user_by_id(&state.pool, &auth.0.sub)
        .await?
        .ok_or_else(|| AppError::Unauthorized("user not found".into()))?;
    if user.deleted_at.is_some() || user.disabled {
        return Err(AppError::Forbidden("account disabled".into()));
    }
    if !user.is_admin && !auth.0.is_admin {
        return Err(AppError::Forbidden("admin required".into()));
    }
    if !user.is_admin {
        return Err(AppError::Forbidden("admin required".into()));
    }
    Ok(user)
}

pub async fn stats(
    State(state): State<AppState>,
    auth: AuthUser,
) -> AppResult<Json<AdminStats>> {
    require_admin(&state, &auth).await?;
    Ok(Json(AdminStats {
        user_count: db::count_users(&state.pool).await?,
        admin_count: db::count_admins(&state.pool).await?,
        disabled_count: db::count_disabled(&state.pool).await?,
        health: "ok".into(),
        db_backend: state.config.db_backend_label().into(),
    }))
}

pub async fn list_users(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<ListUsersQuery>,
) -> AppResult<Json<Vec<AdminUserView>>> {
    require_admin(&state, &auth).await?;
    let users = db::list_users(&state.pool, q.q.as_deref()).await?;
    Ok(Json(users.iter().map(AdminUserView::from).collect()))
}

pub async fn get_user(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<AdminUserView>> {
    require_admin(&state, &auth).await?;
    let user = db::find_user_by_id(&state.pool, &id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    Ok(Json(AdminUserView::from(&user)))
}

pub async fn patch_user(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<PatchUserBody>,
) -> AppResult<Json<AdminUserView>> {
    let admin = require_admin(&state, &auth).await?;
    let user = db::find_user_by_id(&state.pool, &id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    if user.deleted_at.is_some() {
        return Err(AppError::BadRequest("user is deleted".into()));
    }
    if let Some(disabled) = body.disabled {
        if disabled && user.id == admin.id {
            return Err(AppError::BadRequest("cannot disable yourself".into()));
        }
        db::set_disabled(&state.pool, &id, disabled).await?;
        // Always drop AuthUser cache so disable/re-enable is prompt within TTL.
        state.cache.del(&auth_user_key(&id)).await;
        if disabled {
            revoke_sessions(&state, &id).await;
        }
    }
    let updated = db::find_user_by_id(&state.pool, &id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    Ok(Json(AdminUserView::from(&updated)))
}

pub async fn delete_user(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<OkResponse>> {
    let admin = require_admin(&state, &auth).await?;
    let user = db::find_user_by_id(&state.pool, &id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    if user.id == admin.id {
        return Err(AppError::BadRequest("cannot delete yourself".into()));
    }
    db::soft_delete_user(&state.pool, &id).await?;
    revoke_sessions(&state, &id).await;
    Ok(Json(OkResponse { ok: true }))
}

pub async fn revoke_user(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<OkResponse>> {
    require_admin(&state, &auth).await?;
    let _user = db::find_user_by_id(&state.pool, &id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;
    revoke_sessions(&state, &id).await;
    Ok(Json(OkResponse { ok: true }))
}

pub async fn user_sync_meta(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<SyncMeta>> {
    require_admin(&state, &auth).await?;
    let _user = db::find_user_by_id(&state.pool, &id)
        .await?
        .ok_or_else(|| AppError::NotFound("user not found".into()))?;

    let hosts = db::get_hosts(&state.pool, &id).await?;
    let settings = db::get_settings(&state.pool, &id).await?;

    Ok(Json(SyncMeta {
        hosts: blob_meta(hosts.as_ref(), true),
        settings: blob_meta(settings.as_ref(), false),
    }))
}

fn blob_meta(blob: Option<&db::SyncBlob>, hosts: bool) -> BlobMeta {
    match blob {
        Some(b) => {
            let item_count = if hosts {
                serde_json::from_str::<Value>(&b.payload)
                    .ok()
                    .and_then(|v| v.as_array().map(|a| a.len()))
            } else {
                None
            };
            // Never return payload / secrets — sizes + timestamps only.
            let _ = json!({"stripped": true});
            BlobMeta {
                updated_at: b.updated_at,
                byte_size: b.payload.len(),
                item_count,
            }
        }
        None => BlobMeta {
            updated_at: 0,
            byte_size: 0,
            item_count: if hosts { Some(0) } else { None },
        },
    }
}

async fn revoke_sessions(state: &AppState, user_id: &str) {
    let now = chrono::Utc::now().timestamp().to_string();
    state
        .cache
        .set(
            &revoke_key(user_id),
            now,
            Duration::from_secs(state.config.jwt_refresh_ttl_secs as u64),
        )
        .await;
    state.cache.del(&session_key(user_id)).await;
    state.cache.del(&profile_key(user_id)).await;
    state.cache.del(&auth_user_key(user_id)).await;
}
