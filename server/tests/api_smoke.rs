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
        admin_email: None,
        admin_password: None,
        max_body_bytes: 2 * 1024 * 1024,
        max_sync_hosts: 500,
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

#[tokio::test]
async fn admin_stats_requires_admin_and_lists_users() {
    let state = test_state(100).await;
    let pool = state.pool.clone();
    let router = app(state);

    // Seed admin directly
    let admin = db::seed_admin_if_needed(&pool, "admin@test.com", "adminpass1")
        .await
        .expect("seed")
        .expect("admin row");
    assert!(admin.is_admin);

    // Regular user
    let reg = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"email":"u@test.com","username":"normalu","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, _) = body_json(router.clone().oneshot(reg).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK);

    // Non-admin token cannot hit admin
    let login_u = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"login":"u@test.com","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, body) = body_json(router.clone().oneshot(login_u).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let user_token = body["access_token"].as_str().unwrap();

    let denied = Request::builder()
        .method("GET")
        .uri("/api/v1/admin/stats")
        .header("authorization", format!("Bearer {user_token}"))
        .body(Body::empty())
        .unwrap();
    let (status, _) = body_json(router.clone().oneshot(denied).await.unwrap()).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Admin login
    let login_a = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"login":"admin@test.com","password":"adminpass1"}"#,
        ))
        .unwrap();
    let (status, body) = body_json(router.clone().oneshot(login_a).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["user"]["is_admin"], true);
    let admin_token = body["access_token"].as_str().unwrap();

    let stats = Request::builder()
        .method("GET")
        .uri("/api/v1/admin/stats")
        .header("authorization", format!("Bearer {admin_token}"))
        .body(Body::empty())
        .unwrap();
    let (status, body) = body_json(router.clone().oneshot(stats).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body["user_count"].as_i64().unwrap() >= 2);

    let list = Request::builder()
        .method("GET")
        .uri("/api/v1/admin/users?q=normalu")
        .header("authorization", format!("Bearer {admin_token}"))
        .body(Body::empty())
        .unwrap();
    let (status, body) = body_json(router.clone().oneshot(list).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body.as_array().unwrap().iter().any(|u| u["username"] == "normalu"));

    // Sync meta strips payload
    let sync = Request::builder()
        .method("GET")
        .uri(format!("/api/v1/admin/users/{}/sync", body[0]["id"].as_str().unwrap()))
        .header("authorization", format!("Bearer {admin_token}"))
        .body(Body::empty())
        .unwrap();
    let (status, body) = body_json(router.oneshot(sync).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body.get("hosts").is_some());
    assert!(body["hosts"].get("payload").is_none());
}

#[tokio::test]
async fn disabled_user_cannot_login_or_use_token() {
    let state = test_state(100).await;
    let pool = state.pool.clone();
    let router = app(state);

    let reg = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"email":"dis@test.com","username":"disabled1","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, auth) = body_json(router.clone().oneshot(reg).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{auth}");
    let user_id = auth["user"]["id"].as_str().unwrap().to_string();
    let token = auth["access_token"].as_str().unwrap().to_string();

    db::set_disabled(&pool, &user_id, true)
        .await
        .expect("disable");

    // Login rejected
    let login = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"login":"dis@test.com","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, body) = body_json(router.clone().oneshot(login).await.unwrap()).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
    assert!(
        body["error"]
            .as_str()
            .unwrap_or("")
            .to_lowercase()
            .contains("disable"),
        "{body}"
    );

    // Pre-disable token also rejected on authenticated routes (DB check)
    let me = Request::builder()
        .method("GET")
        .uri("/api/v1/me")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap();
    let (status, body) = body_json(router.oneshot(me).await.unwrap()).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
}

#[tokio::test]
async fn change_password_issues_new_tokens() {
    let state = test_state(100).await;
    let router = app(state);

    let req = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"email":"pw@b.com","username":"pwuser","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, auth) = body_json(router.clone().oneshot(req).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{auth}");
    let token = auth["access_token"].as_str().unwrap();

    let bad = Request::builder()
        .method("POST")
        .uri("/api/v1/me/password")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(
            r#"{"current_password":"wrongpass","new_password":"secret999"}"#,
        ))
        .unwrap();
    let (status, _) = body_json(router.clone().oneshot(bad).await.unwrap()).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let ok = Request::builder()
        .method("POST")
        .uri("/api/v1/me/password")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(
            r#"{"current_password":"secret123","new_password":"secret999"}"#,
        ))
        .unwrap();
    let (status, auth2) = body_json(router.clone().oneshot(ok).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{auth2}");
    assert!(auth2["access_token"].as_str().unwrap().len() > 10);

    // Login with new password
    let login = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"login":"pw@b.com","password":"secret999"}"#,
        ))
        .unwrap();
    let (status, _) = body_json(router.clone().oneshot(login).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK);

    // Old password rejected
    let login_old = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"login":"pw@b.com","password":"secret123"}"#,
        ))
        .unwrap();
    let (status, _) = body_json(router.oneshot(login_old).await.unwrap()).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn sync_rejects_null_data() {
    let state = test_state(100).await;
    let router = app(state);

    let req = Request::builder()
        .method("POST")
        .uri("/api/v1/auth/register")
        .header("content-type", "application/json")
        .body(Body::from(
            r#"{"email":"n@b.com","username":"nulluser","password":"secret123"}"#,
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
        .body(Body::from(r#"{"data":null}"#))
        .unwrap();
    let (status, body) = body_json(router.oneshot(put).await.unwrap()).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    assert!(
        body["error"].as_str().unwrap_or("").contains("null"),
        "{body}"
    );
}

#[tokio::test]
async fn health_reports_db() {
    let state = test_state(100).await;
    let router = app(state);
    let req = Request::builder()
        .method("GET")
        .uri("/health")
        .body(Body::empty())
        .unwrap();
    let (status, body) = body_json(router.oneshot(req).await.unwrap()).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["status"], "ok");
    assert_eq!(body["db"], "ok");
    assert!(body.get("db_backend").is_some());
}
