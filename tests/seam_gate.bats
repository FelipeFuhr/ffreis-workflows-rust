#!/usr/bin/env bats
# Guards rust-seam-gate.yml's scan step.
#
# The gate ships NON-BLOCKING (`fail_on_violation` defaults to false), and a
# non-blocking gate is the easiest kind to ship broken: nothing ever goes red,
# so nobody notices it stopped finding anything (rule 4b). So the failure path
# is asserted here, locally and deterministically, against a SEEDED fixture:
#   - it FINDS the fixture's 5 direct constructions (a count, not just "ran")
#   - it EXITS NONZERO on them when fail_on_violation=true
#   - it does NOT flag types, imports, comments, `#[cfg(test)]` code, the
#     escape hatch, or the composition roots the baseline allowlists
#   - a committed allowlist REPLACES the baseline
#   - a scan that matched no files, or an empty type pattern, is a HARD FAILURE
#
# The script under test is EXTRACTED FROM THE YAML by step name, so the suite
# exercises the shipped artifact rather than a copy that can drift.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-seam-gate.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/seam-violations"
STEP="Scan for direct adapter construction"

setup() {
  SCRIPT="$BATS_TEST_TMPDIR/scan.sh"
  python3 "$EXTRACT" "$WORKFLOW" "$STEP" > "$SCRIPT"
  [ -s "$SCRIPT" ]
  # The SHIPPED default, read from the workflow — not a copy in this file.
  DEFAULT_TYPES="$(python3 -c '
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get("on") or wf.get(True)
print(on["workflow_call"]["inputs"]["adapter-types"]["default"])
' "$WORKFLOW")"
  [ -n "$DEFAULT_TYPES" ]
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
}

scan() {
  local dir="$1" fail="$2" allowlist="${3:-.github/seam-gate-allowlist.txt}" types="${4-$DEFAULT_TYPES}"
  ( cd "$dir" && FAIL_ON_VIOLATION="$fail" ALLOWLIST_FILE="$allowlist" \
      ADAPTER_TYPES="$types" WORKDIR="." bash "$SCRIPT" )
}

output_value() {
  grep -E "^$1=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2
}

@test "the step exists in the workflow under the name the suite extracts" {
  run python3 "$EXTRACT" "$WORKFLOW" "$STEP"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "non-blocking: counts the seeded violations and still exits 0" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 5 ]
  echo "$output" | grep -q 'seam-gate: WARN'
  echo "$output" | grep -q '::warning file='
}

@test "blocking: the SAME violations exit nonzero (the gate can fail)" {
  run scan "$FIXTURE" true
  [ "$status" -eq 1 ]
  [ "$(output_value violations)" -eq 5 ]
  echo "$output" | grep -q 'seam-gate: FAIL'
  echo "$output" | grep -q '::error title=Seam gate FAILED'
  echo "$output" | grep -q '::error file='
  ! echo "$output" | grep -q '::warning file='
}

@test "every construction shape is caught" {
  run scan "$FIXTURE" false
  echo "$output" | grep -q 'line=29,.*MockPaymentGateway::new'   # ::new(
  echo "$output" | grep -q 'line=35,.*NoopEmailSender'           # Arc::new(Unit)
  echo "$output" | grep -q 'line=40,.*S3BlobStore::from_env'     # live adapter, ::from_env(
  echo "$output" | grep -q 'line=46,.*FakeClock {'               # struct literal
  echo "$output" | grep -q 'line=52,.*SystemClock'               # = Unit;
}

@test "types, imports, comments, struct defs and the escape hatch are not constructions" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  # 15-16 use-imports, 21 field type, 25 param types, 56-57 comments,
  # 60 seam-gate:allow, 64/67 struct definitions. Every one of these lines
  # DOES contain an adapter type name — that is what makes them discriminate.
  for line in 15 16 21 25 56 57 60 64 67; do
    sed -n "${line}p" "$FIXTURE/src/lib.rs" | grep -qE '(Noop|Mock|Fake|System)[A-Za-z]*'
    ! echo "$output" | grep -q "line=${line},"
  done
}

@test "code after #[cfg(test)] is not scanned" {
  run scan "$FIXTURE" false
  [ "$status" -eq 0 ]
  for line in 76 77; do
    sed -n "${line}p" "$FIXTURE/src/lib.rs" | grep -qE '(Noop|Mock)[A-Za-z]*'
    ! echo "$output" | grep -q "line=${line},"
  done
}

@test "the baseline spares composition roots and says which allowlist it used" {
  run scan "$FIXTURE" false
  ! echo "$output" | grep -q 'src/main.rs'
  ! echo "$output" | grep -q 'src/composition.rs'
  echo "$output" | grep -q 'built-in baseline'
}

@test "a committed allowlist REPLACES the baseline rather than extending it" {
  # allowlist.txt names main.rs only, so composition.rs becomes visible.
  run scan "$FIXTURE" false allowlist.txt
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 6 ]
  echo "$output" | grep -q 'file=src/composition.rs'
  echo "$output" | grep -q 'allowlist file allowlist.txt'
}

@test "annotation paths are prefixed with working-directory" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" GITHUB_STEP_SUMMARY="$GITHUB_STEP_SUMMARY" \
    ADAPTER_TYPES="$DEFAULT_TYPES" \
    bash -c "cd '$FIXTURE' && FAIL_ON_VIOLATION=false ALLOWLIST_FILE=none WORKDIR=sub/dir bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'file=sub/dir/src/lib.rs'
}

@test "an empty adapter-types pattern is a hard failure, not a vacuous pass" {
  run scan "$FIXTURE" true .github/seam-gate-allowlist.txt ""
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'adapter-types is empty'
}

@test "a scan that matched no .rs file is a hard failure, not a pass" {
  empty="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty"
  run scan "$empty" false
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'scanned nothing'
}

@test "a clean tree passes and reports how many files it actually read" {
  clean="$BATS_TEST_TMPDIR/clean"
  mkdir -p "$clean/src"
  printf 'pub fn pay(g: &dyn PaymentGateway) -> bool { g.is_test_double() }\n' > "$clean/src/lib.rs"
  run scan "$clean" true
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 0 ]
  [ "$(output_value files-checked)" -eq 1 ]
  echo "$output" | grep -q 'seam-gate: PASS'
}

@test "a domain type that merely ends in a port suffix is not an adapter" {
  dom="$BATS_TEST_TMPDIR/domain"
  mkdir -p "$dom/src"
  printf 'pub fn f() { let _ = OrderStore::new(); let _ = Gateway::new(); }\n' > "$dom/src/lib.rs"
  run scan "$dom" true
  [ "$status" -eq 0 ]
  [ "$(output_value violations)" -eq 0 ]
}
