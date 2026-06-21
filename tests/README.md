# tests/

Smoke and regression tests for gsealens-explorer.

## Running

```powershell
python tests\test_skill_structure.py
```

Requires only Python 3.8+ stdlib. No external packages needed.

## What's covered

- `test_skill_structure.py`
  - YAML frontmatter validity for `SKILL.md` and `gsealens-explorer.agent.md`
  - `profiles/*.yaml` declare `platform`, `status`, `result_fields`
  - Every script referenced in `SKILL.md` exists under `scripts/`
  - No personal-data leakage (Windows drive paths, study identifiers)
  - Version metadata in `SKILL.md` matches the latest entry in `CHANGELOG.md`

## Planned (v0.6.1)

- `test_extract_gsealens.R` — end-to-end extract on synthetic capsule
- `test_extract_clusterprofiler.R` — clusterProfiler profile validation
- `test_quality_gate.py` — G1/G2/G3 PASS / FAIL fixtures
- `test_classify_flip_mode.R` — cross-contrast direction-flip taxonomy
- `testdata/synthetic_gsea.rds` — script-generated mock capsule with known
  direction-flip cases

## Testdata

`testdata/` is `.gitignore`d except for this readme. Large synthetic RDS files
are generated on demand by the planned `testdata/build_synthetic_capsule.R`
script, not committed.
