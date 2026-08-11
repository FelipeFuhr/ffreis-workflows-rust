# Agent Context

**This repo:** `ffreis-workflows-rust` — reusable GitHub Actions workflow library for
Rust projects. Covers fmt, clippy, test, matrix builds, cargo-audit, unit and
integration coverage, mutation testing, container build, cargo-deny, docs, MSRV
check, benchmarks, and Miri.

## Non-obvious rules (read before changing anything)

1. **ALL `rust-*.yml` workflows must appear in `self-test.yml`.** No exemptions.

   1a. **`rust-affected.yml`** computes which workspace crates a change touches and
   emits `cargo-args` (`--workspace` or `-p a -p b ...`) for downstream jobs to feed
   into their `*-args` inputs. It walks the **intra-workspace reverse-dependency
   graph** from `cargo metadata`, so editing a shared crate expands to every
   dependent (no false skips). It is over-approximating by design and falls back to
   `--workspace` on any uncertainty (unknown base commit, root manifest/lockfile
   change). **Push events always return `--workspace`** so a downstream
   delete-sync upload (e.g. lambdas-packer on main) never drops unchanged
   artifacts — selective build is a PR-only optimisation. Callers gate compile
   jobs on its `changed` output.

   1b. **sccache (S3 backend) is opt-in** on `rust-build/test/lint/coverage/docs`
   via the `sccache`, `sccache-bucket`, `sccache-region`, `sccache-role-arn`
   inputs. Default off → behaviour unchanged. When on with a role ARN, the job
   assumes that role via OIDC; that is why those five jobs carry
   `id-token: write` (a no-op unless sccache+role are set). `CARGO_INCREMENTAL=0`
   is forced under sccache (required — incremental + wrapper are incompatible).
   `SCCACHE_S3_KEY_PREFIX` is set to the caller repo (`github.repository`) so
   each repo's cache is isolated (bounds PR cache-poisoning across same-owner
   repos sharing one bucket).

   1c. **nextest is opt-in** on `rust-test.yml` (`nextest: true`). It runs
   `cargo nextest run` + a separate `cargo test --doc` (nextest skips doctests).
   Opt-in because nextest's post-`--` arg semantics differ from `cargo test`, so a
   hard swap would break callers passing `cargo test`-specific `test-args`.

2. **Miri special case:** Call Miri with `miri-args: --lib` in `self-test.yml` to avoid
   compiling Criterion benchmarks (FFI/unsafe, incompatible with Miri). Do not remove.

3. **`cargo-deny` requires `deny.toml`** at the calling repo's workspace root.
   Callers without it will fail at runtime. Do not make it optional silently.

4. **MSRV input is required** — always a concrete version (e.g., `1.80.0`), not `stable`.

4a. **Private cross-repo cargo git dependencies (`PRIVATE_DEPS_TOKEN` secret).**
   Every workflow that resolves the Cargo dependency graph accepts an optional
   `PRIVATE_DEPS_TOKEN` workflow_call secret (originally added to
   `rust-coverage.yml`, `rust-deny.yml`, `rust-docs.yml`, `rust-lint.yml`,
   `rust-mutation.yml`, `rust-test.yml`, `rust-build.yml` in #54/#56/#57; later
   extended to `rust-bench.yml`, `rust-miri.yml`, `rust-msrv.yml`,
   `rust-proptest.yml`, `rust-quick-checks.yml`, `rust-security.yml`,
   `rust-integration-coverage.yml`). When set,
   a "Configure git for private cargo dependencies" step (right after checkout)
   runs `git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf
   "https://github.com/"` and sets `CARGO_NET_GIT_FETCH_WITH_CLI=true` — required
   because cargo's libgit2 backend does not reliably honor `url.insteadOf`
   rewriting (confirmed empirically, see #56). Secret name is
   SCREAMING_SNAKE_CASE (not `private-deps-token`) because workflow_call secret
   IDs must be valid identifiers — a hyphenated name causes a silent
   `startup_failure` (zero jobs created). `rust-fmt.yml` is intentionally NOT
   wired: `cargo fmt` never resolves the dependency graph, so it has nothing to
   authenticate.

5. **Coverage threshold** (`coverage-threshold`, default 80) is per-workflow input.
   Callers override per their own standard.

6. **`dtolnay/rust-toolchain` pinned to full SHA.** Renovate manages this.

7. **Concurrency is caller-controlled.** Never add `concurrency:` to reusable workflows.

8. **Container build in `self-test.yml`:** pass `push: false` or omit registry inputs —
   no registry credentials required in this repo.

9. **`cargo-build-jobs` input (default `"4"`) caps `CARGO_BUILD_JOBS`** on every
   reusable workflow that compiles Rust source: `rust-build.yml`, `rust-test.yml`,
   `rust-docs.yml`, `rust-mutation.yml`, `rust-coverage.yml`,
   `rust-integration-coverage.yml`, `rust-bench.yml`, `rust-miri.yml`,
   `rust-proptest.yml`, `rust-msrv.yml`, `rust-lint.yml` (clippy
   is a full compile), `rust-quick-checks.yml` (its clippy step), and
   `rust-sonar.yml` (its llvm-cov build). Set as a job-level `env:` so it applies
   to every step. Prevents rustc's default full-core parallelism from
   OOM-SIGKILLing a job on the memory-constrained runner
   when compiling a heavy dependency graph (e.g. `aws-sdk-*`
   crates). Default "4" matches the workspace Makefile convention; GitHub-hosted
   callers wanting full parallelism pass a higher value. `rust-fmt.yml`,
   `rust-deny.yml`, `rust-affected.yml`, and `rust-security.yml` are
   intentionally NOT wired — none of them compile the caller's workspace
   (`cargo fmt`/`cargo deny check`/`cargo metadata`/`cargo audit` all work off
   the manifest or lockfile, not a full build).

10. **`--locked` is conditional on `Cargo.lock` existing**, only in
    `rust-build.yml` and `rust-msrv.yml` — the only two reusable workflows that
    hardcode `--locked` against the *caller's own* workspace build. Every other
    `--locked` in this repo (`rust-quick-checks.yml`, `rust-sonar.yml`,
    `rust-mutation.yml`, `rust-security.yml`) is a `cargo install <tool>
    --locked` pinning the installed TOOL's own bundled lockfile, not the
    caller's — leave those hardcoded. Library crates in the fleet gitignore
    `Cargo.lock` (only binaries/Lambdas commit it), so an unconditional
    `--locked` broke every library caller. Do not hardcode `--locked`
    unconditionally again; detect with `[ -f Cargo.lock ] && locked_arr=("--locked")`.

11. **`rust-integration-coverage.yml` is a SEPARATE metric from `rust-coverage.yml`,
    not a merge of the two.** It runs `cargo llvm-cov ... -- --include-ignored
    --test-threads=1` to a distinct `lcov-integration.info` file, gated by its own
    `coverage-threshold` input, uploaded to Codecov under its own `codecov-flags`
    (default `integration` vs. the unit workflow's `unit`) so the two floors can be
    enforced and tracked independently. It targets convention (a) — `#[ignore]`-tagged
    tests colocated in the crate under test (see the rust-lambda project template) —
    as the primary path; convention (b) (a dedicated `integration-tests` workspace
    member, see a private consumer's `lambdas/integration-tests/`) also works
    unmodified since `--include-ignored` is a no-op with nothing ignored and
    `--workspace` already covers the extra member. `--test-threads=1` is the
    workflow default (not just a caller convention) because integration suites
    commonly share fixtures/DB state/env vars that break under parallel execution.

12. **`rust-mutation.yml`'s `mutants-args` default (`''`) mutates the WHOLE
    workspace** — every crate, not just the one under review. This is the exact
    failure mode that has filled the workspace's build machine's disk before.
    Multi-crate callers MUST pass `-p <crate-name>` (or run a matrix, one job per
    crate). The job itself now prints a `::warning::` (not a failure — a rollout
    safety net, not a policy gate) when `mutants-args` is empty AND the checked-out
    `Cargo.toml` declares a multi-member `[workspace]`, detected via `cargo
    metadata --no-deps` + `jq` (falls back to a `Cargo.toml` text scan if either is
    unavailable). Do NOT change the default without a deliberate, separately-flagged
    migration — single-crate callers rely on the current unscoped behavior being a
    no-op for them. There is no `packages` input on this workflow; the only
    (and correct) scoping mechanism is `mutants-args: '-p <crate>'` — some callers
    have historically passed an invalid `packages:` key that GitHub Actions
    silently drops (not a supported input; fix at the caller, not here).

13. **`CODECOV_TOKEN` is optional on EVERY trigger, push included** — in both
    `rust-coverage.yml` and `rust-integration-coverage.yml`'s "Check Codecov
    token availability" step. This matches the `secrets.CODECOV_TOKEN:
    required: false` declaration on the `workflow_call` block: a missing token
    degrades to `::warning::` + `skip_upload=true`, never `exit 1`. An earlier
    version hard-failed the whole job with `exit 1` specifically on `push`
    events — this broke CI on every push to `main` for every real caller in
    the workspace, none of which had ever wired the secret (confirmed via
    `gh secret list` across ~28 callers), including this repo's own
    `self-test.yml`. Do not reintroduce a push-specific hard-fail without also
    flipping the secret to `required: true` and updating every caller.

## Structure

```
.github/workflows/
  rust-*.yml      ← reusable library
  devops-*.yml    ← repo-maintenance
  ci.yml
examples/hello/   ← minimal Rust project + Cargo.toml
renovate.json     ← auto-updates action SHAs
```

## Build/test

```bash
make setup              # install git hooks and verify gitleaks is installed
make fmt-check          # rustfmt check
make lint               # actionlint + clippy examples
make secrets-scan-staged
```

## Cross-repo role

Consumed by private Lambda repos (pinned SHA). Breaking changes to the SHA
require callers to update their pin via Renovate.

## Public repo — private-repo hygiene

This is a **public** GitHub repository. When writing commit messages, PR titles,
PR descriptions, or any other user-visible text, **never name private repos** —
website content, inventory, infra, Lambda, or data repos that are not publicly
listed. Use generic terms instead: "the fleet inventory", "a private consumer",
"internal infra", "private data repo", etc.

## Keeping this file current

- **If you discover a fact not reflected here:** add it before finishing your task.
- **If something here is wrong or outdated:** correct it in the same commit as the code change.
- **If you rename a file, command, or concept referenced here:** update the reference.
