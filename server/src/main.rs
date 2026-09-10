use hm_ssh_server::auth::jwt::JwtKeys;
use hm_ssh_server::cache;
use hm_ssh_server::config::Config;
use hm_ssh_server::db;
use hm_ssh_server::rate_limit::RateLimiter;
use hm_ssh_server::routes;
use hm_ssh_server::state::AppState;
use anyhow::Context;
use axum::extract::DefaultBodyLimit;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tower_http::compression::CompressionLayer;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let config = Config::load().context("load config")?;
    tracing::info!(
        bind = %config.bind,
        db = %config.db_backend_label(),
        redis = config.redis_url.is_some(),
        auth_rate_limit = config.auth_rate_limit_per_min,
        max_body_bytes = config.max_body_bytes,
        "starting hm-ssh-server"
    );

    let pool = db::connect(&config.database_url)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    if let (Some(email), Some(password)) = (&config.admin_email, &config.admin_password) {
        db::seed_admin_if_needed(&pool, email, password)
            .await
            .map_err(|e| anyhow::anyhow!("seed admin: {e}"))?;
    } else {
        tracing::info!("ADMIN_EMAIL/ADMIN_PASSWORD not set; skip admin seed");
    }

    let jwt = Arc::new(JwtKeys::new(
        &config.jwt_secret,
        config.jwt_access_ttl_secs,
        config.jwt_refresh_ttl_secs,
    ));

    let cache = cache::build_cache(config.redis_url.as_deref()).await;

    let auth_rate_limiter = Arc::new(RateLimiter::new(
        config.auth_rate_limit_per_min,
        Duration::from_secs(60),
    ));

    let max_body = config.max_body_bytes;

    let state = AppState {
        pool,
        jwt,
        cache,
        config: Arc::new(config.clone()),
        auth_rate_limiter,
    };

    routes::health::mark_started();

    let cors = build_cors(&config.cors_origins);
    let app = routes::router(state)
        .layer(DefaultBodyLimit::max(max_body))
        .layer(CompressionLayer::new())
        .layer(TraceLayer::new_for_http())
        .layer(cors);

    let addr: SocketAddr = config
        .bind
        .parse()
        .with_context(|| format!("parse BIND {}", config.bind))?;
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("listening on http://{addr}");
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    tracing::info!("server stopped");
    Ok(())
}

fn build_cors(origins: &[String]) -> CorsLayer {
    // Admin UI (Vite) typically runs at http://localhost:5173 — include it in
    // CORS_ORIGINS when not using *. Bearer token auth does not need credentials.
    use axum::http::{header, Method};
    let headers = [
        header::AUTHORIZATION,
        header::CONTENT_TYPE,
        header::ACCEPT,
    ];
    let methods = [
        Method::GET,
        Method::POST,
        Method::PUT,
        Method::PATCH,
        Method::DELETE,
        Method::OPTIONS,
    ];
    if origins.len() == 1 && origins[0] == "*" {
        return CorsLayer::new()
            .allow_origin(Any)
            .allow_methods(methods)
            .allow_headers(headers);
    }
    let parsed: Vec<_> = origins
        .iter()
        .filter_map(|o| o.parse::<axum::http::HeaderValue>().ok())
        .collect();
    CorsLayer::new()
        .allow_origin(parsed)
        .allow_methods(methods)
        .allow_headers(headers)
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };

    #[cfg(unix)]
    let terminate = async {
        use tokio::signal::unix::{signal, SignalKind};
        match signal(SignalKind::terminate()) {
            Ok(mut s) => {
                s.recv().await;
            }
            Err(_) => std::future::pending::<()>().await,
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    tracing::info!("shutdown signal received");
}
