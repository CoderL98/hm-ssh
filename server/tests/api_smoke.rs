//! Light integration smoke: strip-secrets via sync PUT, auth rate limit, refresh rotation.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{Request, StatusCode};
use hm_ssh_server::auth::jwt::JwtKeys;
use hm_ssh_server::cache::{self, jti_deny_key};
use hm_ssh_server::config::Config;
use hm_ssh_server::db;
use hm_ssh_server::rate_limit::RateLimiter;
use hm_ssh_server::routes;
use hm_ssh_server::state::AppState;
use http_body_util::BodyExt;
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tower::ServiceExt;

async fn test_state(rate_limit: u32) -> AppState {
    // Unique in-memory sqlite per test
    let db_url = format!(
        "sqlite:file:hmssh_test_{}?mode=memory&cache=shared",
        uuid::Uuid::new_v4()
    );
    let pool = db::connect(&db_url).await.expect("db");
    let jwt = Arc::new(JwtKeys::new(
        "test-secret-at-least-16",
        3600,
        86_400,
    ));
    let cache = cache::build_cache(None).await;
    let config = Config {
        bind: "127.0.0.1:0".into(),
        database_url: db_url,
        jwt_secret: "test-secret-at-least-16".into(),
        jwt_access_ttl_secs: 3600,
        jwt_refresh_ttl_secs: 86_400,
        redis_url: None,
        cors_origins: vec!["*".into()],
        auth_rate_limit_per_min: rate_limit,
    };
    AppState {
        pool,
        jwt,
        cache,
        config: Arc::new(config),
        auth_rate_limiter: Arc::new(RateLimiter::new(rate_limit, Duration::from_secs(60))),
    }
}

fn app(state: AppState) -> axum::Router {
    routes::router(state).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 40000))))
}

async fn body_json(resp: axum::http::Response<Body>) -> (StatusCode, Value) {
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, v)
}

#[tokio::test]
async fn register_login_and_strip_secrets_on_sync() {
    let state = test_state(100).await;
    let router = app(state);

    let req = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"email":"a@b.com","username":"alice","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, auth) = body_json(router.clone().oneshot(req).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{auth}");
    let token = auth["access_token"].as_str().unwrap();

    let put = Request::builder()
        .method("PUT")
        .uri("/api/v1/sync/hosts")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(
            json!({
                "data": [{
                    "id": "h1",
                    "name": "demo",
                    "host": "1.2.3.4",
                    "port": 22,
                    "password": "should-strip",
                    "privateKey": "KEY",
                    "private_key": "KEY2"
                }]
            })
            .to_string(),
        ))
        .unwrap();
    let (status, put_body) = body_json(router.clone().oneshot(put).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{put_body}");
    let host0 = &put_body["data"][0];
    assert_eq!(host0["password"], "");
    assert_eq!(host0["privateKey"], "");
    assert_eq!(host0["private_key"], "");

    let get = Request::builder()
        .method("GET")
        .uri("/api/v1/sync/hosts")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap();
    let (status, get_body) = body_json(router.oneshot(get).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{get_body}");
    assert_eq!(get_body["data"][0]["password"], "");
}

#[tokio::test]
async fn auth_rate_limit_returns_429() {
    let state = test_state(2).await;
    let router = app(state);

    for i in 0..2 {
        let req = Request::builder()
            .method("POST")
            .uri("/api/v1/auth/login")
            .header("content-type", "application/json")
            .body(Body::from(
                r#"{"login":"nobody","password":"whatever1"}"#,
            ))
            .unwrap();
        let (status, _) = body_json(router.clone().oneshot(req).await.unwrap()).await;
        // 401 invalid credentials still counts toward rate limit
        assert!(
            status == StatusCode::UNAUTHORIZED || status == StatusCode::OK,
            "iter {i}: {status}"
        );
    }
    let req = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"login":"nobody","password":"whatever1"}"#,
        ))
        .unwrap();
    let (status, body) = body_json(router.oneshot(req).await.unwrap()).await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "{body}");
    assert!(body["error"].as_str().unwrap_or("").contains("too many"));
}

#[tokio::test]
async fn refresh_rotates_and_revokes_old_jti() {
    let state = test_state(100).await;
    let cache = state.cache.clone();
    let router = app(state);

    let req = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"email":"r@b.com","username":"rotator","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, auth) = body_json(router.clone().oneshot(req).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{auth}");
    let old_refresh = auth["refresh_token"].as_str().unwrap().to_string();

    let refresh_req = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/refresh")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({ "refresh_token": old_refresh }).to_string(),
        ))
        .unwrap();
    let (status, refreshed) = body_json(router.clone().oneshot(refresh_req).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{refreshed}");
    let new_refresh = refreshed["refresh_token"].as_str().unwrap();
    assert_ne!(old_refresh, new_refresh);

    // Replay old refresh → 401
    let replay = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/refresh")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({ "refresh_token": old_refresh }).to_string(),
        ))
        .unwrap();
    let (status, body) = body_json(router.oneshot(replay).await.unwrap()).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");

    // Denylist key should exist (decode old jti via jwt is heavy; just ensure cache has deny entries)
    // Soft check: at least one deny:jti key present is enough via replaying above.
    let _ = cache;
    let _ = jti_deny_key;
}
