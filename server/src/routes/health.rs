use crate::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static STARTED_AT_MS: AtomicU64 = AtomicU64::new(0);

pub fn mark_started() {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    STARTED_AT_MS.store(now, Ordering::Relaxed);
}

pub async fn health(State(state): State<AppState>) -> (StatusCode, Json<Value>) {
    let started = STARTED_AT_MS.load(Ordering::Relaxed);
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let uptime_ms = if started > 0 && now >= started {
        now - started
    } else {
        0
    };

    let db_ok = sqlx::query("SELECT 1")
        .execute(&state.pool)
        .await
        .is_ok();

    let status = if db_ok { "ok" } else { "degraded" };
    let code = if db_ok {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };

    let cache_label = if state.config.redis_url.is_some() {
        "redis_configured"
    } else {
        "memory"
    };

    (
        code,
        Json(json!({
            "status": status,
            "service": "hm-ssh-server",
            "db": if db_ok { "ok" } else { "error" },
            "db_backend": state.config.db_backend_label(),
            "cache": cache_label,
            "uptime_ms": uptime_ms,
        })),
    )
}
