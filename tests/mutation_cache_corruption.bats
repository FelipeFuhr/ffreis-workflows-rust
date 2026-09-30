#!/usr/bin/env bats
# Tests `mutation-warm`'s "Verify the cache restore actually worked" step,
# which detects a POISONED cache entry — one that exists (confirmed by an
# independent lookup-only check) but will not restore (confirmed by the
# real restore's own cache-hit output) — and distinguishes it from an
# ordinary first-time cache miss, which must never be treated as an error.
#
# WHY THIS SUITE EXISTS
# ----------------------
# GitHub Actions cache entries are immutable once created (confirmed
# against GitHub's own docs: "You cannot change the contents of an
# existing cache. Instead, you can create a new cache with a new key").
# Observed in production on a private consumer: a corrupt archive under
# this workflow's fixed shared-key failed to extract (`tar` exit code 2)
# on every run, forever, because the save that follows a failed restore is
# ALSO rejected (the key already exists). None of it failed loudly —
# verified directly against actions/toolkit's own cache package source,
# which deliberately treats a failed restore as non-fatal ("caching should
# be optional") and exposes no output that distinguishes "nothing was
# ever cached" from "something is cached but broken" — both report
# cache-hit: false. This suite exercises the detection logic this
# workflow adds on top to tell those two cases apart, on BOTH the healthy
# and the failed-restore paths — detection logic that has never seen a
# failure is not worth shipping.
#
# It runs the script EXTRACTED FROM THE YAML (the same technique
# resolve_build_parallelism.bats and mutation_warm_features.bats use, via
# the repo's existing generic tests/lib/extract_step.py), not a copy.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-mutation.yml"
EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"

setup_file() {
  python3 "$EXTRACT" "$WORKFLOW" "Verify the cache restore actually worked" \
    >"$BATS_FILE_TMPDIR/verify.sh"
  [ -s "$BATS_FILE_TMPDIR/verify.sh" ] || {
    echo "could not extract the cache-verification step from rust-mutation.yml"
    return 1
  }
}

# Runs the extracted script with the given lookup/restore cache-hit values
# and cache key. Prints combined stdout+stderr; caller checks $status.
run_verify() {
  local lookup_hit="$1" restore_hit="$2" key="${3:-mutation}"
  LOOKUP_HIT="$lookup_hit" RESTORE_HIT="$restore_hit" CACHE_KEY="$key" \
    bash "$BATS_FILE_TMPDIR/verify.sh"
}

@test "healthy hit: lookup found it, restore used it -> passes, no error" {
  run run_verify "true" "true"
  [ "$status" -eq 0 ]
  [[ "$output" != *"::error"* ]]
  [[ "$output" == *"Cache restore OK"* ]]
}

@test "ordinary first-time miss: lookup found nothing, restore found nothing -> passes, no error" {
  # The case that must NEVER fail: a brand-new lockfile/toolchain
  # combination has no cache yet, which is normal and expected, not a
  # defect. A naive "cache-hit: false means something is wrong" check
  # would misfire here on every first run of every new consumer.
  run run_verify "false" "false"
  [ "$status" -eq 0 ]
  [[ "$output" != *"::error"* ]]
  [[ "$output" == *"ordinary first build"* ]]
}

@test "POISONED cache: lookup found it, restore could NOT use it -> fails loudly, names the key" {
  # The failure this suite exists to catch: an entry exists (the lookup-only
  # check — immune to extraction failures — confirms it) but the real
  # restore did not get a usable hit. This is corruption, not a miss.
  run run_verify "true" "false" "mutation-custom-salt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error"* ]]
  [[ "$output" == *"Poisoned mutation cache"* ]]
  # The key must be NAMED in the error, not just "something is wrong" —
  # a caller needs to know WHICH shared-key to route around.
  [[ "$output" == *"mutation-custom-salt"* ]]
  # The error must point at the actual recovery lever, not leave the
  # reader to go rediscover it.
  [[ "$output" == *"mutants-cache-salt"* ]]
}

@test "race edge case: lookup found nothing, restore succeeded anyway -> not an error" {
  # Two back-to-back steps hitting the same immutable entry should never
  # actually disagree this way in practice, but if a cache were created in
  # the few seconds between the lookup and the real restore, ending up
  # with a WORKING restore is a good outcome — this must never be treated
  # as a failure just because the earlier lookup's answer is now stale.
  run run_verify "false" "true"
  [ "$status" -eq 0 ]
  [[ "$output" != *"::error"* ]]
  [[ "$output" == *"Cache restore OK"* ]]
}

@test "the key named in a poisoned-cache error reflects mutants-cache-salt, not a hardcoded default" {
  # Guards against the error message silently going stale if a caller HAS
  # already set a salt — the message must report the ACTUAL key in play,
  # not always say "mutation".
  run run_verify "true" "false" "mutation-2026-09-30"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutation-2026-09-30"* ]]
  [[ "$output" != *"key 'mutation'"* ]]
}
