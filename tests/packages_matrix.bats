#!/usr/bin/env bats
# Tests the `packages` input on rust-lint.yml and rust-test.yml: the per-package
# matrix that splits one whole-workspace job into one job per crate.
#
# WHY THIS SUITE EXISTS
# ---------------------
# Two separate risks, and the second is the dangerous one.
#
# 1. The normalisation itself (JSON / comma / newline -> a matrix) must reject
#    garbage LOUDLY. A non-empty `packages` that parses to nothing must never
#    fall back to the whole-workspace run: the caller set it precisely because
#    the workspace does not fit the pod, so a silent fallback reintroduces the
#    OOM it was escaping. "Absence of evidence is not evidence of success" is
#    already a load-bearing rule in this repo (see rust-mutation.yml's scorer).
#
# 2. The DEFAULT path must be byte-for-byte what it was. This reusable is
#    called by many repos across two owners, and `lint` / `test` are required
#    status checks on them. A renamed job, an added `needs`, or a `-p` leaking
#    into the unsplit command would break every caller at once, at whatever
#    moment Renovate bumps their pin — with no human in the loop. Cases 7-10
#    are that proof, asserted structurally against the shipped YAML rather
#    than reasoned about in a commit message.
#
# The normalisation script is EXTRACTED FROM THE YAML, not copied here, for
# the same reason resolve_build_parallelism.bats does it: a copy passes
# forever after the real step drifts.

WORKFLOWS="$BATS_TEST_DIRNAME/../.github/workflows"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"
QUERY="$BATS_TEST_DIRNAME/lib/packages_matrix.py"

setup_file() {
  python3 "$BATS_TEST_DIRNAME/lib/extract_step.py" \
    "$BATS_TEST_DIRNAME/../.github/workflows/rust-lint.yml" \
    "Normalise the packages input" >"$BATS_FILE_TMPDIR/plan.sh"
  [ -s "$BATS_FILE_TMPDIR/plan.sh" ] || {
    echo "could not extract the plan step from rust-lint.yml"
    return 1
  }
}

# Runs the extracted normaliser. Echoes the GITHUB_OUTPUT it wrote on success;
# on failure echoes its stdout (which carries the ::error:: annotation) and
# returns nonzero.
run_plan() {
  local packages="$1" clippy_args="${2:-}"
  local d="$BATS_TEST_TMPDIR/plan.$$.$RANDOM"
  mkdir -p "$d"
  : >"$d/github_output"

  if GITHUB_OUTPUT="$d/github_output" \
    PACKAGES="$packages" \
    CLIPPY_ARGS="$clippy_args" \
    bash "$BATS_FILE_TMPDIR/plan.sh" >"$d/stdout" 2>&1; then
    cat "$d/github_output"
    return 0
  fi
  cat "$d/stdout"
  return 1
}

# Echoes the normaliser's stdout (annotations and log lines) regardless of
# exit status.
plan_stdout() {
  local packages="$1" clippy_args="${2:-}"
  local d="$BATS_TEST_TMPDIR/out.$$.$RANDOM"
  mkdir -p "$d"
  : >"$d/github_output"
  GITHUB_OUTPUT="$d/github_output" \
    PACKAGES="$packages" \
    CLIPPY_ARGS="$clippy_args" \
    bash "$BATS_FILE_TMPDIR/plan.sh" 2>&1 || true
}

# ---------------------------------------------------------------------------
# The normalisation
# ---------------------------------------------------------------------------

@test "case 1: a JSON array becomes the matrix verbatim" {
  run run_plan '["crate-a","crate-b"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'packages=["crate-a","crate-b"]'* ]]
  [[ "$output" == *"count=2"* ]]
}

@test "case 2: a comma list and a newline list reach the SAME matrix" {
  # Three spellings documented on the input; if they diverged, a caller
  # switching spelling would silently change which crates are linted.
  run run_plan 'crate-a, crate-b'
  [ "$status" -eq 0 ]
  [[ "$output" == *'packages=["crate-a","crate-b"]'* ]]

  run run_plan 'crate-a
crate-b'
  [ "$status" -eq 0 ]
  [[ "$output" == *'packages=["crate-a","crate-b"]'* ]]

  # Ragged whitespace is a hand-written YAML block scalar's natural state.
  run run_plan '  crate-a ,,  crate-b
'
  [ "$status" -eq 0 ]
  [[ "$output" == *'packages=["crate-a","crate-b"]'* ]]
}

@test "case 3: a single package still produces a one-leg matrix" {
  # The degenerate case a multi-crate caller hits while migrating crate by
  # crate. It must not be mistaken for "empty".
  run run_plan '["only-one"]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'packages=["only-one"]'* ]]
  [[ "$output" == *"count=1"* ]]
}

@test "case 4: non-empty input that parses to ZERO names is a hard error" {
  # THE important case. Falling back to a whole-workspace run here would
  # silently restore the exact command the caller split to escape, and the
  # job would OOM with no indication that the split never happened.
  run run_plan ',,,'
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
  [[ "$output" == *"parsed to zero package names"* ]]

  run run_plan '[]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"parsed to zero package names"* ]]
}

@test "case 5: malformed JSON and bad package names fail loudly" {
  run run_plan '["unterminated"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not parse"* ]]

  run run_plan '{"crate":"a"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be an ARRAY"* ]]

  # A shell metacharacter in a package name would reach a cargo command line.
  run run_plan 'crate-a;rm -rf /'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid cargo package names"* ]]

  run run_plan '["--workspace"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid cargo package names"* ]]
}

@test "case 6: a duplicate package name fails rather than running twice" {
  # Two identical matrix legs would compile the same crate twice on a tier
  # capped at one replica — pure serialized cost, and GitHub would render two
  # identically-named jobs.
  run run_plan '["crate-a","crate-a"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate package names"* ]]
}

@test "case 7: an arg-level package selector warns, but does not fail" {
  # A rollout safety net, not a policy gate — the same choice rust-mutation.yml
  # makes for its multi-crate warning. Failing here would break a caller who
  # sets both while migrating.
  run run_plan '["crate-a"]' '--workspace -- -D warnings'
  [ "$status" -eq 0 ]

  output="$(plan_stdout '["crate-a"]' '--workspace -- -D warnings')"
  [[ "$output" == *"::warning::"* ]]

  # The default clippy-args must NOT warn, or the warning is noise.
  output="$(plan_stdout '["crate-a"]' '-- -D warnings')"
  [[ "$output" != *"::warning::"* ]]
}

# ---------------------------------------------------------------------------
# Backward compatibility of the DEFAULT (empty `packages`) path
# ---------------------------------------------------------------------------

@test "case 8: the default path's cargo command carries no -p" {
  # The unsplit job must run the command it always ran. If `-p` leaked into
  # it, every caller that never set `packages` would fail on a workspace with
  # more than one crate.
  python3 "$QUERY" default-command rust-lint.yml lint
  python3 "$QUERY" default-command rust-test.yml test
}

@test "case 9: the unsplit job gains no needs and no matrix" {
  # A `needs:` on the default job would make it depend on a plan job that is
  # SKIPPED when `packages` is empty — and a skipped dependency skips its
  # dependents, so `lint` would silently stop running for every existing
  # caller while still reporting green-by-skip.
  python3 "$QUERY" unsplit-standalone rust-lint.yml lint
  python3 "$QUERY" unsplit-standalone rust-test.yml test
}

@test "case 10: the split and unsplit jobs are mutually exclusive" {
  # Exactly one of them may run for any given input. Both running would
  # double the work; neither running would be a vacuous green.
  python3 "$QUERY" mutually-exclusive rust-lint.yml lint lint-package
  python3 "$QUERY" mutually-exclusive rust-test.yml test test-package
}

@test "case 11: the default job keeps its id, so required checks still match" {
  # `lint` and `test` are required status checks on consumer repos. Renaming
  # either — including by folding it into a matrix, which appends the leg's
  # values to the rendered job name — leaves those checks permanently
  # pending, which reads as "still running", not as a break.
  python3 "$QUERY" job-exists rust-lint.yml lint
  python3 "$QUERY" job-exists rust-test.yml test
}

# ---------------------------------------------------------------------------
# The split path's own shape
# ---------------------------------------------------------------------------

@test "case 12: the matrix is fail-fast: false" {
  # One crate's failure must not cancel its siblings: you want every crate's
  # errors from one run, and a cancelled sibling surfaces as `cancelled`
  # rather than as a failure — which this fleet has repeatedly misread as
  # flaky infra, and which cascades into dependent aggregate jobs.
  python3 "$QUERY" fail-fast-false rust-lint.yml lint-package
  python3 "$QUERY" fail-fast-false rust-test.yml test-package
}

@test "case 13: each matrix leg gets an ISOLATED cargo cache" {
  # A cache key shared across legs would restore the whole workspace's
  # target/ into every leg, re-inflating the memory and ephemeral-storage
  # pressure the split exists to remove. Concurrent jobs sharing one cargo
  # target dir have already corrupted results in this fleet, so the
  # isolation is DECLARED here rather than left to rust-cache's implicit
  # matrix-aware keying.
  python3 "$QUERY" cache-isolated rust-lint.yml lint-package
  python3 "$QUERY" cache-isolated rust-test.yml test-package
}

@test "case 14: every matrix leg actually scopes cargo with -p" {
  # The entire point of the split. A leg that ran the whole workspace would
  # be N times the original cost and would still OOM.
  python3 "$QUERY" split-command rust-lint.yml lint-package
  python3 "$QUERY" split-command rust-test.yml test-package
}

@test "case 15: the split job carries a timeout and its own permissions" {
  # Repo rules: per-direct-job `timeout-minutes`, per-job `permissions`,
  # never a top-level block. A direct job without a timeout can occupy a
  # single-replica tier until GitHub's 6h default expires.
  python3 "$QUERY" job-hygiene rust-lint.yml lint-package
  python3 "$QUERY" job-hygiene rust-test.yml test-package
  python3 "$QUERY" job-hygiene rust-lint.yml packages-plan
  python3 "$QUERY" job-hygiene rust-test.yml packages-plan
}

@test "case 16: the split job's permissions do not EXCEED the unsplit job's" {
  # A caller's `permissions` must be a superset of the callee's. If the split
  # job asked for more than the job it replaces, every existing caller's
  # permissions block would become insufficient the moment they opted in.
  python3 "$QUERY" permissions-not-widened rust-lint.yml lint lint-package
  python3 "$QUERY" permissions-not-widened rust-test.yml test test-package
}
