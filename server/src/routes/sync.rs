use crate::db;
use crate::error::{AppError, AppResult};
use crate::routes::AuthUser;
use crate::state::AppState;
use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Serialize)]
pub struct SyncGetResponse {
    pub data: Value,
    pub updated_at: i64,
}

#[derive(Debug, Deserialize)]
pub struct SyncPutRequest {
    pub data: Value,
    /// Optional client timestamp (ms); server still assigns authoritative updated_at.
    pub client_updated_at: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct SyncPutResponse {
    pub data: Value,
    pub updated_at: i64,
}

pub async fn get_hosts(
    State(state): State<AppState>,
    AuthUser(claims): AuthUser,
) -> AppResult<Json<SyncGetResponse>> {
    get_sync(&state, &claims.sub, true).await
}

pub async fn put_hosts(
    State(state): State<AppState>,
    AuthUser(claims): AuthUser,
    Json(body): Json<SyncPutRequest>,
) -> AppResult<Json<SyncPutResponse>> {
    put_sync(&state, &claims.sub, body, true).await
}

pub async fn get_settings(
    State(state): State<AppState>,
    AuthUser(claims): AuthUser,
) -> AppResult<Json<SyncGetResponse>> {
    get_sync(&state, &claims.sub, false).await
}

pub async fn put_settings(
    State(state): State<AppState>,
    AuthUser(claims): AuthUser,
    Json(body): Json<SyncPutRequest>,
) -> AppResult<Json<SyncPutResponse>> {
    put_sync(&state, &claims.sub, body, false).await
}

async fn get_sync(
    state: &AppState,
    user_id: &str,
    hosts: bool,
) -> AppResult<Json<SyncGetResponse>> {
    let blob = if hosts {
        db::get_hosts(&state.pool, user_id).await?
    } else {
        db::get_settings(&state.pool, user_id).await?
    };
    match blob {
        Some(b) => {
            let data: Value = serde_json::from_str(&b.payload)
                .unwrap_or(Value::Null);
            Ok(Json(SyncGetResponse {
                data,
                updated_at: b.updated_at,
            }))
        }
        None => Ok(Json(SyncGetResponse {
            data: if hosts {
                Value::Array(vec![])
            } else {
                Value::Object(Default::default())
            },
            updated_at: 0,
        })),
    }
}

async fn put_sync(
    state: &AppState,
    user_id: &str,
    body: SyncPutRequest,
    hosts: bool,
) -> AppResult<Json<SyncPutResponse>> {
    let _ = body.client_updated_at;
    if hosts && !body.data.is_array() {
        return Err(AppError::BadRequest("hosts data must be a JSON array".into()));
    }
    if !hosts && !body.data.is_object() {
        return Err(AppError::BadRequest(
            "settings data must be a JSON object".into(),
        ));
    }
    let payload = serde_json::to_string(&body.data)
        .map_err(|e| AppError::BadRequest(format!("invalid json: {e}")))?;
    let blob = if hosts {
        db::put_hosts(&state.pool, user_id, &payload).await?
    } else {
        db::put_settings(&state.pool, user_id, &payload).await?
    };
    Ok(Json(SyncPutResponse {
        data: body.data,
        updated_at: blob.updated_at,
    }))
}
