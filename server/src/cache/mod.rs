//! Pluggable cache: in-memory (moka) by default; Redis when REDIS_URL is set.

use async_trait::async_trait;
use std::sync::Arc;
use std::time::Duration;

#[async_trait]
pub trait CacheBackend: Send + Sync {
    async fn get(&self, key: &str) -> Option<String>;
    async fn set(&self, key: &str, value: String, ttl: Duration);
    #[allow(dead_code)]
    async fn del(&self, key: &str);
}

pub struct MemoryCache {
    inner: moka::future::Cache<String, String>,
}

impl MemoryCache {
    pub fn new() -> Self {
        let inner = moka::future::Cache::builder()
            .max_capacity(10_000)
            .time_to_live(Duration::from_secs(3600))
            .build();
        Self { inner }
    }
}

#[async_trait]
impl CacheBackend for MemoryCache {
    async fn get(&self, key: &str) -> Option<String> {
        self.inner.get(key).await
    }

    async fn set(&self, key: &str, value: String, ttl: Duration) {
        // moka global TTL; still insert for hot path
        let _ = ttl;
        self.inner.insert(key.to_string(), value).await;
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
            let secs = ttl.as_secs().max(1) as u64;
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

/// Helpers for session / profile keys.
pub fn session_key(user_id: &str) -> String {
    format!("sess:{user_id}")
}

pub fn profile_key(user_id: &str) -> String {
    format!("profile:{user_id}")
}
