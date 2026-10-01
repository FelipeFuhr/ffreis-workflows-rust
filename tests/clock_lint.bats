#!/usr/bin/env bats
# Guards rust-clock-lint.yml's scan step.
#
# WHY THIS SUITE EXISTS
# ---------------------
# The lint ships NON-BLOCKING (`fail_on_violation` defaults to false), which is
# the right default — rust-shared, forma and petlook all read the clock
# directly today, so a blocking default would turn the Rust fleet red on merge.
# But a non-blocking gate is also the easiest kind to ship broken: nothing ever
# goes red, so nobody notices it stopped finding anything. This repo has
# already shipped exactly that once — rust-mutation.yml reported a clean 100%
# on all 24 consumer repos while reading no results at all (rule 4b).
#
# So the failure path is asserted here, locally and deterministically:
#   - it FINDS the fixture's violations (a count, not just "ran")
#   - it EXITS NONZERO when fail_on_violation=true
#   - it EXITS ZERO on the same violations when fail_on_violation=false
#   - it does NOT flag the allowlisted adapter path
#   - it does NOT flag comments, and DOES flag a `*`-prefixed deref
#   - a committed allowlist REPLACES the baseline rather than extending it
#   - a scan that matched no files is a HARD FAILURE, never a pass
#
# The script under test is EXTRACTED FROM THE YAML by step name, so the suite
# exercises the shipped artifact rather than a copy that can drift — same
# approach as tests/resolve_build_parallelism.bats.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-clock-lint.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/clock-violations"
STEP="Scan for direct clock reads"

setup() {
  SCRIPT="$BATS_TEST_TMPDIR/scan.sh"
  python3 "$EXTRACT" "$WORKFLOW" "$STEP" > "$SCRIPT"
  # An empty extraction would make every assertion below vacuous.
  [ -s "$SCRIPT" ]
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
}

# Run the extracted step in `dir` with the given env.
scan() {
  local dir="$1" fail="$2" allowlist="${3:-.github/clock-lint-allowlist.txt}"
  ( cd "$dir" && FAIL_ON_VIOLATION="$fail" ALLOWLIST_FILE="$allowlist" \
      WORKDIR="." bash "$SCRIPT" )
}

output_value() {
  grep -E "^$1=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2
}

@test "the step exists in the workflow under the name the suite extracts" {
  # If the step is renamed, every other test here silently stops testing the
  # shipped script. Fail loudly instead.
  run python3 "$EXTRACT" "$WORKFLOW" "$STEP"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "non-blocking: finds the fixture's violations and still exits 0" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 5 ]
  echo "$output" | grep -q 'clock-lint: WARN'
  echo "$output" | grep -q '::warning file='
}

@test "blocking: the SAME violations exit nonzero (the gate can fail)" {
  run scan "$FIXTURE" true
  [ "$status" -eq 1 ]
  [ "$(output_value violations)" -eq 5 ]
  echo "$output" | grep -q 'clock-lint: FAIL'
  echo "$output" | grep -q '::error title=Clock lint FAILED'
  # Blocking runs must annotate at error level, not warning.
  echo "$output" | grep -q '::error file='
  ! echo "$output" | grep -q '::warning file='
}

@test "every forbidden spelling is caught, including a deref assignment" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  # Imported, fully qualified, chrono, the `*slot = Instant::now();` line
  # whose leading asterisk a naive comment filter would swallow, and a bare
  # positive `Local::now()` call — previously this spelling only had NEGATIVE
  # cases below (a comment mention, the allow-listed escape hatch), so it was
  # never actually proven to fire.
  echo "$output" | grep -q 'line=20,'  # SystemTime::now()
  echo "$output" | grep -q 'line=29,'  # std::time::SystemTime::now()
  echo "$output" | grep -q 'line=38,'  # chrono::Utc::now()
  echo "$output" | grep -q 'line=44,'  # *slot = Instant::now();
  echo "$output" | grep -q 'line=53,'  # chrono::Local::now()
}

@test "a mention in a comment is not a violation" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  # Doc comment (18), line comment (56), block comment open (58) and its
  # ` * ` continuation (59, naming Local::now()) all name a forbidden call
  # and must be ignored.
  for line in 18 56 58 59; do
    ! echo "$output" | grep -q "line=${line},"
  done
}

@test "the clock-lint:allow escape hatch suppresses its own line" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  # Line 64 is `chrono::Local::now()` carrying the marker plus a reason.
  ! echo "$output" | grep -q 'line=64,'
}

@test "the baseline allowlist spares the adapter path" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  # Identical SystemTime::now() call, under */adapters/*.
  ! echo "$output" | grep -q 'adapters/system_clock.rs'
  # And the run says which allowlist it used — an absent file is never
  # silently an empty allowlist.
  echo "$output" | grep -q 'built-in baseline'
}

@test "a committed allowlist REPLACES the baseline rather than extending it" {
  # allowlist.txt covers src/lib.rs only, so the adapter — baseline-covered,
  # unlisted there — becomes visible. A repo adopting an allowlist must carry
  # its adapter paths over, and this is what says so.
  run scan "$FIXTURE" false allowlist.txt
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 1 ]
  echo "$output" | grep -q 'adapters/system_clock.rs'
  echo "$output" | grep -q 'allowlist file allowlist.txt'
}

@test "annotation paths are prefixed with working-directory" {
  # The in-diff path bug (rule 17) in miniature: a caller whose workspace sits
  # in a subdirectory gets repo-root-relative annotations or GitHub drops them.
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" GITHUB_STEP_SUMMARY="$GITHUB_STEP_SUMMARY" \
    bash -c "cd '$FIXTURE' && FAIL_ON_VIOLATION=false ALLOWLIST_FILE=none WORKDIR=sub/dir bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'file=sub/dir/src/lib.rs'
}

@test "a scan that matched no .rs file is a hard failure, not a pass" {
  # The vacuous-gate guard. A wrong working-directory must never read as clean.
  empty="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty"
  run scan "$empty" false
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'scanned nothing'
}

@test "an allowlist that swallows every file warns instead of passing quietly" {
  wide="$BATS_TEST_TMPDIR/wide"
  mkdir -p "$wide"
  printf 'pub fn t() { let _ = std::time::SystemTime::now(); }\n' > "$wide/a.rs"
  printf '*\n' > "$wide/all.txt"
  run scan "$wide" false all.txt
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 0 ]
  [ "$(output_value files-checked)" -eq 0 ]
  echo "$output" | grep -q 'scanned no unallowlisted file'
}

@test "a clean tree passes and reports how many files it actually read" {
  clean="$BATS_TEST_TMPDIR/clean"
  mkdir -p "$clean/src"
  printf 'pub fn now(c: &dyn Clock) -> u64 { c.now_unix() }\n' > "$clean/src/lib.rs"
  run scan "$clean" true
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 0 ]
  [ "$(output_value files-checked)" -eq 1 ]
  echo "$output" | grep -q 'clock-lint: PASS'
}

@test "target/ build output is never scanned" {
  stale="$BATS_TEST_TMPDIR/stale"
  mkdir -p "$stale/target/debug/build/x"
  printf 'fn g() { let _ = std::time::SystemTime::now(); }\n' \
    > "$stale/target/debug/build/x/out.rs"
  mkdir -p "$stale/src"
  printf 'pub fn ok() {}\n' > "$stale/src/lib.rs"
  run scan "$stale" true
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 0 ]
  [ "$(output_value files-checked)" -eq 1 ]
}
