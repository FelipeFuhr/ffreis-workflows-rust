use hello::{validate_email, validate_username};
use std::env;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: hello <username|email> <value>");
        process::exit(1);
    }

    let valid = match args[1].as_str() {
        "username" => validate_username(&args[2]),
        "email" => validate_email(&args[2]),
        other => {
            eprintln!("unknown kind: {other}  (expected username or email)");
            process::exit(1);
        }
    };

    println!("{valid}");
}
