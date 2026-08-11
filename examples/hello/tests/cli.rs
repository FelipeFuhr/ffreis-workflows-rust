use std::process::Command;

fn hello() -> Command {
    Command::new(env!("CARGO_BIN_EXE_hello"))
}

#[test]
fn cli_wrong_arg_count_exits_nonzero() {
    let output = hello().output().expect("failed to run binary");
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("usage:"));
}

#[test]
fn cli_username_kind_prints_result() {
    let output = hello()
        .args(["username", "alice_42"])
        .output()
        .expect("failed to run binary");
    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "true");
}

#[test]
fn cli_email_kind_prints_result() {
    let output = hello()
        .args(["email", "notanemail"])
        .output()
        .expect("failed to run binary");
    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "false");
}

#[test]
fn cli_unknown_kind_exits_nonzero() {
    let output = hello()
        .args(["phone", "555-1234"])
        .output()
        .expect("failed to run binary");
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unknown kind"));
}
