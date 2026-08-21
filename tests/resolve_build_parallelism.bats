#!/usr/bin/env bats
# Tests the "Resolve build parallelism" step that every compiling rust-*.yml
# ships.
#
# WHY THIS SUITE EXISTS
# ---------------------
# That step decides CARGO_BUILD_JOBS for every Rust job in the fleet. Getting
# it wrong is not a loud failure: the runner agent shares the pod cgroup, so
# over-committing kills the AGENT, and the job surfaces as "the self-hosted
# runner lost communication with the server" with no logs at all. The value it
# replaced was a hardcoded "4" that silently went stale across five tier
# resizes (4.5Gi -> 2Gi -> 2.25Gi -> 2.5Gi -> 3Gi). A derivation that is never
# exercised would just be a more elaborate way to be wrong.
#
# It runs the script EXTRACTED FROM THE YAML rather than a copy, so the test
# cannot drift away from what actually ships (workspace rule: "test the
# artifact as used"). `CGROUP_MEMORY_MAX_PATH` is the one production seam;
# `nproc` is stubbed on PATH so no second seam is needed.

WORKFLOWS="$BATS_TEST_DIRNAME/../.github/workflows"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_resolve_step.py"

setup_file() {
  python3 "$BATS_TEST_DIRNAME/lib/extract_resolve_step.py" \
    "$BATS_TEST_DIRNAME/../.github/workflows/rust-build.yml" \
    >"$BATS_FILE_TMPDIR/resolve.sh"
  [ -s "$BATS_FILE_TMPDIR/resolve.sh" ] || {
    echo "could not extract the resolve step from rust-build.yml"
    return 1
  }
}

# Prints the resolve step's script for one workflow, or nothing if absent.
step_body() { python3 "$EXTRACT" "$1"; }

# Runs the extracted script with a fixture cgroup limit and cpu count.
# Echoes the CARGO_BUILD_JOBS value it wrote to $GITHUB_ENV.
run_resolve() {
  local requested="$1" limit="$2" cpus="$3"
  local d="$BATS_TEST_TMPDIR/run.$$.$RANDOM"
  mkdir -p "$d/bin"

  # "__MISSING__" deliberately leaves the file absent, exercising the
  # unreadable-limit path rather than a value.
  if [ "$limit" != "__MISSING__" ]; then
    printf '%s\n' "$limit" >"$d/memory.max"
  fi

  printf '#!/bin/sh\necho %s\n' "$cpus" >"$d/bin/nproc"
  chmod +x "$d/bin/nproc"

  : >"$d/github_env"
  PATH="$d/bin:$PATH" \
  GITHUB_ENV="$d/github_env" \
  REQUESTED="$requested" \
  CGROUP_MEMORY_MAX_PATH="$d/memory.max" \
    bash "$BATS_FILE_TMPDIR/resolve.sh" >"$d/stdout" 2>&1 || return 1

  sed -n 's/^CARGO_BUILD_JOBS=//p' "$d/github_env"
}

@test "case 1: an explicit number always wins over the derivation" {
  # The escape hatch for crates whose baseline alone exceeds the pod
  # (ffreis-rust-shared: 2541 MB at jobs=1). If this broke, those crates
  # would be silently raised back into OOM territory.
  [ "$(run_resolve 1 2147483648 4)" = "1" ]
  [ "$(run_resolve 8 2147483648 4)" = "8" ]
}

@test "case 2: auto derives from the real cgroup limit" {
  # 2 GiB is the live ci-light pod (measured on a real runner 2026-08-21),
  # and must reproduce the hand-tuned "2" it replaces — otherwise this change
  # is a silent fleet-wide retune rather than a refactor.
  [ "$(run_resolve auto 2147483648 4)" = "2" ]
  # 3 GiB is the heavy tier after this session's resize.
  [ "$(run_resolve auto 3221225472 4)" = "3" ]
}

@test "case 3: auto never exceeds the cpu count" {
  # An 8Gi xl pod on a 4-core box: more compile units than cores buys
  # nothing and costs memory.
  [ "$(run_resolve auto 8589934592 4)" = "4" ]
  [ "$(run_resolve auto 8589934592 2)" = "2" ]
}

@test "case 4: a sub-1GiB pod still gets at least one job" {
  # Integer division floors to 0, and cargo rejects --jobs 0.
  [ "$(run_resolve auto 536870912 4)" = "1" ]
}

@test "case 5: an unreadable or unlimited limit falls back, never guesses big" {
  # 'max' is what hosted runners and cgroup-v1 layouts report. Deriving a
  # large number from an absent limit is how you OOM a small pod.
  [ "$(run_resolve auto max 4)" = "2" ]
  [ "$(run_resolve auto __MISSING__ 4)" = "2" ]
  [ "$(run_resolve auto garbage 4)" = "2" ]
}

@test "case 6: every workflow that ships the step ships an IDENTICAL one" {
  # The step is duplicated by necessity — a reusable workflow cannot
  # reference a repo-local composite action without a self-referential SHA
  # pin. Duplication without a drift guard is how one file quietly keeps the
  # old behaviour.
  local ref="" name="" body="" count=0
  for f in "$WORKFLOWS"/rust-*.yml; do
    name="$(basename "$f")"
    body="$(step_body "$f")"
    [ -n "$body" ] || continue
    count=$((count + 1))
    if [ -z "$ref" ]; then
      ref="$body"
    elif [ "$body" != "$ref" ]; then
      echo "$name's resolve step has drifted from the first one"
      diff <(printf '%s' "$ref") <(printf '%s' "$body") || true
      false
    fi
  done
  [ "$count" -eq 13 ] || {
    echo "expected 13 workflows with the step, found $count"
    false
  }
}

@test "case 7: no COMPILING workflow is missing the step" {
  # The important half: catches a NEW workflow added later that compiles but
  # never resolves its parallelism, which would silently stop tracking the
  # tier. Derived from what each file actually invokes rather than a
  # hand-maintained list, because hand-lists drift silently. Correctly exempt
  # today: rust-affected (cargo metadata), rust-fmt (cargo fmt), rust-deny
  # (cargo deny), rust-container / rust-semgrep (no cargo at all).
  local missing=0 name=""
  for f in "$WORKFLOWS"/rust-*.yml; do
    name="$(basename "$f")"
    [ -n "$(step_body "$f")" ] && continue
    # Strip comments first — rust-security.yml discusses `cargo install` in
    # prose while deliberately using a prebuilt binary instead.
    if sed 's/#.*//' "$f" |
      grep -qE 'cargo (build|test|clippy|doc|bench|install|llvm-cov|mutants|miri)'; then
      echo "$name compiles but has no 'Resolve build parallelism' step"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "case 8: no workflow still pins CARGO_BUILD_JOBS at job level" {
  # A leftover job-level env is overridden by this step's $GITHUB_ENV write,
  # so it would be dead config that still reads as authoritative. Guards
  # against a partial revert.
  ! grep -rn 'CARGO_BUILD_JOBS: ' "$WORKFLOWS"
}

@test "case 9: the resolve step never depends on the caller's working-directory" {
  # It runs BEFORE actions/checkout, so the job's default working-directory
  # (the caller's `working-directory` input, e.g. examples/hello) does not
  # exist yet — bash cannot start and the whole job dies before checkout.
  # That is exactly how the first CI run of this change failed, and nothing
  # in the extracted-script tests could see it because the bug is in the
  # step's PLACEMENT, not its logic.
  local missing=0 name=""
  for f in "$WORKFLOWS"/rust-*.yml; do
    name="$(basename "$f")"
    [ -n "$(step_body "$f")" ] || continue
    if ! python3 "$BATS_TEST_DIRNAME/lib/check_working_directory.py" "$f"; then
      echo "$name's resolve step is not pinned to the workspace root"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ]
}
