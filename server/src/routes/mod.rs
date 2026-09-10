pub mod admin;
pub mod auth;
pub mod health;
pub mod me;
pub mod sync;

use crate::auth::jwt::Claims;
use crate::cache::{auth_user_key, AUTH_USER_CACHE_TTL_SECS};
use crate::db;
use crate::error::{AppError, AppResult};
use crate::state::AppState;
use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use std::time::Duration;

pub struct AuthUser(pub Claims);

/// Cached AuthUser DB status. Positive ("ok") lookups are cached with a short TTL;
/// disabled/deleted are rejected and any stale positive entry is deleted.
const CACHE_OK: &str = "ok";
const CACHE_DISABLED: &str = "disabled";

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| AppError::Unauthorized("missing Authorization header".into()))?;

        let token = header
            .strip_prefix("Bearer ")
            .or_else(|| header.strip_prefix("bearer "))
            .ok_or_else(|| AppError::Unauthorized("expected Bearer token".into()))?;

        let claims = state.jwt.decode_access(token)?;
        if auth::is_revoked(state, &claims.sub, claims.iat).await {
            return Err(AppError::Unauthorized("session revoked".into()));
        }

        // Short-TTL cache of positive user lookups (invalidate-on-write preferred).
        let cache_key = auth_user_key(&claims.sub);
        if let Some(raw) = state.cache.get(&cache_key).await {
            match raw.as_str() {
                CACHE_OK => return Ok(AuthUser(claims)),
                CACHE_DISABLED => {
                    return Err(AppError::Unauthorized("account disabled".into()));
                }
                _ => {
                    // Unknown / corrupt → fall through to DB
                    state.cache.del(&cache_key).await;
                }
            }
        }

        match db::find_user_by_id(&state.pool, &claims.sub).await? {
            Some(user) if user.deleted_at.is_some() || user.disabled => {
                // Cache disabled briefly so repeated hits stay cheap; revoke/disable
                // paths also invalidate so re-enable is prompt.
                state
                    .cache
                    .set(
                        &cache_key,
                        CACHE_DISABLED.into(),
                        Duration::from_secs(AUTH_USER_CACHE_TTL_SECS),
                    )
                    .await;
                return Err(AppError::Unauthorized("account disabled".into()));
            }
            None => {
                state.cache.del(&cache_key).await;
                return Err(AppError::Unauthorized("user not found".into()));
            }
            Some(_) => {
                state
                    .cache
                    .set(
                        &cache_key,
                        CACHE_OK.into(),
                        Duration::from_secs(AUTH_USER_CACHE_TTL_SECS),
                    )
                    .await;
            }
        }
        Ok(AuthUser(claims))
    }
}

pub fn router(state: AppState) -> axum::Router {
    use axum::routing::{get, post};
    use axum::Router;

    Router::new()
        .route("/health", get(health::health))
        .route("/api/v1/auth/register", post(auth::register))
        .route("/api/v1/auth/login", post(auth::login))
        .route("/api/v1/auth/refresh", post(auth::refresh))
        .route("/api/v1/auth/logout", post(auth::logout))
        .route("/api/v1/me", get(me::me))
        .route("/api/v1/me/password", post(me::change_password))
        .route(
            "/api/v1/sync/hosts",
            get(sync::get_hosts).put(sync::put_hosts),
        )
        .route(
            "/api/v1/sync/settings",
            get(sync::get_settings).put(sync::put_settings),
        )
        .route("/api/v1/admin/stats", get(admin::stats))
        .route("/api/v1/admin/users", get(admin::list_users))
        .route(
            "/api/v1/admin/users/{id}",
            get(admin::get_user)
                .patch(admin::patch_user)
                .delete(admin::delete_user),
        )
        .route(
            "/api/v1/admin/users/{id}/revoke",
            post(admin::revoke_user),
        )
        .route(
            "/api/v1/admin/users/{id}/sync",
            get(admin::user_sync_meta),
        )
        .with_state(state)
}

#[allow(dead_code)]
pub type RouteResult<T> = AppResult<T>;
