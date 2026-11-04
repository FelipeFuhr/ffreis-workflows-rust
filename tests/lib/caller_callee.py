#!/usr/bin/env python3
"""Verify self-test.yml never passes an undeclared secret/input to a callee.

An undeclared `secrets:`/`with:` key on a `workflow_call` produces a
startup_failure: zero jobs, no log, and a check that reads as "still
queuing" rather than as a failure. This catches it statically.
"""

import argparse
import pathlib
import sys

import yaml

# PyYAML parses the unquoted `on:` key as the boolean True, so a reusable
# workflow's trigger block lives under `True`, not `"on"`. Looking only for
# the string silently finds nothing and passes vacuously.
ON_KEYS = (True, "on")


def trigger_block(doc):
    for key in ON_KEYS:
        if key in doc:
            return doc[key] or {}
    return {}


def declared(callee_path, kind):
    doc = yaml.safe_load(callee_path.read_text(encoding="utf-8"))
    call = (trigger_block(doc) or {}).get("workflow_call") or {}
    return set((call.get(kind) or {}).keys())


def check(workflows: pathlib.Path, kind: str):
    self_test = workflows / "self-test.yml"
    doc = yaml.safe_load(self_test.read_text(encoding="utf-8"))
    problems, sites = [], 0
    passed_key = "secrets" if kind == "secrets" else "with"

    for job_id, job in (doc.get("jobs") or {}).items():
        uses = job.get("uses")
        # Local calls only: a remote `uses:` cannot be resolved offline, and
        # guessing would make this check lie.
        if not uses or not uses.startswith("./"):
            continue
        passed = job.get(passed_key)
        # `secrets: inherit` is a string, not a mapping, and declares nothing.
        if not isinstance(passed, dict):
            continue
        # removeprefix, NOT lstrip: lstrip("./") strips EVERY leading "." and
        # "/" character, so "./.github/workflows/x.yml" became
        # "github/workflows/x.yml" and nothing resolved. And resolve() first,
        # because the caller passes a path containing ".." whose .parent is
        # not what it looks like.
        root = workflows.resolve().parent.parent
        callee = root / uses.removeprefix("./")
        if not callee.exists():
            problems.append(f"job {job_id}: callee {uses} does not exist")
            continue
        sites += 1
        missing = set(passed) - declared(callee, kind)
        for name in sorted(missing):
            problems.append(
                f"job {job_id} passes {kind[:-1]} '{name}' which is "
                f"NOT declared by {uses} -> startup_failure (zero jobs created)"
            )
    return sites, problems


FIXTURES = {
    "undeclared-secret": {
        "callee": {
            True: {"workflow_call": {"secrets": {"SONAR_TOKEN": {"required": True}}}},
            "jobs": {},
        },
        "caller": {
            "jobs": {
                "sonar": {
                    "uses": "./.github/workflows/fixture-callee.yml",
                    "secrets": {
                        "SONAR_TOKEN": "x",
                        "SONARQUBE_LOCAL_TOKEN": "y",  # undeclared
                    },
                }
            }
        },
    }
}


def run_fixture(name, kind, tmp: pathlib.Path):
    spec = FIXTURES[name]
    wf = tmp / "repo" / ".github" / "workflows"
    wf.mkdir(parents=True)
    (wf / "fixture-callee.yml").write_text(yaml.safe_dump(spec["callee"]))
    (wf / "self-test.yml").write_text(yaml.safe_dump(spec["caller"]))
    return check(wf, kind)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--workflows", type=pathlib.Path)
    ap.add_argument("--kind", choices=("secrets", "inputs"), required=True)
    ap.add_argument("--self-test-fixture", choices=sorted(FIXTURES))
    args = ap.parse_args()

    if args.self_test_fixture:
        import tempfile

        with tempfile.TemporaryDirectory() as td:
            sites, problems = run_fixture(
                args.self_test_fixture, args.kind, pathlib.Path(td)
            )
    else:
        if not args.workflows:
            print("--workflows is required unless --self-test-fixture is given")
            return 2
        sites, problems = check(args.workflows, args.kind)

    print(f"inspected {sites} call site(s) for {args.kind}")
    for problem in problems:
        print(f"  {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
