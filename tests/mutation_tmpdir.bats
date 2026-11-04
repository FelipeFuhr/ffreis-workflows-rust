#!/usr/bin/env bats
# Locks `rust-mutation.yml`'s TMPDIR redirect — the fix for cargo-mutants'
# scratch trees evicting the runner pod off the `tmp` emptyDir.
#
# WHY THIS SUITE EXISTS
# ----------------------
# The failure it guards is INVISIBLE in the job log. cargo-mutants copies the
# source tree (plus target/, via its default `copy_target`) per parallel job
# into TMPDIR; /tmp in this fleet's runner pods is an emptyDir whose per-tier
# sizeLimit never exceeds 10Gi, so the pod is Evicted and the job reports
# only "The runner has received a shutdown signal" — indistinguishable from a
# network outage. Measured 2026-11-04 on ffreis-urbs-admin run 41738911842:
# 13m13s elapsed, ZERO mutants tested, and the gate would have reported a
# pass had item 4b's "no results is not a pass" guard not existed.
#
# Three things are asserted, each of which has an independent way of silently
# reverting:
#   1. the redirect exists at all, and lands OFF /tmp;
#   2. it is the FIRST step of the `mutation` job (ordering is load-bearing —
#      see case 3's comment);
#   3. it refuses to continue when the directory cannot be made, instead of
#      falling back to /tmp with no signal.
#
# Runs the script EXTRACTED FROM THE YAML, not a copy — the workspace's
# "test the artifact as used" rule, same technique as
# mutation_warm_features.bats and resolve_build_parallelism.bats.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-mutation.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"
STEP_NAME="Redirect TMPDIR off the tmp volume"

setup_file() {
  python3 "$EXTRACT" "$WORKFLOW" "$STEP_NAME" >"$BATS_FILE_TMPDIR/tmpdir.sh"
  [ -s "$BATS_FILE_TMPDIR/tmpdir.sh" ] || {
    echo "could not extract '$STEP_NAME' from rust-mutation.yml"
    return 1
  }
}

# Runs the extracted script with RUNNER_TEMP=$1 and a scratch GITHUB_ENV,
# echoing the GITHUB_ENV contents after stdout so a test can assert on both.
run_step() {
  local runner_temp="$1"
  local d="$BATS_TEST_TMPDIR/run.$$.$RANDOM"
  mkdir -p "$d"
  : >"$d/github_env"
  RUNNER_TEMP="$runner_temp" GITHUB_ENV="$d/github_env" \
    bash "$BATS_FILE_TMPDIR/tmpdir.sh"
  local rc=$?
  echo "--- GITHUB_ENV ---"
  cat "$d/github_env"
  return $rc
}

# Asserts the captured output carries no TMPDIR= export line. Kept as a
# function so the negative is stated once and cannot drift between cases.
refute_exported_tmpdir() {
  if grep -q '^TMPDIR=' <<<"$1"; then
    echo "expected no TMPDIR export, got: $(grep '^TMPDIR=' <<<"$1")"
    return 1
  fi
}

@test "1: the redirect exports a TMPDIR under RUNNER_TEMP, not /tmp" {
  local work="$BATS_TEST_TMPDIR/work.$$"
  mkdir -p "$work"
  run run_step "$work"
  [ "$status" -eq 0 ]
  # The whole point: TMPDIR must be exported, and must NOT be /tmp or a
  # subdirectory of it. A redirect that resolves back under /tmp is the
  # original bug wearing the fix's name.
  [[ "$output" == *"TMPDIR=$work/"* ]]
  # The redirect must DERIVE its base from RUNNER_TEMP, which is what makes
  # it correct on both the self-hosted pods and the hosted runners the
  # `runs-on` expression routes public repos to.
  #
  # Note what is NOT asserted here, and why: "the exported path is not under
  # /tmp" looks like the obvious check and is unusable — BATS_TEST_TMPDIR is
  # itself under /tmp, so every honest run of this suite would fail it. The
  # first draft did exactly that. The no-hardcoded-/tmp property is a
  # property of the SHIPPED SCRIPT, asserted in case 1b against its text.
  local exported
  exported="$(grep -m1 '^TMPDIR=' <<<"$output" | cut -d= -f2-)"
  [ -n "$exported" ]
  [ "$exported" = "$work/mutants-tmp" ]
}

@test "1b: the shipped script never falls back to a /tmp base" {
  # An unset RUNNER_TEMP must degrade to the work emptyDir, NOT to /tmp. A
  # `${RUNNER_TEMP:-/tmp}` default would pass every other case in this file
  # while reinstating the eviction on any runner that does not export
  # RUNNER_TEMP.
  run grep -n 'RUNNER_TEMP' "$BATS_FILE_TMPDIR/tmpdir.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'${RUNNER_TEMP:-/home/runner/_work/_temp}'* ]]
  # ...and no `:-/tmp` default anywhere. Scoped to parameter-expansion
  # defaults on purpose: the step's ::error message MENTIONS /tmp, correctly
  # — it is naming the consequence for whoever reads the failed run. A
  # blanket "no /tmp substring" check flagged that message and would have
  # pushed the explanation out of the annotation to keep a test quiet, which
  # is the wrong trade.
  run grep -c ':-/tmp' "$BATS_FILE_TMPDIR/tmpdir.sh"
  [ "$output" = "0" ]
}

@test "2: the exported directory actually exists and is writable afterwards" {
  local work="$BATS_TEST_TMPDIR/work2.$$"
  mkdir -p "$work"
  run run_step "$work"
  [ "$status" -eq 0 ]
  local exported
  exported="$(grep -m1 '^TMPDIR=' <<<"$output" | cut -d= -f2-)"
  [ -n "$exported" ]
  [ -d "$exported" ]
  [ -w "$exported" ]
}

@test "3: the redirect is the FIRST step of the mutation job" {
  # Ordering is load-bearing, not cosmetic. Every step after this one — the
  # node-based actions included (actions/checkout, taiki-e/install-action)
  # — reads TMPDIR from the job env. A redirect placed after them leaves
  # those steps on /tmp, which is where the toolchain and action tarballs
  # land; that is a smaller spill than cargo-mutants' tree copies but it is
  # the same 2Gi budget on the light tier. Asserted structurally because a
  # reorder is a one-line diff that no other case here would notice.
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = wf["jobs"]["mutation"]["steps"]
print(steps[0].get("name", "<unnamed>"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "Redirect TMPDIR off the tmp volume" ]
}

@test "4: an unmakeable directory is a hard error, never a silent /tmp fallback" {
  # RUNNER_TEMP pointing at a plain FILE makes `mkdir -p` impossible. The
  # step must exit non-zero AND write nothing to GITHUB_ENV — a TMPDIR that
  # never gets exported is exactly the silent fallback to /tmp this guards.
  local f="$BATS_TEST_TMPDIR/not-a-dir.$$"
  : >"$f"
  run run_step "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error title=TMPDIR redirect failed"* ]]
  # The annotation must name the real consequence, so a future reader does
  # not have to rediscover the kubelet event.
  [[ "$output" == *"sizeLimit"* ]]
  # Nothing may be exported: a TMPDIR that never appears is precisely the
  # silent fallback to /tmp this case exists to forbid. Plain conditional for
  # the same reason as case 1 — a nested `run` would overwrite the very
  # $output being inspected.
  refute_exported_tmpdir "$output"
}

@test "5: the step runs from the workspace root, before checkout exists" {
  # The job's `defaults.run.working-directory` is the caller's
  # `working-directory` input, which does not exist until actions/checkout
  # has run. A step placed before checkout WITHOUT this override cannot even
  # start bash — the exact failure "Resolve build parallelism" already
  # carries a comment about, caught there on its first real run.
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for step in wf["jobs"]["mutation"]["steps"]:
    if step.get("name") == "Redirect TMPDIR off the tmp volume":
        print(step.get("working-directory", "<unset>"))
        break
PY
  [ "$status" -eq 0 ]
  [ "$output" = '${{ github.workspace }}' ]
}

@test "6: mutation-warm is deliberately left alone" {
  # Not an oversight, and this case is what records that. mutation-warm runs
  # one ordinary `cargo test --no-run` with no tree copy — the same shape
  # every other rust-*.yml job runs on these tiers without eviction. If a
  # future change DOES need it there, this case failing is the prompt to
  # update the step's own comment rather than to quietly fork a second copy
  # that then drifts (see item 9's 13-duplicated-copies problem).
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
names = [s.get("name") for s in wf["jobs"]["mutation-warm"]["steps"]]
print("present" if "Redirect TMPDIR off the tmp volume" in names else "absent")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "absent" ]
}
