#!/usr/bin/env bats
# Tests `rust-sonar.yml`'s `sonar.sources` precedence.
#
# WHY THIS SUITE EXISTS
# ----------------------
# The workflow hardcoded `-Dsonar.sources=src` onto the scanner command line.
# Scanner CLI args OVERRIDE sonar-project.properties, so that one key in a
# consumer repo's own properties file was INERT — it could not win no matter
# what it said. Measured across the fleet's rust-sonar callers, nine repos ship
# a `sonar.sources` that was being ignored, including three pointing at
# `lambdas` (so `src` resolved to a directory that does not exist under their
# project base dir) and two listing explicit per-crate paths under `crates/`.
#
# The load-bearing case is the MIDDLE one: when the file sets the key the
# workflow must pass NOTHING, because passing anything at all overrides the
# file. "Passes src" and "passes nothing" look identical in a diff of the
# scanner invocation unless something asserts the empty string.
#
# CI CANNOT PROVE THIS. `self-test.yml` has no `pull_request` trigger at all,
# and `ci.yml`'s `sonar` job is gated on `vars.SONAR_ENABLED == 'true'` AND on
# the PR not being a draft — every PR here opens as a draft. So the sonar job
# is skipped on the PR that changes this workflow. `ci.yml`'s
# `resolve-parallelism-tests` job runs `make test` with no draft gate, which
# makes this suite the only thing that actually executes.
#
# Runs the script EXTRACTED FROM THE YAML (workspace rule: "test the artifact
# as used"); renaming the step breaks the extraction loudly.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-sonar.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"

setup_file() {
  python3 "$EXTRACT" "$WORKFLOW" "Build Sonar extra args" \
    >"$BATS_FILE_TMPDIR/sonar.sh"
  [ -s "$BATS_FILE_TMPDIR/sonar.sh" ] || {
    echo "could not extract 'Build Sonar extra args' from rust-sonar.yml"
    return 1
  }
}

setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  rm -rf "$WORK"
  mkdir -p "$WORK"
  cd "$WORK" || return 1
}

# Runs the step the way the job does: inside inputs.working-directory, with the
# step's `env:` block supplied. $1 is the `sources` input.
run_args_step() {
  PROJECT_KEY_INPUT=key \
    PROJECT_KEY_VAR= \
    ORGANIZATION_INPUT=org \
    ORGANIZATION_VAR= \
    OWNER=owner \
    REPO=repo \
    SOURCES_INPUT="${1:-}" \
    GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out.txt" \
    bash -c "cd '$WORK' && bash '$BATS_FILE_TMPDIR/sonar.sh'"
}

sources_arg() {
  sed -n 's/^sources_arg=//p' "$BATS_TEST_TMPDIR/out.txt"
}

# "Expected empty" must mean "the key was emitted and its value is empty",
# never "the key is absent" — otherwise every empty-expecting case below passes
# vacuously against a workflow that emits no sources_arg at all, which is the
# exact shape of this repo's 2026-08-19 vacuous-gate bug (absence of evidence
# is not evidence of success).
assert_sources_arg_empty() {
  grep -q '^sources_arg=$' "$BATS_TEST_TMPDIR/out.txt"
}

# Precedence 3 — the backward-compatibility assertion. No properties file and
# no input must reproduce the previous hardcoded value EXACTLY, or every
# existing caller's scan scope moves.
@test "case 1: no properties file and no input yields the historical -Dsonar.sources=src" {
  run run_args_step ""
  [ "$status" -eq 0 ]
  [ "$(sources_arg)" = "-Dsonar.sources=src" ]
}

# Precedence 3 again, for the shape this repo's OWN sonar-project.properties
# has (projectKey + organization, no sources) — so this repo's own sonar job is
# byte-identical after the change.
@test "case 2: a properties file WITHOUT sonar.sources still yields the default" {
  printf 'sonar.projectKey=ffreis-workflows-rust\nsonar.organization=felipefuhr\n' \
    >sonar-project.properties
  run run_args_step ""
  [ "$status" -eq 0 ]
  [ "$(sources_arg)" = "-Dsonar.sources=src" ]
}

# Precedence 2 — THE FIX. Must pass NOTHING so the file wins. Asserting the
# empty string is the whole point: any non-empty value overrides the file.
@test "case 3: a properties file WITH sonar.sources passes no CLI override at all" {
  printf 'sonar.sources=crates/a/src,crates/b/src\n' >sonar-project.properties
  run run_args_step ""
  [ "$status" -eq 0 ]
  assert_sources_arg_empty
}

@test "case 4: the properties file wins for a lambdas-shaped workspace too" {
  printf 'sonar.projectKey=x\nsonar.sources=lambdas\n' >sonar-project.properties
  run run_args_step ""
  [ "$status" -eq 0 ]
  assert_sources_arg_empty
}

# Tolerate the spacing the properties format allows, or a repo written
# `sonar.sources = src` silently falls through to the default and the defect
# survives for it.
@test "case 5: whitespace around the key and '=' is still detected" {
  printf '  sonar.sources = crates/a/src\n' >sonar-project.properties
  run run_args_step ""
  [ "$status" -eq 0 ]
  assert_sources_arg_empty
}

# A commented-out key must NOT suppress the default — otherwise a repo that
# disabled the line gets no sonar.sources at all.
@test "case 6: a commented sonar.sources does not count" {
  printf '#sonar.sources=crates/a/src\n' >sonar-project.properties
  run run_args_step ""
  [ "$status" -eq 0 ]
  [ "$(sources_arg)" = "-Dsonar.sources=src" ]
}

# Precedence 1 — an explicit caller value beats everything, properties
# included, so a caller can always force a scope.
@test "case 7: an explicit sources input overrides the properties file" {
  printf 'sonar.sources=crates/a/src\n' >sonar-project.properties
  run run_args_step "lambdas"
  [ "$status" -eq 0 ]
  [ "$(sources_arg)" = "-Dsonar.sources=lambdas" ]
}

@test "case 8: an explicit sources input works with no properties file" {
  run run_args_step "crates"
  [ "$status" -eq 0 ]
  [ "$(sources_arg)" = "-Dsonar.sources=crates" ]
}

# The step's pre-existing outputs must survive the change — they feed the
# scanner's project-key/organization inputs.
@test "case 9: project_key and organization outputs are unaffected" {
  run run_args_step ""
  [ "$status" -eq 0 ]
  grep -q '^project_key=key$' "$BATS_TEST_TMPDIR/out.txt"
  grep -q '^organization=org$' "$BATS_TEST_TMPDIR/out.txt"
}
