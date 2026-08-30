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
   `--workspace` on any uncertainty (unknown base commit, root manifest/lockfile,
   unmappable path). A single package at the repository root is represented
   explicitly; never make either case selective. **Push events always return
   `--workspace`** so a downstream
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

4b. **`rust-mutation.yml`: never pass `--output` to cargo-mutants, and never let
   "no results" mean "pass".** `cargo mutants --output DIR` treats `DIR` as the
   PARENT and writes `DIR/mutants.out/`. This workflow used `--output
   mutants.out` while the scorer read `mutants.out/*.txt`, so every count came
   back 0, the `total == 0 -> pass` branch fired, and the gate reported a clean
   **100% on all 24 consumer repos without ever measuring anything** (found
   2026-08-19; cargo-mutants 27.1.0). Two invariants now hold the fix:
   the default output path is used (`./mutants.out`), and a missing
   `mutants.out/` — or a `mutants.out/` with no `caught/missed/unviable/timeout.txt`
   — is a **hard error**, never a pass. Absence of evidence is not evidence of
   success.
   `examples/hello` could not catch this: a fully-tested crate scores 100
   whether the harness works or not. That is what `examples/partial` (half
   tested, scores 50) plus the `assert-mutation-not-vacuous` job in
   `self-test.yml` exist for — **do not add tests to `shrink_to_fit_len()`** or
   the fixture stops discriminating.

4c. **`in-diff: true` is how a real crate gets a usable mutation gate.** A full
   run scales with crate size and silently becomes unrunnable: `ffreis-job-arbiter`
   has 987 mutants against a ~28s suite, ≈123 min at 4 workers versus the 90 min
   default `timeout-minutes` — so it never completed once and the gate was pure
   cost. `in-diff: true` mutates only the lines a PR changed (7 mutants / 109s on
   that same repo, measured). Requires `fetch-depth: 0`, which the workflow sets
   itself; note the quoted `'0'`/`'1'` in that expression, because GitHub treats
   the *number* `0` as falsy and the unquoted form silently yields a shallow clone.
   cargo-mutants also rejects a diff that does not match the working tree, hence
   the three-dot `base...HEAD` diff computed on the PR head.

5. **Coverage threshold** (`coverage-threshold`, default 80) is per-workflow input.
   Callers override per their own standard.

6. **`dtolnay/rust-toolchain` pinned to full SHA.** Renovate manages this.

7. **Concurrency is caller-controlled.** Never add `concurrency:` to reusable workflows.

8. **Container build in `self-test.yml`:** pass `push: false` or omit registry inputs —
   no registry credentials required in this repo.

9. **`cargo-build-jobs` input (default `"auto"`) caps `CARGO_BUILD_JOBS`** on every
   reusable workflow that compiles Rust source: `rust-build.yml`, `rust-test.yml`,
   `rust-docs.yml`, `rust-mutation.yml`, `rust-coverage.yml`,
   `rust-integration-coverage.yml`, `rust-bench.yml`, `rust-miri.yml`,
   `rust-proptest.yml`, `rust-msrv.yml`, `rust-lint.yml` (clippy
   is a full compile), `rust-quick-checks.yml` (its clippy step), and
   `rust-sonar.yml` (its llvm-cov build). Prevents rustc's default full-core
   parallelism from OOM-SIGKILLing a job on a memory-constrained runner when
   compiling a heavy dependency graph (e.g. `aws-sdk-*` crates).

   **`"auto"` derives the cap from `/sys/fs/cgroup/memory.max` at job start**
   (~1 GiB per compile unit, capped by `nproc`, floored at 1) in a
   `Resolve build parallelism` step that runs before anything invokes cargo.
   It is deliberately NOT a job-level `env:` any more: a `$GITHUB_ENV` write
   overrides both a job-level `env:` and the pod's container env (measured on
   a real runner, not assumed), so the step is authoritative — and if it were
   ever skipped, the pod's own value applies as a safe fallback instead of the
   variable being unset.

   **Why derived rather than a constant:** the previous default `"4"` was
   documented as memory-safe on a 4.5Gi pod and was never updated as the tier
   went 4.5Gi -> 2Gi -> 2.25Gi -> 2.5Gi -> 3Gi, silently over-committing every
   caller. That failure is not loud — the runner agent shares the pod cgroup,
   so it dies and the job reads as "the self-hosted runner lost communication
   with the server" with no logs. (This very list said `"4"` while `main` said
   `"2"`, which is the same drift one level up.)

   **An explicit number always wins over `auto`**, and some crates need it:
   `ffreis-rust-shared` peaked at 2541 MB with `jobs=1` against a 2560M limit,
   so memory is dominated by a per-crate baseline rather than being linear in
   job count — no derivation rescues a crate whose baseline alone exceeds the
   pod, and the honest fix there is a bigger tier. Unreadable or unlimited
   limits (hosted runners, cgroup v1) fall back to `2`, never to a large guess.

   `tests/resolve_build_parallelism.bats` (run by `make test`, and by the
   `resolve-parallelism-tests` job in `ci.yml`) exercises the script
   **extracted from the YAML** rather than a copy, and guards the 13 duplicated
   copies against drifting apart. Which workflows need the step is derived from
   the cargo verbs each file invokes, not hand-listed.

   `rust-fmt.yml`, `rust-deny.yml`, `rust-affected.yml`, `rust-container.yml`,
   `rust-semgrep.yml`, and `rust-security.yml` are intentionally NOT wired —
   none compile the caller's workspace (`cargo fmt`/`cargo deny check`/
   `cargo metadata`/`cargo audit` all work off the manifest or lockfile, and
   `rust-security.yml` deliberately uses a prebuilt cargo-audit binary rather
   than `cargo install`).

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

11b. **`CODECOV_TOKEN` is `required: false` on both coverage workflows'
    `secrets:` block, and the upload-gate step must actually honor that on
    EVERY trigger, push included.** A caller repo with no Codecov integration
    configured must never have its default-branch CI fail over this — the
    coverage-threshold check earlier in the same job is the real correctness
    gate; the Codecov upload is supplementary reporting. Do not reintroduce a
    push-specific hard-fail without deliberately flipping this secret to
    `required: true` fleet-wide first (i.e. auditing every caller for the
    token before tightening the contract, not after).

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

13. **`rust-mutation.yml`'s `runner` input defaults to the `heavy` self-hosted
    tier (`["self-hosted","local","heavy"]`), not `light` and NOT `xl`.**
    cargo-mutants rebuilds the crate once per mutant and is the single most
    memory-hungry job in the fleet; the `light` tier is a 2Gi pod, and
    because the GitHub runner AGENT shares that pod's cgroup with the build,
    the agent itself gets OOM-killed before the job ever reaches `Compute
    score and enforce threshold`. That surfaces as "the self-hosted runner
    lost communication with the server" with `BlobNotFound` job logs —
    indistinguishable from a real network outage unless you check whether the
    scoring step ran — and was misdiagnosed as flaky infra for multiple
    sessions before being traced to the pod (measured live: 1714Mi against
    the 2Gi limit). Every other reusable `rust-*.yml` workflow in this repo
    still defaults `runner` to `light`; do not "fix" those too without
    separately verifying they need it — `rust-mutation.yml` is the outlier
    because it is the only workflow that rebuilds the crate per mutant rather
    than once.

    **A first correction over-shot to `xl` (8Gi) — do not repeat that
    mistake.** The reasoning at the time ("xl fits the footprint and scales
    to zero like light") sounded right but was never checked against
    scheduling: xl sits at 0 replicas because it is UNSCHEDULABLE, not idle.
    Its 8Gi pod cannot be admitted on either fleet node while light/heavy are
    already running (burst-node: 9.71Gi allocatable, ~4.7Gi free;
    local-server: 7.58Gi allocatable, ~3.6Gi free — job-arbiter only
    schedules a class when a single node can hold it), so a mutation job on
    xl queues forever instead of failing — worse than the OOM it replaced,
    because a queued job never surfaces as a failure at all. `heavy` (3Gi) is
    50% headroom over the 2Gi that OOM'd and IS schedulable alongside
    light/heavy on either node. Evidence it's enough without measuring a
    third tier: `ffreis-job-arbiter`'s mutation job PASSED on the 2Gi light
    tier; only `ffreis-cluster-warden`'s failed there — so the real
    requirement sits between 2Gi and something modest, not up at 8Gi. If a
    future crate's mutation job OOMs even on `heavy`, measure its actual
    footprint before reaching for `xl` again; do not assume by elimination.

14. **`rust-mutation.yml`'s `mutation` job is a matrix over `shard-count`
    shards (default 4), aggregated by a separate `mutation-aggregate` job —
    it is a JOB-SIZE fix, not a wall-clock fix.** The fleet's `heavy`
    self-hosted class (item 13) is capped at `max_replicas: 1`
    (`platform/ffreis-home-infra` ansible role `job_arbiter`, `ci-build`
    class), so shards queue and run SERIALLY on one pod — sharding here only
    guarantees no single job can exceed `timeout-minutes` (default 85,
    deliberately under job-arbiter's 90-min stale-job reaper) or get
    silently killed mid-run; it does NOT parallelize the work, and adds
    roughly N× the fixed per-shard overhead (checkout, toolchain install,
    baseline test run) to total wall-clock. Do not raise the default
    `shard-count` to "go faster" — it won't, under today's runner capacity —
    and do not add a second `runner: heavy` replica to make it actually
    parallel without first checking it fits: 2 × 3Gi = 6Gi exceeds either
    node's currently-free headroom (burst-node ~4.7Gi, local-server ~3.6Gi),
    the same unschedulable trap item 13's `xl` mistake fell into.

    The `in-diff` input (default `false`) is the lever that actually reduces
    wall-clock — it scopes the WORK (only the PR's changed `.rs` lines)
    rather than just redistributing the same work across more jobs. It
    defaults to `false` at this reusable-workflow level, not `true`,
    DELIBERATELY: this repo's own `renovate/github-actions.json` preset
    auto-merges minor/patch/digest bumps to `uses: FelipeFuhr/...@SHA` pins
    with no human review, so flipping the default here would silently
    narrow every already-migrated caller's mutation gate from whole-crate to
    diff-only the moment Renovate bumps their pin — with no scheduled
    full-sweep recovering the coverage that was lost, since (verified
    2026-08-23) not one fleet consumer of this workflow has a `schedule:`
    trigger for a full/unscoped run. That is exactly the "silently weaken a
    gate" failure mode the workspace rules forbid. Adopt `in-diff: true`
    per-repo, explicitly, paired with a companion `schedule:`-triggered full
    run (`in-diff` omitted/false, `shard-count` raised for that crate) in the
    SAME PR — never as a bare default flip.

    On a `pull_request` event with `in-diff` actually active, `shard-plan`
    collapses `shard-count` to 1 automatically regardless of the caller's
    input — a diff-scoped PR run is typically a handful of mutants (measured:
    7 mutants / 109s on ffreis-job-arbiter), and sharding that would pay N×
    fixed overhead for work that finishes in under a minute unsharded.

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
