#!/usr/bin/env bats
# Asserts self-test.yml never passes a secret (or input) that the reusable
# workflow it calls does not declare.
#
# WHY THIS SUITE EXISTS
# ----------------------
# An undeclared `secrets:`/`with:` key on a `workflow_call` is a
# **startup_failure**: zero jobs are created, there is no log to read, and
# the check renders as though it is still queuing rather than as a failure.
# That has cost this fleet multiple sessions and is a RECURRING class, not a
# one-off — which is exactly the kind of thing a structural test should hold
# rather than a reviewer's memory.
#
# It is also the only coverage available for some of this: `self-test.yml`'s
# `sonar` job is gated on `vars.SONAR_ENABLED == 'true'`, which is NOT set on
# this repo, so that job never runs here and cannot catch a typo in
# rust-sonar.yml's secret ids by executing. This suite catches it statically
# instead, and runs unconditionally under `make test`.

HELPER="$BATS_TEST_DIRNAME/lib/caller_callee.py"
WORKFLOWS="$BATS_TEST_DIRNAME/../.github/workflows"

@test "every secret self-test.yml passes is declared by its callee" {
  run python3 "$HELPER" --workflows "$WORKFLOWS" --kind secrets
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "every input self-test.yml passes is declared by its callee" {
  run python3 "$HELPER" --workflows "$WORKFLOWS" --kind inputs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the checker actually fails on an undeclared secret" {
  # Absence of evidence is not evidence of success (item 4b). If the helper
  # silently found nothing to check — wrong path, renamed job, empty parse —
  # both cases above would pass vacuously. This feeds it a known-bad fixture.
  run python3 "$HELPER" --self-test-fixture undeclared-secret --kind secrets
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT declared"* ]]
}

@test "the checker reports how many call sites it inspected" {
  # A count of zero is the vacuous-pass signature, so it is surfaced rather
  # than left implicit.
  run python3 "$HELPER" --workflows "$WORKFLOWS" --kind secrets
  [ "$status" -eq 0 ]
  [[ "$output" == *"call site"* ]]
  refute_zero_call_sites "$output"
}

refute_zero_call_sites() {
  if [[ "$1" == *"0 call site"* ]]; then
    echo "checker inspected ZERO call sites — it is testing nothing: $1"
    return 1
  fi
}
