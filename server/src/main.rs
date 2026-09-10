mod auth;
mod cache;
mod config;
mod db;
mod error;
mod routes;
mod state;

use crate::auth::jwt::JwtKeys;
use crate::config::Config;
use crate::state::AppState;
use anyhow::Context;
use std::net::SocketAddr;
use std::sync::Arc;
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
        "starting hm-ssh-server"
    );

    let pool = db::connect(&config.database_url)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    let jwt = Arc::new(JwtKeys::new(
        &config.jwt_secret,
        config.jwt_access_ttl_secs,
        config.jwt_refresh_ttl_secs,
    ));

    let cache = cache::build_cache(config.redis_url.as_deref()).await;

    let state = AppState {
        pool,
        jwt,
        cache,
        config: Arc::new(config.clone()),
    };

    let cors = build_cors(&config.cors_origins);
    let app = routes::router(state)
        .layer(TraceLayer::new_for_http())
        .layer(cors);

    let addr: SocketAddr = config
        .bind
        .parse()
        .with_context(|| format!("parse BIND {}", config.bind))?;
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("listening on http://{addr}");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

fn build_cors(origins: &[String]) -> CorsLayer {
    if origins.len() == 1 && origins[0] == "*" {
        return CorsLayer::new()
            .allow_origin(Any)
            .allow_methods(Any)
            .allow_headers(Any);
    }
    let parsed: Vec<_> = origins
        .iter()
        .filter_map(|o| o.parse::<axum::http::HeaderValue>().ok())
        .collect();
    CorsLayer::new()
        .allow_origin(parsed)
        .allow_methods(Any)
        .allow_headers(Any)
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutdown signal received");
}
