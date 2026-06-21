# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Project renamed: `gsea-explorer` → `gsealens-explorer`**. Resolves a three-way naming collision:
  - `gsealens` (lowercase) stays as the platform profile name pointing to the upstream [GSEAlens](https://github.com/DDL095/GSEAlens) R package schema
  - `gsealens-explorer` is now this project (the interpretation agent)
  - The interpretation methodology is renamed from "GSEAlens-style |NES| framework" to the neutral "|NES| enrichment direction framework", removing the methodology/package conflation
  - "GSEA Explorer" (used as the agent role title) replaced with "GSEAlens Explorer" to avoid collision with the Broad Institute's desktop GSEA tool
- Renamed skill files: `gsea-explorer.agent.md` / `gsea-explorer.md` / `agents/gsea-explorer.md` → `gsealens-explorer.*`
- Renamed `references/gsealens_nes_prompt.md` → `references/nes_direction_prompt.md` to match the methodology decoupling
- `tests/test_skill_structure.py` leakage patterns now also flag the legacy `gsea-explorer` / `GSEA Explorer` names so accidental reintroduction is caught
- GitHub repository renamed: `DDL095/gsea-explorer` → `DDL095/gsealens-explorer` (old URL redirects automatically)

### Added
- Public repository scaffold: LICENSE (MIT), README, CONTRIBUTING, CITATION.cff.
- Dual deploy scripts (`deploy/deploy_to_copilot.{ps1,sh}`) for local personalization layer workflow.
- `tests/` skeleton with structural smoke test.
- `docs/architecture.md` documenting the "source repo + local override" split.
- `docs/roadmap.md` capturing v0.6+ plans (multi-SA orchestration, clusterProfiler first-class, Quarto reports).

### Changed
- Repository scope expanded from a single `.md` file to the full skill bundle (`SKILL.md`, `agents/`, `scripts/`, `profiles/`, `references/`, `examples/`, `author_background_template.md`).
- All hard-coded Windows paths and dataset names replaced with placeholders and generic examples.

### Removed
- Personal dataset identifiers (real study names, user handles, absolute Windows paths) from all public files.

## [0.5.5] — 2026-06-16

### Added
- Full subcollection coverage rule (S4): all subcollections in the RDS must be emitted as independent CSVs.
- Multi-contrast cascade heatmap spec (§5c): required for ≥3 contrasts.
- Bioconductor knowledge base layer (§5d): decoupleR / GSVA / VIPER / AUCell / rrvgo / ComplexHeatmap usage notes.
- Paper-level figure planning (§6d): 4 main figures (GSEA dot / cascade / leading-edge+ORA / mechanism model).
- Medium-threshold pathway module (§2.7): FDR ∈ [0.05, 0.25) and |NES| ∈ [1.0, 1.5) collected to `evidence/medium/`, surfaced only on user trigger.

### Changed
- Leading-edge CPM weighting (§5b) reframed as optional parallel capability, never replacing the raw leading-edge interpretation.

## [0.5.4] — 2026-06-14

### Added
- Cross-contrast direction-flip taxonomy (§2.1.4): `true_flip` / `p_suppression` / `p_restoration` / `rtp_only` / `rt_only` / `no_flip` / `ambiguous`, with `classify_flip_mode()` reference implementation.
- "Comparison axis" concept (§2.1.5): every contrast pair forms an independent axis; cross-axis interpretation must confirm left/right roles first.

### Fixed
- Resolved cross-contrast NES-direction confusion (e.g. interpreting RTP_vs_RT NES<0 as "back to control" was wrong because right_group=RT, not control).

## [0.5.2] — 2026-06-13

### Added
- MSigDB local MCP hard-binding (§3a): 4-step emergent discovery SOP (EXTRACT / CLUSTER / SYNTHESIZE / HYPOTHESIZE).
- KEGG misnomer defense: KEGG_LEGACY / KEGG_MEDICUS pathway names are often misleading (e.g. `KEGG_PARKINSONS_DISEASE` is really Complex I); must consult `description_full` before interpreting.

## [0.3.0] — 2026-05

### Added
- Persistent R REPL via the `r-interactive` skill — no more `Rscript` one-shot.
- Full-significant-pathway extraction (removed top-30 cap).
- |NES| enrichment direction interpretation framework with 3-tier confidence (High / Medium / Low).
- Multi-tissue crosstalk architecture (§3).

## [0.2.1] — 2026-04

### Added
- Initial 4-script toolkit: `sniff_platform.R`, `extract_gsea_capsule.R`, `audit_logger.py`, `quality_gate_check.py`.
- Dual-format audit logging (`audit.log` + `audit.jsonl`).
- Quality gates G1 (data support), G2 (anti-patterns), G3 (limitations).
- gsealens platform validated end-to-end against a 141 MB GSEA Capsule RDS.
