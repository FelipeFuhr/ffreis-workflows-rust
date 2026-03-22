//! Minimal validator library for platform workflow self-testing.

/// Validates a username: 3–32 characters, alphanumeric or underscore only.
///
/// # Examples
///
/// ```
/// use hello::validate_username;
/// assert!(validate_username("alice_42"));
/// assert!(!validate_username("ab"));        // too short
/// assert!(!validate_username("alice!"));    // invalid char
/// ```
pub fn validate_username(s: &str) -> bool {
    let len = s.chars().count();
    (3..=32).contains(&len) && s.chars().all(|c| c.is_alphanumeric() || c == '_')
}

/// Validates an email address with a simple structural check.
///
/// Requires exactly one `@`, a non-empty local part, and a domain containing
/// at least one `.` that is not at the start or end.
///
/// # Examples
///
/// ```
/// use hello::validate_email;
/// assert!(validate_email("user@example.com"));
/// assert!(!validate_email("notanemail"));
/// assert!(!validate_email("user@localhost"));
/// ```
pub fn validate_email(s: &str) -> bool {
    if s.matches('@').count() != 1 {
        return false;
    }
    let (local, domain) = s.split_once('@').unwrap();
    !local.is_empty()
        && domain.contains('.')
        && !domain.starts_with('.')
        && !domain.ends_with('.')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn username_valid() {
        assert!(validate_username("alice_42"));
    }

    #[test]
    fn username_too_short() {
        assert!(!validate_username("ab"));
    }

    #[test]
    fn username_too_long() {
        assert!(!validate_username(&"a".repeat(33)));
    }

    #[test]
    fn username_invalid_chars() {
        assert!(!validate_username("alice!"));
    }

    #[test]
    fn username_boundary_min() {
        assert!(validate_username("abc"));
    }

    #[test]
    fn username_boundary_max() {
        assert!(validate_username(&"a".repeat(32)));
    }

    #[test]
    fn email_valid() {
        assert!(validate_email("user@example.com"));
    }

    #[test]
    fn email_no_at() {
        assert!(!validate_email("notanemail"));
    }

    #[test]
    fn email_no_dot_in_domain() {
        assert!(!validate_email("user@localhost"));
    }

    #[test]
    fn email_empty_local() {
        assert!(!validate_email("@example.com"));
    }

    #[test]
    fn email_dot_at_start_of_domain() {
        assert!(!validate_email("user@.example.com"));
    }

    #[test]
    fn email_dot_at_end_of_domain() {
        assert!(!validate_email("user@example.com."));
    }

    #[test]
    fn email_multiple_at_signs() {
        assert!(!validate_email("a@b@c.com"));
    }
}
