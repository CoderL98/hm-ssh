//! Simple fixed-window rate limiter (in-memory). Used for auth register/login.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug)]
pub struct RateLimiter {
    max_per_window: u32,
    window: Duration,
    hits: Mutex<HashMap<String, (Instant, u32)>>,
}

impl RateLimiter {
    pub fn new(max_per_window: u32, window: Duration) -> Self {
        Self {
            max_per_window: max_per_window.max(1),
            window,
            hits: Mutex::new(HashMap::new()),
        }
    }

    /// Returns `Ok(remaining)` if allowed, `Err(())` if over limit.
    pub fn check(&self, key: &str) -> Result<u32, ()> {
        let mut map = self.hits.lock().expect("rate limiter mutex");
        let now = Instant::now();
        // Opportunistic prune when map grows
        if map.len() > 4096 {
            map.retain(|_, (start, _)| now.duration_since(*start) < self.window);
        }
        let entry = map.entry(key.to_string()).or_insert((now, 0));
        if now.duration_since(entry.0) >= self.window {
            entry.0 = now;
            entry.1 = 0;
        }
        if entry.1 >= self.max_per_window {
            return Err(());
        }
        entry.1 += 1;
        Ok(self.max_per_window.saturating_sub(entry.1))
    }

    pub fn max_per_window(&self) -> u32 {
        self.max_per_window
    }

    #[cfg(test)]
    pub fn reset(&self) {
        self.hits.lock().expect("rate limiter mutex").clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn allows_up_to_max_then_blocks() {
        let rl = RateLimiter::new(3, Duration::from_secs(60));
        assert!(rl.check("ip1").is_ok());
        assert!(rl.check("ip1").is_ok());
        assert!(rl.check("ip1").is_ok());
        assert!(rl.check("ip1").is_err());
        // different key still ok
        assert!(rl.check("ip2").is_ok());
    }

    #[test]
    fn window_reset_allows_again() {
        let rl = RateLimiter::new(1, Duration::from_millis(30));
        assert!(rl.check("a").is_ok());
        assert!(rl.check("a").is_err());
        std::thread::sleep(Duration::from_millis(40));
        assert!(rl.check("a").is_ok());
    }
}
