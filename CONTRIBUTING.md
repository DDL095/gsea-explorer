# Contributing to gsealens-explorer

Thanks for your interest in improving gsealens-explorer. This document describes the
minimum expectations for contributions and the review process.

## Repository layout

```
gsealens-explorer/
├── SKILL.md                       # Master skill definition (read by the agent runtime)
├── gsealens-explorer.agent.md         # Agent role / phase contract
├── gsealens-explorer.md               # Compact role overview
├── agents/                        # Sub-agent role definitions
├── scripts/                       # R / Python / shell helpers invoked by the agent
├── profiles/                      # Per-platform schema mappings (YAML)
├── references/                    # Reference prompts and methodology notes
├── examples/                      # Worked walkthroughs on synthetic data
├── author_background_template.md  # Structured questionnaire used in S1
├── docs/                          # Architecture, roadmap, customization
├── tests/                         # Smoke + regression tests
└── deploy/                        # Local deployment helpers
```

The skill ships as a self-contained bundle: the agent runtime reads `SKILL.md`
and `gsealens-explorer.agent.md`, then loads supporting material on demand.

## Ground rules

1. **Methodology changes touch `SKILL.md`.** Any change to interpretation rules,
   NES direction conventions, phase contracts, or quality gates must update the
   master skill file and `CHANGELOG.md` in the same PR.
2. **Keep platform profiles honest.** When you add or update a profile in
   `profiles/`, the `status` field must reflect actual test coverage. A profile
   marked `status: full` must have a passing end-to-end test in `tests/`.
3. **No personal data.** Real RDS paths, study identifiers, usernames, and lab
   dataset names must never appear in committed files. Use placeholders such as
   `<your_rds_path>` or `study_A_vs_B`. See `docs/customization.md` for the
   local personalization layer pattern.
4. **Scripts stay side-effect free by default.** Scripts under `scripts/` must
   not modify the input RDS, must write outputs only to the user-provided
   output directory, and must exit non-zero on validation failure.
5. **Tests are required for new logic.** Add a test under `tests/` for any new
   extraction, classification, or gate behaviour.

## Development workflow

1. Fork and branch from `main`. Use a descriptive branch name such as
   `feat/clusterprofiler-profile` or `fix/nes-direction-doc`.
2. Make your changes. If you touch the skill methodology, update
   `CHANGELOG.md` under `[Unreleased]`.
3. Run the smoke tests locally:
   ```powershell
   python tests\test_skill_structure.py
   ```
4. Open a pull request against `main`. The PR template asks for:
   - What changed and why
   - Which phase / section of `SKILL.md` is affected
   - Whether tests were added or updated
   - Whether any new platform profile or external dependency was introduced

## Release process (for maintainers)

1. Update `CHANGELOG.md`: move `[Unreleased]` entries to a new version section
   and date-stamp it.
2. Update the `version` field in `SKILL.md` frontmatter and
   `gsealens-explorer.agent.md` description.
3. Tag the release: `git tag -a v0.6.0 -m "release notes"` then push tags.
4. Publish a GitHub Release with the changelog excerpt.

## Coding conventions

- **R scripts**: header comment with usage and exit codes. Flat `if` chains for
  platform detection (avoid nested `if/else` under CJK locales — see
  `references/` for the parser ambiguity note).
- **Python helpers**: type hints, docstrings, argparse with explicit exit
  codes. No implicit file deletion outside the user's output directory.
- **YAML profiles**: every field documented inline. `status` ∈
  `{full, skeleton, planned}`.

## Reporting issues

Open an issue for:
- Bugs in extraction, classification, or quality gates (attach the relevant
  `audit.jsonl` excerpt — redact real paths first).
- Methodology gaps (e.g. a GSEA platform whose schema is not handled).
- Documentation improvements.

For security or private-data concerns, do not open a public issue; contact the
maintainer directly.
