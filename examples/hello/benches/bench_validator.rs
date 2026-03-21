use criterion::{criterion_group, criterion_main, Criterion};
use hello::{validate_email, validate_username};

fn bench_validate_username(c: &mut Criterion) {
    let mut group = c.benchmark_group("validate_username");
    group.bench_function("valid", |b| b.iter(|| validate_username("alice_42")));
    group.bench_function("too_short", |b| b.iter(|| validate_username("ab")));
    group.bench_function("invalid_char", |b| b.iter(|| validate_username("alice!")));
    group.finish();
}

fn bench_validate_email(c: &mut Criterion) {
    let mut group = c.benchmark_group("validate_email");
    group.bench_function("valid", |b| b.iter(|| validate_email("user@example.com")));
    group.bench_function("no_at", |b| b.iter(|| validate_email("notanemail")));
    group.bench_function("no_dot", |b| b.iter(|| validate_email("user@localhost")));
    group.finish();
}

criterion_group!(benches, bench_validate_username, bench_validate_email);
criterion_main!(benches);
