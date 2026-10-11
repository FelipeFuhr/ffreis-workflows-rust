#!/usr/bin/env python3
"""Structural assertions about the `packages` per-package matrix.

Exit 0 when the assertion holds; print why and exit 1 when it does not. Each
subcommand answers one question that `packages_matrix.bats` asks, against the
SHIPPED YAML rather than against a description of it — the point being that a
change to rust-lint.yml / rust-test.yml cannot quietly break a consumer's
required status check or re-widen a permissions block without a red test.

usage: packages_matrix.py <check> <workflow.yml> <job> [<job2>]
"""

import pathlib
import sys

import yaml

WORKFLOWS = pathlib.Path(__file__).resolve().parents[2] / ".github" / "workflows"


def load(name):
    with open(WORKFLOWS / name, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def fail(msg):
    print(msg)
    raise SystemExit(1)


def job_of(wf_name, job_id):
    jobs = load(wf_name).get("jobs") or {}
    if job_id not in jobs:
        fail(f"{wf_name}: no job `{job_id}` (jobs: {sorted(jobs)})")
    return jobs[job_id]


def steps_of(wf_name, job_id):
    return job_of(wf_name, job_id).get("steps") or []


def cargo_lines(wf_name, job_id):
    """Every line in the job's steps that invokes a cargo build verb."""
    verbs = ("cargo clippy", "cargo test", "cargo nextest run")
    out = []
    for step in steps_of(wf_name, job_id):
        for line in (step.get("run") or "").splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if any(v in stripped for v in verbs):
                out.append(stripped)
    return out


# --- checks ----------------------------------------------------------------


def check_job_exists(wf, job, _other):
    job_of(wf, job)
    print(f"{wf}: job `{job}` present")


def check_default_command(wf, job, _other):
    """The unsplit job's cargo invocations must carry no package selector."""
    lines = cargo_lines(wf, job)
    if not lines:
        fail(f"{wf}:{job}: found no cargo invocation at all — test is vacuous")
    for line in lines:
        if " -p " in line or line.endswith(" -p") or "-p=" in line:
            fail(
                f"{wf}:{job}: the DEFAULT (unsplit) path carries a package "
                f"selector, which would break every caller that never set "
                f"`packages`:\n    {line}"
            )
        if "matrix.package" in line:
            fail(f"{wf}:{job}: unsplit path references matrix.package:\n    {line}")
    print(f"{wf}:{job}: {len(lines)} cargo invocation(s), none package-scoped")


def check_split_command(wf, job, _other):
    """Every cargo invocation in the split job must be package-scoped."""
    lines = cargo_lines(wf, job)
    if not lines:
        fail(f"{wf}:{job}: found no cargo invocation at all — test is vacuous")
    for line in lines:
        if '-p "${PACKAGE}"' not in line:
            fail(
                f"{wf}:{job}: a matrix leg runs cargo WITHOUT -p, so it would "
                f"compile the whole workspace N times:\n    {line}"
            )
    env_names = set()
    for step in steps_of(wf, job):
        env_names |= set((step.get("env") or {}).keys())
    if "PACKAGE" not in env_names:
        fail(f"{wf}:{job}: no step passes the matrix value in as PACKAGE")
    print(f"{wf}:{job}: all {len(lines)} cargo invocation(s) scoped with -p")


def check_unsplit_standalone(wf, job, _other):
    spec = job_of(wf, job)
    if "needs" in spec:
        fail(
            f"{wf}:{job}: the unsplit job gained `needs: {spec['needs']}`. The "
            f"plan job is SKIPPED when `packages` is empty, and a skipped "
            f"dependency skips its dependents — so this job would stop running "
            f"for every existing caller while reporting green-by-skip."
        )
    if "strategy" in spec:
        fail(
            f"{wf}:{job}: the unsplit job gained a `strategy`, which appends "
            f"the leg's values to the rendered job name and so breaks the "
            f"`{job}` required status check on consumer repos."
        )
    print(f"{wf}:{job}: standalone — no needs, no strategy")


def check_mutually_exclusive(wf, job, other):
    a = str(job_of(wf, job).get("if", ""))
    b = str(job_of(wf, other).get("if", ""))
    if "inputs.packages == ''" not in a:
        fail(f"{wf}:{job}: `if` does not gate on an EMPTY packages input:\n  {a}")
    if "inputs.packages != ''" not in b:
        fail(f"{wf}:{other}: `if` does not gate on a NON-EMPTY packages input:\n  {b}")
    # Both must keep the draft gate, or promoting a draft PR leaves a job that
    # never ran reading as green.
    for name, expr in ((job, a), (other, b)):
        if "draft" not in expr:
            fail(f"{wf}:{name}: `if` lost the draft gate:\n  {expr}")
    print(f"{wf}: `{job}` and `{other}` are mutually exclusive on `packages`")


def check_fail_fast_false(wf, job, _other):
    strategy = job_of(wf, job).get("strategy") or {}
    if strategy.get("fail-fast") is not False:
        fail(
            f"{wf}:{job}: strategy.fail-fast is {strategy.get('fail-fast')!r}, "
            f"not False — one crate's failure would cancel its siblings, and a "
            f"cancelled job surfaces as `cancelled` rather than as a failure."
        )
    axes = (strategy.get("matrix") or {})
    if "package" not in axes:
        fail(f"{wf}:{job}: matrix has no `package` axis (axes: {sorted(axes)})")
    print(f"{wf}:{job}: fail-fast: false, matrix axis `package`")


def check_cache_isolated(wf, job, _other):
    for step in steps_of(wf, job):
        uses = step.get("uses") or ""
        if not uses.startswith("Swatinem/rust-cache@"):
            continue
        key = str((step.get("with") or {}).get("key", ""))
        if "matrix.package" not in key:
            fail(
                f"{wf}:{job}: rust-cache `key` is {key!r} — it does not carry "
                f"the package, so legs would SHARE one cache and restore the "
                f"whole workspace's target/ into every leg."
            )
        print(f"{wf}:{job}: rust-cache key isolated per package ({key})")
        return
    fail(f"{wf}:{job}: no Swatinem/rust-cache step found — test is vacuous")


def check_job_hygiene(wf, job, _other):
    spec = job_of(wf, job)
    doc = load(wf)
    if "permissions" in doc:
        fail(f"{wf}: has a TOP-LEVEL permissions block; repo rules require per-job")
    if "timeout-minutes" not in spec:
        fail(
            f"{wf}:{job}: direct job has no `timeout-minutes`; it could hold a "
            f"single-replica tier until GitHub's 6h default expires"
        )
    if "permissions" not in spec:
        fail(f"{wf}:{job}: no per-job `permissions` block")
    print(f"{wf}:{job}: timeout + per-job permissions present")


def check_permissions_not_widened(wf, job, other):
    base = job_of(wf, job).get("permissions") or {}
    split = job_of(wf, other).get("permissions") or {}
    extra = {k: v for k, v in split.items() if base.get(k) != v}
    if extra:
        fail(
            f"{wf}:{other}: asks for permissions the `{job}` job does not "
            f"({extra}). A caller's permissions must be a superset of the "
            f"callee's, so every existing caller's block would become "
            f"insufficient the moment they opted in."
        )
    print(f"{wf}: `{other}` permissions ⊆ `{job}` permissions")


CHECKS = {
    "job-exists": check_job_exists,
    "default-command": check_default_command,
    "split-command": check_split_command,
    "unsplit-standalone": check_unsplit_standalone,
    "mutually-exclusive": check_mutually_exclusive,
    "fail-fast-false": check_fail_fast_false,
    "cache-isolated": check_cache_isolated,
    "job-hygiene": check_job_hygiene,
    "permissions-not-widened": check_permissions_not_widened,
}


def main():
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    check, wf, job = sys.argv[1], sys.argv[2], sys.argv[3]
    other = sys.argv[4] if len(sys.argv) > 4 else None
    if check not in CHECKS:
        print(f"unknown check {check!r}; have {sorted(CHECKS)}", file=sys.stderr)
        return 2
    CHECKS[check](wf, job, other)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
