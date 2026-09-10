//! Runtime configuration from env / optional TOML.

use anyhow::{bail, Context, Result};
use serde::Deserialize;
use std::env;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Config {
    pub bind: String,
    pub database_url: String,
    pub jwt_secret: String,
    pub jwt_access_ttl_secs: i64,
    pub jwt_refresh_ttl_secs: i64,
    pub redis_url: Option<String>,
    pub cors_origins: Vec<String>,
}

#[derive(Debug, Deserialize, Default)]
struct TomlConfig {
    bind: Option<String>,
    database_url: Option<String>,
    jwt_secret: Option<String>,
    jwt_access_ttl_secs: Option<i64>,
    jwt_refresh_ttl_secs: Option<i64>,
    redis_url: Option<String>,
    cors_origins: Option<String>,
}

impl Config {
    pub fn load() -> Result<Self> {
        let toml_cfg = load_toml().unwrap_or_default();

        let bind = env::var("BIND")
            .ok()
            .or(toml_cfg.bind)
            .unwrap_or_else(|| "0.0.0.0:8080".into());

        let database_url = env::var("DATABASE_URL")
            .ok()
            .or(toml_cfg.database_url)
            .unwrap_or_else(|| "sqlite:hmssh.db".into());

        let jwt_secret = env::var("JWT_SECRET")
            .ok()
            .or(toml_cfg.jwt_secret)
            .unwrap_or_else(|| "dev-only-insecure-secret-change-me".into());

        if jwt_secret.len() < 16 {
            bail!("JWT_SECRET must be at least 16 characters");
        }

        let jwt_access_ttl_secs = env::var("JWT_ACCESS_TTL_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .or(toml_cfg.jwt_access_ttl_secs)
            .unwrap_or(86_400);

        let jwt_refresh_ttl_secs = env::var("JWT_REFRESH_TTL_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .or(toml_cfg.jwt_refresh_ttl_secs)
            .unwrap_or(604_800);

        let redis_url = env::var("REDIS_URL")
            .ok()
            .filter(|s| !s.is_empty())
            .or(toml_cfg.redis_url.filter(|s| !s.is_empty()));

        let cors_raw = env::var("CORS_ORIGINS")
            .ok()
            .or(toml_cfg.cors_origins)
            .unwrap_or_else(|| "*".into());
        let cors_origins = cors_raw
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        Ok(Config {
            bind,
            database_url,
            jwt_secret,
            jwt_access_ttl_secs,
            jwt_refresh_ttl_secs,
            redis_url,
            cors_origins,
        })
    }

    pub fn db_backend_label(&self) -> &'static str {
        let u = self.database_url.to_lowercase();
        if u.starts_with("postgres://") || u.starts_with("postgresql://") {
            "postgres"
        } else if u.starts_with("mysql://") {
            "mysql"
        } else {
            "sqlite"
        }
    }
}

fn load_toml() -> Result<TomlConfig> {
    let path = env::var("CONFIG_PATH").unwrap_or_else(|_| "config.toml".into());
    if !Path::new(&path).exists() {
        return Ok(TomlConfig::default());
    }
    let text = fs::read_to_string(&path)
        .with_context(|| format!("read config {}", path))?;
    let cfg: TomlConfig = toml::from_str(&text).context("parse config.toml")?;
    Ok(cfg)
}
