// Composition module (baseline-allowlisted).
pub fn wire() -> std::sync::Arc<dyn ffreis_rust_shared::email_sender::EmailSender> {
    std::sync::Arc::new(ffreis_rust_shared::email_sender::NoopEmailSender)
}
