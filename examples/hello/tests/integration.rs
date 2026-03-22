use hello::{validate_email, validate_username};

#[test]
fn integration_username_examples() {
    assert!(validate_username("alice_42"));
    assert!(!validate_username("ab"));
    assert!(!validate_username("alice!"));
}

#[test]
fn integration_email_examples() {
    assert!(validate_email("user@example.com"));
    assert!(!validate_email("notanemail"));
    assert!(!validate_email("user@localhost"));
}
