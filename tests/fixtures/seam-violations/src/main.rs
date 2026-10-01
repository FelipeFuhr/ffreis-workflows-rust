// Composition root (baseline-allowlisted): building adapters HERE is correct.
fn main() {
    let _gw = ffreis_rust_shared::payment::MockPaymentGateway::new(
        ffreis_rust_shared::payment::MockPaymentScenario::Approved,
    );
}
