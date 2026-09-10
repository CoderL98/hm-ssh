//! Pluggable cache: in-memory (moka) by default; Redis when REDIS_URL is set.

use async_trait::async_trait;
use moka::Expiry;
use std::sync::Arc;
use std::time::{Duration, Instant};

#[async_trait]
pub trait CacheBackend: Send + Sync {
    async fn get(&self, key: &str) -> Option<String>;
    async fn set(&self, key: &str, value: String, ttl: Duration);
    async fn del(&self, key: &str);
}

/// Value stores caller TTL seconds alongside the payload for per-entry expiry.
type MemEntry = (u64, String);

struct EntryExpiry;

impl Expiry<String, MemEntry> for EntryExpiry {
    fn expire_after_create(
        &self,
        _key: &String,
        value: &MemEntry,
        _current_time: Instant,
    ) -> Option<Duration> {
        Some(Duration::from_secs(value.0.max(1)))
    }

    fn expire_after_update(
        &self,
        _key: &String,
        value: &MemEntry,
        _current_time: Instant,
        _current_duration: Option<Duration>,
    ) -> Option<Duration> {
        Some(Duration::from_secs(value.0.max(1)))
    }
}

pub struct MemoryCache {
    inner: moka::future::Cache<String, MemEntry>,
}

impl MemoryCache {
    pub fn new() -> Self {
        let inner = moka::future::Cache::builder()
            .max_capacity(10_000)
            .expire_after(EntryExpiry)
            .build();
        Self { inner }
    }
}

#[async_trait]
impl CacheBackend for MemoryCache {
    async fn get(&self, key: &str) -> Option<String> {
        self.inner.get(key).await.map(|(_ttl, v)| v)
    }

    async fn set(&self, key: &str, value: String, ttl: Duration) {
        let secs = ttl.as_secs().max(1);
        self.inner.insert(key.to_string(), (secs, value)).await;
    }

    async fn del(&self, key: &str) {
        self.inner.invalidate(key).await;
    }
}

#[cfg(feature = "redis-cache")]
pub mod redis_backend {
    use super::*;
    use redis::aio::ConnectionManager;
    use redis::AsyncCommands;

    pub struct RedisCache {
        conn: ConnectionManager,
    }

    impl RedisCache {
        pub async fn connect(url: &str) -> anyhow::Result<Self> {
            let client = redis::Client::open(url)?;
            let conn = ConnectionManager::new(client).await?;
            Ok(Self { conn })
        }
    }

    #[async_trait]
    impl CacheBackend for RedisCache {
        async fn get(&self, key: &str) -> Option<String> {
            let mut conn = self.conn.clone();
            conn.get::<_, Option<String>>(key).await.ok().flatten()
        }

        async fn set(&self, key: &str, value: String, ttl: Duration) {
            let mut conn = self.conn.clone();
            let secs = ttl.as_secs().max(1);
            let _: Result<(), _> = conn.set_ex(key, value, secs).await;
        }

        async fn del(&self, key: &str) {
            let mut conn = self.conn.clone();
            let _: Result<(), _> = conn.del(key).await;
        }
    }
}

pub async fn build_cache(redis_url: Option<&str>) -> Arc<dyn CacheBackend> {
    #[cfg(feature = "redis-cache")]
    if let Some(url) = redis_url {
        match redis_backend::RedisCache::connect(url).await {
            Ok(c) => {
                tracing::info!("cache backend: redis");
                return Arc::new(c);
            }
            Err(e) => {
                tracing::warn!("redis connect failed ({e:#}); falling back to in-memory");
            }
        }
    }
    #[cfg(not(feature = "redis-cache"))]
    let _ = redis_url;

    tracing::info!("cache backend: in-memory (moka)");
    Arc::new(MemoryCache::new())
}

/// Helpers for session / profile / revoke keys.
pub fn session_key(user_id: &str) -> String {
    format!("sess:{user_id}")
}

pub fn profile_key(user_id: &str) -> String {
    format!("profile:{user_id}")
}

pub fn revoke_key(user_id: &str) -> String {
    format!("revoke:{user_id}")
}

pub fn jti_deny_key(jti: &str) -> String {
    format!("deny:jti:{jti}")
}

