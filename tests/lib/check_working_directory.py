#!/usr/bin/env python3
"""Exit 0 iff a workflow's resolve step is pinned to the workspace root.

The step runs BEFORE `actions/checkout`, so it must not inherit the job's
default `working-directory` — that is the caller's `working-directory` input
(e.g. `examples/hello`), which does not exist yet. When it does inherit it,
bash cannot start at all and the job dies before checkout with

    An error occurred trying to start process '/usr/bin/bash' with working
    directory '.../examples/hello'. No such file or directory

which is how the first CI run of this change failed. The extracted-script
tests cannot catch it: the defect is in the step's PLACEMENT, not its logic.

Exit 0 when the workflow has no resolve step at all — "absent" is a separate
question, asserted by its own case in the bats suite.
"""

import sys

import yaml

EXPECTED = "${{ github.workspace }}"


def is_pinned(path: str) -> bool:
    """True when every resolve step in the file pins working-directory.

    Vacuously true when the file has no resolve step — whether one *should*
    be there is a different question, asserted by its own case.
    """
    with open(path, encoding="utf-8") as handle:
        workflow = yaml.safe_load(handle)

    for job in (workflow.get("jobs") or {}).values():
        for step in job.get("steps") or []:
            if step.get("name") != "Resolve build parallelism":
                continue
            if step.get("working-directory") != EXPECTED:
                return False
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_working_directory.py <workflow.yml>", file=sys.stderr)
        return 2
    return 0 if is_pinned(sys.argv[1]) else 1


if __name__ == "__main__":
    sys.exit(main())
