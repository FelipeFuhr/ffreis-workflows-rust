// Fixture for rust-clock-lint.yml. DELIBERATELY VIOLATING — do not "fix" it.
//
// `tests/clock_lint.bats` and `self-test.yml` both point the clock lint at this
// directory and assert it finds exactly the violations below. If someone
// routes these through a `Clock` port, the lint stops discriminating and every
// consumer's gate silently becomes vacuous — the same trap
// `examples/partial`'s untested `shrink_to_fit_len()` guards for mutation.
//
// NOT a Cargo crate on purpose: the lint reads `.rs` files as text, so there is
// nothing to compile, and `make lint`/`make fmt-check` (which loop over
// `examples/*/`) stay away from it.
//
// Expected findings in this file: 5 (lines marked VIOLATION below).
// Expected findings in src/adapters/system_clock.rs: 0 (allowlisted path).

use std::time::{Instant, SystemTime, UNIX_EPOCH};

/// VIOLATION 1 — `SystemTime::now()` in domain logic.
pub fn issued_at() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

/// VIOLATION 2 — fully-qualified spelling; the lint must not depend on the
/// `use` statement above.
pub fn expires_at(ttl_secs: u64) -> u64 {
    std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + ttl_secs
}

/// VIOLATION 3 — chrono's spelling, as used by forma and petlook today.
pub fn stamp() -> String {
    format!("{:?}", chrono::Utc::now())
}

/// VIOLATION 4 — a deref assignment. This line starts with `*`, which a naive
/// "skip lines starting with an asterisk" comment filter would swallow.
pub fn reset(slot: &mut Instant) {
    *slot = Instant::now();
}

/// VIOLATION 5 — `Local::now()`, proven to actually fire. The other three
/// forbidden spellings above already have a positive case; this one
/// previously had only negative cases below (a comment mention and the
/// allow-listed escape hatch), so the suite never proved the spelling itself
/// is caught.
pub fn local_stamp() -> String {
    format!("{:?}", chrono::Local::now())
}

// A mention of SystemTime::now() inside a comment is documentation, not a
// clock read, and must NOT be counted.
/* Neither is Utc::now() inside a block comment.
 * Nor Local::now() on a continuation line.
 */

/// Not a violation: carries the escape hatch with a reason.
pub fn legacy_stamp() -> String {
    format!("{:?}", chrono::Local::now()) // clock-lint:allow — frozen log format, migrates in S4
}
