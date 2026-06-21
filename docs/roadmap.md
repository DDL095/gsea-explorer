# Roadmap

> Living document. Dates are indicative, not commitments.

## North star

Make gsea-explorer the de facto interpretation layer for anyone running GSEA on
bulk transcriptomics data — usable from Copilot Chat, from any LLM agent
framework, and eventually as a plain R/Python library for non-LLM users.

## v0.6 — Public release foundation (next)

Theme: **clusterProfiler first-class + tests + multi-SA POC**.

### v0.6.0 — clusterProfiler first-class

Today only the gsealens profile is fully validated. Most public users will
arrive with `clusterProfiler::gseGO` / `gseNES` output, so this must be solved
first.

- Promote `profiles/clusterprofiler.yaml` from `status: skeleton` to
  `status: full`.
- Extend `scripts/extract_gsea_capsule.R` (or add a sibling extractor) to
  handle the `gseaResult` S4 object directly — `NES`, `p.adjust`,
  `core_enrichment` are already standard slots.
- Add `tests/test_extract_clusterprofiler.R` using a mock `gseaResult` built
  from `clusterProfiler`'s own example data.

### v0.6.1 — Test harness + synthetic test data

- `tests/testdata/synthetic_gsea.rds` — script-generated mock capsule with 5
  contrasts × 50 Hallmark pathways, including a few pre-engineered
  direction-flip cases (true_flip, p_suppression, p_restoration).
- `tests/test_skill_structure.py` — frontmatter validity, profile ↔ script
  cross-references, anti-pattern regex on SKILL.md itself.
- `tests/test_quality_gate.py` — feed G1/G2/G3 a known PASS and a known FAIL
  report, assert correct verdict.
- Wire up GitHub Actions CI to run the smoke test on every PR.

### v0.6.2 — Multi-SA parallel architecture POC

This is the differentiating feature for v0.6. Instead of one SA doing
everything sequentially, split into a fan-out / fan-in pattern with a shared
R REPL. Full design in [`multi_sa_architecture.md`](multi_sa_architecture.md).

## v0.7 — Decoupling and visualization

### v0.7.0 — MSigDB decoupling

Today §3a hard-depends on a private MSigDB MCP. Public users do not have it.

- Default to the `msigdbr` R package (CRAN, all collections, gene lists only).
- Treat `get_geneset_brief` / `search_text` as **optional** enhancements:
  auto-detect availability at S0, route through MCP when present, fall back to
  `msigdbr` + curated descriptions when absent.
- Document the degraded path explicitly in SKILL.md §3a.

### v0.7.1 — Visualization code lands

SKILL.md §5c currently *describes* the cascade heatmap in prose; no code ships.

- `scripts/plot_cascade_heatmap.R` — ComplexHeatmap implementation of §5c.
- `scripts/plot_gsea_dot.R` — Fig 3 dot plot from §6d.
- `scripts/plot_leading_edge.R` — Fig 5 UpSet + heatmap from §6d.

## v0.8 — Report ergonomics

### v0.8.0 — Quarto reports

- Move from plain Markdown to `.qmd` so users can render PDF / HTML / Word
  from one source.
- Parameterize the report template so the same analysis renders differently
  for lab internal review vs. manuscript supplementary.

### v0.8.1 — Publication ecosystem

- Document hand-off to `academic-paper` for turning the report into a paper
  Results section.
- Provide a `nature-paper2ppt`-compatible PPT export path.

## v1.0 — General availability

- Test coverage ≥ 80% across R + Python.
- Three independently-reported use cases cited in README.
- Submit to [JOSS](https://joss.theoj.org/) (Journal of Open Source Software)
  for a DOI-backed publication.
- Stable profile support for all four platforms (gsealens / clusterProfiler /
  fgsea / enrichit), each with an end-to-end test.

## Explicitly deferred

These have been considered and pushed out of scope for now:

- **VS Code extension (.vsix)** — the skill + agent role form is sufficient;
  the extension wrapper adds maintenance cost without clear user benefit yet.
- **Single-cell / spatial RNA-seq GSEA** — different output schemas; revisit
  once bulk is rock-solid.
- **Non-LLM pure R/Python library form** — attractive for reproducibility, but
  the value proposition of this project is the agent loop. Revisit at v1.x.

## How to influence the roadmap

Open a `feature_request` issue (see `.github/ISSUE_TEMPLATE/`). Pull requests
that land methodology changes ahead of the schedule are welcome — just update
`SKILL.md` and `CHANGELOG.md` in the same PR.
