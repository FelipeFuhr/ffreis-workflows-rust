#!/usr/bin/env bats
# Tests that `mutation-aggregate` refuses to score an INCOMPLETE set of shard
# reports, and still passes the legitimate "every shard reported, collectively
# nothing to mutate" run.
#
# WHY THIS SUITE EXISTS
# ----------------------
# The aggregate scorer sums outcome files with
# `downloaded/mutants-report-shard-*/<file>` under `shopt -s nullglob`. A shard
# whose artifact never arrived therefore contributes 0 caught and 0 missed
# SILENTLY: the score becomes a ratio over whatever subset did arrive and the
# run reports a pass on a partial measurement. With every artifact missing it
# takes the `total == 0` branch and reports a clean 100 — the same shape as the
# vacuous-gate bug of 2026-08-19, one level up.
#
# `Fail fast if any shard did not succeed` cannot catch it: that step reads
# `needs.mutation.result`, the MATRIX AGGREGATE, which reads `success` as long
# as no leg failed — an upload that failed, an artifact that expired, or a leg
# skipped individually all leave it at `success`. And `Download all shard
# reports` is deliberately `continue-on-error: true`, so a download that failed
# outright is invisible there too.
#
# The hard part is that "no artifacts at all" is ALSO a legitimate outcome: a
# shard whose --in-diff slice has nothing mutable exits 0 without writing
# mutants.out/, and `if-no-files-found: ignore` then creates no artifact. That
# is why the `mutation` job leaves a per-shard RECEIPT: it turns "this shard
# reported" into something the aggregate can count, so the assertion can fail
# the missing-artifact case without failing the nothing-to-mutate case. Both
# halves are asserted below — a fix for one that breaks the other is not a fix.
#
# CI CANNOT PROVE THE FAILING SIDE. GitHub forbids `continue-on-error` on a job
# that calls a reusable workflow (actionlint rejects it), so self-test.yml has
# no way to run a mutation job with a deliberately-deleted shard artifact
# without reddening itself — the same constraint recorded for
# `assert-clock-lint-can-fail`. This suite is the proof that the gate can fail,
# and it runs the scripts EXTRACTED FROM THE YAML (workspace rule: "test the
# artifact as used") via the repo's generic tests/lib/extract_step.py, the same
# technique resolve_build_parallelism.bats and mutation_warm_features.bats use.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-mutation.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"

setup_file() {
  python3 "$EXTRACT" "$WORKFLOW" "Assert every shard reported" \
    >"$BATS_FILE_TMPDIR/assert.sh"
  [ -s "$BATS_FILE_TMPDIR/assert.sh" ] || {
    echo "could not extract 'Assert every shard reported' from rust-mutation.yml"
    return 1
  }

  python3 "$EXTRACT" "$WORKFLOW" \
    "Leave a shard receipt so the aggregate can count reporters" \
    >"$BATS_FILE_TMPDIR/receipt.sh"
  [ -s "$BATS_FILE_TMPDIR/receipt.sh" ] || {
    echo "could not extract the shard receipt step from rust-mutation.yml"
    return 1
  }

  python3 "$EXTRACT" "$WORKFLOW" "Compute aggregate score and enforce threshold" \
    >"$BATS_FILE_TMPDIR/score.sh"
  [ -s "$BATS_FILE_TMPDIR/score.sh" ] || {
    echo "could not extract the aggregate scoring step from rust-mutation.yml"
    return 1
  }
}

# A throwaway directory standing in for the mutation-aggregate job's workspace.
# The extracted scripts reference `downloaded/` relative to the current
# directory, exactly as the job does, so the fixture is built by cd-ing here.
workspace() {
  local d="$BATS_TEST_TMPDIR/ws.$$.$RANDOM"
  mkdir -p "$d"
  echo "$d"
}

# Builds `downloaded/mutants-report-shard-<i>/` for each index in $2.., with
# $1 caught mutants and 0 missed in each, so the scorer would report 100.
make_shard_reports() {
  local caught="$1"
  shift
  local i n
  for i in "$@"; do
    mkdir -p "downloaded/mutants-report-shard-${i}"
    : >"downloaded/mutants-report-shard-${i}/missed.txt"
    : >"downloaded/mutants-report-shard-${i}/caught.txt"
    for ((n = 0; n < caught; n++)); do
      echo "src/lib.rs:${n}: replace foo with bar" \
        >>"downloaded/mutants-report-shard-${i}/caught.txt"
    done
  done
}

run_assert() {
  EXPECTED_SHARDS="$1" bash "$BATS_FILE_TMPDIR/assert.sh"
}

# ---------------------------------------------------------------------------
# The hole this change closes: a missing shard must not be scored past.
# ---------------------------------------------------------------------------

@test "complete shard set passes" {
  cd "$(workspace)"
  make_shard_reports 3 0 1 2 3
  run run_assert 4
  [ "$status" -eq 0 ]
  [[ "$output" == *"All 4 shard report(s) present"* ]]
}

@test "ONE missing shard fails, and the error names the expected/actual counts and the missing index" {
  cd "$(workspace)"
  make_shard_reports 3 0 1 3   # shard 2's artifact never arrived
  run run_assert 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error title=Incomplete mutation shard set::"* ]]
  [[ "$output" == *"expected 4 shard report(s), found 3"* ]]
  [[ "$output" == *"Missing shard(s): 2"* ]]
}

@test "several missing shards are all named" {
  cd "$(workspace)"
  make_shard_reports 3 1
  run run_assert 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 4 shard report(s), found 1"* ]]
  [[ "$output" == *"Missing shard(s): 0 2 3"* ]]
}

@test "ALL artifacts missing fails — the worst case, which the scorer alone reports as a clean 100" {
  # This is the case a naive "tolerate zero directories" exemption would wave
  # through, and it is the most dangerous one: the scorer's `total == 0`
  # branch reports score=100 and the gate passes having measured nothing.
  cd "$(workspace)"
  mkdir -p downloaded
  run run_assert 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 4 shard report(s), found 0"* ]]
  [[ "$output" == *"Missing shard(s): 0 1 2 3"* ]]
}

@test "downloaded/ absent entirely (the download step itself failed under continue-on-error) fails" {
  cd "$(workspace)"
  run run_assert 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"Incomplete mutation shard set"* ]]
}

@test "the unsharded path (total=1) is checked too" {
  cd "$(workspace)"
  mkdir -p downloaded
  run run_assert 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 1 shard report(s), found 0"* ]]

  cd "$(workspace)"
  make_shard_reports 3 0
  run run_assert 1
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# What must NOT break: the deliberate "nothing to mutate" pass, and the
# receipt that makes it distinguishable from a missing artifact.
# ---------------------------------------------------------------------------

@test "receipt step creates mutants.out/ and a receipt when cargo-mutants wrote nothing" {
  cd "$(workspace)"
  SHARD_INDEX=2 SHARD_TOTAL=4 bash "$BATS_FILE_TMPDIR/receipt.sh"
  [ -f mutants.out/shard-receipt.txt ]
  [ "$(cat mutants.out/shard-receipt.txt)" = "shard 2 of 4 reported" ]
}

@test "receipt step leaves real cargo-mutants outcome files untouched" {
  cd "$(workspace)"
  mkdir -p mutants.out
  echo "src/lib.rs:7: replace a with b" >mutants.out/caught.txt
  echo "src/lib.rs:9: replace c with d" >mutants.out/missed.txt
  SHARD_INDEX=0 SHARD_TOTAL=1 bash "$BATS_FILE_TMPDIR/receipt.sh"
  [ "$(cat mutants.out/caught.txt)" = "src/lib.rs:7: replace a with b" ]
  [ "$(cat mutants.out/missed.txt)" = "src/lib.rs:9: replace c with d" ]
  [ -f mutants.out/shard-receipt.txt ]
}

@test "receipt is not counted as a mutant outcome by the scorer" {
  # The receipt filename must stay outside caught/missed/unviable/timeout.txt,
  # or every shard would inflate the counts by one.
  cd "$(workspace)"
  mkdir -p downloaded/mutants-report-shard-0
  SHARD_INDEX=0 SHARD_TOTAL=1 bash "$BATS_FILE_TMPDIR/receipt.sh"
  cp mutants.out/shard-receipt.txt downloaded/mutants-report-shard-0/
  GITHUB_OUTPUT="$PWD/gh_output" THRESHOLD=80 run bash "$BATS_FILE_TMPDIR/score.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Caught: 0  Missed: 0"* ]]
}

@test "EVERY shard reported with nothing to mutate still passes, end to end" {
  # The legitimate zero outcome, assembled the way a real run produces it:
  # each shard runs the receipt step with no mutants.out/ of its own, its
  # artifact is uploaded holding only the receipt, and the aggregate then
  # sees N directories and zero mutant outcomes. The assertion must pass and
  # the scorer must still take its `total == 0` branch.
  local ws
  ws="$(workspace)"
  cd "$ws"
  local i
  for i in 0 1 2 3; do
    mkdir -p "shard${i}"
    cd "$ws/shard${i}"
    SHARD_INDEX="$i" SHARD_TOTAL=4 bash "$BATS_FILE_TMPDIR/receipt.sh"
    cd "$ws"
    # Mirrors `upload-artifact` + `download-artifact`: the contents of the
    # shard's mutants.out/ become downloaded/mutants-report-shard-<i>/.
    mkdir -p "downloaded/mutants-report-shard-${i}"
    cp "shard${i}/mutants.out/"* "downloaded/mutants-report-shard-${i}/"
  done

  run run_assert 4
  [ "$status" -eq 0 ]

  GITHUB_OUTPUT="$ws/gh_output" THRESHOLD=80 run bash "$BATS_FILE_TMPDIR/score.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no shard reported any caught/missed mutants"* ]]
  grep -q '^score=100$' "$ws/gh_output"
}

@test "a real sharded run is scored unchanged once complete" {
  # Regression guard on the ordering: the assertion must not disturb the
  # score. 3 caught + 1 missed per shard over 4 shards = 12/16 = 75%.
  local ws
  ws="$(workspace)"
  cd "$ws"
  make_shard_reports 3 0 1 2 3
  local i
  for i in 0 1 2 3; do
    echo "src/lib.rs:1: replace x with y" \
      >"downloaded/mutants-report-shard-${i}/missed.txt"
  done

  run run_assert 4
  [ "$status" -eq 0 ]

  GITHUB_OUTPUT="$ws/gh_output" THRESHOLD=70 run bash "$BATS_FILE_TMPDIR/score.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Score: 75%"* ]]
  grep -q '^score=75$' "$ws/gh_output"
}

# ---------------------------------------------------------------------------
# Edge cases around the expected count itself.
# ---------------------------------------------------------------------------

@test "an unknown expected total is a hard failure, never an unchecked pass" {
  # If shard-plan's `total` output is ever lost (renamed output, a job
  # expression that evaluated to empty), the expected shard set is unknown.
  # Scoring anyway would be the vacuous branch all over again.
  cd "$(workspace)"
  make_shard_reports 3 0 1 2 3
  for bad in "" "abc" "0" "-1" "2.5"; do
    run run_assert "$bad"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a positive integer"* ]]
  done
}

@test "an unexpected shard index warns but does not block scoring" {
  # Structurally impossible while the matrix comes from shard-plan's
  # `seq 0 total-1`, and extra evidence cannot hide a surviving mutant — so
  # it is reported, not failed.
  cd "$(workspace)"
  make_shard_reports 3 0 1 9
  run run_assert 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning title=Unexpected mutation shard report::"* ]]
  [[ "$output" == *"9"* ]]
}

@test "one missing shard plus one stray does not cancel out to the right count" {
  # Why the check is per-index and not a bare count comparison.
  cd "$(workspace)"
  make_shard_reports 3 0 1 7   # expected 0,1,2 — 2 missing, 7 unplanned
  run run_assert 3
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing shard(s): 2"* ]]
}

@test "a stray index that looks octal does not abort the step under set -e" {
  # "08" through a bare (( idx >= expected )) is "value too great for base",
  # which under `set -euo pipefail` kills the step — turning a cosmetic
  # surprise into a red gate. Hence the 10# prefix.
  cd "$(workspace)"
  make_shard_reports 3 0 1 08
  run run_assert 2
  [ "$status" -eq 0 ]
  [[ "$output" != *"value too great for base"* ]]
  [[ "$output" == *"::warning title=Unexpected mutation shard report::"* ]]
}

@test "a non-directory matching the artifact glob is not mistaken for a report" {
  cd "$(workspace)"
  make_shard_reports 3 0 1
  : >downloaded/mutants-report-shard-2
  run run_assert 3
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing shard(s): 2"* ]]
}
