#!/usr/bin/env bats
# Executes the Detect affected crates script extracted from rust-affected.yml.
# A copied implementation would not guard the workflow consumers actually run.

EXTRACT="$BATS_TEST_DIRNAME/lib/extract_step.py"
WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/rust-affected.yml"

setup_file() {
  python3 "$EXTRACT" "$WORKFLOW" "Detect affected crates" >"$BATS_FILE_TMPDIR/detect.sh"
  [ -s "$BATS_FILE_TMPDIR/detect.sh" ]
}

run_detect() {
  local repo="$BATS_TEST_TMPDIR/root-crate"
  mkdir -p "$repo/src" "$repo/bin"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name test
  printf '[package]\nname = "root-crate"\nversion = "0.1.0"\nedition = "2021"\n' >"$repo/Cargo.toml"
  printf 'pub fn answer() -> u8 { 42 }\n' >"$repo/src/lib.rs"
  git -C "$repo" add .
  git -C "$repo" commit -qm base
  local base
  base="$(git -C "$repo" rev-parse HEAD)"
  printf 'pub fn answer() -> u8 { 43 }\n' >"$repo/src/lib.rs"
  git -C "$repo" add .
  git -C "$repo" commit -qm changed
  # The detector needs only cargo metadata. Stub exactly that boundary so this
  # regression test remains runnable on contributors' machines without a
  # installed Rust toolchain; the fixture's paths still come from the real
  # temporary git repository.
  cat >"$repo/bin/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != "metadata" ]]; then
  echo "unexpected cargo invocation: $*" >&2
  exit 1
fi
printf '{"workspace_root":"%s","packages":[{"name":"root-crate","manifest_path":"%s/Cargo.toml","dependencies":[]}]}' "$PWD" "$PWD"
EOF
  chmod +x "$repo/bin/cargo"
  : >"$repo/output"
  (cd "$repo" && PATH="$repo/bin:$PATH" GITHUB_OUTPUT="$repo/output" WORKDIR=. EVENT_NAME=pull_request \
    PR_BASE_SHA="$base" PUSH_BEFORE_SHA='' PUSH_BUILDS_WORKSPACE=true \
    bash "$BATS_FILE_TMPDIR/detect.sh")
  cat "$repo/output"
}

@test "a source change in a single root crate is never skipped" {
  run run_detect
  [ "$status" -eq 0 ]
  [[ "$output" == *$'cargo-args=--workspace'* ]]
  [[ "$output" == *$'changed=true'* ]]
}

@test "unmapped changed paths fail closed to a workspace build" {
  grep -Fq 'changed paths did not map to a crate; building everything' "$BATS_FILE_TMPDIR/detect.sh"
  grep -Fq 'emit "--workspace" "true" ""' "$BATS_FILE_TMPDIR/detect.sh"
}
