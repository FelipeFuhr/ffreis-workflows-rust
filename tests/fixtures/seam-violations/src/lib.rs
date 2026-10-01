// Fixture for rust-seam-gate.yml. DELIBERATELY VIOLATING — do not "fix" it.
//
// `tests/seam_gate.bats` and `self-test.yml` point the seam gate at this
// directory and assert it finds exactly the violations below. If someone moves
// these into a composition root, the gate stops discriminating and every
// consumer's gate silently becomes vacuous.
//
// NOT a Cargo crate on purpose: the gate reads `.rs` files as text.
//
// Expected findings in this file: 5 (lines marked VIOLATION below).
// Expected findings in src/main.rs and src/composition.rs: 0 (baseline roots).

use std::sync::Arc;

use ffreis_rust_shared::email_sender::{EmailSender, NoopEmailSender};
use ffreis_rust_shared::payment::{MockPaymentGateway, MockPaymentScenario};

/// A type position, not a construction: must NOT be flagged.
pub struct Checkout {
    pub mailer: Arc<dyn EmailSender>,
    pub fallback: Option<NoopEmailSender>,
}

/// Parameter types are not constructions either.
pub fn takes(_m: NoopEmailSender, _g: &MockPaymentGateway) {}

pub fn charge() {
    // VIOLATION 1 — a fake gateway built in domain code, skipping the resolver.
    let gw = MockPaymentGateway::new(MockPaymentScenario::Approved);
    let _ = gw;
}

pub fn notify() -> Arc<dyn EmailSender> {
    // VIOLATION 2 — unit-struct adapter used as a value.
    Arc::new(NoopEmailSender)
}

pub async fn upload(client: aws_sdk_s3::Client) {
    // VIOLATION 3 — a live adapter built in place: also a bypass.
    let store = ffreis_rust_shared::blob_store::S3BlobStore::from_env(client);
    let _ = store;
}

pub fn clock() -> u64 {
    // VIOLATION 4 — struct-literal construction.
    let c = FakeClock { now: 1_700_000_000 };
    c.now
}

pub fn system() {
    // VIOLATION 5 — `= Type;` unit construction.
    let c = SystemClock;
    let _ = c;
}

// A comment naming MockPaymentGateway::new(..) is documentation, not construction.
/* Nor is a block comment: NoopEmailSender::default() */

pub fn escape_hatch() {
    let g = MockPaymentGateway::new(MockPaymentScenario::Declined); // seam-gate:allow — fixture for the escape hatch
    let _ = g;
}

pub struct FakeClock {
    pub now: u64,
}
pub struct SystemClock;

#[cfg(test)]
mod tests {
    use super::*;

    // Tests constructing doubles directly is the point of tests: not flagged.
    #[test]
    fn t() {
        let _ = MockPaymentGateway::new(MockPaymentScenario::Approved);
        let _ = Arc::new(NoopEmailSender);
    }
}
