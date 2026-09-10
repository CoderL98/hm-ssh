//! JWT access (+ optional refresh) tokens.

use crate::error::{AppError, AppResult};
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub email: String,
    pub username: String,
    /// "access" | "refresh"
    pub typ: String,
    /// Admin flag embedded at issue time; middleware also re-checks DB.
    #[serde(default)]
    pub is_admin: bool,
    pub exp: i64,
    pub iat: i64,
    pub jti: String,
}

pub struct JwtKeys {
    encoding: EncodingKey,
    decoding: DecodingKey,
    access_ttl_secs: i64,
    refresh_ttl_secs: i64,
}

impl JwtKeys {
    pub fn new(secret: &str, access_ttl_secs: i64, refresh_ttl_secs: i64) -> Self {
        Self {
            encoding: EncodingKey::from_secret(secret.as_bytes()),
            decoding: DecodingKey::from_secret(secret.as_bytes()),
            access_ttl_secs,
            refresh_ttl_secs,
        }
    }

    pub fn issue_access(
        &self,
        user_id: &str,
        email: &str,
        username: &str,
        is_admin: bool,
    ) -> AppResult<(String, i64)> {
        self.issue(
            user_id,
            email,
            username,
            is_admin,
            "access",
            self.access_ttl_secs,
        )
    }

    pub fn issue_refresh(
        &self,
        user_id: &str,
        email: &str,
        username: &str,
        is_admin: bool,
    ) -> AppResult<(String, i64)> {
        self.issue(
            user_id,
            email,
            username,
            is_admin,
            "refresh",
            self.refresh_ttl_secs,
        )
    }

    fn issue(
        &self,
        user_id: &str,
        email: &str,
        username: &str,
        is_admin: bool,
        typ: &str,
        ttl: i64,
    ) -> AppResult<(String, i64)> {
        let now = Utc::now();
        let exp = (now + Duration::seconds(ttl)).timestamp();
        let claims = Claims {
            sub: user_id.to_string(),
            email: email.to_string(),
            username: username.to_string(),
            typ: typ.to_string(),
            is_admin,
            exp,
            iat: now.timestamp(),
            jti: Uuid::new_v4().to_string(),
        };
        let token = encode(&Header::default(), &claims, &self.encoding)
            .map_err(|e| AppError::Internal(e.into()))?;
        Ok((token, exp))
    }

    pub fn decode_access(&self, token: &str) -> AppResult<Claims> {
        let data = decode::<Claims>(token, &self.decoding, &Validation::default())
            .map_err(|_| AppError::Unauthorized("invalid or expired token".into()))?;
        if data.claims.typ != "access" {
            return Err(AppError::Unauthorized("expected access token".into()));
        }
        Ok(data.claims)
    }

    pub fn decode_refresh(&self, token: &str) -> AppResult<Claims> {
        let data = decode::<Claims>(token, &self.decoding, &Validation::default())
            .map_err(|_| AppError::Unauthorized("invalid or expired token".into()))?;
        if data.claims.typ != "refresh" {
            return Err(AppError::Unauthorized("expected refresh token".into()));
        }
        Ok(data.claims)
    }
}
