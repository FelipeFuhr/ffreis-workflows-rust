# ffreis-platform-workflows-rust

Reusable GitHub Actions workflows for Rust projects in the ffreis org.

All workflows use `on: workflow_call:` and are consumed from other repositories with:

```yaml
uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/<file>.yml@main
```

---

## Workflows

| Workflow file | Purpose | Key inputs |
|---|---|---|
| `rust-fmt.yml` | `cargo fmt --all -- --check` | `toolchain`, `working-directory` |
| `rust-lint.yml` | Clippy with `-- -D warnings` | `toolchain`, `working-directory`, `clippy-args` |
| `rust-test.yml` | `cargo test` | `toolchain`, `working-directory`, `test-args`, `timeout-minutes` |
| `rust-build.yml` | Matrix build across Rust versions and OS | `rust-versions` (JSON), `os-list` (JSON), `working-directory`, `build-args` |
| `rust-security.yml` | `cargo-audit` CVE scan (schedule weekly in caller) | `toolchain`, `working-directory`, `ignore-advisories` |
| `rust-coverage.yml` | `cargo-llvm-cov` + Codecov upload | `toolchain`, `working-directory`, `coverage-args`, `coverage-threshold`, `codecov-flags`; secret `CODECOV_TOKEN` |
| `rust-container.yml` | Container image build (podman/docker) + smoke test | `image-name` (required), `containerfile`, `context`, `build-args` |
| `rust-deny.yml` | `cargo-deny` license/ban/advisory/source checks | `working-directory`, `checks` |
| `rust-docs.yml` | `cargo doc` with `RUSTDOCFLAGS=-D warnings` | `toolchain`, `working-directory`, `doc-args` |
| `rust-msrv.yml` | Compile + test-compile against declared MSRV | `msrv` (required), `working-directory`, `build-args` |
| `rust-bench.yml` | Criterion benchmarks + artifact upload | `toolchain`, `working-directory`, `bench-args`, `timeout-minutes` |
| `rust-miri.yml` | Miri undefined-behavior detection (nightly) | `working-directory`, `miri-args`, `timeout-minutes` |

---

## Caller examples

### Format check on every PR

```yaml
# .github/workflows/ci.yml  (in consumer repo)
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  fmt:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-fmt.yml@main
    with:
      working-directory: app
```

### Lint

```yaml
  lint:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-lint.yml@main
    with:
      working-directory: app
      clippy-args: "-- -D warnings"
```

### Tests

```yaml
  test:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-test.yml@main
    with:
      working-directory: app
      test-args: "--all-features"
      timeout-minutes: 20
```

### Matrix build

```yaml
  build:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-build.yml@main
    with:
      rust-versions: '["stable","1.88.0"]'
      os-list: '["ubuntu-latest","macos-latest"]'
      working-directory: app
```

### Security audit (scheduled weekly)

```yaml
  audit:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-security.yml@main
    with:
      working-directory: app
      ignore-advisories: "RUSTSEC-2024-0001"
```

### Coverage with Codecov

```yaml
  coverage:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-coverage.yml@main
    with:
      working-directory: app
      coverage-threshold: 80
      codecov-flags: unit
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### Container build

```yaml
  container:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-container.yml@main
    with:
      image-name: my-service:latest
      containerfile: Containerfile
      context: .
```

### cargo-deny

```yaml
  deny:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-deny.yml@main
    with:
      working-directory: app
```

> **Note:** The calling repository must have a `deny.toml` at the workspace root.

### Docs

```yaml
  docs:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-docs.yml@main
    with:
      working-directory: app
```

### MSRV check

```yaml
  msrv:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-msrv.yml@main
    with:
      msrv: "1.80.0"
      working-directory: app
```

### Benchmarks

```yaml
  bench:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-bench.yml@main
    with:
      working-directory: app
      timeout-minutes: 90
```

### Miri

```yaml
  miri:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-miri.yml@main
    with:
      working-directory: app
      timeout-minutes: 60
```

---

## Action version pins

| Action | Pinned SHA |
|---|---|
| `actions/checkout` | `v6` |
| `dtolnay/rust-toolchain` | `e97e2d8cc328f1b50210efc529dca0028893a2d9` |
| `Swatinem/rust-cache` | `779680da715d629ac1d338a641029a2f4372abb5` |
| `codecov/codecov-action` | `671740ac38dd9b0130fbe1cec585b89eea48d3de` |

Pins are kept up to date by Renovate (see `renovate.json`).
