#!/usr/bin/env bats
# Tests that `mutation-warm`'s cache-priming build (and, alongside it, each
# shard's own "Baseline test run") pass cargo-mutants the SAME feature flags
# cargo-mutants will actually build with — extracted from `mutants-args`,
# not hardcoded.
#
# WHY THIS SUITE EXISTS
# ----------------------
# cargo-mutants does NOT default to --all-features (verified against
# cargo-mutants 27.1.0's own --help: --all-features, --no-default-features
# and --features are all opt-in). cargo hashes build artifacts by feature
# set, so a warm target/ built with the WRONG features satisfies nothing —
# cargo rebuilds from scratch on restore, and mutation-warm becomes a
# no-op that still costs an extra runner job. A first version of this job
# hardcoded --all-features unconditionally; harmless for a crate with no
# [features] section (every crate this fix was measured against), silently
# defeating the whole fix for any other consumer. Caught in review before
# merge — this suite is what stops it recurring.
#
# It runs the scripts EXTRACTED FROM THE YAML (workspace rule: "test the
# artifact as used"), the same technique resolve_build_parallelism.bats
# uses, via the repo's existing generic tests/lib/extract_step.py.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-mutation.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"

setup_file() {
  python3 "$EXTRACT" "$WORKFLOW" "Prime target/ for the matrix (build only, do not run)" \
    >"$BATS_FILE_TMPDIR/prime.sh"
  [ -s "$BATS_FILE_TMPDIR/prime.sh" ] || {
    echo "could not extract mutation-warm's priming step from rust-mutation.yml"
    return 1
  }

  python3 "$EXTRACT" "$WORKFLOW" "Baseline test run" \
    >"$BATS_FILE_TMPDIR/baseline.sh"
  [ -s "$BATS_FILE_TMPDIR/baseline.sh" ] || {
    echo "could not extract the mutation job's Baseline test run step from rust-mutation.yml"
    return 1
  }
}

# Runs an extracted script ($1) with MUTANTS_ARGS=$2 against a stub `cargo`
# that logs its argv instead of building anything, and echoes exactly what
# `cargo` was invoked with.
run_with_stub_cargo() {
  local script="$1" mutants_args="$2"
  local d="$BATS_TEST_TMPDIR/run.$$.$RANDOM"
  mkdir -p "$d/bin"
  local log="$d/cargo_argv.txt"

  cat >"$d/bin/cargo" <<'STUB'
#!/bin/bash
echo "$@" >>"$CARGO_LOG"
exit 0
STUB
  chmod +x "$d/bin/cargo"

  : >"$log"
  PATH="$d/bin:$PATH" \
  CARGO_LOG="$log" \
  MUTANTS_ARGS="$mutants_args" \
    bash "$script" >"$d/stdout" 2>&1 || return 1

  cat "$log"
}

@test "mutation-warm priming: no feature flags in mutants-args -> none passed" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "")" = "test --no-run" ]
}

@test "mutation-warm priming: -p <crate> alone (typical scoped caller) -> still no feature flags" {
  # mutants-args carrying an unrelated flag must not accidentally trip the
  # feature extraction.
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "-p mycrate")" = "test --no-run" ]
}

@test "mutation-warm priming: --all-features is carried through" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "--all-features")" = "test --all-features --no-run" ]
}

@test "mutation-warm priming: --no-default-features is carried through" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "--no-default-features")" = "test --no-default-features --no-run" ]
}

@test "mutation-warm priming: --features a,b (split form) is carried through" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "--features a,b")" = "test --features a,b --no-run" ]
}

@test "mutation-warm priming: --features=a,b (joined form) matches the split form" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "--features=a,b")" = "test --features a,b --no-run" ]
}

@test "mutation-warm priming: mixed mutants-args extracts only the feature flags, in a fixed order" {
  # Irrelevant flags (-p, --timeout) are ignored; the three feature flags
  # always emit in the same order (--all-features, --no-default-features,
  # --features) regardless of how the caller ordered them.
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "-p mycrate --features x,y --timeout 60 --all-features")" = "test --all-features --features x,y --no-run" ]
}

@test "Baseline test run: no feature flags in mutants-args -> none passed (and no --no-run — it actually runs)" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/baseline.sh" "")" = "test" ]
}

@test "Baseline test run: --all-features is carried through" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/baseline.sh" "--all-features")" = "test --all-features" ]
}

@test "Baseline test run: --features=a,b (joined form) is carried through" {
  [ "$(run_with_stub_cargo "$BATS_FILE_TMPDIR/baseline.sh" "--features=a,b")" = "test --features a,b" ]
}

@test "mutation-warm priming and Baseline test run resolve the SAME features from the same mutants-args" {
  # The whole point: these two steps must never disagree, or one of them
  # rebuilds a target/ the other one just threw away. Compared here
  # directly rather than only against a hardcoded expectation, so the two
  # scripts drifting from EACH OTHER (not just from cargo-mutants) is also
  # caught.
  local mutants_args="--features a,b --no-default-features"
  local prime_out baseline_out
  prime_out="$(run_with_stub_cargo "$BATS_FILE_TMPDIR/prime.sh" "$mutants_args")"
  baseline_out="$(run_with_stub_cargo "$BATS_FILE_TMPDIR/baseline.sh" "$mutants_args")"
  # Strip the priming-only "--no-run" before comparing — everything else
  # (the feature flags, in order) must be identical.
  [ "${prime_out% --no-run}" = "$baseline_out" ]
}
