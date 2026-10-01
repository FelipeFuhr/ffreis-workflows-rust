// Fixture for rust-clock-lint.yml — the ALLOWLISTED half.
//
// `*/adapters/*` is in the lint's documented baseline, because the adapter that
// implements the `Clock` port is exactly where reading the host clock is the
// point. The lint must find ZERO violations here even though the call is
// identical to `src/lib.rs`'s first one. Together with `src/lib.rs` this pins
// both directions: the gate fires, and it does not fire everywhere.

use std::time::{SystemTime, UNIX_EPOCH};

pub struct SystemClock;

impl SystemClock {
    pub fn now_unix(&self) -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }
}
