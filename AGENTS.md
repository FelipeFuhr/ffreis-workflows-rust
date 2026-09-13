# Agent Context

**This repo:** `ffreis-workflows-rust` — reusable GitHub Actions workflow library for
Rust projects. Covers fmt, clippy, test, matrix builds, cargo-audit, unit and
integration coverage, mutation testing, container build, cargo-deny, docs, MSRV
check, benchmarks, and Miri.

## Where the rest lives

This file used to carry every section inline (19,322 bytes, paid in full at the start of
every session). It was split **mechanically and verbatim** — every heading below became
one file, character-for-character, with nothing paraphrased or summarised — mirroring the
same split already applied elsewhere in this workspace. The path-scoped rule below
auto-loads at zero cost when a touched file matches its `paths:` glob; reference files
cost zero at startup and are read on demand, by name.

| Original heading | Destination |
| --- | --- |
| Non-obvious rules (read before changing anything) | `.claude/rules/non-obvious-workflow-rules.md` (auto-loads on `.github/workflows/**`) |
| Structure | `.claude/reference/structure.md` |
| Build/test | `.claude/reference/build-test.md` |
| Cross-repo role | `.claude/reference/cross-repo-role.md` |
| Public repo — private-repo hygiene | `.claude/reference/public-repo-private-repo-hygiene.md` |
| Keeping this file current | `.claude/reference/keeping-this-file-current.md` |

`.claude/reference/_manifest.json` records the reference-file mapping (heading, file, byte
count) so `scripts/check-instructions.sh` (`make lint-instructions`) can verify nothing was
silently lost or truncated. The rule file is verified separately by the same script, which
checks every `.claude/rules/*.md` declares `paths:` frontmatter — a rule file without it
never auto-loads, so it would be silently absent exactly when needed.
