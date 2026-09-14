#!/usr/bin/env python3
"""Report how each job in a workflow derives its `runs-on` label set.

WHY THIS EXISTS
---------------
Two shapes in this repo look alike and mean opposite things:

  runs-on: ${{ fromJson(inputs.runner) }}   -> the array IS one label set
  runs-on: ${{ matrix.os }}                 -> each ELEMENT of the array
    with  os: ${{ fromJson(inputs.os-list) }}  is one leg's whole label set

So `'["self-hosted","local"]'` is correct for the first and WRONG for the
second, where it yields two legs of one label each. A single-label job is a
subset of no runner class, so job-arbiter never scales for it and logs
`"reason":"queued_unroutable"` (v2.0.0 shipped exactly that as rust-build's
`os-list` default; ffreis-forma-lambdas-rust #21 is where it stranded).

Modes
-----
classify <workflow.yml>...
    One TSV line per job: workflow, job, kind, input, shape, default.
    kind is `matrix-axis` (runs-on comes from a matrix axis fed by a
    workflow_call input), `input-labels` (runs-on consumes the input
    directly), or `literal`. shape is `nested`, `flat`, or `n/a`.

expand <workflow.yml> <axis-input-json>
    One TSV line per matrix leg the build job would produce for that
    `os-list` value: leg index, the rust version, and the leg's `runs-on`
    labels comma-joined. This models fromJson + the matrix cross product, so
    the expansion is executed rather than argued about.
"""

import json
import re
import sys

import yaml

# `${{ matrix.os }}` — a runs-on driven by a matrix axis.
MATRIX_REF = re.compile(r"\$\{\{\s*matrix\.([A-Za-z0-9_-]+)\s*\}\}")
# `fromJson(inputs.runner)` — a runs-on (or axis) driven by a workflow input.
INPUT_REF = re.compile(r"fromJson\(\s*inputs\.([A-Za-z0-9_-]+)\s*\)")


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def call_inputs(workflow: dict) -> dict:
    """workflow_call inputs. PyYAML parses the `on:` key as the boolean True."""
    triggers = workflow.get("on", workflow.get(True)) or {}
    if not isinstance(triggers, dict):  # `on: [push, pull_request]`
        return {}
    return ((triggers.get("workflow_call") or {}).get("inputs")) or {}


def shape_of(default) -> str:
    """`nested` when every element is itself a list, else `flat`."""
    if not isinstance(default, str):
        return "unparsed"
    try:
        parsed = json.loads(default)
    except json.JSONDecodeError:
        return "unparsed"
    if not isinstance(parsed, list) or not parsed:
        return "unparsed"
    return "nested" if all(isinstance(item, list) for item in parsed) else "flat"


def classify(path: str) -> list[tuple[str, ...]]:
    workflow = load(path)
    inputs = call_inputs(workflow)
    rows = []
    for name, job in (workflow.get("jobs") or {}).items():
        runs_on = job.get("runs-on")
        if runs_on is None:  # a job that only `uses:` a reusable workflow
            continue
        text = runs_on if isinstance(runs_on, str) else json.dumps(runs_on)

        axis = MATRIX_REF.search(text)
        if axis:
            axis_expr = ((job.get("strategy") or {}).get("matrix") or {}).get(
                axis.group(1)
            )
            ref = INPUT_REF.search(str(axis_expr or ""))
            key = ref.group(1) if ref else ""
            default = (inputs.get(key) or {}).get("default") if key else None
            rows.append(
                (path, name, "matrix-axis", key, shape_of(default), str(default))
            )
            continue

        ref = INPUT_REF.search(text)
        if ref and ref.group(1) in inputs:
            key = ref.group(1)
            default = (inputs.get(key) or {}).get("default")
            rows.append(
                (path, name, "input-labels", key, shape_of(default), str(default))
            )
            continue

        rows.append((path, name, "literal", "", "n/a", text))
    return rows


def expand(path: str, axis_json: str) -> list[tuple[str, ...]]:
    """Model the build job's matrix cross product for a given os-list value."""
    workflow = load(path)
    inputs = call_inputs(workflow)
    versions = json.loads((inputs["rust-versions"] or {})["default"])
    legs = json.loads(axis_json)
    rows = []
    index = 0
    for version in versions:
        for entry in legs:
            labels = entry if isinstance(entry, list) else [entry]
            rows.append((str(index), str(version), ",".join(map(str, labels))))
            index += 1
    return rows


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    mode, args = sys.argv[1], sys.argv[2:]
    if mode == "classify":
        rows = [row for path in args for row in classify(path)]
    elif mode == "expand":
        if len(args) != 2:
            print("usage: runner_labels.py expand <workflow.yml> <json>", file=sys.stderr)
            return 2
        rows = expand(args[0], args[1])
    else:
        print(f"unknown mode: {mode}", file=sys.stderr)
        return 2
    for row in rows:
        print("\t".join(row))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
