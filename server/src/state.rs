use crate::auth::jwt::JwtKeys;
use crate::cache::CacheBackend;
use crate::config::Config;
use crate::db::DbPool;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub pool: DbPool,
    pub jwt: Arc<JwtKeys>,
    pub cache: Arc<dyn CacheBackend>,
    pub config: Arc<Config>,
}
