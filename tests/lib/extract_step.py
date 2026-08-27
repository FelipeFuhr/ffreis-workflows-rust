#!/usr/bin/env python3
"""Print a named workflow step's script so Bats executes the shipped artifact."""

import sys

import yaml


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: extract_step.py <workflow.yml> <step name>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as handle:
        workflow = yaml.safe_load(handle)
    for job in (workflow.get("jobs") or {}).values():
        for step in job.get("steps") or []:
            if step.get("name") == sys.argv[2]:
                sys.stdout.write(step.get("run", ""))
                return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
