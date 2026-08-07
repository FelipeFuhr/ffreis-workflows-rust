# ffreis-platform-workflows-rust

<!-- ffreis-badges:start -->
[![CI](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-workflows-rust/ci.json)](https://github.com/FelipeFuhr/ffreis-workflows-rust/actions) [![Latest version](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-workflows-rust/version.json)](https://github.com/FelipeFuhr/ffreis-workflows-rust/releases) [![License](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-workflows-rust/license.json)](https://github.com/FelipeFuhr/ffreis-workflows-rust/blob/main/LICENSE)
<!-- ffreis-badges:end -->

Reusable GitHub Actions workflows for Rust projects in the ffreis org.


All workflows use `on: workflow_call` and should be consumed from other repositories by pinning to a specific commit SHA for reproducibility and security. Example:

```yaml
uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/<file>.yml@<sha> # v1.x.y
```

Replace `<sha>` with the commit SHA corresponding to the desired release tag. Avoid using `@main` or floating `@vX` tags for production workflows.

---

## Workflows

| Workflow file | Purpose | Key inputs |
|---|---|---|
| `rust-fmt.yml` | `cargo fmt --all -- --check` | `toolchain`, `working-directory` |
| `rust-lint.yml` | Clippy with `-- -D warnings` | `toolchain`, `working-directory`, `clippy-args` |
| `rust-test.yml` | `cargo test` | `toolchain`, `working-directory`, `test-args`, `timeout-minutes` |
| `rust-build.yml` | Matrix build across Rust versions and OS | `rust-versions` (JSON), `os-list` (JSON), `working-directory`, `build-args` |
| `rust-security.yml` | `cargo-audit` CVE scan (schedule weekly in caller) | `toolchain`, `working-directory`, `ignore-advisories` |
| `rust-coverage.yml` | `cargo-llvm-cov` + Codecov upload (unit tests) | `toolchain`, `working-directory`, `coverage-args`, `coverage-threshold`, `codecov-flags`; secret `CODECOV_TOKEN` |
| `rust-integration-coverage.yml` | `cargo-llvm-cov --include-ignored` + Codecov upload (integration tests), gated as a separate metric from unit coverage | `toolchain`, `working-directory`, `coverage-args`, `coverage-threshold`, `codecov-flags`; secret `CODECOV_TOKEN` |
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
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-fmt.yml@<sha> # v1.x.y
    with:
      working-directory: app
```

### Lint

```yaml
  lint:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-lint.yml@<sha> # v1.x.y
    with:
      working-directory: app
      clippy-args: "-- -D warnings"
```

### Tests

```yaml
  test:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-test.yml@<sha> # v1.x.y
    with:
      working-directory: app
      test-args: "--all-features"
      timeout-minutes: 20
```

### Matrix build

```yaml
  build:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-build.yml@<sha> # v1.x.y
    with:
      rust-versions: '["stable","1.88.0"]'
      os-list: '["ubuntu-latest","macos-latest"]'
      working-directory: app
```

### Security audit (scheduled weekly)

```yaml
  audit:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-security.yml@<sha> # v1.x.y
    with:
      working-directory: app
      ignore-advisories: "RUSTSEC-2024-0001"
```

### Coverage with Codecov

```yaml
  coverage:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-coverage.yml@<sha> # v1.x.y
    with:
      working-directory: app
      coverage-threshold: 80
      codecov-flags: unit
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### Integration coverage with Codecov

`#[ignore]`-tagged tests colocated with the crate under test (convention (a) —
see e.g. the rust-lambda project template) are the primary target. Runs
`--include-ignored --test-threads=1` by default and uploads to a separate
Codecov flag so unit and integration floors are tracked independently.

```yaml
  integration-coverage:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-integration-coverage.yml@<sha> # v1.x.y
    with:
      working-directory: app
      coverage-threshold: 75
      codecov-flags: integration
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### Container build

```yaml
  container:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-container.yml@<sha> # v1.x.y
    with:
      image-name: my-service:latest
      containerfile: Containerfile
      context: .
```

### cargo-deny

```yaml
  deny:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-deny.yml@<sha> # v1.x.y
    with:
      working-directory: app
```

> **Note:** The calling repository must have a `deny.toml` at the workspace root.

### Docs

```yaml
  docs:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-docs.yml@<sha> # v1.x.y
    with:
      working-directory: app
```

### MSRV check

```yaml
  msrv:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-msrv.yml@<sha> # v1.x.y
    with:
      msrv: "1.80.0"
      working-directory: app
```

### Benchmarks

```yaml
  bench:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-bench.yml@<sha> # v1.x.y
    with:
      working-directory: app
      timeout-minutes: 90
```

### Miri

```yaml
  miri:
    uses: ffreis/ffreis-platform-workflows-rust/.github/workflows/rust-miri.yml@<sha> # v1.x.y
    with:
      working-directory: app
      timeout-minutes: 60
```

## Action version pins

| Action | Pinned SHA |
|---|---|
| `actions/checkout` | `v6` |
| `dtolnay/rust-toolchain` | `e97e2d8cc328f1b50210efc529dca0028893a2d9` |
| `Swatinem/rust-cache` | `779680da715d629ac1d338a641029a2f4372abb5` |
| `codecov/codecov-action` | `671740ac38dd9b0130fbe1cec585b89eea48d3de` |

Pins are kept up to date by Renovate (see `renovate.json`).
