#!/usr/bin/env python3
"""Print the "Resolve build parallelism" step's script from a workflow file.

Exists so `resolve_build_parallelism.bats` exercises the script that actually
ships rather than a copy pasted into the test. A copy would pass forever after
the real step drifted, which is the failure mode the suite is meant to catch.

Prints nothing (exit 0) when the workflow has no such step — several rust-*.yml
workflows legitimately never compile (`cargo fmt`, `cargo deny`,
`cargo metadata`) and so carry no resolve step. Distinguishing "absent" from
"broken" is the caller's job: the bats suite treats empty output as absent and
asserts separately that no COMPILING workflow is in that set.
"""

import sys

import yaml


def resolve_step_script(path: str) -> str:
    """The step's `run:` body, or "" when the workflow has no resolve step."""
    with open(path, encoding="utf-8") as handle:
        workflow = yaml.safe_load(handle)

    for job in (workflow.get("jobs") or {}).values():
        for step in job.get("steps") or []:
            if step.get("name") == "Resolve build parallelism":
                return step.get("run", "")
    return ""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: extract_resolve_step.py <workflow.yml>", file=sys.stderr)
        return 2
    sys.stdout.write(resolve_step_script(sys.argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
