#!/usr/bin/env bats
# Tests `rust-mutation.yml`'s `base-ref` input: that `--in-diff` can be scoped
# on a NON-pull_request event, and that an unresolvable ref FAILS rather than
# silently running an unscoped whole-crate sweep.
#
# WHY THIS SUITE EXISTS
# ----------------------
# `cargo mutants --in-diff` needs a base to diff against. On `pull_request` the
# base comes from `github.event.pull_request.base.ref`; on every other event
# there was none, so `in-diff: true` was SILENTLY IGNORED and the sweep ran
# UNSCOPED. On the crate this workflow's own `in-diff` description measures
# that is 109s scoped versus ~123 min unscoped against an 85-minute
# `timeout-minutes` — i.e. the run could not finish, while the input the caller
# set said it would be cheap.
#
# CI CANNOT PROVE THIS. `self-test.yml` runs on `push: [main]` and
# `workflow_dispatch` only — it has NO `pull_request` trigger, so it never
# fires on a PR at all. `ci.yml` does run on `pull_request`, but its `mutation`
# job carries `if: ${{ !github.event.pull_request.draft }}` and every PR in
# this workspace opens as a draft, so that job is SKIPPED on the PR that
# changes this very workflow. Neither passes `in-diff`/`base-ref` either. This
# suite is therefore the only thing that exercises the new path on a draft PR:
# `ci.yml`'s `resolve-parallelism-tests` job runs `make test` with no draft
# gate.
#
# It runs the script EXTRACTED FROM THE YAML (workspace rule: "test the
# artifact as used") via the repo's generic tests/lib/extract_step.py, the same
# technique resolve_build_parallelism.bats and mutation_shard_completeness.bats
# use. Renaming the step breaks the extraction loudly rather than silently
# testing nothing.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-mutation.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"

setup_file() {
  python3 "$EXTRACT" "$WORKFLOW" "Compute PR diff for --in-diff" \
    >"$BATS_FILE_TMPDIR/diff.raw"
  [ -s "$BATS_FILE_TMPDIR/diff.raw" ] || {
    echo "could not extract 'Compute PR diff for --in-diff' from rust-mutation.yml"
    return 1
  }
  # The step interpolates ${{ inputs.working-directory }} into two log lines.
  # Substitute it the way the runner would before bash ever sees it.
  sed 's|\${{ inputs.working-directory }}|wd|g' \
    "$BATS_FILE_TMPDIR/diff.raw" >"$BATS_FILE_TMPDIR/diff.sh"
}

# A repo with a tagged base commit on `main` and one later commit on a FEATURE
# branch touching a .rs file under `wd/` — a SUBDIRECTORY workspace, matching
# every *-lambdas-rust caller. The feature branch matters: this models the real
# scenario the input exists for (dispatch a run from a branch and diff it
# against main). Committing both on main would make `main...HEAD` empty and the
# scoping cases would assert nothing.
setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  rm -rf "$REPO"
  mkdir -p "$REPO/wd/src"
  cd "$REPO" || return 1
  git init -q -b main .
  git config user.email t@example.com
  git config user.name t
  echo 'fn a() -> i32 { 1 }' >wd/src/lib.rs
  git add -A
  git commit -qm base
  git tag v1
  BASE_SHA="$(git rev-parse HEAD)"
  git checkout -q -b feature
  echo 'fn b() -> i32 { 2 }' >>wd/src/lib.rs
  git add -A
  git commit -qm change
}

# Runs the extracted step as the `mutation` job does: inside
# inputs.working-directory, with BASE_REF/BASE_REF_SOURCE supplied by the
# step's own `env:` block.
run_diff_step() {
  DIFF_PATH="$BATS_TEST_TMPDIR/pr.diff" \
    GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out.txt" \
    BASE_REF="$1" \
    BASE_REF_SOURCE="${2:-the base-ref input}" \
    bash -c "cd '$REPO/wd' && bash '$BATS_FILE_TMPDIR/diff.sh'"
}

@test "case 1: a branch base-ref scopes the diff on a non-pull_request event" {
  run run_diff_step main
  [ "$status" -eq 0 ]
  grep -q '^result=ok$' "$BATS_TEST_TMPDIR/out.txt"
}

@test "case 2: a tag base-ref resolves (bare, not origin/<ref>)" {
  run run_diff_step v1
  [ "$status" -eq 0 ]
  grep -q '^result=ok$' "$BATS_TEST_TMPDIR/out.txt"
}

@test "case 3: a raw commit SHA base-ref resolves" {
  run run_diff_step "$BASE_SHA"
  [ "$status" -eq 0 ]
  grep -q '^result=ok$' "$BATS_TEST_TMPDIR/out.txt"
}

# The whole point of the input. A silent fall back to an unscoped sweep is the
# bug, and it fails in the EXPENSIVE direction: the caller asked for a 109s run
# and would get one that blows timeout-minutes.
@test "case 4: an unresolvable base-ref is a HARD ERROR, not an unscoped sweep" {
  run run_diff_step no-such-ref
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot resolve base ref 'no-such-ref'"* ]]
  [[ "$output" == *"Refusing to fall back to an UNSCOPED whole-crate sweep"* ]]
  # It must NOT have declared a usable diff.
  run grep -q '^result=ok$' "$BATS_TEST_TMPDIR/out.txt"
  [ "$status" -ne 0 ]
}

# The error message has to name the knob the caller actually turned, or the
# reader goes looking at fetch-depth when they set base-ref (and vice versa).
@test "case 5: the failure names which knob supplied the ref" {
  run run_diff_step no-such-ref "the base-ref input"
  [ "$status" -ne 0 ]
  [[ "$output" == *"from the base-ref input"* ]]
}

# The best-effort fetch must not be able to abort the step before the gate
# runs: this fixture has NO remote at all, so both fetch arms fail. If their
# `|| true` were dropped, `set -e` would kill the step here and the clear
# "cannot resolve" message would become an unexplained failure.
@test "case 6: a failing best-effort fetch still reaches the gate" {
  run git -C "$REPO" remote
  [ -z "$output" ]
  run run_diff_step no-such-ref
  [ "$status" -eq 1 ]
  [[ "$output" == *"even after trying to fetch it"* ]]
}

# Item 17's invariant, re-asserted on the new code path: cargo-mutants reads
# the diff's paths as relative to working-directory, so a subdirectory
# workspace must emit `src/lib.rs`, never `wd/src/lib.rs`.
@test "case 7: diff paths stay relative to working-directory on the base-ref path" {
  run run_diff_step v1
  [ "$status" -eq 0 ]
  grep -q '^+++ b/src/lib.rs$' "$BATS_TEST_TMPDIR/pr.diff"
  run grep -q '^+++ b/wd/' "$BATS_TEST_TMPDIR/pr.diff"
  [ "$status" -ne 0 ]
}

# Nothing changed is a legitimate pass, not a failure — the `Run mutation
# testing` step keys off result=empty to skip itself.
@test "case 8: no changed Rust source reports empty and exits 0" {
  run run_diff_step HEAD
  [ "$status" -eq 0 ]
  grep -q '^result=empty$' "$BATS_TEST_TMPDIR/out.txt"
}
