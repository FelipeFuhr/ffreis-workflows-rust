#!/usr/bin/env bats
# Guards how every reusable workflow here derives its `runs-on` label set.
#
# WHY THIS SUITE EXISTS
# ---------------------
# Two shapes in this repo look alike and mean opposite things:
#
#   runs-on: ${{ fromJson(inputs.runner) }}    the array IS one label set
#   runs-on: ${{ matrix.os }}                  each ELEMENT of the array is
#     with os: ${{ fromJson(inputs.os-list) }} one leg's WHOLE label set
#
# `'["self-hosted","local"]'` is right for the first and WRONG for the second.
# v2.0.0 (#74) rewrote every runner default from `["ubuntu-latest"]` to
# `["self-hosted","local"]` in one pass, which was correct everywhere except
# rust-build.yml's `os-list` — a matrix axis, where it silently became two legs
# of ONE label each.
#
# A single-label job is not a loud failure. job-arbiter's match_class requires
# a class's configured labels to be a SUBSET of the job's labels, so such a job
# matches zero classes, never triggers a scale-up, and is logged
# `"reason":"queued_unroutable"` — yet still lands opportunistically on any pod
# a sibling job already scaled up. It strands only when nothing else is scaling
# that tier, which is why it survived the whole v2.x line until
# ffreis-forma-lambdas-rust #21 hit it.
#
# So the invariant is asserted STRUCTURALLY over every workflow, not just over
# the one file that regressed, and the expansion is EXECUTED (see `expand`)
# rather than argued about in a comment.

WORKFLOWS="$BATS_TEST_DIRNAME/../.github/workflows"
LABELS="$BATS_TEST_DIRNAME/lib/runner_labels.py"
BUILD="$WORKFLOWS/rust-build.yml"

classify_all() { python3 "$LABELS" classify "$WORKFLOWS"/*.yml; }

@test "the repo still has a matrix-driven runs-on to guard" {
  # Keeps the structural cases below from passing vacuously if the matrix
  # build is ever refactored away.
  run classify_all
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'\tmatrix-axis\t'
}

@test "every matrix-axis runner input defaults to a NESTED array" {
  run classify_all
  [ "$status" -eq 0 ]
  # field 3 = kind, field 5 = shape. A matrix axis that is not `nested` puts
  # one label on a leg and strands it.
  offenders="$(echo "$output" | awk -F'\t' '$3 == "matrix-axis" && $5 != "nested"')"
  [ -z "$offenders" ] || {
    echo "matrix-axis default is not nested (each element is a whole leg):"
    echo "$offenders"
    false
  }
}

@test "every directly-consumed runner input defaults to a FLAT array" {
  # The mirror image: `runs-on: ${{ fromJson(inputs.runner) }}` consumes the
  # array AS the label set, so nesting these would break them. Asserted so a
  # future sweep for the os-list bug does not "fix" the correct ones too.
  run classify_all
  [ "$status" -eq 0 ]
  offenders="$(echo "$output" | awk -F'\t' '$3 == "input-labels" && $5 != "flat"')"
  [ -z "$offenders" ] || {
    echo "a directly-consumed runner input is not flat:"
    echo "$offenders"
    false
  }
}

@test "rust-build's default expands to ONE leg per toolchain, fully labelled" {
  default="$(python3 - "$BUILD" <<'PY'
import sys, yaml
w = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
on = w.get("on", w.get(True))
print(on["workflow_call"]["inputs"]["os-list"]["default"])
PY
)"
  run python3 "$LABELS" expand "$BUILD" "$default"
  [ "$status" -eq 0 ]
  # Two toolchains (stable, MSRV) x one runner leg.
  [ "$(echo "$output" | wc -l)" -eq 2 ]
  # Every leg carries the FULL self-hosted label set, not one label of it.
  [ "$(echo "$output" | awk -F'\t' '$3 == "self-hosted,local"' | wc -l)" -eq 2 ]
}

@test "a FLAT os-list strands legs on a single label (the bug this locks out)" {
  # The control. Without it the case above could pass for the wrong reason.
  run python3 "$LABELS" expand "$BUILD" '["self-hosted","local"]'
  [ "$status" -eq 0 ]
  # Four legs, each with exactly one label -> subset of no runner class.
  [ "$(echo "$output" | wc -l)" -eq 4 ]
  [ "$(echo "$output" | awk -F'\t' '$3 !~ /,/' | wc -l)" -eq 4 ]
}

@test "a multi-leg NESTED os-list still fans out across runner types" {
  # Back-compat: nesting the DEFAULT must not cost callers the ability to
  # build on several runner types. Each leg keeps its own full label set.
  run python3 "$LABELS" expand "$BUILD" '[["self-hosted","local"],["ubuntu-latest"]]'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 4 ]
  [ "$(echo "$output" | awk -F'\t' '$3 == "self-hosted,local"' | wc -l)" -eq 2 ]
  [ "$(echo "$output" | awk -F'\t' '$3 == "ubuntu-latest"' | wc -l)" -eq 2 ]
}

@test "a single GitHub-hosted label is still a legal one-element os-list" {
  # `'["ubuntu-latest"]'` is flat but harmless: one element, one label, and
  # GitHub-hosted labels are matched by GitHub, not by job-arbiter. The
  # workflow must keep accepting it — several callers pass exactly this.
  run python3 "$LABELS" expand "$BUILD" '["ubuntu-latest"]'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 2 ]
  [ "$(echo "$output" | awk -F'\t' '$3 == "ubuntu-latest"' | wc -l)" -eq 2 ]
}
